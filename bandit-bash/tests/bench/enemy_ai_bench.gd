# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_ai_bench.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

extends Node
## Enemy AI cost benchmark (enemies and AI plan, EN3): one enemy's decision per M1 class, every
## enemy decided once ([method EnemyAI.next_plan]), and one full enemy phase as the
## [constant CombatHooks.Hook.ENEMY_COMMANDS] hook plays it: [method EnemyAI.next_command] (with
## its validation), the command resolved, then the next, until every enemy has acted.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash res://tests/bench/enemy_ai_bench.tscn[/code][br]
## The workload is a seeded M1-sized board (8 × 8 with forest and a fort): the loadout fixture
## tree's Brute, Crossbowman and Hedge Healer at level 1 against four player units mid-battle,
## the Brute and one player unit wounded, so the Brute and Crossbowman have attacks and the healer
## a heal. The phase rows resolve with [ForecastRolls] (every hit lands) on a fresh board per run,
## built outside the timer. Each row prints its repeat count, median and p95 in microseconds,
## warm-up runs discarded; verify mode is off, as in release builds.[br]
## Measures only; changes nothing outside tests/bench/. Exits with code 1 if the fixture is not
## the intended one.
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

# Preloaded scripts used as types (gdscript.md, Naming): the test helpers have no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")

const ROWS: Array[String] = [
	"plain plain plain plain forest plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain forest plain plain plain plain forest plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain forest plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain fort plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
]

# Enemies: id, class, tile.
const ENEMIES: Array = [
	["e1", "loadout_brute", Vector2i(4, 2)],
	["e2", "loadout_crossbowman", Vector2i(6, 4)],
	["e3", "loadout_hedge_healer", Vector2i(6, 2)],
]

# Player units: id, tile, weapon preset, base changes.
const PLAYERS: Array = [
	["p1", Vector2i(1, 2), "sword", {}],
	["p2", Vector2i(2, 4), "bow", {}],
	["p3", Vector2i(3, 6), "sword", {CombatValue.Key.DEF: 4.0}],
	["p4", Vector2i(1, 3), "sword", {}],
]

# Warm-up runs and measured repeats per row: enough for a stable p95 while the bench stays near a
# minute on the dev machine. A p95 of fewer than 20 samples is the largest sample.
const WARMUP: int = 3
const REPEATS: int = 30

var _catalog: EffectCatalog.Index = null
var _failures: PackedStringArray = []


func _ready() -> void:
	_print_header()
	_catalog = EffectCatalog.load_tree(LoadoutCases.TREE)
	if _check_fixture():
		_bench_decisions()
		_bench_phase()
	if _failures.is_empty():
		print("\nDone: every check passed.")
	else:
		print("\nDone with %d failures:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _print_header() -> void:
	var version: Dictionary = Engine.get_version_info()
	print("=== EN3 enemy AI benchmark ===")
	print("Godot %s, %s build (the editor binary): rules code runs slower than an export" % [
		version.get("string", "?"), "debug" if OS.is_debug_build() else "release",
	])
	print("CPU: %s, %d logical cores; main thread only (question 17)" % [
		OS.get_processor_name(), OS.get_processor_count(),
	])
	print("Times in microseconds; warm-up runs discarded; verify mode off.")


# The board, with the enemy phase open so next_command's validation passes as in a battle.
func _build_world() -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, ROWS, ForecastRolls.new())
	for row: Array in ENEMIES:
		var enemy_id: String = row[0]
		var class_id: String = row[1]
		var enemy_tile: Vector2i = row[2]
		world.add_enemy(enemy_id, class_id, enemy_tile)
	for row: Array in PLAYERS:
		var player_id: String = row[0]
		var player_tile: Vector2i = row[1]
		var weapon: String = row[2]
		var changes: Dictionary = row[3]
		world.add_player(player_id, player_tile, weapon, changes)
	world.wound("e1", 12)
	world.wound("p2", 10)
	world.engine().verify = false
	world.state().phase_side = CombatFact.CombatSide.ENEMY
	world.state().turn = 2
	return world


func _check_fixture() -> bool:
	var world: AiWorld = _build_world()
	var reach: PackedStringArray = []
	for row: Array in ENEMIES:
		var unit_id: String = row[0]
		var tiles: int = Pathing.reach(world.engine(), world.state(), unit_id).size()
		reach.append("%s %d tiles" % [unit_id, tiles])
	print("\nFixture: 3 enemies vs 4 player units on 8 × 8; reach %s" % [", ".join(reach)])
	var kinds: PackedStringArray = []
	for row: Array in ENEMIES:
		var unit_id: String = row[0]
		var plan: EnemyPlan = world.decide(unit_id)
		kinds.append("%s %s" % [unit_id, EnemyPlan.Kind.find_key(plan.kind)])
	print("Plans: %s" % [", ".join(kinds)])
	var expected: PackedStringArray = ["e1 ATTACK", "e2 ATTACK", "e3 STAFF"]
	if not world.problems.is_empty() or kinds != expected:
		_failures.append("fixture: %s %s, expected %s" % [world.problems, kinds, expected])
		return false
	return true


func _bench_decisions() -> void:
	print("\n-- Decisions (one board, unchanged) --")
	var world: AiWorld = _build_world()
	for row: Array in ENEMIES:
		var unit_id: String = row[0]
		var decide: Callable = func() -> void:
			world.decide(unit_id)
		_report("decide %s (%s)" % [unit_id, row[1]], _time(decide))
	var all: Callable = func() -> void:
		EnemyAI.next_plan(world.engine(), _catalog)
	_report("next_plan: every enemy decided once", _time(all))


func _bench_phase() -> void:
	print("\n-- One full enemy phase (next_command, resolve, until none is left) --")
	var samples: PackedInt64Array = []
	var commands: int = 0
	for run: int in WARMUP + REPEATS:
		var world: AiWorld = _build_world()
		var engine: EffectEngine = world.engine()
		var given: int = 0
		# PhaseRunner's limit: an AI that keeps giving commands is a fault, not a longer phase.
		var limit: int = PhaseRunner.ENEMY_COMMANDS_PER_UNIT * ENEMIES.size()
		var started: int = Time.get_ticks_usec()
		while given < limit:
			var command: Command = EnemyAI.next_command(world.session, _catalog)
			if command == null:
				break
			given += 1
			engine.begin_step()
			command.resolve(world.session)
			engine.drain()
		var elapsed: int = Time.get_ticks_usec() - started
		if not engine.diagnostics.is_empty() or given == limit:
			_failures.append("phase: %d commands, diagnostics %s" % [given, engine.diagnostics])
			return
		if run >= WARMUP:
			samples.append(elapsed)
			commands = given
	_report("full enemy phase (%d commands)" % [commands], samples)


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
