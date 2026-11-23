# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intents.gd
# Author:
# Created:  November 3, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name Intents
extends RefCounted
## The enemy phase as the AI expects it: one [EnemyIntent] per enemy, in the order they would act,
## and the [DangerZone] (enemies and AI plan, Intents and the danger zone; questions 3, 9, 10).
##
## [b]Compute[/b] ([method compute]): a [Sandbox] of the session, rolling with [ForecastRolls],
## crosses the player Phase End (every Phase End effect) and the enemy
## Phase Start as the turn loop does ([method PhaseRunner.cross_to_enemy_phase]), then plays the
## phase as [method EnemyAI.next_plan] plays it: every enemy yet to act decides on the board as it
## is, the highest-rated acts with every hit landing, and the rest decide again on that board. So
## a kill that exposes a unit shows the follow-up that punishes it. The real phase decides again
## after each resolved action, so a miss changes what follows (question 8).[br]
## [b]Preview[/b] ([method preview]): the same with one player unit moved to a hovered tile, built
## on the latest intents. An enemy keeps its decision while no tile where the boards differ can
## change what it read ([EnemyAI.Footprint]); the rest decide again, so a move handing a later
## enemy a kill moves it up the order; once a different plan acts, later steps decide afresh
## (question 10). [method prepare_preview] reads the session; [method PreviewJob.run] re-plans.[br]
## [b]When[/b] ([method register]): after every player Phase Start and every step of the player
## phase that recorded a fact, into [member CombatSession.intents], announced by
## [signal CombatSession.intents_changed]; P07 draws it. Not saved: derived from the battle state.
## [br]
## Rules code: pure and deterministic, no logging ([member diagnostics] carries the sandbox's).
## Main thread only, except [method PreviewJob.run]: everything else reads the session.
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md
##
## @todo: TOD-001 [MEDIUM] - A hover on a tile the sweep hasn't reached meets the 50 ms target
## only on M1: unswept, in debug, median / p95, the 9-enemy key board 203 / 326 ms and the boss
## board 657 / 1,043 ms (release 158 / 245, 456 / 736), more while a sweep preview runs. On
## engaged boards the moved unit stands within most enemies' reach, so few decisions are kept.
## Swept tiles are a lookup; the options left are in move-preview.md (Where it stands).

## The text a checking-mode difference starts with in [member diagnostics].
const CHECK_PREFIX: String = "check: "

# How many attack forecasts previews may add to the latest intents' store, for later previews to
# reuse, the oldest dropped first: about 60 to 90 MB in debug on the 9-enemy bench boards, kept
# until the next fact. The computation's own are kept besides.
const _PREVIEW_FORECASTS: int = 2000

## Checking mode, as [member EffectEngine.verify] is for stat sheets: a preview also decides
## afresh every decision it keeps from the latest intents, and reports each that differs in
## [member diagnostics], starting [constant CHECK_PREFIX]. Results never change. Off by default
## and ignored outside debug builds; [method prepare_preview] reads it, so a running job keeps the
## value it started with. Tests and debug runs set it on the main thread.
static var is_checking: bool = false

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

## Kept decisions and reused attack forecasts that checking mode ([member is_checking]) made afresh
## and compared; 0 when it is off. Not counted in [member decisions].
var checked: int = 0

## Attack forecasts this computation's decisions reused from its store ([EnemyAI.ForecastStore]),
## and made afresh.
var forecasts_reused: int = 0
var forecasts_made: int = 0

## The sandbox's diagnostics, for the main thread to log.
var diagnostics: PackedStringArray = []

# The catalog the enemies' classes are read from; previews built on these use it too.
var _catalog: EffectCatalog.Index = null

# The tiles the player side must reach (EnemyAI.objective_tiles), read from the session with the
# catalog; previews built on these use them too.
var _objective: Array[Vector2i] = []

# One per step of the phase: every enemy yet to act, decided, and the one that acted.
var _rounds: Array[Round] = []

# The signature moves the crossed enemy Phase Start fired, by their enemy (_signatures_fired).
var _signatures: Dictionary[String, Signature] = {}

# For previews built on these intents, which share their board: each moved player unit's flood
# (Pathing.flood with its budget) and end tiles (Pathing.reach), by unit id. Main thread only.
var _walked_of: Dictionary[String, Dictionary] = {}
var _ends_of: Dictionary[String, Dictionary] = {}

# Each effect definition's positional reach (_reach_in), filled as margins are taken: definitions
# are read-only at runtime, so a reach never changes. Main thread only.
var _reaches: Dictionary[EffectDefinition, int] = {}

# The attack forecasts compute made, which every preview built on these intents reuses and adds
# to; dropped with them, when a fact makes them stale.
var _forecasts: EnemyAI.ForecastStore = null

# What compute's crossing of the phase boundary recorded, each fact with its line (_fact_line),
# and the tile of every unit and object on the board it crossed to (_board_tiles): a preview
# finds what its move changed by comparing its own walk and crossing with these.
var _crossing: Array[CombatFact] = []
var _crossing_lines: PackedStringArray = []
var _crossed_tiles: Dictionary[String, Vector2i] = {}


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
## now, their classes read from [param catalog]. An enemy whose signature move the crossed enemy
## Phase Start fires, or its own action fires (the Bloodhound's kill), shows
## [constant EnemyIntent.Kind.SIGNATURE], the phase before it fires
## ([method EnemyIntent.show_signature]); previews do the same. Changes nothing on the map.
static func compute(session: CombatSession, catalog: EffectCatalog.Index) -> Intents:
	var found: Intents = Intents.new()
	found._catalog = catalog
	found._objective = EnemyAI.objective_tiles(session)
	found.based_on_seq = session.last_seq()
	var sandbox: Sandbox = Sandbox.new(session.engine, ForecastRolls.new())
	# Verify mode rebuilds every cached sheet read to check it, a debug-only check that took about
	# four fifths of a refresh; it changes no result, the session's own reads keep it, and so does
	# checking mode, which tests run.
	sandbox.engine.verify = sandbox.engine.verify and is_checking
	found.danger = DangerZone.compute(sandbox.engine)
	var crossed_from: int = sandbox.engine.fact_log.size()
	PhaseRunner.cross_to_enemy_phase(session, sandbox.engine)
	found._signatures = _signatures_fired(sandbox.engine, catalog, crossed_from)
	for index: int in range(crossed_from, sandbox.engine.fact_log.size()):
		var fact: CombatFact = sandbox.engine.fact_log[index]
		found._crossing.append(fact)
		found._crossing_lines.append(_fact_line(fact))
	var crossed: CombatState = sandbox.engine.state
	found._crossed_tiles = _board_tiles(crossed)
	var no_move: Array[Vector2i] = []
	var margin: int = _effect_margin(sandbox.engine, found._reaches)
	found._forecasts = EnemyAI.ForecastStore.new(_PREVIEW_FORECASTS)
	var forecasts: EnemyAI.Forecasts = EnemyAI.Forecasts.new(
			found._forecasts, margin, is_checking and OS.is_debug_build(), true
	)
	_play(
			found,
			sandbox.engine,
			EnemyAI.flooded_tiles(session.state),
			null,
			no_move,
			margin,
			false,
			forecasts
	)
	_take_forecasts(found, sandbox.engine, forecasts)
	found.diagnostics = sandbox.engine.diagnostics
	return found


# TODO(TOD-001): [MEDIUM] A hover on a tile the sweep hasn't reached meets the 50 ms target
# only on M1: unswept, in debug, median / p95, the 9-enemy key board 203 / 326 ms and the boss
# board 657 / 1,043 ms (release 158 / 245, 456 / 736), more while a sweep preview runs. On
# engaged boards the moved unit stands within most enemies' reach, so few decisions are kept.
# Swept tiles are a lookup; the options left are in move-preview.md (Where it stands).
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
	var walked_from: int = engine.fact_log.size()
	engine.begin_step()
	var check: CombatGrid.PathCheck = UnitTurnCommand.walk_path(engine, moved_state, unit_id, path)
	engine.drain()
	if not check.is_legal:
		return job
	var found: Intents = Intents.new()
	found._catalog = base._catalog
	found._objective = base._objective
	found.based_on_seq = base.based_on_seq
	found.moved_unit_id = unit_id
	found.moved_to = tile
	found.danger = _danger_after_walk(session, engine, base, walked_from)
	var crossed_from: int = engine.fact_log.size()
	PhaseRunner.cross_to_enemy_phase(session, engine)
	found._signatures = _signatures_fired(engine, base._catalog, crossed_from)
	job._found = found
	job._engine = engine
	job._flooded = EnemyAI.flooded_tiles(session.state)
	job._base = base
	job._changed_from = walked_from
	job._margin = _effect_margin(engine, base._reaches)
	job._is_checking = is_checking and OS.is_debug_build()
	job._forecasts = base._forecasts
	return job


# The phase on engine, one step per enemy: every enemy yet to act decided, as EnemyAI.next_plan
# decides them, then the best carried out. With base, each enemy decision base made at that step
# is kept while no tile of touched (where engine's board differs from base's, _changed_tiles) can
# change it (Decision.touches), until a plan other than base's acts or a second move goes
# elsewhere. margin: _effect_margin of engine as it starts. checking: also decide each kept one
# afresh (_check_kept). forecasts: the attack forecasts every decision reuses and adds to, across
# steps. job: stops before a step once it is cancelled, found left part-built. Pure on engine:
# PreviewJob.run calls it on a worker.
static func _play(
		found: Intents,
		engine: EffectEngine,
		flooded: Dictionary[Vector2i, bool],
		base: Intents,
		touched: Array[Vector2i],
		margin: int,
		checking: bool = false,
		forecasts: EnemyAI.Forecasts = null,
		job: PreviewJob = null
) -> void:
	var state: CombatState = engine.state
	var is_reusing: bool = base != null and margin >= 0
	for step: int in state.units_of(CombatFact.CombatSide.ENEMY).size():
		if job != null and job._is_asked_to_stop():
			return
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
				if decision.touches(touched, engine, found.moved_unit_id, margin):
					decision = null
				elif checking:
					_check_kept(found, engine, unit_id, step, decision, flooded, margin)
			if decision == null:
				decision = _decide(
						engine,
						found._catalog,
						unit_id,
						flooded,
						margin,
						found._objective,
						forecasts
				)
				found.decisions += 1
			round_of.decisions[unit_id] = decision
			if best == null or decision.plan.is_better_than(best.plan):
				best = decision
		if best == null:
			return
		round_of.winner = best
		found._rounds.append(round_of)
		var definition: EnemyClassDefinition = null
		if found._catalog != null:
			definition = found._catalog.enemy_class(state.unit_type_of(best.plan.actor_id))
		var intent: EnemyIntent = EnemyIntent.from_plan(engine, best.plan, step, definition)
		var fired: Signature = found._signatures.get(best.plan.actor_id, null)
		if fired != null:
			intent.show_signature(fired.name, fired.area)
		found.enemies.append(intent)
		var acted_from: int = engine.fact_log.size()
		round_of.second_path = _carry_out(engine, best.plan, found, flooded)
		# A kept plan acts as it did on base's board, but its second move is decided afresh: one
		# that goes elsewhere leaves the boards differing past touched, so reuse stops there.
		is_reusing = (
				known != null
				and best == known.winner
				and round_of.second_path == known.second_path
		)
		# A signature move that fires while it acts (the Bloodhound's, on a kill) shows on the
		# action that sets it off.
		if fired == null:
			var on_action: Signature = _signatures_fired(engine, found._catalog, acted_from).get(
					best.plan.actor_id, null
			)
			if on_action != null:
				intent.show_signature(on_action.name, on_action.area)


# Checking mode for one decision kept at step: decides unit_id afresh on engine, as a preview
# would without reuse (no kept forecasts either), and adds a CHECK_PREFIX line to engine's
# diagnostics when the plans differ (_plan_text). Counts it in found.checked, never in
# found.decisions; changes no result.
static func _check_kept(
		found: Intents,
		engine: EffectEngine,
		unit_id: String,
		step: int,
		kept: Decision,
		flooded: Dictionary[Vector2i, bool],
		margin: int
) -> void:
	var fresh: Decision = _decide(
			engine, found._catalog, unit_id, flooded, margin, found._objective
	)
	found.checked += 1
	var was: String = _plan_text(kept.plan)
	var now: String = _plan_text(fresh.plan)
	if was != now:
		engine.diagnostics.append("%sstep %d, %s kept [%s], a re-plan gives [%s]" % [
			CHECK_PREFIX, step, unit_id, was, now,
		])


# Takes forecasts' counts into found, and each forecast checking mode found changed into engine's
# diagnostics as a CHECK_PREFIX line.
static func _take_forecasts(
		found: Intents, engine: EffectEngine, forecasts: EnemyAI.Forecasts
) -> void:
	found.forecasts_reused = forecasts.reused
	found.forecasts_made = forecasts.made
	found.checked += forecasts.checked
	for mismatch: String in forecasts.mismatches:
		engine.diagnostics.append("%sforecast %s" % [CHECK_PREFIX, mismatch])


# plan as one line holding everything a re-plan must reproduce: its kind, target, weapon, path,
# rating and the outcome of its forecast for every unit.
static func _plan_text(plan: EnemyPlan) -> String:
	var parts: PackedStringArray = [
		plan.actor_id, EnemyPlan.Kind.find_key(plan.kind), plan.target_id, plan.weapon_id,
		str(plan.path), str(plan.tile), str(plan.is_kill), str(plan.kill_chance),
		str(plan.target_rule_key), str(plan.value), str(plan.safety), str(plan.progress),
		EnemyPlan.Step.find_key(plan.decided_by),
	]
	if plan.forecast != null:
		for outcome: CombatForecast.UnitOutcome in plan.forecast.units:
			parts.append("%s %d>%d b%d>%d s%d>%d %s>%s %s" % [
				outcome.unit_id, outcome.hp_before, outcome.hp_after, outcome.block_before,
				outcome.block_after, outcome.stance_before, outcome.stance_after,
				outcome.tile_before, outcome.tile_after, outcome.is_defeated,
			])
	return " ".join(parts)


# Where a preview's board, engine with its walk and crossing recorded from fact from on, differs
# from base's crossed board (move-preview.md, layer 1): each fact one recorded and the other didn't
# (compared as _fact_line, in any order) adds its tile and the tiles, on both boards, of the units
# and objects it names. Rules code records a fact for every change, so a tile not returned holds
# the same unit in the same state on both. Returns [CombatFact.NO_TILE] when such a fact names
# something else, such as an effect with no holder, which can reach every unit.
static func _changed_tiles(base: Intents, engine: EffectEngine, from: int) -> Array[Vector2i]:
	# By facts, not the moved unit's two tiles: a Phase End effect or a keg thrown during the
	# crossing can change a unit or tile far from both.
	var unmatched: Dictionary[String, int] = {}
	for line: String in base._crossing_lines:
		unmatched[line] = unmatched.get(line, 0) + 1
	var differing: Array[CombatFact] = []
	for index: int in range(from, engine.fact_log.size()):
		var fact: CombatFact = engine.fact_log[index]
		var line: String = _fact_line(fact)
		if unmatched.get(line, 0) > 0:
			unmatched[line] -= 1
		else:
			differing.append(fact)
	for index: int in base._crossing.size():
		var line: String = base._crossing_lines[index]
		if unmatched.get(line, 0) > 0:
			unmatched[line] -= 1
			differing.append(base._crossing[index])
	var touched: Dictionary[Vector2i, bool] = {}
	var state: CombatState = engine.state
	var now: Dictionary[String, Vector2i] = _board_tiles(state)
	var everywhere: Array[Vector2i] = [CombatFact.NO_TILE]
	for fact: CombatFact in differing:
		if not _add_named(fact, now, base._crossed_tiles, touched):
			return everywhere
	var tiles: Array[Vector2i] = []
	tiles.assign(touched.keys())
	return tiles


# The preview's danger zone on engine's board, session's with one unit walked (its facts recorded
# from fact from on): base's, each enemy whose reach covers a tile the walk changed recomputed
# (DangerZone.compute). Every enemy afresh when a walk fact names a map object, whose blast
# reaches past any enemy's walk, or something off the board.
static func _danger_after_walk(
		session: CombatSession, engine: EffectEngine, base: Intents, from: int
) -> DangerZone:
	var touched: Dictionary[Vector2i, bool] = {}
	var walked: CombatState = engine.state
	var now: Dictionary[String, Vector2i] = _board_tiles(walked)
	var was: Dictionary[String, Vector2i] = _board_tiles(session.state)
	var objects: Dictionary[String, MapState.ObjectState] = session.state.map.objects
	for index: int in range(from, engine.fact_log.size()):
		var fact: CombatFact = engine.fact_log[index]
		var names_object: bool = objects.has(fact.actor_id) or objects.has(fact.target_id)
		if names_object or not _add_named(fact, now, was, touched):
			return DangerZone.compute(engine)
	var tiles: Array[Vector2i] = []
	tiles.assign(touched.keys())
	return DangerZone.compute(engine, base.danger, tiles, _effect_margin(engine, base._reaches))


# Adds to touched fact's tile and the tiles in now and was (two boards' _board_tiles) of the units
# and objects it names. Returns false when it names an id neither board holds.
static func _add_named(
		fact: CombatFact,
		now: Dictionary[String, Vector2i],
		was: Dictionary[String, Vector2i],
		touched: Dictionary[Vector2i, bool]
) -> bool:
	if fact.tile != CombatFact.NO_TILE:
		touched[fact.tile] = true
	for id: String in [fact.actor_id, fact.target_id]:
		if id.is_empty():
			continue
		if not now.has(id) and not was.has(id):
			return false
		for tiles: Dictionary[String, Vector2i] in [now, was]:
			var tile: Vector2i = tiles.get(id, CombatFact.NO_TILE)
			if tile != CombatFact.NO_TILE:
				touched[tile] = true
	return true


# The tile of every unit and map object on state's map, by id.
static func _board_tiles(state: CombatState) -> Dictionary[String, Vector2i]:
	var tiles: Dictionary[String, Vector2i] = {}
	for unit_id: String in state.unit_ids():
		tiles[unit_id] = state.tile_of(unit_id)
	for object_id: String in state.map.objects:
		var spot: MapState.ObjectState = state.map.objects[object_id]
		tiles[object_id] = spot.tile
	return tiles


# fact as one line holding every field but its seq and session id.
static func _fact_line(fact: CombatFact) -> String:
	return "%d %s %s %d %d %d %d %d %s %s %d %d %s %d %s" % [
		fact.kind, fact.actor_id, fact.target_id, fact.amount, fact.hp_amount, fact.block_amount,
		fact.damage_type, fact.source, fact.source_effect_id, fact.tile, fact.flags, fact.side,
		fact.item_id, fact.key, fact.unit_types,
	]


# unit_id's decision on engine's board, with what it read (EnemyAI.Footprint), so a preview can
# tell the tiles a change must touch to change it. objective: the tiles the player side must reach
# (EnemyAI.objective_tiles). forecasts: the attack forecasts it may reuse; null makes each afresh.
static func _decide(
		engine: EffectEngine,
		catalog: EffectCatalog.Index,
		unit_id: String,
		flooded: Dictionary[Vector2i, bool],
		margin: int,
		objective: Array[Vector2i],
		forecasts: EnemyAI.Forecasts = null
) -> Decision:
	var decision: Decision = Decision.new()
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	decision.plan = EnemyAI.decide(
			engine, catalog, unit_id, flooded, objective, forecasts, footprint
	)
	decision.footprint = footprint
	decision.margin = margin
	# An effect reading the whole map can change any decision.
	decision.is_global = margin < 0 or footprint.is_whole
	return decision


# How far any effect on engine's map reaches from a unit by position: the largest Area shape and
# "within N tiles" or adjacency test in any effect's definition, and the powder kegs' blasts
# chained end to end (a keg in range can kill a unit one blast past it, or past a chain); -1 when
# one reads the whole map (no ally closer to the enemy), so every decision counts as touched by
# any move. reaches: each definition's _reach_in, read and filled here.
static func _effect_margin(engine: EffectEngine, reaches: Dictionary[EffectDefinition, int]) -> int:
	var state: CombatState = engine.state
	var kegs: int = 0
	for keg: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.POWDER_KEG):
		if not keg.is_destroyed:
			kegs += 1
	var margin: int = kegs * _reach_in(MapObjects.KEG_BLAST)
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
	if block is TargetShape:
		# An Area's reach is its shape's farthest tile by grid distance: a square's corner is
		# twice its size away.
		for tile: Vector2i in (block as TargetShape).tiles(Vector2i.ZERO):
			found = maxi(found, absi(tile.x) + absi(tile.y))
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
# that resolves to no action becomes a Wait, as EnemyAI.next_command makes a rejected one. When
# the action leaves it free to move again, its second move follows at once, as
# EnemyAI.next_plan plays it, decided with found's catalog and objective and flooded. Returns the
# second move's path; empty for none.
static func _carry_out(
		engine: EffectEngine, plan: EnemyPlan, found: Intents, flooded: Dictionary[Vector2i, bool]
) -> Array[Vector2i]:
	var second_path: Array[Vector2i] = []
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
		EnemyPlan.Kind.LOOT, EnemyPlan.Kind.USE_OBJECT:
			MapObjects.use(engine, state, actor, plan.target_id)
	if state.has_unit(actor) and not state.unit(actor).has_acted:
		state.wait(engine, actor)
	engine.drain()
	var acts: bool = plan.kind != EnemyPlan.Kind.WAIT
	if (
			acts
			and state.has_unit(actor)
			and engine.stats(actor).is_allowed(CombatValue.Permission.MAY_MOVE_AFTER_ACTING)
	):
		var second: EnemyPlan = EnemyAI.decide_second_move(
				engine, found._catalog, actor, flooded, found._objective
		)
		if not second.path.is_empty():
			engine.begin_step()
			UnitTurnCommand.walk_path(engine, state, actor, second.path)
			engine.drain()
			second_path = second.path
	return second_path


# Every signature move engine fired from fact from on (the crossed enemy Phase Start), by the
# enemy it belongs to: an EFFECT_ACTIVATED of the effect its class names as its signature_move,
# with its label and the tiles its Area operations cover around the enemy, in row-major order.
static func _signatures_fired(
		engine: EffectEngine, catalog: EffectCatalog.Index, from: int
) -> Dictionary[String, Signature]:
	var fired: Dictionary[String, Signature] = {}
	if catalog == null:
		return fired
	var state: CombatState = engine.state
	for index: int in range(from, engine.fact_log.size()):
		var fact: CombatFact = engine.fact_log[index]
		if fact.kind != CombatFact.Kind.EFFECT_ACTIVATED:
			continue
		var instance: EffectInstance = engine.get_instance(fact.source_effect_id)
		if instance == null or instance.owner == null:
			continue
		var owner_id: String = instance.owner.subject_id()
		if fired.has(owner_id) or state.side_of(owner_id) != CombatFact.CombatSide.ENEMY:
			continue
		var definition: EnemyClassDefinition = catalog.enemy_class(state.unit_type_of(owner_id))
		if definition == null or definition.signature_move != instance.definition:
			continue
		var signature: Signature = Signature.new()
		signature.name = instance.label
		signature.area = _covered_by(state, instance.definition, state.tile_of(owner_id))
		if KegBarrage.is_barrage(instance.definition):
			signature.area = _barrage_blast(engine, from, owner_id)
		fired[owner_id] = signature
	return fired


# The tiles on engine's map the blast of the keg thrower_id threw from fact from on covers (its
# LANDED fact; KegBarrage throws at the crossed Phase Start), in row-major order; empty when it
# threw none.
static func _barrage_blast(
		engine: EffectEngine, from: int, thrower_id: String
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var state: CombatState = engine.state
	for index: int in range(from, engine.fact_log.size()):
		var fact: CombatFact = engine.fact_log[index]
		var is_landing: bool = (
				fact.kind == CombatFact.Kind.OBJECT_STATE_CHANGED
				and fact.key == MapObjects.Change.LANDED
				and fact.target_id == thrower_id
		)
		if not is_landing:
			continue
		for tile: Vector2i in MapObjects.KEG_BLAST.tiles(fact.tile):
			if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
				tiles.append(tile)
		tiles.sort_custom(EnemyPlan.tile_precedes)
		break
	return tiles


# The tiles on state's map the Area targets of definition's operations cover around its owner's
# tile owner_tile (an Area centred elsewhere has no centre at Phase Start), in row-major order.
static func _covered_by(
		state: CombatState, definition: EffectDefinition, owner_tile: Vector2i
) -> Array[Vector2i]:
	var covered: Dictionary[Vector2i, bool] = {}
	for operation: EffectOperation in definition.operations:
		var area: Area = operation.get(&"target") as Area
		if area == null or area.shape == null or area.center != Area.Center.OWNER:
			continue
		for tile: Vector2i in area.shape.tiles(owner_tile):
			if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
				covered[tile] = true
	var tiles: Array[Vector2i] = []
	tiles.assign(covered.keys())
	tiles.sort_custom(EnemyPlan.tile_precedes)
	return tiles


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


## One enemy's decision at one step, with what a change must touch to change it.
class Decision:
	extends RefCounted

	## The plan [method EnemyAI.decide] gave.
	var plan: EnemyPlan = null
	## Whether any change can change it: a lever's seal, or an effect reading the whole map.
	var is_global: bool = false
	## What it read of the board; it reads nothing for an enemy with no class.
	var footprint: EnemyAI.Footprint = null
	## The effect margin it was decided with: the largest positional reach of any effect on the map.
	var margin: int = 0

	## Whether a change on any of [param tiles] can change this decision: a unit entering, leaving
	## or changing there. [param engine]: the board it is asked for, with player unit
	## [param moved_id] moved, whose threat counts it compares; without it, any decision counting
	## threats is touched. [param board_margin]: that board's effect margin, when larger.
	func touches(
			tiles: Array[Vector2i],
			engine: EffectEngine = null,
			moved_id: String = "",
			board_margin: int = 0
	) -> bool:
		if is_global:
			return true
		if footprint == null:
			return false
		var widest: int = maxi(margin, board_margin)
		for tile: Vector2i in tiles:
			if footprint.can_change(tile, widest):
				return true
		return footprint.threat_changed(engine, tiles, moved_id)


## A move preview between [method Intents.prepare_preview], on the main thread, and [method run],
## on any thread: the sandbox it re-plans on and the intents it builds on. It shares nothing
## mutable with the session, so the session may resolve commands while it runs. [method cancel]
## stops it from another thread at its next step, keeping nothing.
class PreviewJob:
	extends RefCounted

	# Guards the three flags below, which cancel sets from one thread while run reads them on
	# another.
	var _lock: Mutex = Mutex.new()
	var _is_cancel_asked: bool = false
	var _is_stopped: bool = false
	var _has_ended: bool = false
	# The answer prepare_preview found without re-planning (null, or the base intents), then run's.
	var _result: Intents = null
	# What run re-plans, all set together by prepare_preview; cleared once it has run.
	var _found: Intents = null
	var _engine: EffectEngine = null
	var _flooded: Dictionary[Vector2i, bool] = {}
	var _base: Intents = null
	# The first fact of the walk on _engine, from which its board is compared with _base's.
	var _changed_from: int = 0
	var _margin: int = 0
	# Intents.is_checking in a debug build when prepare_preview built the job.
	var _is_checking: bool = false
	# The base intents' attack forecasts, reused and added to (a locked store).
	var _forecasts: EnemyAI.ForecastStore = null

	## The previewed intents, re-planning the enemies on the first call; later calls return the
	## same. Pure rules code on the job's own sandbox, reading only the base intents and content
	## definitions: no session, node, autoload or log, so it may run on a worker thread, one call
	## at a time. It reuses the base's forecasts and adds its own to them as it ends (a locked
	## store). The sandbox's diagnostics are in [member Intents.diagnostics]. Null once cancelled.
	func run() -> Intents:
		if _found == null:
			return _result
		if _is_asked_to_stop():
			_stop()
			return null
		var forecasts: EnemyAI.Forecasts = EnemyAI.Forecasts.new(
				_forecasts, _margin, _is_checking
		)
		var touched: Array[Vector2i] = Intents._changed_tiles(_base, _engine, _changed_from)
		var reused: Intents = _base
		if touched.has(CombatFact.NO_TILE):
			reused = null
		Intents._play(
				_found, _engine, _flooded, reused, touched, _margin, _is_checking, forecasts, self
		)
		# The last point a cancel stops it: past here its result counts and cancel does nothing.
		_lock.lock()
		var is_stopping: bool = _is_cancel_asked
		_has_ended = not is_stopping
		_lock.unlock()
		if is_stopping:
			_stop()
			return null
		forecasts.add_overlay_to_store()
		Intents._take_forecasts(_found, _engine, forecasts)
		_found.diagnostics = _engine.diagnostics
		# Only the intents a preview builds on read their rounds; a preview's own, with every
		# decision's plan, footprint and forecast, would hold about 1 MB each in a sweep's done
		# previews (debug).
		_found._rounds.clear()
		_result = _found
		_found = null
		_engine = null
		_base = null
		_forecasts = null
		return _result

	## Asks the job to stop, from any thread: [method run] stops before its next step of the
	## phase (one enemy acting) or as it ends, then returns null, keeps none of its forecasts in
	## the base's store and holds no result. A job that has ended keeps its result, and one that
	## never re-plans returns its answer. Can't be undone.
	func cancel() -> void:
		_lock.lock()
		if not _has_ended:
			_is_cancel_asked = true
		_lock.unlock()

	## Whether [method run] stopped on a [method cancel], with no result; false while it runs.
	func is_cancelled() -> bool:
		_lock.lock()
		var stopped: bool = _is_stopped
		_lock.unlock()
		return stopped

	# Whether cancel was asked: Intents._play reads it before each step.
	func _is_asked_to_stop() -> bool:
		_lock.lock()
		var asked: bool = _is_cancel_asked
		_lock.unlock()
		return asked

	# Drops everything run would build on or keep, so a later run returns null too.
	func _stop() -> void:
		_found = null
		_engine = null
		_base = null
		_forecasts = null
		_result = null
		_lock.lock()
		_is_stopped = true
		_lock.unlock()


## One step of the phase: every enemy yet to act, decided, and the decision that acted.
class Round:
	extends RefCounted

	## Each enemy's decision, by id.
	var decisions: Dictionary[String, Decision] = {}
	## The one that acted.
	var winner: Decision = null
	## The path of the second move it took after acting; empty for none.
	var second_path: Array[Vector2i] = []


## A signature move the coming enemy Phase Start fires: its name and the tiles it covers.
class Signature:
	extends RefCounted

	## Its name as players read it, the effect's label ("War Horn").
	var name: String = ""
	## The tiles it covers, in row-major order.
	var area: Array[Vector2i] = []
