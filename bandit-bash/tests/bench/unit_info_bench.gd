# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_info_bench.gd
# Author:
# Created:  November 6, 2026
# Modified: November 6, 2026
# ==============================================================================

extends Node
## Unit info layer benchmark (combat UI plan, UI7F row; question 29 (2)): the cost of one camera
## move with every M1 unit placed, which is what [BattleView] pays each frame the camera or a
## token moves: [method CameraRig.board_to_screen] and [method UnitInfoLayer.follow] over every
## unit's [UnitInfo].
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash res://tests/bench/unit_info_bench.tscn[/code][br]
## The workload is the M1 battle tests/ui begins (seed 0x0C0FFEE), after the opening swap window's
## Start, on a [BattleView] in the tree, zoomed onto a quarter of the map so the camera can move.
## Each sample moves the camera to the next point of a fixed walk across the map, then times one
## follow; the first [constant WARMUP] are dropped. After the timed loop a real frame runs and every
## info is checked against where the engine's own canvas transform draws its token. Measures only;
## changes nothing outside tests/bench/. Exits with code 1 if a check fails.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# Preloaded script used as a type (gdscript.md, Naming): the test helper has no class name.
const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")

# tests/ui's seed, so the board is the one the UI cases play.
const SEED: int = 0x0C0FFEE

# Timed camera moves, after as many dropped warm-ups.
const SAMPLES: int = 2000
const WARMUP: int = 200

# Points of the camera's walk: a Lissajous path over the map, so every move is a real one.
const WALK_X: float = 3.0
const WALK_Y: float = 2.0

# How far an info may sit from where the engine draws its token: rounding only.
const PLACE_TOLERANCE: float = 0.5

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
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
		_finish(run)
		return
	var session: CombatSession = battle.get_session(0)
	var view: BattleView = VIEW_SCENE.instantiate()
	add_child(view)
	view.bind(session)
	battle.submit(StartCommand.new(0), session.session_id)
	battle.resolve_queued()
	BattleViewCases.settle(view)
	var layer: UnitInfoLayer = view.get_info_layer()
	var units: int = layer.info_count()
	print("\nFixture: M1 battle, turn %d, %d units placed, %d infos" % [
		session.state.turn, session.state.unit_ids().size(), units,
	])
	if units == 0 or units != session.state.unit_ids().size():
		_failures.append("not one info per unit")
	_bench_moves(view)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_against_engine(view)
	view.queue_free()
	_finish(run)


func _print_header() -> void:
	var version: Dictionary = Engine.get_version_info()
	print("=== UI7F unit info layer benchmark ===")
	print("Godot %s, %s build (the editor binary): script runs slower than an export" % [
		version.get("string", "?"), "debug" if OS.is_debug_build() else "release",
	])
	print("CPU: %s, %d logical cores" % [OS.get_processor_name(), OS.get_processor_count()])
	print("Times in microseconds; one sample per camera move, %d warm-ups dropped." % [WARMUP])


func _bench_moves(view: BattleView) -> void:
	print("\n-- One camera move (every M1 unit placed) --")
	var rig: CameraRig = view.get_camera_rig()
	var layer: UnitInfoLayer = view.get_info_layer()
	var camera: Camera2D = rig.get_node(^"%Camera")
	var whole: Rect2 = view.map_rect()
	rig.frame(Rect2(whole.position, whole.size * 0.5))
	rig.map_rect = whole
	var transforms: PackedInt64Array = []
	var follows: PackedInt64Array = []
	var both: PackedInt64Array = []
	for i: int in SAMPLES + WARMUP:
		var t: float = float(i) / float(SAMPLES + WARMUP) * TAU
		var point: Vector2 = whole.get_center() + Vector2(
				sin(t * WALK_X) * whole.size.x * 0.5, sin(t * WALK_Y) * whole.size.y * 0.5
		)
		camera.position = rig.clamp_to_map(point)
		var started: int = Time.get_ticks_usec()
		var to_screen: Transform2D = rig.board_to_screen()
		var built: int = Time.get_ticks_usec()
		layer.follow(to_screen)
		var done: int = Time.get_ticks_usec()
		if i >= WARMUP:
			transforms.append(built - started)
			follows.append(done - built)
			both.append(done - started)
	_report("board_to_screen()", transforms)
	_report("follow() over every info", follows)
	_report("one camera move, total", both)
	print("Per info: median %.2f us" % [_median(follows) / maxf(layer.info_count(), 1.0)])


# After real frames the engine has applied the camera; each info must sit on its token.
func _check_against_engine(view: BattleView) -> void:
	var layer: UnitInfoLayer = view.get_info_layer()
	var worst: float = 0.0
	for unit_id: String in view.token_ids():
		var token: UnitToken = view.token_of(unit_id)
		var engine: Vector2 = token.get_global_transform_with_canvas().origin + layer.unit_offset
		worst = maxf(worst, layer.info_of(unit_id).position.distance_to(engine))
	print("\nAfter a real frame, the farthest info from where the engine draws its token: %.3f px" % [
		worst,
	])
	if worst > PLACE_TOLERANCE:
		_failures.append("an info is %.3f px off its token" % [worst])


func _finish(run: CampaignSession) -> void:
	run.close()
	if _failures.is_empty():
		print("\nDone: every check passed.")
	else:
		print("\nDone with %d failures:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


static func _report(label: String, samples: PackedInt64Array) -> void:
	print("%-48s n=%4d  median %7.1f  p95 %7.1f  max %7.0f" % [
		label, samples.size(), _median(samples), _p95(samples), _max(samples),
	])


static func _median(samples: PackedInt64Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: PackedInt64Array = samples.duplicate()
	sorted.sort()
	return float(sorted[floori(sorted.size() / 2.0)])


static func _p95(samples: PackedInt64Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: PackedInt64Array = samples.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.95))])


static func _max(samples: PackedInt64Array) -> float:
	var top: int = 0
	for sample: int in samples:
		top = maxi(top, sample)
	return float(top)
