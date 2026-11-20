# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     preview_profile.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The move preview's per-phase profile for [code]preview_bench.gd[/code] (move-preview.md, build
## step A): on one board, [constant SAMPLES] hovers spread over every move tile, on the main thread.
## Each is timed whole ([method Intents.prepare_preview], then [method Intents.PreviewJob.run]),
## then its preparation is rebuilt phase by phase with the same calls (sandbox copy, walk, danger
## zone, phase crossing) and, on the crossed board, every enemy's first-round decision is timed
## with no forecast cache, with its parts: its board's two floods, each attack forecast it weighs,
## its reuse zone's flood. Forecasts are counted and timed by enumerating the options as
## [method EnemyAI.decide] does, outside it, so the parts are estimates a remainder balances. Every
## [constant PARTS_EVERY]th hover takes each of those forecasts apart step by step. Measures only.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# Hovers profiled per board, spread evenly over every move tile but the units' own.
const SAMPLES: int = 24

# One profiled hover in this many also takes every attack forecast of its first round apart
# (_take_apart), which repeats each forecast once more: SAMPLES / PARTS_EVERY hovers per board.
const PARTS_EVERY: int = 8

# The steps of one forecast, in the order CombatForecast runs them.
const PARTS: Array[String] = [
	"state copy (CombatState.copy_for_sandbox)",
	"engine copy (instances, sheets, run state)",
	"outcomes before, recorder",
	"walk the path",
	"exchange (swap, resolve, drain)",
	"outcomes after",
]

# Behaviors whose decision weighs every attack in reach (EnemyAI.decide: Aggressive, Skirmisher,
# Hold, and Guard through its attacks).
const ATTACKERS: Array[EnemyClassDefinition.Behavior] = [
	EnemyClassDefinition.Behavior.AGGRESSIVE,
	EnemyClassDefinition.Behavior.SKIRMISHER,
	EnemyClassDefinition.Behavior.HOLD,
	EnemyClassDefinition.Behavior.GUARD,
]

var _session: CombatSession = null
var _catalog: EffectCatalog.Index = null

# Sums over every profiled hover, in microseconds, by phase.
var _phases: Dictionary[String, int] = {}
# Per enemy class: decisions timed, then sums of decide, floods, forecasts counted, forecast time,
# zone flood, in that order.
var _classes: Dictionary[String, PackedInt64Array] = {}
var _decisions: int = 0
var _hovers: int = 0
# Attack forecasts the profiled previews made afresh, and reused from the latest intents' store.
var _made: int = 0
var _reused: int = 0

# Each forecast taken apart: the sums of its PARTS, in microseconds; how many; their facts; and
# the instances and units on the boards they ran on.
var _parts: Dictionary[String, int] = {}
var _parted: int = 0
var _parted_facts: int = 0
var _parted_instances: int = 0
var _parted_units: int = 0


func _init(session: CombatSession, catalog: EffectCatalog.Index) -> void:
	_session = session
	_catalog = catalog


## Profiles the samples and prints the per-phase table and the per-class decision table.
func run() -> void:
	var samples: Array[Array] = _samples()
	for index: int in samples.size():
		var unit_id: String = samples[index][0]
		var tile: Vector2i = samples[index][1]
		_profile_hover(unit_id, tile, index % PARTS_EVERY == 0)
	if _hovers == 0:
		print("\n-- Profile: no hover to profile --")
		return
	_print_phases()
	_print_classes()
	_print_parts()


# SAMPLES (unit id, tile) pairs at even steps through every acting unit's move tiles in turn,
# leaving out each unit's own tile, which a preview answers without work.
func _samples() -> Array[Array]:
	var all: Array[Array] = []
	for unit_id: String in TurnInputModel.acting_units(_session, 0):
		var origin: Vector2i = _session.state.tile_of(unit_id)
		for tile: Vector2i in TurnInputModel.move_tiles(_session, unit_id):
			if tile != origin:
				all.append([unit_id, tile])
	var picked: Array[Array] = []
	if all.is_empty():
		return picked
	var count: int = mini(SAMPLES, all.size())
	for index: int in count:
		picked.append(all[floori(index * all.size() / float(count))])
	return picked


# One hover whole, then its phases; with takes_parts, every first-round forecast taken apart too.
func _profile_hover(unit_id: String, tile: Vector2i, takes_parts: bool) -> void:
	var started: int = Time.get_ticks_usec()
	var job: Intents.PreviewJob = Intents.prepare_preview(_session, unit_id, tile)
	_add("prepare", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	var found: Intents = job.run()
	_add("run", Time.get_ticks_usec() - started)
	if found == null:
		return
	_hovers += 1
	_decisions += found.decisions
	_made += found.forecasts_made
	_reused += found.forecasts_reused
	var path: Array[Vector2i] = EnemyAI.Board.new(_session.engine, unit_id, {}).path_to(tile)
	started = Time.get_ticks_usec()
	var sandbox: Sandbox = Sandbox.new(_session.engine, ForecastRolls.new())
	_add("copy", Time.get_ticks_usec() - started)
	var engine: EffectEngine = sandbox.engine
	engine.verify = false
	var moved: CombatState = engine.state
	started = Time.get_ticks_usec()
	engine.begin_step()
	UnitTurnCommand.walk_path(engine, moved, unit_id, path)
	engine.drain()
	_add("walk", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	DangerZone.compute(engine)
	_add("danger", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	PhaseRunner.cross_to_enemy_phase(_session, engine)
	_add("cross", Time.get_ticks_usec() - started)
	_profile_enemies(engine)
	if takes_parts:
		_parts_of_round(engine)


# Every enemy's first-round decision on engine, the crossed board, with its parts.
func _profile_enemies(engine: EffectEngine) -> void:
	var state: CombatState = engine.state
	var flooded: Dictionary[Vector2i, bool] = EnemyAI.flooded_tiles(_session.state)
	var objective: Array[Vector2i] = EnemyAI.objective_tiles(_session)
	for enemy_id: String in state.units_of(ENEMY):
		if state.unit(enemy_id).has_acted:
			continue
		var class_id: String = state.unit_type_of(enemy_id)
		var row: PackedInt64Array = _classes.get(class_id, PackedInt64Array([0, 0, 0, 0, 0, 0]))
		var started: int = Time.get_ticks_usec()
		EnemyAI.decide(engine, _catalog, enemy_id, flooded, objective)
		var decided: int = Time.get_ticks_usec() - started
		row[1] += decided
		_add("round1", decided)
		started = Time.get_ticks_usec()
		var board: EnemyAI.Board = EnemyAI.Board.new(engine, enemy_id, flooded)
		row[2] += Time.get_ticks_usec() - started
		if ATTACKERS.has(_behavior_of(state, enemy_id)):
			var forecasts: Vector2i = _time_forecasts(engine, board)
			row[3] += forecasts.x
			row[4] += forecasts.y
		started = Time.get_ticks_usec()
		_zone_flood(engine, enemy_id)
		row[5] += Time.get_ticks_usec() - started
		row[0] += 1
		_classes[class_id] = row


# The behavior enemy_id plays, after the darkness switch (EnemyAI.decide).
func _behavior_of(state: CombatState, enemy_id: String) -> EnemyClassDefinition.Behavior:
	var definition: EnemyClassDefinition = _catalog.enemy_class(state.unit_type_of(enemy_id))
	if definition == null:
		return EnemyClassDefinition.Behavior.AGGRESSIVE
	if Reinforcements.has_darkness_arrived(state) and not definition.holds_post:
		return EnemyClassDefinition.Behavior.AGGRESSIVE
	return definition.behavior


# Every attack forecast each attacking enemy on engine weighs in its first-round decision, each
# taken apart (_take_apart).
func _parts_of_round(engine: EffectEngine) -> void:
	var state: CombatState = engine.state
	var flooded: Dictionary[Vector2i, bool] = EnemyAI.flooded_tiles(_session.state)
	for enemy_id: String in state.units_of(ENEMY):
		if state.unit(enemy_id).has_acted or not ATTACKERS.has(_behavior_of(state, enemy_id)):
			continue
		var board: EnemyAI.Board = EnemyAI.Board.new(engine, enemy_id, flooded)
		for command: UnitTurnCommand in _attack_commands(board):
			_take_apart(engine, command)


# One attack forecast rebuilt step by step with CombatForecast's own calls (_simulate, without
# breakdowns), each step timed into _parts. The state copy is timed alone first, then again inside
# the whole sandbox copy, whose remainder is the engine's own copy.
func _take_apart(engine: EffectEngine, command: UnitTurnCommand) -> void:
	var started: int = Time.get_ticks_usec()
	engine.state.copy_for_sandbox()
	var state_copy: int = Time.get_ticks_usec() - started
	_part(PARTS[0], state_copy)
	started = Time.get_ticks_usec()
	var trial: EffectEngine = Sandbox.new(engine, ForecastRolls.new()).engine
	_part(PARTS[1], Time.get_ticks_usec() - started - state_copy)
	var state: CombatState = trial.state
	var actor: String = command.actor_id
	started = Time.get_ticks_usec()
	var before: Array[CombatForecast.UnitOutcome] = []
	for unit_id: String in state.unit_ids():
		before.append(CombatForecast.UnitOutcome.before(state, unit_id))
	var recorder: CombatForecast.Recorder = CombatForecast.Recorder.new(
			trial, actor, command.target_id, false
	)
	trial.add_context_observer(recorder.observe)
	_part(PARTS[2], Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	trial.begin_step()
	UnitTurnCommand.walk_path(trial, state, actor, command.path)
	_part(PARTS[3], Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	if not command.weapon_id.is_empty() and command.weapon_id != state.equipped_weapon_id(actor):
		WeaponSwap.resolve(trial, state, actor, true)
	ExchangeResolver.resolve(trial, state, actor, command.target_id)
	trial.drain()
	_part(PARTS[4], Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	for outcome: CombatForecast.UnitOutcome in before:
		outcome.finish(state)
	_part(PARTS[5], Time.get_ticks_usec() - started)
	_parted += 1
	_parted_facts += trial.fact_log.size()
	_parted_instances += engine.get_instances().size()
	_parted_units += engine.state.unit_ids().size()


func _part(part: String, spent: int) -> void:
	var total: int = _parts.get(part, 0)
	_parts[part] = total + spent


# Every attack command board's enemy weighs, as EnemyAI's attacks enumerate them: each weapon that
# attacks, each end tile, each player unit or unbroken keg in range.
func _attack_commands(board: EnemyAI.Board) -> Array[UnitTurnCommand]:
	var commands: Array[UnitTurnCommand] = []
	var state: CombatState = board.state
	var holder: CombatUnitState = state.unit(board.unit_id)
	var weapon_ids: Array[String] = [holder.equipped_weapon_id, holder.stowed_weapon_id]
	var targets: PackedStringArray = state.units_of(PLAYER)
	for keg: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.POWDER_KEG):
		if not keg.is_destroyed:
			targets.append(keg.id)
	for order: int in weapon_ids.size():
		var held: CombatState.WeaponStats = state.weapon(weapon_ids[order])
		if held == null or (held.is_staff() and held.staff != CombatState.WeaponStats.Staff.ATTACK):
			continue
		var span: Vector2i = ExchangeResolver.weapon_range(board.engine, board.unit_id, held.id)
		for tile: Vector2i in board.reach:
			var path: Array[Vector2i] = board.path_to(tile)
			for target: String in targets:
				var distance: int = state.grid.distance(tile, state.tile_of(target))
				if distance < span.x or distance > span.y:
					continue
				var command: UnitTurnCommand = UnitTurnCommand.new(
						-1, board.unit_id, UnitTurnCommand.Action.ATTACK, target, path
				)
				if order == 1:
					command.weapon_id = held.id
				commands.append(command)
	return commands


# Each attack forecast board's enemy weighs (_attack_commands). Returns (forecasts, their total
# time in microseconds).
func _time_forecasts(engine: EffectEngine, board: EnemyAI.Board) -> Vector2i:
	var count: int = 0
	var spent: int = 0
	for command: UnitTurnCommand in _attack_commands(board):
		var started: int = Time.get_ticks_usec()
		CombatForecast.exchange(engine, command, ForecastRolls.new(), false)
		spent += Time.get_ticks_usec() - started
		count += 1
	return Vector2i(count, spent)


# The reuse zone an attacking decision builds (Intents' zone): a flood with the enemy's budget and
# every tile within its longest range plus the effect margin, taken as 1, of each tile it walks.
func _zone_flood(engine: EffectEngine, enemy_id: String) -> void:
	var state: CombatState = engine.state
	var mover: CombatUnitState = state.unit(enemy_id)
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(engine, state, enemy_id),
			mover.movement_type,
			mover.side
	)
	var longest: int = 1
	for span: Vector2i in DangerZone.attack_ranges(engine, enemy_id):
		longest = maxi(longest, span.y)
	var zone: Dictionary[Vector2i, bool] = {}
	for walked_tile: Vector2i in walked:
		for near: Vector2i in DangerZone.tiles_within(walked_tile, Vector2i(0, longest + 1)):
			zone[near] = true


func _add(phase: String, spent: int) -> void:
	var total: int = _phases.get(phase, 0)
	_phases[phase] = total + spent


func _print_phases() -> void:
	var hovers: float = float(_hovers)
	var prepare: float = _mean("prepare")
	var job: float = _mean("run")
	var whole: float = prepare + job
	var decisions: float = _decisions / hovers
	var decide: float = _mean_decide()
	var parts: float = 0.0
	for phase: String in ["copy", "walk", "danger", "cross"]:
		parts += _mean(phase)
	print("\n-- Profile: %d hovers on the main thread, mean per hover --" % [_hovers])
	_line("hover (prepare + run)", whole, whole)
	_line("prepare_preview (main thread)", prepare, whole)
	_line("  sandbox copy", _mean("copy"), whole)
	_line("  walk to the tile", _mean("walk"), whole)
	_line("  danger zone", _mean("danger"), whole)
	_line("  phase crossing (Phase End, enemy Phase Start)", _mean("cross"), whole)
	_line("  the rest (path, checks, signatures, margin)", prepare - parts, whole)
	_line("PreviewJob.run (worker in play)", job, whole)
	print("  %.1f decisions; attack forecasts made %.1f, reused %.1f (the store as the sweep" % [
		decisions, _made / hovers, _reused / hovers,
	] + " left it)")
	# Timed outside the preview, with no forecast reused: what one round costs without the cache.
	print("Reference: every enemy's first-round decision with no cache, %.0f each, %.0f in all" % [
		decide, _mean("round1"),
	])


func _print_classes() -> void:
	print("\n-- Profile: each enemy's first-round decision, mean per decision --")
	print("%-16s %5s %9s %9s %9s %9s %9s %9s" % [
		"class", "n", "decide", "floods", "forecasts", "each", "rest", "zone",
	])
	var all_count: int = 0
	var all_time: int = 0
	for class_id: String in _classes:
		var row: PackedInt64Array = _classes[class_id]
		var n: float = float(row[0])
		var each: float = 0.0 if row[3] == 0 else row[4] / float(row[3])
		all_count += row[3]
		all_time += row[4]
		print("%-16s %5d %9.0f %9.0f %9.1f %9.0f %9.0f %9.0f" % [
			class_id, row[0], row[1] / n, row[2] / n, row[3] / n, each,
			(row[1] - row[2] - row[4]) / n, row[5] / n,
		])
	print("One attack forecast (CombatForecast.exchange): %.0f on average over %d" % [
		0.0 if all_count == 0 else all_time / float(all_count), all_count,
	])
	print("decide: the whole decision; floods: its board's reach and walk; forecasts: counted per")
	print("decision, each timed; rest: decide less floods and forecasts (rating, staves, safety")
	print("floods); zone: the reuse zone's flood, outside decide.")


func _print_parts() -> void:
	if _parted == 0:
		return
	var count: float = float(_parted)
	var whole: float = 0.0
	for part: String in PARTS:
		var spent: int = _parts.get(part, 0)
		whole += spent / count
	print("\n-- Profile: one attack forecast taken apart, mean over %d --" % [_parted])
	for part: String in PARTS:
		var spent: int = _parts.get(part, 0)
		_line(part, spent / count, whole)
	_line("forecast (the parts' sum)", whole, whole)
	print("Per forecast: %.1f facts; the board held %.1f effect instances and %.1f units" % [
		_parted_facts / count, _parted_instances / count, _parted_units / count,
	])


func _mean_decide() -> float:
	var count: int = 0
	var spent: int = 0
	for class_id: String in _classes:
		count += _classes[class_id][0]
		spent += _classes[class_id][1]
	return 0.0 if count == 0 else spent / float(count)


static func _line(label: String, spent: float, whole: float) -> void:
	print("%-52s %9.0f  %5.1f%%" % [label, spent, 0.0 if whole <= 0.0 else 100.0 * spent / whole])


# The mean of phase per profiled hover, in microseconds.
func _mean(phase: String) -> float:
	var total: int = _phases.get(phase, 0)
	return total / float(_hovers)
