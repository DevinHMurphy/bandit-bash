# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     move_preview_bench.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

extends Node
## Move preview and tile pick benchmark (combat UI plan, UI3 row; questions 9 and 15 (h); enemies
## and AI plan, question 10's 50 ms per hovered tile): on the M1 battle,
## [method MovePreview.compute] and its two parts ([method Darkness.damage_at],
## [method Intents.preview]) for every tile each player unit can end its move on; the same through
## the threaded [MovePreview.Queue] (UI3F): the main thread's work in each frame and the latency
## per hover; and a tile pick's [method TurnInputModel.actions_at], with the
## [method Command.validate] calls it makes and one validation's cost.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash res://tests/bench/move_preview_bench.tscn[/code][br]
## The workload is the M1 battle tests/ui begins (seed 0x0C0FFEE), after the opening swap window's
## Start, on turn 1's player phase. Every move tile is one sample, so p95 is across tiles; each
## tile is warmed once first. Validations per pick are counted from the loops of
## [method TurnInputModel.actions_at] on the board as it stands (one per weapon, target and action
## it tries; within one, as its staff loop skips the unit when its own staff is legal), not
## instrumented. Measures only; changes nothing outside tests/bench/. Exits with code 1 if the
## fixture is not the intended one.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# Preloaded script used as a type (gdscript.md, Naming): the test helper has no class name.
const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# tests/ui's seed, so the board is the one the UI cases play.
const SEED: int = 0x0C0FFEE

# Question 10's target for one hovered tile.
const TARGET_USEC: float = 50000.0

# The threaded section's wait between polls: finer than a 60 Hz frame, so the latency it reports
# is the worker's own to within a millisecond, without a busy loop taking a core from the worker.
const POLL_USEC: int = 1000

# Runs of one validation, after as many warm-ups.
const VALIDATE_REPEATS: int = 200

var _failures: PackedStringArray = []


func _ready() -> void:
	_print_header()
	var map: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var battle: CombatEncounter = null
	if map != null:
		battle = BattleViewCases.begin_m1(EffectCatalog.index(), map, run)
	if battle == null:
		_failures.append("the M1 battle didn't begin")
	else:
		var session: CombatSession = battle.get_session(0)
		battle.submit(StartCommand.new(0), session.session_id)
		battle.resolve_queued()
		session.playback.play_all()
		if _check_fixture(session):
			_bench_preview(session)
			_bench_threaded(session)
			_bench_pick(session)
	run.close()
	if _failures.is_empty():
		print("\nDone: every check passed.")
	else:
		print("\nDone with %d failures:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _print_header() -> void:
	var version: Dictionary = Engine.get_version_info()
	print("=== UI3 move preview and tile pick benchmark ===")
	print("Godot %s, %s build (the editor binary): rules code runs slower than an export" % [
		version.get("string", "?"), "debug" if OS.is_debug_build() else "release",
	])
	print("CPU: %s, %d logical cores; one worker thread in the threaded section" % [
		OS.get_processor_name(), OS.get_processor_count(),
	])
	print("Times in microseconds; one sample per move tile, each warmed once.")


func _check_fixture(session: CombatSession) -> bool:
	var acting: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var enemies: int = session.state.units_of(CombatFact.CombatSide.ENEMY).size()
	print("\nFixture: M1 battle, turn %d, %d acting player units, %d enemies, intents %s" % [
		session.state.turn, acting.size(), enemies, session.intents != null,
	])
	if acting.is_empty() or session.intents == null or session.state.turn != 1:
		_failures.append("not turn 1's player phase with intents")
		return false
	return true


func _bench_preview(session: CombatSession) -> void:
	print("\n-- Move preview (every move tile of every acting unit) --")
	var whole: PackedInt64Array = []
	var darkness: PackedInt64Array = []
	var intents: PackedInt64Array = []
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			MovePreview.compute(session, unit_id, tile)
			var started: int = Time.get_ticks_usec()
			MovePreview.compute(session, unit_id, tile)
			whole.append(Time.get_ticks_usec() - started)
			started = Time.get_ticks_usec()
			Darkness.damage_at(session.engine, unit_id, tile)
			darkness.append(Time.get_ticks_usec() - started)
			started = Time.get_ticks_usec()
			Intents.preview(session, unit_id, tile)
			intents.append(Time.get_ticks_usec() - started)
	_report("MovePreview.compute (one hover)", whole)
	_report("  Darkness.damage_at", darkness)
	_report("  Intents.preview", intents)
	print("Question 10's target (%.0f per tile): median %s, p95 %s" % [
		TARGET_USEC,
		"met" if _median(whole) <= TARGET_USEC else "missed",
		"met" if _p95(whole) <= TARGET_USEC else "missed",
	])


# The threaded queue (MovePreview.Queue, as BattleController runs it): for each move tile, the
# main thread's work in the frame that starts the preview, in each frame while the worker runs
# (a poll every POLL_USEC, standing for frames), and in the frame that draws it, and the latency
# from the request to the preview returned.
func _bench_threaded(session: CombatSession) -> void:
	print("\n-- Threaded move preview (main-thread work per frame; latency per hover) --")
	var starts: PackedInt64Array = []
	var polls: PackedInt64Array = []
	var collects: PackedInt64Array = []
	var latencies: PackedInt64Array = []
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var queue: MovePreview.Queue = MovePreview.Queue.new()
			var requested: int = Time.get_ticks_usec()
			queue.request(unit_id, tile)
			queue.run_pending(session)
			starts.append(Time.get_ticks_usec() - requested)
			var ready: MovePreview = null
			while ready == null:
				OS.delay_usec(POLL_USEC)
				var polled: int = Time.get_ticks_usec()
				ready = queue.run_pending(session)
				var spent: int = Time.get_ticks_usec() - polled
				if ready == null:
					polls.append(spent)
				else:
					collects.append(spent)
			latencies.append(Time.get_ticks_usec() - requested)
	_report("frame that starts it (main thread)", starts)
	_report("frame while it runs (main thread)", polls)
	_report("frame that draws it (main thread)", collects)
	_report("hover to preview (latency)", latencies)


func _bench_pick(session: CombatSession) -> void:
	print("\n-- Tile pick (TurnInputModel.actions_at, every move tile) --")
	var picks: PackedInt64Array = []
	var counts: PackedInt64Array = []
	var sample: UnitTurnCommand = null
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			TurnInputModel.actions_at(session, unit_id, path)
			var started: int = Time.get_ticks_usec()
			TurnInputModel.actions_at(session, unit_id, path)
			picks.append(Time.get_ticks_usec() - started)
			counts.append(_validations(session, unit_id, path))
			if sample == null:
				sample = UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", path)
	_report("actions_at (one tile pick)", picks)
	counts.sort()
	print("%-48s n=%3d  median %9.0f  p95 %9.0f" % [
		"  validations per pick (counted)", counts.size(), _median(counts), _p95(counts),
	])
	var one: PackedInt64Array = []
	for run: int in VALIDATE_REPEATS * 2:
		var started: int = Time.get_ticks_usec()
		sample.validate(session)
		if run >= VALIDATE_REPEATS:
			one.append(Time.get_ticks_usec() - started)
	_report("  one UnitTurnCommand.validate (a Wait)", one)


# The validate() calls actions_at makes for unit_id after path, from its loops: each weapon on each
# enemy, the staff on itself and every unit, the item on each player unit, a shove on each other
# unit, the swap, each rune on each unit on the unit's own tile, and the wait.
static func _validations(session: CombatSession, unit_id: String, path: Array[Vector2i]) -> int:
	var state: CombatState = session.state
	if TurnInputModel.is_second_move(session, unit_id):
		return 1
	var unit: CombatUnitState = state.unit(unit_id)
	var weapons: int = 1
	if not unit.stowed_weapon_id.is_empty() and unit.stowed_weapon_id != unit.equipped_weapon_id:
		weapons = 2
	var count: int = state.units_of(CombatFact.CombatSide.ENEMY).size() * weapons
	count += state.unit_ids().size() + 1
	if not unit.pouch_item_id.is_empty():
		count += state.units_of(CombatFact.CombatSide.PLAYER).size()
	count += state.unit_ids().size() - 1
	count += 1
	if path.size() <= 1:
		var seat: int = state.seat_of(unit_id)
		var slots: PackedStringArray = state.rune_slots.get(seat, PackedStringArray())
		count += slots.size() * state.unit_ids().size()
	return count + 1


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
