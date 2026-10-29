# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     objectives.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name Objectives
extends RefCounted
## The win and loss checks of one map: after every step they record
## [constant CombatFact.Kind.COMBAT_ENDED] once, with [member CombatFact.side] naming the side that
## won (combat map plan, Objectives and the end of a combat).
##
## [method register] adds [method check] to a session's [constant CombatHooks.Hook.AFTER_STEP];
## [CombatEncounter] does it for every map it opens. The objective is the map's
## [member CombatMapDefinition.objective], and its tiles are the layout's markers. Losses come
## first:[br]
## - [b]Lost:[/b] a commander on the map is defeated, no player unit is left on it, or (Defend) an
## enemy ends its turn on a defend tile.[br]
## - [b]Rout:[/b] won when no enemy is on the map; waves not yet arrived are cancelled
## ([method cancel_pending_waves]).[br]
## - [b]Defeat the Leader, Defeat the Boss:[/b] won when every enemy that appeared on a leader slot
## is defeated.[br]
## - [b]Seize:[/b] won when a player unit ends its turn on a seize tile.[br]
## - [b]Survive and Defend:[/b] won when turn [member CombatMapDefinition.survive_turns]'s enemy
## Phase End has run, or early when no enemy is on the map and every reinforcement point is closed.
## A point with no waves left is closed.[br]
## A unit "ends its turn" at its side's Phase End, where it records
## [constant CombatFact.Kind.UNIT_TURN_END] with its tile. Nothing is checked before turn 1, nor on
## a map with no setup. The fact's [member CombatFact.amount] is the turn the combat ended on, and
## its [member CombatFact.key] is the turns a Survive or Defend map was won early (the speed bonus
## P08 grades); 0 otherwise.[br]
## Pure rules code: it records through the session's engine and never awaits.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md
##
## @todo: TOD-001 - Cancel the waves not yet arrived in cancel_pending_waves() (P04 MP7).
## @todo: TOD-002 - Count a point a player unit closed as closed (P04 MP7); now only a point with
## no waves left is.

# ASSUMPTION: the waves' shape until P04 MP7 draws them; MP7 may add fields, never drop "turn".
## The key of [member CombatEncounter.EncounterSetup.shared] where setup step 5 puts the
## reinforcement waves (P04 MP7). Its value maps each reinforcement point's
## [member MapLayout.Marker.index], as a String, to an Array of waves, each a Dictionary whose
## [code]"turn"[/code] is its arrival turn. A point with no entry has no waves.
const WAVES_KEY: String = "reinforcement_waves"

const _ROUT: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
const _SURVIVE: CombatMapDefinition.Objective = CombatMapDefinition.Objective.SURVIVE
const _DEFEND: CombatMapDefinition.Objective = CombatMapDefinition.Objective.DEFEND


## Adds [method check] to [param session]'s [constant CombatHooks.Hook.AFTER_STEP].
static func register(session: CombatSession) -> void:
	session.hooks.add(CombatHooks.Hook.AFTER_STEP, Objectives.check)


## Records [constant CombatFact.Kind.COMBAT_ENDED] on [param session] when its map is won or lost.
## Does nothing once the map has finished, before turn 1, or with no setup.
static func check(session: CombatSession) -> void:
	if session.is_finished or session.setup == null or session.setup.map == null:
		return
	if session.state.turn < 1:
		return
	var definition: CombatMapDefinition = session.setup.map
	var winner: CombatFact.CombatSide = CombatFact.CombatSide.NONE
	# ASSUMPTION: a loss beats a win reached in the same step (the commander and the last enemy
	# falling to one exchange, or Defend's tile taken as turn N's enemy phase ends).
	if _is_lost(session):
		winner = CombatFact.CombatSide.ENEMY
	elif _is_won(session):
		winner = CombatFact.CombatSide.PLAYER
	else:
		return
	if winner == CombatFact.CombatSide.PLAYER and definition.objective == _ROUT:
		cancel_pending_waves(session)
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	ended.amount = session.state.turn
	if winner == CombatFact.CombatSide.PLAYER:
		ended.key = turns_early(session)
	session.engine.record(ended)


## The turns a Survive or Defend map ends before turn
## [member CombatMapDefinition.survive_turns]'s enemy Phase End, counting the current turn unless
## its enemy Phase End has run; 0 for the other objectives and at the end of the last turn.
static func turns_early(session: CombatSession) -> int:
	var definition: CombatMapDefinition = session.setup.map
	if definition.objective != _SURVIVE and definition.objective != _DEFEND:
		return 0
	# ASSUMPTION: the speed bonus counts whole turns not finished; P08 sets what each is worth.
	return maxi(0, definition.survive_turns - _turns_finished(session.state))


## Cancels every reinforcement wave on [param session]'s map that hasn't arrived: Rout's win
## calls it. The one entry point for that; P04 MP7 fills it in. Until then waves exist only in
## the setup result and nothing sends them, so it changes nothing.
static func cancel_pending_waves(_session: CombatSession) -> void:
	# TODO(TOD-001): Mark the session's pending waves cancelled once reinforcements exist (P04 MP7).
	pass


## The waves still to come at reinforcement point [param point_index] on [param session]'s map:
## those whose arrival turn is the current turn or later ([constant WAVES_KEY]).
static func waves_left(session: CombatSession, point_index: int) -> int:
	if session.setup == null:
		return 0
	var drawn: Variant = session.setup.shared.get(WAVES_KEY, {})
	if not drawn is Dictionary:
		return 0
	var by_point: Dictionary = drawn
	var waves: Variant = by_point.get(str(point_index), [])
	if not waves is Array:
		return 0
	var left: int = 0
	# Untyped: setup results are plain data.
	for wave: Variant in waves:
		if not wave is Dictionary:
			continue
		# A float after a JSON round trip.
		var arrival: float = (wave as Dictionary).get("turn", 0)
		if arrival >= session.state.turn:
			left += 1
	return left




static func _is_lost(session: CombatSession) -> bool:
	var state: CombatState = session.state
	# ASSUMPTION: any commander's fall loses a map shared by several seats.
	for commander_id: String in session.commander_ids.values():
		var commander: CombatUnitState = state.unit(commander_id)
		if commander != null and commander.is_defeated:
			return true
	if state.units_of(CombatFact.CombatSide.PLAYER).is_empty():
		return true
	return (
			session.setup.map.objective == _DEFEND
			and _turn_ended_on(session, CombatFact.CombatSide.ENEMY, MapLayout.MarkerKind.DEFEND)
	)


static func _is_won(session: CombatSession) -> bool:
	var definition: CombatMapDefinition = session.setup.map
	match definition.objective:
		CombatMapDefinition.Objective.ROUT:
			return session.state.units_of(CombatFact.CombatSide.ENEMY).is_empty()
		CombatMapDefinition.Objective.DEFEAT_LEADER, CombatMapDefinition.Objective.DEFEAT_BOSS:
			return _marked_enemies_defeated(session)
		CombatMapDefinition.Objective.SEIZE:
			return _turn_ended_on(
					session, CombatFact.CombatSide.PLAYER, MapLayout.MarkerKind.SEIZE
			)
		_SURVIVE, _DEFEND:
			return _has_survived(session) or _is_cleared(session)
	return false


# Whether every enemy that appeared on a leader slot is defeated; false when none did.
# ASSUMPTION: the boss or mini-boss is the enemy placed on a leader slot until P05 marks bosses.
static func _marked_enemies_defeated(session: CombatSession) -> bool:
	var state: CombatState = session.state
	var slots: Array[Vector2i] = session.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT)
	var marked: int = 0
	for fact: CombatFact in session.engine.fact_log:
		if (
				fact.kind != CombatFact.Kind.UNIT_SPAWNED
				or not slots.has(fact.tile)
				or state.side_of(fact.actor_id) != CombatFact.CombatSide.ENEMY
		):
			continue
		marked += 1
		if state.has_unit(fact.actor_id):
			return false
	return marked > 0


# Whether a unit of side recorded Unit Turn End on a tile marked kind at the Phase End just run.
static func _turn_ended_on(
		session: CombatSession, side: CombatFact.CombatSide, kind: MapLayout.MarkerKind
) -> bool:
	var state: CombatState = session.state
	if state.phase_side != side or not state.is_phase_ended:
		return false
	var tiles: Array[Vector2i] = session.layout.tiles_of(kind)
	if tiles.is_empty():
		return false
	var facts: Array[CombatFact] = session.engine.fact_log
	# Back to that Phase End: nothing after it starts a phase while is_phase_ended holds.
	for i: int in range(facts.size() - 1, -1, -1):
		var fact: CombatFact = facts[i]
		if fact.kind == CombatFact.Kind.PHASE_END:
			return false
		if (
				fact.kind == CombatFact.Kind.UNIT_TURN_END
				and tiles.has(fact.tile)
				and state.side_of(fact.actor_id) == side
		):
			return true
	return false


# Whether turn survive_turns's enemy Phase End has run. An unset count (0) never ends the map.
static func _has_survived(session: CombatSession) -> bool:
	var survive_turns: int = session.setup.map.survive_turns
	return survive_turns > 0 and _turns_finished(session.state) >= survive_turns


# Survive and Defend's early end: no enemy on the map and every reinforcement point closed.
static func _is_cleared(session: CombatSession) -> bool:
	if not session.state.units_of(CombatFact.CombatSide.ENEMY).is_empty():
		return false
	# TODO(TOD-002): A point a player unit closed is closed too (P04 MP7).
	for point: MapLayout.Marker in session.layout.markers_of(
			MapLayout.MarkerKind.REINFORCEMENT_POINT
	):
		if waves_left(session, point.index) > 0:
			return false
	return true


# Turns whose enemy Phase End has run.
static func _turns_finished(state: CombatState) -> int:
	var is_enemy_phase_over: bool = (
			state.phase_side == CombatFact.CombatSide.ENEMY and state.is_phase_ended
	)
	return state.turn if is_enemy_phase_over else state.turn - 1
