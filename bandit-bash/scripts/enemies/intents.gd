# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intents.gd
# Author:
# Created:  November 3, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name Intents
extends RefCounted
## The enemy phase as the AI expects it: one [EnemyIntent] per enemy, in the order they would act,
## and the [DangerZone] (enemies and AI plan, Intents and the danger zone; questions 3, 9, 10).
##
## [b]Compute[/b] ([method compute]): a [Sandbox] of the session, rolling with [ForecastRolls],
## crosses the player Phase End (every Phase End effect, darkness damage included) and the enemy
## Phase Start as the turn loop does ([method PhaseRunner.cross_to_enemy_phase]), then plays the
## phase as [method EnemyAI.next_plan] plays it: every enemy yet to act decides on the board as it
## is, the highest-rated acts with every hit landing, and the rest decide again on that board. So
## a kill that exposes a unit shows the follow-up that punishes it. The real phase decides again
## after each resolved action, so a miss changes what follows (question 8).[br]
## [b]Preview[/b] ([method preview]): the same with one player unit moved to a hovered tile, built
## on the latest intents. An enemy whose options the unit's old and new tiles don't touch keeps
## its decision from them; the rest decide again, so a move that hands a later enemy a kill moves
## it up the order. Once a different plan acts, every later step decides afresh (question 10).
## [method prepare_preview] reads the session; [method PreviewJob.run] re-plans, on any thread.[br]
## [b]When[/b] ([method register]): after every player Phase Start and every step of the player
## phase that recorded a fact, into [member CombatSession.intents], announced by
## [signal CombatSession.intents_changed]; P07 draws it. Not saved: derived from the battle state.
## [br]
## Rules code: pure and deterministic, no logging ([member diagnostics] carries the sandbox's).
## Main thread only, except [method PreviewJob.run]: everything else reads the session.
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md
##
## @todo: TOD-001 [MEDIUM] - The move preview underperforms its 50 ms target (P05 question 10;
## debug, M1 turn 1, per hover: 56 ms median and 181 ms p95 as UI3 built it, 17 ms and 33-40 ms
## after UI3F, on a worker thread; every enemy is re-planned, 6 decisions for 3 enemies) and needs
## re-architecting: see the orchestrator's design item 'Re-architect the move preview'.

## Every enemy that would act, in order ([member EnemyIntent.order]).
var enemies: Array[EnemyIntent] = []

## Every tile each enemy could attack next phase, on the board these intents read (for a preview,
## with the unit moved).
var danger: DangerZone = null

## [method CombatSession.last_seq] when these were computed: any newer fact makes them stale.
var based_on_seq: int = Command.NO_SEQ

## For a preview, the player unit moved; empty otherwise.
var moved_unit_id: String = ""

## For a preview, the tile it was moved to; [constant CombatFact.NO_TILE] otherwise.
var moved_to: Vector2i = CombatFact.NO_TILE

## Enemy decisions ([method EnemyAI.decide]) this computation made; a preview reuses the rest.
var decisions: int = 0

## The sandbox's diagnostics, for the main thread to log.
var diagnostics: PackedStringArray = []

# The catalog the enemies' classes are read from; previews built on these use it too.
var _catalog: EffectCatalog.Index = null

# One per step of the phase: every enemy yet to act, decided, and the one that acted.
var _rounds: Array[Round] = []

# For previews built on these intents, which share their board: each moved player unit's flood
# (Pathing.flood with its budget) and end tiles (Pathing.reach), by unit id. Main thread only.
var _walked_of: Dictionary[String, Dictionary] = {}
var _ends_of: Dictionary[String, Dictionary] = {}

# Each effect definition's positional reach (_reach_in), filled as margins are taken: definitions
# are read-only at runtime, so a reach never changes. Main thread only.
var _reaches: Dictionary[EffectDefinition, int] = {}


## The intent of [param unit_id]; null for an enemy that doesn't act (one defeated first).
func intent_of(unit_id: String) -> EnemyIntent:
	for intent: EnemyIntent in enemies:
		if intent.unit_id == unit_id:
			return intent
	return null


## Keeps [param session]'s [member CombatSession.intents] current, reading enemy classes from
## [param catalog]: [method refresh] on [constant CombatHooks.Hook.INTENTS] and
## [constant CombatHooks.Hook.AFTER_STEP]. Once per session, after the AI and the reinforcement
## warnings, so the intents read the board those leave.
static func register(session: CombatSession, catalog: EffectCatalog.Index) -> void:
	var run: Callable = Intents.refresh.bind(catalog)
	session.hooks.add(CombatHooks.Hook.INTENTS, run)
	session.hooks.add(CombatHooks.Hook.AFTER_STEP, run)


## The registration: during an open player phase, when a fact has been recorded since the latest
## intents, computes new ones into [member CombatSession.intents], hands their diagnostics to the
## engine and emits [signal CombatSession.intents_changed]. Records nothing on the map.
static func refresh(session: CombatSession, catalog: EffectCatalog.Index) -> void:
	var state: CombatState = session.state
	if session.is_finished or state.phase_side != CombatFact.CombatSide.PLAYER:
		return
	# No intents in the opening swap window, before turn 1's Phase Start runs (question 23).
	if state.is_phase_ended or state.map.opening_swap_open:
		return
	if session.intents != null and session.intents.based_on_seq == session.last_seq():
		return
	var latest: Intents = compute(session, catalog)
	for line: String in latest.diagnostics:
		session.engine.diagnostics.append("Intents: %s" % [line])
	session.intents = latest
	session.intents_changed.emit(latest)


## The intents of [param session]'s enemies on its board as it stands, if the player phase ended
## now, their classes read from [param catalog]. Changes nothing on the map.
static func compute(session: CombatSession, catalog: EffectCatalog.Index) -> Intents:
	var found: Intents = Intents.new()
	found._catalog = catalog
	found.based_on_seq = session.last_seq()
	var sandbox: Sandbox = Sandbox.new(session.engine, ForecastRolls.new())
	found.danger = DangerZone.compute(sandbox.engine)
	PhaseRunner.cross_to_enemy_phase(session, sandbox.engine)
	var no_move: Array[Vector2i] = []
	var margin: int = _effect_margin(sandbox.engine, found._reaches)
	_play(found, sandbox.engine, EnemyAI.flooded_tiles(session.state), null, no_move, margin)
	found.diagnostics = sandbox.engine.diagnostics
	return found


# TODO(TOD-001): [MEDIUM] The move preview underperforms its 50 ms target (P05 question 10;
# debug, M1 turn 1, per hover: 56 ms median and 181 ms p95 as UI3 built it, 17 ms and 33-40 ms
# after UI3F, on a worker thread; every enemy is re-planned, 6 decisions for 3 enemies) and needs
# re-architecting: see the orchestrator's design item 'Re-architect the move preview'.
## The intents if player unit [param unit_id] moved to [param tile] now, before any action, built
## on [member CombatSession.intents] (computed afresh first when stale, not stored). The latest
## intents for the unit's own tile; null when nothing keeps intents on [param session], or the unit
## can't end its move there. [method prepare_preview], then [method PreviewJob.run], here.
static func preview(session: CombatSession, unit_id: String, tile: Vector2i) -> Intents:
	return prepare_preview(session, unit_id, tile).run()


## The part of [method preview] that reads [param session], for [method PreviewJob.run] to finish:
## the checks, a [Sandbox] of the session with the unit walked to [param tile], its danger zone,
## and the phase boundary crossed there, which runs the session's registrations. Main thread only.
## [br]Returns a job whose [method PreviewJob.run] gives what [method preview] would.
static func prepare_preview(session: CombatSession, unit_id: String, tile: Vector2i) -> PreviewJob:
	var job: PreviewJob = PreviewJob.new()
	var base: Intents = session.intents
	if base == null:
		return job
	if base.based_on_seq != session.last_seq():
		base = compute(session, base._catalog)
	var state: CombatState = session.state
	if not state.has_unit(unit_id) or state.side_of(unit_id) != CombatFact.CombatSide.PLAYER:
		return job
	if state.unit(unit_id).has_acted:
		return job
	var origin: Vector2i = state.tile_of(unit_id)
	if tile == origin:
		job._result = base
		return job
	var path: Array[Vector2i] = base._path_to(session.engine, unit_id, tile)
	if path.is_empty():
		return job

	var sandbox: Sandbox = Sandbox.new(session.engine, ForecastRolls.new())
	var engine: EffectEngine = sandbox.engine
	# Verify mode rebuilds every cached sheet read to check it, a debug-only check that took most
	# of a preview's time; it changes no result, and the session's own reads keep it.
	engine.verify = false
	var moved_state: CombatState = engine.state
	engine.begin_step()
	var check: CombatGrid.PathCheck = UnitTurnCommand.walk_path(engine, moved_state, unit_id, path)
	engine.drain()
	if not check.is_legal:
		return job
	var found: Intents = Intents.new()
	found._catalog = base._catalog
	found.based_on_seq = base.based_on_seq
	found.moved_unit_id = unit_id
	found.moved_to = tile
	found.danger = DangerZone.compute(engine)
	PhaseRunner.cross_to_enemy_phase(session, engine)
	job._found = found
	job._engine = engine
	job._flooded = EnemyAI.flooded_tiles(session.state)
	job._base = base
	job._touched = [origin, tile]
	job._margin = _effect_margin(engine, base._reaches)
	return job


# The phase on engine, one step per enemy: every enemy yet to act decided, as EnemyAI.next_plan
# decides them, then the best carried out. With base, each enemy decision base made at that step
# is kept while none of touched lies in its options, until a plan other than base's acts. margin:
# _effect_margin of engine as it starts. Pure on engine: PreviewJob.run calls it on a worker.
static func _play(
		found: Intents,
		engine: EffectEngine,
		flooded: Dictionary[Vector2i, bool],
		base: Intents,
		touched: Array[Vector2i],
		margin: int
) -> void:
	var state: CombatState = engine.state
	var is_reusing: bool = base != null and margin >= 0
	for step: int in state.units_of(CombatFact.CombatSide.ENEMY).size():
		var known: Round = null
		if is_reusing and step < base._rounds.size():
			known = base._rounds[step]
		var round_of: Round = Round.new()
		var best: Decision = null
		# NOTE: the same enemies, order and tie rule as EnemyAI.next_plan; change both together.
		for unit_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
			if state.unit(unit_id).has_acted:
				continue
			var decision: Decision = null
			if known != null and known.decisions.has(unit_id):
				decision = known.decisions[unit_id]
				if decision.touches(touched):
					decision = null
			if decision == null:
				decision = _decide(engine, found._catalog, unit_id, flooded, margin)
				found.decisions += 1
			round_of.decisions[unit_id] = decision
			if best == null or decision.plan.is_better_than(best.plan):
				best = decision
		if best == null:
			return
		is_reusing = known != null and best == known.winner
		round_of.winner = best
		found._rounds.append(round_of)
		var definition: EnemyClassDefinition = null
		if found._catalog != null:
			definition = found._catalog.enemy_class(state.unit_type_of(best.plan.actor_id))
		found.enemies.append(EnemyIntent.from_plan(engine, best.plan, step, definition))
		_carry_out(engine, best.plan)


# unit_id's decision on engine's board, with the tiles a moved player unit would have to touch to
# change it.
static func _decide(
		engine: EffectEngine,
		catalog: EffectCatalog.Index,
		unit_id: String,
		flooded: Dictionary[Vector2i, bool],
		margin: int
) -> Decision:
	var decision: Decision = Decision.new()
	decision.plan = EnemyAI.decide(engine, catalog, unit_id, flooded)
	var plan: EnemyPlan = decision.plan
	if plan.kind == EnemyPlan.Kind.WAIT and plan.target_rule_id.is_empty():
		return decision
	# Support rates every end tile by every player unit's reach, an advance follows the nearest foe
	# anywhere on the map, and a Wait with a class had no foe in reach: any move can change them.
	decision.is_global = (
			margin < 0
			or plan.behavior == EnemyClassDefinition.Behavior.SUPPORT
			or plan.kind != EnemyPlan.Kind.ATTACK
	)
	if not decision.is_global:
		decision.zone = _zone_of(engine, unit_id, margin)
	return decision


# The tiles whose occupant can change an attacking enemy's options: every tile it can walk
# through, and every tile within its longest range plus margin of one, so the units it could
# attack, whoever blocks or frees its path, and whoever the effects around a target or its splash
# reach all fall inside.
static func _zone_of(
		engine: EffectEngine, unit_id: String, margin: int
) -> Dictionary[Vector2i, bool]:
	var state: CombatState = engine.state
	var mover: CombatUnitState = state.unit(unit_id)
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
	var longest: int = 1
	for span: Vector2i in DangerZone.attack_ranges(engine, unit_id):
		longest = maxi(longest, span.y)
	var around: Vector2i = Vector2i(0, longest + margin)
	var zone: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in walked:
		for near: Vector2i in DangerZone.tiles_within(tile, around):
			zone[near] = true
	return zone


# How far any effect on engine's map reaches from a unit by position: the largest Area radius and
# "within N tiles" or adjacency test in any effect's definition; -1 when one reads the whole map
# (no ally closer to the enemy), so every decision counts as touched by any move. reaches: each
# definition's _reach_in, read and filled here.
static func _effect_margin(engine: EffectEngine, reaches: Dictionary[EffectDefinition, int]) -> int:
	var margin: int = 0
	for instance: EffectInstance in engine.get_instances():
		var definition: EffectDefinition = instance.definition
		if definition == null:
			continue
		if not reaches.has(definition):
			reaches[definition] = _reach_in(definition)
		var reach: int = reaches[definition]
		if reach < 0:
			return -1
		margin = maxi(margin, reach)
	return margin


# The largest positional reach in block and every resource it stores; -1 for the whole map.
static func _reach_in(block: Object) -> int:
	var found: int = 0
	if block is Area:
		found = (block as Area).radius
	if block is WhilePositionCondition:
		var position: WhilePositionCondition = block
		match position.kind:
			WhilePositionCondition.Kind.NO_ALLY_CLOSER_TO_ENEMY:
				return -1
			WhilePositionCondition.Kind.WITHIN:
				found = maxi(found, position.tiles)
			WhilePositionCondition.Kind.ADJACENT_TO:
				found = maxi(found, 1)
	# Every stored resource, so a selector nested in an operation or a value source counts.
	for property: Dictionary in block.get_property_list():
		var usage: int = property["usage"]
		var kind: int = property["type"]
		if usage & PROPERTY_USAGE_STORAGE == 0 or (kind != TYPE_OBJECT and kind != TYPE_ARRAY):
			continue
		var property_name: StringName = property["name"]
		var value: Variant = block.get(property_name)
		var children: Array = value if value is Array else [value]
		for child: Variant in children:
			if not (child is Resource) or child is Script:
				continue
			var inner: int = _reach_in(child as Resource)
			if inner < 0:
				return -1
			found = maxi(found, inner)
	return found


# Carries plan out on engine as UnitTurnCommand.resolve would: the walk, then the action. A plan
# that resolves to no action becomes a Wait, as EnemyAI.next_command makes a rejected one.
static func _carry_out(engine: EffectEngine, plan: EnemyPlan) -> void:
	var state: CombatState = engine.state
	var actor: String = plan.actor_id
	engine.begin_step()
	UnitTurnCommand.walk_path(engine, state, actor, plan.path)
	match plan.kind:
		EnemyPlan.Kind.ATTACK:
			var unit: CombatUnitState = state.unit(actor)
			if not plan.weapon_id.is_empty() and plan.weapon_id != unit.equipped_weapon_id:
				WeaponSwap.resolve(engine, state, actor, true)
			ExchangeResolver.resolve(engine, state, actor, plan.target_id)
		EnemyPlan.Kind.STAFF:
			StaffResolver.resolve(engine, state, actor, plan.target_id)
	if state.has_unit(actor) and not state.unit(actor).has_acted:
		state.wait(engine, actor)
	engine.drain()


# A cheapest walk for unit_id from its tile to tile on engine, the board these intents read, as
# EnemyAI walks: each step back to the first neighbor, in CombatGrid.DIRECTIONS order, whose cost
# leads to it. Empty when it can't end there. The unit's flood and end tiles are kept for the next
# hover: the board can't change without a fact, which makes these intents stale.
func _path_to(engine: EffectEngine, unit_id: String, tile: Vector2i) -> Array[Vector2i]:
	var state: CombatState = engine.state
	var path: Array[Vector2i] = []
	if not _ends_of.has(unit_id):
		_ends_of[unit_id] = Pathing.reach(engine, state, unit_id)
	var ends: Dictionary[Vector2i, int] = _ends_of[unit_id]
	if not ends.has(tile):
		return path
	var mover: CombatUnitState = state.unit(unit_id)
	if not _walked_of.has(unit_id):
		_walked_of[unit_id] = Pathing.flood(
				state,
				mover.tile,
				Pathing.budget_of(engine, state, unit_id),
				mover.movement_type,
				mover.side
		)
	var walked: Dictionary[Vector2i, int] = _walked_of[unit_id]
	path.append(tile)
	var at: Vector2i = tile
	while at != mover.tile:
		var entry: int = state.grid.move_cost(at, mover.movement_type)
		var came_from: Vector2i = CombatFact.NO_TILE
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			var before: Vector2i = state.grid.step(at, direction)
			if walked.has(before) and walked[before] + entry == walked[at]:
				came_from = before
				break
		if came_from == CombatFact.NO_TILE:
			path.clear()
			return path
		path.push_front(came_from)
		at = came_from
	return path


## One enemy's decision at one step, with what a moved player unit must touch to change it.
class Decision:
	extends RefCounted

	## The plan [method EnemyAI.decide] gave.
	var plan: EnemyPlan = null
	## Whether any move can change it: Support, a move or a Wait, or an effect reading the map.
	var is_global: bool = false
	## Otherwise, the tiles whose occupant can change it; empty for an enemy with no class.
	var zone: Dictionary[Vector2i, bool] = {}

	## Whether a unit leaving or entering any of [param tiles] can change this decision.
	func touches(tiles: Array[Vector2i]) -> bool:
		if is_global:
			return true
		for tile: Vector2i in tiles:
			if zone.has(tile):
				return true
		return false


## A move preview between [method Intents.prepare_preview], on the main thread, and [method run],
## on any thread: the sandbox it re-plans on and the intents it builds on. It shares nothing
## mutable with the session, so the session may resolve commands while it runs.
class PreviewJob:
	extends RefCounted

	# The answer prepare_preview found without re-planning (null, or the base intents), then run's.
	var _result: Intents = null
	# What run re-plans, all set together by prepare_preview; cleared once it has run.
	var _found: Intents = null
	var _engine: EffectEngine = null
	var _flooded: Dictionary[Vector2i, bool] = {}
	var _base: Intents = null
	var _touched: Array[Vector2i] = []
	var _margin: int = 0

	## The previewed intents, re-planning the enemies on the first call; later calls return the
	## same. Pure rules code on the job's own sandbox, reading only the base intents and content
	## definitions: no session, node, autoload or log, so it may run on a worker thread, one call
	## at a time. The sandbox's diagnostics are in [member Intents.diagnostics].
	func run() -> Intents:
		if _found == null:
			return _result
		Intents._play(_found, _engine, _flooded, _base, _touched, _margin)
		_found.diagnostics = _engine.diagnostics
		_result = _found
		_found = null
		_engine = null
		_base = null
		return _result


## One step of the phase: every enemy yet to act, decided, and the decision that acted.
class Round:
	extends RefCounted

	## Each enemy's decision, by id.
	var decisions: Dictionary[String, Decision] = {}
	## The one that acted.
	var winner: Decision = null
