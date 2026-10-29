# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_bench.gd
# Author:
# Created:  October 27, 2026
# Modified: October 29, 2026
# ==============================================================================

extends Node
## Forecast and AI cost benchmark (event bus plan, EB9): sandbox creation, value queries with and
## without cached stat sheets, one player forecast, and [ExchangeOutcome] at exact enumeration for
## exchanges of 2, 4 and 8 attacks, single-threaded and on [WorkerThreadPool].
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash res://tests/bench/forecast_bench.tscn[/code][br]
## The workload is a seeded 6-vs-5 map on the stub grid with the combat tests' fixtures (Vanguard,
## Momentum, Phalanx, Cleave, War Horn, Iron Heart, Brittle Guard, and a two-sided damage pair),
## played to the third player phase with one real exchange, so timed modifiers, Block, counters
## and damage are mid-battle. Each row prints its repeat count, median and p95 in microseconds,
## warm-up runs discarded. Verify mode is off for every row except those that say otherwise,
## because release builds run without it. A census then counts what one sandbox copies against
## what an exchange reads.[br]
## Measures only; changes nothing outside tests/bench/. Exits with code 1 if the fixture is not
## the intended one or a worker result differs from the main thread's.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

# Preloaded scripts used as types (gdscript.md, Naming): the test helpers have no class name.
const CombatWorld = preload("res://tests/combat/combat_world.gd")
const FakeExchange = preload("res://tests/effects/harness/fake_exchange.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# The seed of the real session's combat stream (the combat tests' SEED, exchange_cases.gd).
const SEED: int = 20261027

const MAP_SIZE: Vector2i = Vector2i(8, 8)

# Every unit's base stats, from exchange_cases.gd's UNIT_BASES: Might 3, Speed 5, Defense 2,
# Resistance 1, Constitution 20 (no weapon slows anyone). CombatWorld adds HP 20 and Stance 2.
const UNIT_BASES: Dictionary = {
	CombatValue.Key.MGT: 3.0,
	CombatValue.Key.SPD: 5.0,
	CombatValue.Key.DEF: 2.0,
	CombatValue.Key.RES: 1.0,
	CombatValue.Key.CON: 20.0,
}

# The map: id, tile, CombatWorld weapon preset, base changes. Players are seat 0.
#   y0  .  p5  .   .
#   y1  .  p1  e1  .        p1-e1: sword vs axe, 1 + 1 attacks
#   y2  .  p6  .   e4
#   y3  .  p2  e2  .        p2-e2: gauntlets (AtkX 2), 2 + 2 attacks, both in forest
#   y4  .  p4  .   .
#   y5  .  p3  e3  e5       p3-e3: gauntlets, Speed gap 10 gives 2 bonus turns: 8 attacks
const PLAYER_UNITS: Array = [
	["p1", Vector2i(1, 1), "sword", {}],
	["p2", Vector2i(1, 3), "gauntlets", {}],
	["p3", Vector2i(1, 5), "gauntlets", {CombatValue.Key.SPD: 15.0}],
	["p4", Vector2i(1, 4), "bow", {}],
	["p5", Vector2i(2, 0), "lance", {}],
	["p6", Vector2i(1, 2), "fire", {}],
]
const ENEMY_UNITS: Array = [
	["e1", Vector2i(2, 1), "axe", {}],
	["e2", Vector2i(2, 3), "gauntlets", {}],
	["e3", Vector2i(2, 5), "gauntlets", {}],
	["e4", Vector2i(3, 2), "bow", {}],
	["e5", Vector2i(3, 5), "fire", {}],
]

# Forest tiles under the 4- and 8-attack pairs, so their 100-Hit gauntlets can miss. The terrain
# numbers are exchange_cases.gd's forest: avoid 20, Defense 1, Resistance 2.
const FOREST_TILES: Array[Vector2i] = [
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(1, 5), Vector2i(2, 5),
]

# Attacker and defender by the attacks their exchange plans when nobody is defeated.
const PAIRS: Dictionary[int, Array] = {
	2: ["p1", "e1"],
	4: ["p2", "e2"],
	8: ["p3", "e3"],
}

# The keys one exchange reads, queried for every unit in the value-query batches.
const QUERY_KEYS: Array[int] = [
	CombatValue.Key.ATTACK_SPEED, CombatValue.Key.NET_WEIGHT, CombatValue.Key.ATK_X,
	CombatValue.Key.PARRY, CombatValue.Key.HIT, CombatValue.Key.AVOID,
	CombatValue.Key.CRIT_CHANCE, CombatValue.Key.CRIT_X, CombatValue.Key.STANCE_MAX,
	CombatValue.Key.RANGE_MIN, CombatValue.Key.RANGE_MAX, CombatValue.Key.DAMAGE_TYPE,
	CombatValue.Key.EFFECTIVE_MODIFIER, CombatValue.Key.MGT, CombatValue.Key.SPD,
	CombatValue.Key.DEF, CombatValue.Key.RES, CombatValue.Key.CON,
	DamageStage.Key.ATTACK, DamageStage.Key.MITIGATION, DamageStage.Key.MULTIPLIERS,
	DamageStage.Key.INCOMING_MULTIPLIERS,
]

# Branch budget for "exact" enumeration: far above any branch count this fixture reaches, so every
# outcome reports complete (printed per row).
const BRANCH_BUDGET: int = 1 << 20

# Warm-up runs and measured repeats per row. Chosen so the whole bench runs in about six minutes
# on a 16-thread desktop; cheap rows get enough samples for a stable p95, the 8-attack enumeration
# as many as fit (one high-priority 8-attack pool batch is about 40 s). A p95 of fewer than 20
# samples is the largest sample.
const CHEAP_WARMUP: int = 20
const CHEAP_REPEATS: int = 200
const OUTCOME_WARMUP: Dictionary[int, int] = {2: 3, 4: 2, 8: 1}
const OUTCOME_REPEATS: Dictionary[int, int] = {2: 50, 4: 20, 8: 5}
const POOL_WARMUP: int = 2
const POOL_REPEATS: int = 20
const POOL_OUTCOME_WARMUP: Dictionary[int, int] = {2: 2, 4: 1, 8: 1}
const POOL_OUTCOME_REPEATS: Dictionary[int, int] = {2: 10, 4: 5, 8: 2}

# Tasks per WorkerThreadPool batch: a plausible candidate count for one enemy (tiles × targets);
# the 8-attack outcome uses one task per logical core to keep its row short.
const POOL_TASKS: int = 64
const POOL_OUTCOME_TASKS: Dictionary[int, int] = {2: 32, 4: 32, 8: 16}

# Godot's cap on low-priority pool tasks, as a share of the pool's threads (printed in the header).
const LOW_PRIORITY_RATIO_SETTING: String = "threading/worker_pool/low_priority_thread_ratio"

# Resolutions per pair in the read census: ForecastRolls, all misses, then seeded live streams.
const CENSUS_SEEDS: int = 32

# The real session the benchmarks copy.
var _world: CombatWorld = null
var _engine: EffectEngine = null
var _state: CombatState = null

# What went wrong, for the exit code.
var _failures: PackedStringArray = []

# The last thing a timed call returned, kept so freeing it falls outside the timing.
var _hold: Variant = null


func _ready() -> void:
	_print_header()
	_world = _build_world(LiveRolls.new(RngStream.new(SEED)), false)
	_engine = _world.engine
	_state = _world.state
	if _check_fixture():
		_engine.verify = false
		_bench_sandbox()
		_bench_queries()
		_bench_forecasts()
		_bench_outcomes()
		_bench_pool()
		_census()
	if _failures.is_empty():
		print("\nDone: every check passed.")
	else:
		print("\nDone with %d failures:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _print_header() -> void:
	var version: Dictionary = Engine.get_version_info()
	var version_text: String = version.get("string", "?")
	var pool_threads: int = ProjectSettings.get_setting("threading/worker_pool/max_threads", -1)
	print("=== EB9 forecast benchmark ===")
	print("Godot %s, %s build (the editor binary): rules code runs slower than an export" % [
		version_text, "debug" if OS.is_debug_build() else "release",
	])
	var ratio_text: String = "not found"
	if ProjectSettings.has_setting(LOW_PRIORITY_RATIO_SETTING):
		ratio_text = str(ProjectSettings.get_setting(LOW_PRIORITY_RATIO_SETTING))
	print("CPU: %s, %d logical cores; WorkerThreadPool max threads %s" % [
		OS.get_processor_name(), OS.get_processor_count(),
		"= core count" if pool_threads < 0 else str(pool_threads),
	])
	print("WorkerThreadPool low-priority thread ratio: %s" % [ratio_text])
	print("Times in microseconds; warm-up runs discarded; verify mode off unless a row says on.")


# --- Fixture -------------------------------------------------------------------------------------


# The 6-vs-5 map, played to the third player phase with one real exchange (p5 on e1). With
# `tracked`, the state is a ReadTracker for the census.
func _build_world(rolls: RollSource, tracked: bool) -> CombatWorld:
	var world: CombatWorld = CombatWorld.new(rolls, MAP_SIZE)
	if tracked:
		world.state = ReadTracker.new(world.grid)
		world.engine = EffectEngine.new(world.state, rolls)
		world.engine.verify = true
	var forest: CombatGrid.TileBonus = CombatGrid.TileBonus.new()
	forest.avoid = 20
	forest.defense = 1
	forest.resistance = 2
	for tile: Vector2i in FOREST_TILES:
		world.grid.set_bonus(tile, forest)
	for row: Array in PLAYER_UNITS:
		_place(world, row, PLAYER, 0)
	for row: Array in ENEMY_UNITS:
		_place(world, row, ENEMY, -1)
	var e3: CombatUnitState = world.state.unit("e3")
	e3.tags = PackedStringArray(["Beast"])

	var vanguard: EffectDefinition = _vanguard()
	var momentum: EffectDefinition = _momentum()
	var phalanx: EffectDefinition = _phalanx()
	world.add_effect("effect:vanguard_p1", vanguard, "p1")
	world.add_effect("effect:vanguard_p4", vanguard, "p4")
	world.add_effect("effect:momentum_p1", momentum, "p1")
	world.add_effect("effect:momentum_p2", momentum, "p2")
	world.add_effect("effect:momentum_p3", momentum, "p3")
	world.add_effect("effect:phalanx_p4", phalanx, "p4")
	world.add_effect("effect:phalanx_p6", phalanx, "p6")
	world.add_effect("effect:bane_p3", _beast_bane(), "p3")
	world.add_effect("effect:cleave_e1", _cleave(), "e1")
	world.add_effect("effect:frailty_e3", _magic_frailty(), "e3")
	world.add_effect("effect:war_horn_e4", _war_horn(), "e4")
	var army: EffectOwner = EffectOwner.for_army("seat:0", 0)
	world.engine.register(EffectInstance.new(
			"effect:iron_heart", _iron_heart(), army, Modifier.SourceKind.HEIRLOOM, "Iron Heart"
	))
	world.engine.register(EffectInstance.new(
			"effect:brittle_guard", _brittle_guard(), army, Modifier.SourceKind.CURSE,
			"Brittle Guard"
	))

	# Phases through FakeExchange's helpers (the combat core has no turn loop yet): War Horn fires
	# on its second Phase Start, and its modifier lasts through the next phase, the current one.
	var harness: FakeExchange = FakeExchange.new(world.engine)
	for side: CombatFact.CombatSide in [PLAYER, ENEMY, PLAYER, ENEMY]:
		harness.phase_start(side)
		harness.phase_end(side)
	harness.phase_start(PLAYER)
	world.engine.begin_step()
	ExchangeResolver.resolve(world.engine, world.state, "p5", "e1")
	return world


func _place(world: CombatWorld, row: Array, side: CombatFact.CombatSide, seat: int) -> void:
	var id: String = row[0]
	var tile: Vector2i = row[1]
	var preset: String = row[2]
	var extra: Dictionary = row[3]
	var bases: Dictionary = UNIT_BASES.duplicate()
	bases.merge(extra, true)
	if world.add_unit(id, side, seat, tile, bases) == null:
		_fail("fixture: %s could not be placed on %s" % [id, tile])
		return
	world.add_weapon("w:" + id, preset)
	world.arm(id, "w:" + id)


# Prints the fixture and checks it is the intended one: no diagnostics from the setup (run in
# verify mode), and each pair legal with the attack count its row claims.
func _check_fixture() -> bool:
	var timed: int = 0
	for id: String in _state.unit_ids():
		timed += _engine.get_timed_modifiers(id).size()
	print("\nFixture: %d units (6 vs 5), %d effect instances, %d timed modifiers, %d facts" % [
		_state.unit_ids().size(), _engine.get_instances().size(), timed, _engine.fact_log.size(),
	])
	if not _engine.diagnostics.is_empty():
		_fail("fixture: setup diagnostics %s" % [_engine.diagnostics])
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		var reason: String = ExchangeResolver.check(_engine, _state, attacker, defender)
		var order: PackedStringArray = ExchangeResolver.turn_order(
				_engine, _state, attacker, defender
		)
		var planned: int = 0
		for turn_unit: String in order:
			var target: String = defender if turn_unit == attacker else attacker
			planned += ExchangeResolver.attacks_per_turn(
					_engine, _state, turn_unit, target, attacker
			)
		var ahead: EffectContext = ExchangeResolver.context(
				_engine, _state, attacker, defender, attacker, 0
		)
		var back: EffectContext = ExchangeResolver.context(
				_engine, _state, defender, attacker, attacker, 1
		)
		print("  %s -> %s: turns %s = %d attacks; Hit %d / %d; HP %d / %d; Block %d / %d" % [
			attacker, defender, ",".join(order), planned,
			ExchangeResolver.hit_chance(_engine, _state, ahead),
			ExchangeResolver.hit_chance(_engine, _state, back),
			_state.get_hp(attacker), _state.get_hp(defender),
			_state.get_block(attacker), _state.get_block(defender),
		])
		if not reason.is_empty() or planned != attacks:
			_fail("fixture: %s -> %s plans %d attacks (%s)" % [
				attacker, defender, planned, reason,
			])
	return _failures.is_empty()


# --- Benchmarks ----------------------------------------------------------------------------------


# Item 1, with the parts of a copy timed on their own to show what dominates.
func _bench_sandbox() -> void:
	_section("1. Sandbox creation (one copy of the whole session)")
	var create: Job = Job.new(Job.Kind.CREATE, _engine, "", "")
	var total: float = _report("Sandbox.new(session, ForecastRolls)", _run_job(create))
	var state_copy: Callable = func() -> Variant:
		return _state.copy_for_sandbox()
	var instance_copies: Callable = func() -> Variant:
		var copies: Array[EffectInstance] = []
		for instance: EffectInstance in _engine.get_instances():
			copies.append(instance.copy())
		return copies
	var subjects: PackedStringArray = _state.unit_ids()
	var sheet_copies: Callable = func() -> Variant:
		var copies: Array[StatSheet] = []
		for id: String in subjects:
			copies.append(_engine.stats(id).copy_for(null))
		return copies
	var parts: float = 0.0
	parts += _report("  part: CombatState.copy_for_sandbox()", _measure(state_copy))
	parts += _report("  part: EffectInstance.copy() x %d" % [
		_engine.get_instances().size(),
	], _measure(instance_copies))
	parts += _report("  part: cached StatSheet.copy_for() x %d" % [subjects.size()],
			_measure(sheet_copies))
	print("  rest (registering the copies, run state, queue; total - parts): %.1f" % [
		total - parts,
	])


# Item 2: every unit's exchange keys, read through the cached sheet and through a fresh one.
func _bench_queries() -> void:
	_section("2. Value queries: %d units x %d keys = %d queries per batch" % [
		_state.unit_ids().size(), QUERY_KEYS.size(), _state.unit_ids().size() * QUERY_KEYS.size(),
	])
	# Units in a pair query with their attack context, so conditional modifiers (the Beast bane,
	# the magic frailty, the triangle) are tested live; the rest query without one.
	var ids: PackedStringArray = _state.unit_ids()
	var contexts: Array[EffectContext] = []
	for id: String in ids:
		contexts.append(_query_context(id))
	var queries: int = ids.size() * QUERY_KEYS.size()
	var cached: Callable = func() -> Variant:
		for i: int in ids.size():
			for key: int in QUERY_KEYS:
				_engine.stats(ids[i]).get_value(key, contexts[i])
		return null
	var fresh: Callable = func() -> Variant:
		for i: int in ids.size():
			for key: int in QUERY_KEYS:
				_engine.fresh_stats(ids[i]).get_value(key, contexts[i])
		return null
	var with_cache: float = _report("batch, cached sheets (stats())", _measure(cached))
	var without: float = _report("batch, no cache (fresh_stats() per query)", _measure(fresh))
	_engine.verify = true
	var verified: float = _report("batch, cached sheets, verify mode on", _measure(cached))
	_engine.verify = false
	print("  per query (median / %d): cached %.2f, no cache %.2f, cached + verify %.2f" % [
		queries, with_cache / queries, without / queries, verified / queries,
	])


# Item 3: one player forecast per pair, then the exchange alone on a sandbox made beforehand.
func _bench_forecasts() -> void:
	_section("3. Player forecast: Sandbox + ForecastRolls + one exchange")
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		var job: Job = Job.new(Job.Kind.FORECAST, _engine, attacker, defender)
		_report("%d attacks (%s -> %s)" % [attacks, attacker, defender], _run_job(job))
		_check_job(job)
		print("    result: %s" % [job.summary])
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		_report("  exchange only, %d attacks (sandbox made untimed)" % [attacks],
				_exchange_only(attacker, defender))
	var middle_attacker: String = PAIRS[4][0]
	var middle_defender: String = PAIRS[4][1]
	_engine.verify = true
	var verified: Job = Job.new(Job.Kind.FORECAST, _engine, middle_attacker, middle_defender)
	_report("4 attacks, verify mode on", _run_job(verified))
	_engine.verify = false


# Item 4: exact enumeration, one sandbox per branch.
func _bench_outcomes() -> void:
	_section("4. ExchangeOutcome, exact enumeration (ForcedRolls, one sandbox per branch)")
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		var job: Job = Job.new(Job.Kind.OUTCOME, _engine, attacker, defender)
		var median: float = _report("%d attacks (%s -> %s)" % [attacks, attacker, defender],
				_run_job(job, OUTCOME_WARMUP[attacks], OUTCOME_REPEATS[attacks]))
		_check_job(job)
		print("    %d branches, %s; %.1f per branch" % [
			job.branches, "complete" if job.complete else "INCOMPLETE",
			median / maxi(job.branches, 1),
		])
		print("    %s" % [job.summary])
		if not job.complete:
			_fail("outcome %d attacks: enumeration incomplete at the budget" % [attacks])


# Item 5: items 1, 3 and 4 as batches of tasks, each on its own base sandbox, run back to back on
# the main thread and then on WorkerThreadPool.
func _bench_pool() -> void:
	_section("5. WorkerThreadPool: batches of tasks, one sandbox per task")
	# NOTE: each task copies its own base sandbox, made here on the main thread, because
	# EffectEngine.copy_for_sandbox() is main-thread-only for the real session. A base holds the
	# same content as the session, so a task's copy costs what a copy of the session costs.
	# Each batch runs as a low-priority group (add_group_task's default) and as a high-priority one,
	# since Godot caps low-priority tasks at a share of the pool's threads.
	_pool_row("1 Sandbox creation", Job.Kind.CREATE, "", "", POOL_TASKS, POOL_WARMUP,
			POOL_REPEATS)
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		_pool_row("3 Forecast, %d attacks" % [attacks], Job.Kind.FORECAST, attacker, defender,
				POOL_TASKS, POOL_WARMUP, POOL_REPEATS)
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		_pool_row("4 Outcome, %d attacks" % [attacks], Job.Kind.OUTCOME, attacker, defender,
				POOL_OUTCOME_TASKS[attacks], POOL_OUTCOME_WARMUP[attacks],
				POOL_OUTCOME_REPEATS[attacks])


func _pool_row(
		label: String,
		kind: Job.Kind,
		attacker: String,
		defender: String,
		tasks: int,
		warmup: int,
		repeats: int
) -> void:
	var jobs: Array[Job] = []
	for i: int in tasks:
		jobs.append(Job.new(kind, Sandbox.new(_engine, ForecastRolls.new()).engine, attacker,
				defender))
	var task: Callable = func(index: int) -> void:
		jobs[index].run()
	var single: PackedInt64Array = []
	var low: PackedInt64Array = []
	var high: PackedInt64Array = []
	var per_task_single: PackedInt64Array = []
	var per_task_low: PackedInt64Array = []
	var per_task_high: PackedInt64Array = []
	var failures_before: int = _failures.size()
	for repeat: int in warmup + repeats:
		var measured: bool = repeat >= warmup
		var start: int = Time.get_ticks_usec()
		for job: Job in jobs:
			job.run()
		var single_time: int = Time.get_ticks_usec() - start
		var reference: PackedStringArray = []
		for job: Job in jobs:
			reference.append(job.summary)
			if measured:
				per_task_single.append(job.elapsed_usec)
		var low_time: int = _pool_batch(label, jobs, task, false, reference)
		if measured:
			for job: Job in jobs:
				per_task_low.append(job.elapsed_usec)
		var high_time: int = _pool_batch(label, jobs, task, true, reference)
		if measured:
			for job: Job in jobs:
				per_task_high.append(job.elapsed_usec)
			single.append(single_time)
			low.append(low_time)
			high.append(high_time)
	print("%s, %d tasks per batch:" % [label, tasks])
	var single_median: float = _report("  batch, main thread", single)
	var low_median: float = _report("  batch, pool, low priority (default)", low)
	var high_median: float = _report("  batch, pool, high priority", high)
	_report("  per task, main thread", per_task_single)
	_report("  per task, pool, low priority", per_task_low)
	_report("  per task, pool, high priority", per_task_high)
	print("  speedup %.2fx low priority, %.2fx high priority; worker results equal: %s" % [
		single_median / maxf(low_median, 1.0), single_median / maxf(high_median, 1.0),
		"yes" if _failures.size() == failures_before else "NO",
	])


# Runs `jobs` as one WorkerThreadPool group through `task`; returns the wall time. Reports any job
# whose result differs from `reference`, the main thread's results in job order.
func _pool_batch(
		label: String,
		jobs: Array[Job],
		task: Callable,
		high_priority: bool,
		reference: PackedStringArray
) -> int:
	var start: int = Time.get_ticks_usec()
	var group: int = WorkerThreadPool.add_group_task(task, jobs.size(), -1, high_priority)
	WorkerThreadPool.wait_for_group_task_completion(group)
	var elapsed: int = Time.get_ticks_usec() - start
	for i: int in jobs.size():
		if jobs[i].summary != reference[i]:
			_fail("%s: task %d on a worker differs from the main thread" % [label, i])
	return elapsed


# --- Census --------------------------------------------------------------------------------------


# What a sandbox copies against what an exchange reads: each pair resolved on a fresh tracked map
# with ForecastRolls, with every roll failing, and with CENSUS_SEEDS live streams; the union of
# the units each resolution read or wrote.
func _census() -> void:
	_section("Census: what one sandbox copies vs what one exchange reads")
	var timed: int = 0
	for id: String in _state.unit_ids():
		timed += _engine.get_timed_modifiers(id).size()
	print("Each sandbox copies: %d units (every field), %d occupancy entries, %d instances" % [
		_state.unit_ids().size(), _state.unit_ids().size(), _engine.get_instances().size(),
	])
	print("  (counters, charges), %d timed modifiers, every base sheet and cached stat sheet," % [
		timed,
	])
	print("  and the weapon table (records shared, the dictionary copied).")
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		var masks: Dictionary[String, int] = {}
		for run: int in CENSUS_SEEDS + 2:
			var rolls: RollSource = ForecastRolls.new()
			if run == 1:
				rolls = ForcedRolls.new(PackedInt32Array())
			elif run > 1:
				rolls = LiveRolls.new(RngStream.new(SEED + run))
			var world: CombatWorld = _build_world(LiveRolls.new(RngStream.new(SEED)), true)
			var tracker: ReadTracker = world.state
			world.engine.rolls = rolls
			tracker.reads.clear()
			world.engine.begin_step()
			ExchangeResolver.resolve(world.engine, tracker, attacker, defender)
			for id: String in tracker.reads:
				var mask: int = masks.get(id, 0)
				masks[id] = mask | tracker.reads[id]
			if not world.engine.diagnostics.is_empty():
				_fail("census %s: %s" % [attacker, world.engine.diagnostics])
		var data: PackedStringArray = []
		var scanned: PackedStringArray = []
		var untouched: PackedStringArray = []
		var written: PackedStringArray = []
		for id: String in _state.unit_ids():
			var mask: int = masks.get(id, 0)
			if mask & ReadTracker.DATA:
				data.append(id)
			elif mask & ReadTracker.SCAN:
				scanned.append(id)
			else:
				untouched.append(id)
			if mask & ReadTracker.WRITE:
				written.append(id)
		print("%d attacks (%s -> %s), %d resolutions:" % [
			attacks, attacker, defender, CENSUS_SEEDS + 2,
		])
		print("  unit data read (HP, Block, Stance, weapon, tags): %s" % [", ".join(data)])
		print("  only scanned (id, side, tile; selectors and scope): %s" % [", ".join(scanned)])
		print("  never read: %s" % ["-" if untouched.is_empty() else ", ".join(untouched)])
		print("  written: %s" % [", ".join(written)])


# --- Helpers -------------------------------------------------------------------------------------


# Runs `job` warmup + repeats times on the main thread; returns the measured runs' times.
func _run_job(
		job: Job, warmup: int = CHEAP_WARMUP, repeats: int = CHEAP_REPEATS
) -> PackedInt64Array:
	var samples: PackedInt64Array = []
	for i: int in warmup + repeats:
		job.run()
		if i >= warmup:
			samples.append(job.elapsed_usec)
	return samples


# Times `work` warmup + repeats times; what it returns is freed outside the timing.
func _measure(
		work: Callable, warmup: int = CHEAP_WARMUP, repeats: int = CHEAP_REPEATS
) -> PackedInt64Array:
	var samples: PackedInt64Array = []
	for i: int in warmup + repeats:
		var start: int = Time.get_ticks_usec()
		_hold = work.call()
		var elapsed: int = Time.get_ticks_usec() - start
		_hold = null
		if i >= warmup:
			samples.append(elapsed)
	return samples


# The exchange alone: a fresh sandbox per run, made before the timer starts.
func _exchange_only(attacker: String, defender: String) -> PackedInt64Array:
	var samples: PackedInt64Array = []
	for i: int in CHEAP_WARMUP + CHEAP_REPEATS:
		var sandbox: Sandbox = Sandbox.new(_engine, ForecastRolls.new())
		var state: CombatState = sandbox.engine.state
		var start: int = Time.get_ticks_usec()
		sandbox.engine.begin_step()
		ExchangeResolver.resolve(sandbox.engine, state, attacker, defender)
		var elapsed: int = Time.get_ticks_usec() - start
		if i >= CHEAP_WARMUP:
			samples.append(elapsed)
	return samples


# The attack context `id` reads with in its pair's exchange; null for a unit in no pair.
func _query_context(id: String) -> EffectContext:
	for attacks: int in PAIRS:
		var attacker: String = PAIRS[attacks][0]
		var defender: String = PAIRS[attacks][1]
		if id == attacker:
			return ExchangeResolver.context(_engine, _state, attacker, defender, attacker, 0)
		if id == defender:
			return ExchangeResolver.context(_engine, _state, defender, attacker, attacker, 1)
	return null


func _check_job(job: Job) -> void:
	if job.diagnostics > 0:
		_fail("%s -> %s: %d sandbox diagnostics" % [job.attacker_id, job.defender_id,
				job.diagnostics])


func _section(title: String) -> void:
	print("\n%s" % [title])
	print("  %-58s %5s %12s %12s" % ["", "reps", "median", "p95"])


# Prints one row; returns the median.
func _report(label: String, samples: PackedInt64Array) -> float:
	var sorted: PackedInt64Array = samples.duplicate()
	sorted.sort()
	var median: float = _median(sorted)
	print("  %-58s %5d %12.1f %12.1f" % [label, sorted.size(), median, _p95(sorted)])
	return median


func _fail(detail: String) -> void:
	push_error("ForecastBench: %s" % [detail])
	_failures.append(detail)


# --- Fixture effects -----------------------------------------------------------------------------
# Rebuilt from the effect and combat tests' fixtures (their builders are private to those files):
# golden_cases.gd for Vanguard, Phalanx, War Horn, Iron Heart and Brittle Guard, exchange_cases.gd
# for Momentum, Cleave, the Beast bane and the magic frailty.


# Vanguard: Phase Start, no ally closer to the nearest enemy: gain 3 Block.
func _vanguard() -> EffectDefinition:
	var front: WhilePositionCondition = WhilePositionCondition.new()
	front.kind = WhilePositionCondition.Kind.NO_ALLY_CLOSER_TO_ENEMY
	return _definition(
			EffectTerms.Trigger.PHASE_START, [front],
			[_gain_block(null, _constant(3.0))]
	)


# Momentum (Fighter): Missed: +15 Hit on the next attack this combat.
func _momentum() -> EffectDefinition:
	var bonus: AddTimedModifier = AddTimedModifier.new()
	bonus.key = CombatValue.Key.HIT
	bonus.mode = Modifier.Mode.ADD
	bonus.value = 15.0
	bonus.end = AddTimedModifier.End.THIS_COMBAT
	bonus.uses = 1
	return _definition(EffectTerms.Trigger.MISSED, [], [bonus])


# Phalanx: Unit Turn Start: gain 1 Block per adjacent ally.
func _phalanx() -> EffectDefinition:
	var count: CountOf = CountOf.new()
	count.selector = _area(1, EffectTerms.UnitSide.ALLY, false)
	return _definition(EffectTerms.Trigger.UNIT_TURN_START, [], [_gain_block(null, count)])


# Cleave (Brute): Hit dealt: 2 splash damage to adjacent units, friend or foe.
func _cleave() -> EffectDefinition:
	var splash: DealSplash = DealSplash.new()
	splash.target = _area(1, EffectTerms.UnitSide.ANY, false)
	splash.amount = _constant(2.0)
	return _definition(EffectTerms.Trigger.HIT_DEALT, [], [splash])


# War Horn: the second Phase Start: units within 2 tiles get +2 Attack until the end of the next
# phase.
func _war_horn() -> EffectDefinition:
	var second: CounterCondition = CounterCondition.new()
	second.count = 2
	var horn: AddTimedModifier = AddTimedModifier.new()
	horn.target = _area(2, EffectTerms.UnitSide.ANY, true)
	horn.key = DamageStage.Key.ATTACK
	horn.value = 2.0
	horn.end = AddTimedModifier.End.END_OF_NEXT_PHASE
	return _definition(EffectTerms.Trigger.PHASE_START, [second], [horn])


# Iron Heart (heirloom): every 7th attack by your units has lifesteal.
func _iron_heart() -> EffectDefinition:
	var seventh: CounterCondition = CounterCondition.new()
	seventh.count = 7
	var lifesteal: ModifyThat = ModifyThat.new()
	lifesteal.what = ModifyThat.What.FLAG
	lifesteal.flag = ModifyThat.Flag.LIFESTEAL
	var heart: EffectDefinition = _definition(
			EffectTerms.Trigger.ATTACK_MADE, [seventh], [lifesteal]
	)
	heart.scope = EffectTerms.Scope.YOUR_UNIT
	return heart


# Brittle Guard (curse): your units' Block gains are 1 lower, never below 0.
func _brittle_guard() -> EffectDefinition:
	var lower: ModifyThat = ModifyThat.new()
	lower.what = ModifyThat.What.AMOUNT
	lower.mode = Modifier.Mode.ADD
	lower.value = -1.0
	var floor_zero: ModifyThat = ModifyThat.new()
	floor_zero.what = ModifyThat.What.AMOUNT
	floor_zero.mode = Modifier.Mode.FLOOR
	floor_zero.value = 0.0
	var guard: EffectDefinition = _definition(
			EffectTerms.Trigger.BLOCK_GAINED, [], [lower, floor_zero]
	)
	guard.scope = EffectTerms.Scope.YOUR_UNIT
	guard.tags = EffectDefinition.Tag.CURSE
	return guard


# The attacker's side of the two-sided damage stages: deals x2 damage to Beasts.
func _beast_bane() -> EffectDefinition:
	var against: WhileAttackCondition = WhileAttackCondition.new()
	against.role = WhileAttackCondition.Role.ATTACKING
	against.kind = WhileAttackCondition.Kind.OPPONENT_TAG
	against.type_name = "Beast"
	return _definition(
			EffectTerms.Trigger.ALWAYS, [against],
			[_times(DamageStage.Key.MULTIPLIERS, 2.0)]
	)


# The defender's side: takes x2 damage from magic.
func _magic_frailty() -> EffectDefinition:
	var magic: WhileAttackCondition = WhileAttackCondition.new()
	magic.role = WhileAttackCondition.Role.ATTACKED
	magic.kind = WhileAttackCondition.Kind.DAMAGE_TYPE
	return _definition(
			EffectTerms.Trigger.ALWAYS, [magic],
			[_times(DamageStage.Key.INCOMING_MULTIPLIERS, 2.0)]
	)


func _definition(
		trigger: EffectTerms.Trigger, conditions: Array, operations: Array
) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = trigger
	definition.conditions.assign(conditions)
	definition.operations.assign(operations)
	return definition


func _gain_block(target: TargetSelector, amount: ValueSource) -> GainResource:
	var gain: GainResource = GainResource.new()
	gain.pool = GainResource.Pool.BLOCK
	gain.target = target
	gain.amount = amount
	return gain


func _constant(value: float) -> Constant:
	var constant: Constant = Constant.new()
	constant.value = value
	return constant


func _area(radius: int, side: EffectTerms.UnitSide, include_center: bool) -> Area:
	var area: Area = Area.new()
	area.center = Area.Center.OWNER
	area.radius = radius
	area.side = side
	area.include_center = include_center
	return area


func _times(key: int, value: float) -> ModifyValue:
	var modify: ModifyValue = ModifyValue.new()
	modify.key = key
	modify.mode = Modifier.Mode.MULTIPLY
	modify.value = value
	return modify


static func _median(sorted: PackedInt64Array) -> float:
	var count: int = sorted.size()
	if count == 0:
		return 0.0
	var middle: int = floori(count / 2.0)
	if count % 2 == 1:
		return float(sorted[middle])
	return (sorted[middle - 1] + sorted[middle]) / 2.0


# Nearest-rank 95th percentile.
static func _p95(sorted: PackedInt64Array) -> float:
	if sorted.is_empty():
		return 0.0
	var rank: int = ceili(0.95 * sorted.size())
	return float(sorted[clampi(rank, 1, sorted.size()) - 1])


## One unit of work, run on the main thread or as one [WorkerThreadPool] task. A job owns its base
## engine and everything it makes, so tasks share no mutable state.
class Job:
	extends RefCounted

	## What [method run] does.
	enum Kind {
		## Copies [member base] into a new [Sandbox].
		CREATE = 0,
		## A player forecast: a sandbox with [ForecastRolls], then one exchange.
		FORECAST = 1,
		## [ExchangeOutcome] by exact enumeration, one sandbox per branch.
		OUTCOME = 2,
	}

	## What the job does.
	var kind: Kind = Kind.CREATE
	## The engine every sandbox of this job copies. Touched by no other job.
	var base: EffectEngine = null
	## The attacking unit, for a forecast or an outcome.
	var attacker_id: String = ""
	## The defending unit, for a forecast or an outcome.
	var defender_id: String = ""
	## Microseconds the last [method run] took; freeing the previous run's result is excluded.
	var elapsed_usec: int = 0
	## The last run's result as text, to compare a worker with the main thread; empty for CREATE.
	var summary: String = ""
	## Resolver runs the last outcome made.
	var branches: int = 0
	## Whether the last outcome enumerated every branch.
	var complete: bool = true
	## Diagnostics the last run's sandboxes reported.
	var diagnostics: int = 0

	var _made: Sandbox = null

	func _init(job_kind: Kind, source: EffectEngine, attacker: String, defender: String) -> void:
		kind = job_kind
		base = source
		attacker_id = attacker
		defender_id = defender

	## Runs the job once, timing it.
	func run() -> void:
		_made = null
		var result: ExchangeResolver.Result = null
		var outcome: ExchangeOutcome = null
		var start: int = Time.get_ticks_usec()
		match kind:
			Kind.CREATE:
				_made = Sandbox.new(base, ForecastRolls.new())
			Kind.FORECAST:
				_made = Sandbox.new(base, ForecastRolls.new())
				var state: CombatState = _made.engine.state
				_made.engine.begin_step()
				result = ExchangeResolver.resolve(_made.engine, state, attacker_id, defender_id)
			Kind.OUTCOME:
				outcome = ExchangeOutcome.enumerate(resolve_branch, BRANCH_BUDGET)
		elapsed_usec = Time.get_ticks_usec() - start
		if result != null:
			var after: SandboxState = _made.engine.state
			diagnostics = _made.engine.diagnostics.size()
			summary = "%d attacks; %s HP %d Block %d Stance %d; %s HP %d Block %d Stance %d" % [
				result.attacks,
				attacker_id, after.get_hp(attacker_id), after.get_block(attacker_id),
				after.get_stance(attacker_id),
				defender_id, after.get_hp(defender_id), after.get_block(defender_id),
				after.get_stance(defender_id),
			]
		if outcome != null:
			summary = outcome.to_text()
			branches = outcome.branch_count
			complete = outcome.complete
			diagnostics = outcome.diagnostics.size()

	## One branch for [method ExchangeOutcome.enumerate]: the exchange in its own sandbox through
	## [param rolls], reported as the attacker's and defender's losses.
	func resolve_branch(rolls: ForcedRolls) -> ExchangeOutcome.Branch:
		var sandbox: Sandbox = Sandbox.new(base, rolls)
		var engine: EffectEngine = sandbox.engine
		var state: CombatState = engine.state
		var defender_hp: int = state.get_hp(defender_id)
		var defender_block: int = state.get_block(defender_id)
		var attacker_hp: int = state.get_hp(attacker_id)
		var attacker_block: int = state.get_block(attacker_id)
		engine.begin_step()
		ExchangeResolver.resolve(engine, state, attacker_id, defender_id)
		var branch: ExchangeOutcome.Branch = ExchangeOutcome.Branch.new()
		branch.attacker_defeated = not state.has_unit(attacker_id)
		branch.defender_defeated = not state.has_unit(defender_id)
		branch.dealt_hp = defender_hp - state.get_hp(defender_id)
		branch.dealt_block = maxi(defender_block - state.get_block(defender_id), 0)
		branch.taken_hp = attacker_hp - state.get_hp(attacker_id)
		branch.taken_block = maxi(attacker_block - state.get_block(attacker_id), 0)
		branch.defender_exposed = state.get_stance(defender_id) == 0
		branch.diagnostics = engine.diagnostics
		return branch


## A [CombatState] that records which units are read and written, for the census. Every read and
## write still goes to [CombatState]; only the bookkeeping is added.
class ReadTracker:
	extends CombatState

	## Read for a scan: listed, tested for presence, its side or tile read.
	const SCAN: int = 1
	## Its own data read: HP, Block, Stance, weapon, tags, type, movement, its state record.
	const DATA: int = 2
	## HP, Block, Stance or growth written.
	const WRITE: int = 4

	## Per unit id, the kinds of access seen ([constant SCAN], [constant DATA], [constant WRITE]).
	var reads: Dictionary[String, int] = {}

	func _init(map_grid: CombatGrid = null) -> void:
		super(map_grid)

	func unit(id: String) -> CombatUnitState:
		_note(id, DATA)
		return super(id)

	func occupant_at(tile: Vector2i) -> String:
		var id: String = super(tile)
		if not id.is_empty():
			_note(id, SCAN)
		return id

	func unit_ids() -> PackedStringArray:
		var ids: PackedStringArray = super()
		for id: String in ids:
			_note(id, SCAN)
		return ids

	func has_unit(id: String) -> bool:
		_note(id, SCAN)
		return super(id)

	func side_of(id: String) -> CombatFact.CombatSide:
		_note(id, SCAN)
		return super(id)

	func seat_of(id: String) -> int:
		_note(id, SCAN)
		return super(id)

	func tile_of(id: String) -> Vector2i:
		_note(id, SCAN)
		return super(id)

	func get_hp(id: String) -> int:
		_note(id, DATA)
		return super(id)

	func get_block(id: String) -> int:
		_note(id, DATA)
		return super(id)

	func get_stance(id: String) -> int:
		_note(id, DATA)
		return super(id)

	func tiles_moved(id: String) -> int:
		_note(id, DATA)
		return super(id)

	func darkness_layer(id: String) -> int:
		_note(id, DATA)
		return super(id)

	func equipped_weapon_id(unit_id: String) -> String:
		_note(unit_id, DATA)
		return super(unit_id)

	func tags_of(id: String) -> PackedStringArray:
		_note(id, DATA)
		return super(id)

	func unit_type_of(id: String) -> String:
		_note(id, DATA)
		return super(id)

	func set_hp(id: String, value: int) -> void:
		_note(id, WRITE)
		super(id, value)

	func set_block(id: String, value: int) -> void:
		_note(id, WRITE)
		super(id, value)

	func set_stance(id: String, value: int) -> void:
		_note(id, WRITE)
		super(id, value)

	func add_growth(id: String, stat: int, points: int) -> void:
		_note(id, WRITE)
		super(id, stat, points)

	func _note(id: String, kind: int) -> void:
		var mask: int = reads.get(id, 0)
		reads[id] = mask | kind
