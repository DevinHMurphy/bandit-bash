# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intents_bench.gd
# Author:
# Created:  November 3, 2026
# Modified: November 3, 2026
# ==============================================================================

extends Node
## Intents cost benchmark (enemies and AI plan, EN4; question 10's target is 50 ms per hovered
## tile): [method Intents.compute] (the chained enemy phase and the danger zone), the danger zone
## alone, and [method Intents.preview] for every tile each player unit can end its move on.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash res://tests/bench/intents_bench.tscn[/code][br]
## The workload is EN3's benchmark board ([code]enemy_ai_bench.gd[/code]): the loadout fixture
## tree's Brute, Crossbowman and Hedge Healer at level 1 against four player units on 8 × 8, in
## turn 2's player phase. Previews build on intents computed once, outside the timer; every
## hovered tile is one sample, so its p95 is across tiles. Each row prints its sample count,
## median and p95 in microseconds, warm-up runs discarded; verify mode is off, as in release
## builds. Measures only; changes nothing outside tests/bench/. Exits with code 1 if the fixture
## is not the intended one.
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

# Preloaded scripts used as types (gdscript.md, Naming): the test helpers have no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")
const EnemyAiBench = preload("res://tests/bench/enemy_ai_bench.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")

# Question 10's target for one hovered tile.
const TARGET_USEC: float = 50000.0

# Warm-up runs and measured repeats for the compute rows, as EN3's benchmark.
const WARMUP: int = 3
const REPEATS: int = 30

var _catalog: EffectCatalog.Index = null
var _failures: PackedStringArray = []


func _ready() -> void:
	_print_header()
	_catalog = EffectCatalog.load_tree(LoadoutCases.TREE)
	var world: AiWorld = _build_world()
	if _check_fixture(world):
		_bench_compute(world)
		_bench_preview(world)
	if _failures.is_empty():
		print("\nDone: every check passed.")
	else:
		print("\nDone with %d failures:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _print_header() -> void:
	var version: Dictionary = Engine.get_version_info()
	print("=== EN4 intents benchmark ===")
	print("Godot %s, %s build (the editor binary): rules code runs slower than an export" % [
		version.get("string", "?"), "debug" if OS.is_debug_build() else "release",
	])
	print("CPU: %s, %d logical cores; main thread only (question 17)" % [
		OS.get_processor_name(), OS.get_processor_count(),
	])
	print("Times in microseconds; warm-up runs discarded; verify mode off.")


# EN3's board, in turn 2's player phase with its intents computed.
func _build_world() -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, EnemyAiBench.ROWS, ForecastRolls.new())
	for row: Array in EnemyAiBench.ENEMIES:
		var enemy_id: String = row[0]
		var class_id: String = row[1]
		var enemy_tile: Vector2i = row[2]
		world.add_enemy(enemy_id, class_id, enemy_tile)
	for row: Array in EnemyAiBench.PLAYERS:
		var player_id: String = row[0]
		var player_tile: Vector2i = row[1]
		var weapon: String = row[2]
		var changes: Dictionary = row[3]
		world.add_player(player_id, player_tile, weapon, changes)
	world.wound("e1", 12)
	world.wound("p2", 10)
	world.engine().verify = false
	world.state().phase_side = CombatFact.CombatSide.PLAYER
	world.state().turn = 2
	world.session.intents = Intents.compute(world.session, _catalog)
	return world


func _check_fixture(world: AiWorld) -> bool:
	var shown: PackedStringArray = []
	for intent: EnemyIntent in world.session.intents.enemies:
		shown.append(intent.describe())
	print("\nFixture: 3 enemies vs 4 player units on 8 × 8")
	print("Intents: %s" % [" | ".join(shown)])
	if not world.problems.is_empty() or shown.size() != EnemyAiBench.ENEMIES.size():
		_failures.append("fixture: %s, %d intents" % [world.problems, shown.size()])
		return false
	return true


func _bench_compute(world: AiWorld) -> void:
	print("\n-- Compute (one board, unchanged) --")
	var compute: Callable = func() -> void:
		Intents.compute(world.session, _catalog)
	_report("compute: the chained phase and danger zone", _time(compute))
	var zone: Callable = func() -> void:
		DangerZone.compute(world.engine())
	_report("danger zone alone", _time(zone))


func _bench_preview(world: AiWorld) -> void:
	print("\n-- Preview (every tile each player unit can end on, one sample per tile) --")
	var all: PackedInt64Array = []
	var decided: int = 0
	for row: Array in EnemyAiBench.PLAYERS:
		var unit_id: String = row[0]
		var samples: PackedInt64Array = []
		var tiles: Dictionary[Vector2i, int] = Pathing.reach(world.engine(), world.state(), unit_id)
		var ordered: Array[Vector2i] = tiles.keys()
		for warm: int in WARMUP:
			Intents.preview(world.session, unit_id, ordered[warm % ordered.size()])
		for tile: Vector2i in tiles:
			var started: int = Time.get_ticks_usec()
			var preview: Intents = Intents.preview(world.session, unit_id, tile)
			var elapsed: int = Time.get_ticks_usec() - started
			if preview == null:
				_failures.append("preview: %s to %s gave none" % [unit_id, tile])
				continue
			samples.append(elapsed)
			decided += preview.decisions
		_report("preview %s (%d tiles)" % [unit_id, tiles.size()], samples)
		all.append_array(samples)
	_report("preview, every tile", all)
	all.sort()
	print("Decisions per preview: %.2f on average (compute makes %d)" % [
		float(decided) / maxi(all.size(), 1), world.session.intents.decisions,
	])
	var p95: float = _p95(all)
	print("Question 10's target (%.0f per tile): p95 %s, median %s" % [
		TARGET_USEC,
		"met" if p95 <= TARGET_USEC else "missed",
		"met" if _median(all) <= TARGET_USEC else "missed",
	])


func _time(work: Callable) -> PackedInt64Array:
	var samples: PackedInt64Array = []
	for run: int in WARMUP + REPEATS:
		var started: int = Time.get_ticks_usec()
		work.call()
		var elapsed: int = Time.get_ticks_usec() - started
		if run >= WARMUP:
			samples.append(elapsed)
	return samples


func _report(label: String, samples: PackedInt64Array) -> void:
	samples.sort()
	print("%-48s n=%3d  median %9.0f  p95 %9.0f" % [
		label, samples.size(), _median(samples), _p95(samples),
	])


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
