# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intents.gd
# Author:
# Created:  November 3, 2026
# Modified: November 4, 2026
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
## it up the order. Once a different plan acts, every later step decides afresh (question 10).[br]
## [b]When[/b] ([method register]): after every player Phase Start and every step of the player
## phase that recorded a fact, into [member CombatSession.intents], announced by
## [signal CombatSession.intents_changed]; P07 draws it. Not saved: derived from the battle state.
## [br]
## Rules code: pure and deterministic, no logging ([member diagnostics] carries the sandbox's).
## Main thread only: every decision creates sandboxes (question 17).
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

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
	_play(found, sandbox.engine, EnemyAI.flooded_tiles(session.state), null, no_move)
	found.diagnostics = sandbox.engine.diagnostics
	return found


## The intents if player unit [param unit_id] moved to [param tile] now, before any action, built
## on [member CombatSession.intents] (computed afresh first when stale, not stored). The latest
## intents for the unit's own tile; null when nothing keeps intents on [param session], or the unit
## can't end its move there.
static func preview(session: CombatSession, unit_id: String, tile: Vector2i) -> Intents:
	var base: Intents = session.intents
	if base == null:
		return null
	if base.based_on_seq != session.last_seq():
		base = compute(session, base._catalog)
	var state: CombatState = session.state
	if not state.has_unit(unit_id) or state.side_of(unit_id) != CombatFact.CombatSide.PLAYER:
		return null
	if state.unit(unit_id).has_acted:
		return null
	var origin: Vector2i = state.tile_of(unit_id)
	if tile == origin:
		return base
	var path: Array[Vector2i] = _path_to(session.engine, unit_id, tile)
	if path.is_empty():
		return null

	var sandbox: Sandbox = Sandbox.new(session.engine, ForecastRolls.new())
	var engine: EffectEngine = sandbox.engine
	var moved_state: CombatState = engine.state
	engine.begin_step()
	var check: CombatGrid.PathCheck = UnitTurnCommand.walk_path(engine, moved_state, unit_id, path)
	engine.drain()
	if not check.is_legal:
		return null
	var found: Intents = Intents.new()
	found._catalog = base._catalog
	found.based_on_seq = base.based_on_seq
	found.moved_unit_id = unit_id
	found.moved_to = tile
	found.danger = DangerZone.compute(engine)
	PhaseRunner.cross_to_enemy_phase(session, engine)
	var touched: Array[Vector2i] = [origin, tile]
	_play(found, engine, EnemyAI.flooded_tiles(session.state), base, touched)
	found.diagnostics = engine.diagnostics
	return found


# The phase on engine, one step per enemy: every enemy yet to act decided, as EnemyAI.next_plan
# decides them, then the best carried out. With base, each enemy decision base made at that step
# is kept while none of touched lies in its options, until a plan other than base's acts.
static func _play(
		found: Intents,
		engine: EffectEngine,
		flooded: Dictionary[Vector2i, bool],
		base: Intents,
		touched: Array[Vector2i]
) -> void:
	var state: CombatState = engine.state
	var margin: int = _effect_margin(engine)
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
# (no ally closer to the enemy), so every decision counts as touched by any move.
static func _effect_margin(engine: EffectEngine) -> int:
	var margin: int = 0
	var seen: Dictionary[EffectDefinition, bool] = {}
	for instance: EffectInstance in engine.get_instances():
		if instance.definition == null or seen.has(instance.definition):
			continue
		seen[instance.definition] = true
		var reach: int = _reach_in(instance.definition)
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


# A cheapest walk for unit_id from its tile to tile, as EnemyAI walks: each step back to the first
# neighbor, in CombatGrid.DIRECTIONS order, whose cost leads to it. Empty when it can't end there.
static func _path_to(engine: EffectEngine, unit_id: String, tile: Vector2i) -> Array[Vector2i]:
	var state: CombatState = engine.state
	var path: Array[Vector2i] = []
	if not Pathing.reach(engine, state, unit_id).has(tile):
		return path
	var mover: CombatUnitState = state.unit(unit_id)
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
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


## One step of the phase: every enemy yet to act, decided, and the decision that acted.
class Round:
	extends RefCounted

	## Each enemy's decision, by id.
	var decisions: Dictionary[String, Decision] = {}
	## The one that acted.
	var winner: Decision = null
