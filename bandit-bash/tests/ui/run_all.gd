# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends SceneTree
## Combat UI suite (combat UI plan, P07): the battle board's view-model, the board on the M1 map,
## an M1 battle's facts played through the board, and the darkness overlay
## ([code]battle_view_cases.gd[/code]); then the gameplay screen itself, which begins a new solo
## run's M1 battle, plays it to its end from the debug bar and routes to Results.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/ui/run_all.gd[/code][br]
## Prints one PASS, FAIL or SKIP line per check and the summary line
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure.[br]
## The cases run from the first frame, when autoloads exist, and the routing case runs over a few
## more frames so the scene change happens. This script never names an autoload, or the gameplay
## screen's class (whose script does), since it compiles before autoloads are registered; it
## reaches them as nodes and loads the screen at run time.[br]
## [b]The routing case[/b] drives the real [code]SaveService[/code], which writes save files, so it
## runs only with a test user folder ([code]tools/run_tests.sh[/code] makes one; see
## [code]tests/sessions/run_all.gd[/code]) and is skipped otherwise.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const CatalogCases = preload("res://tests/content/catalog_cases.gd")

const GAMEPLAY_SCENE: String = "res://scenes/gameplay/gameplay.tscn"

# SceneRouter.Screen.RESULTS: this script can't name the autoload (see the class doc).
const SCREEN_RESULTS: int = 4

# NetLog.Level.WARN, for the same reason.
const LOG_WARN: int = 1

# Any fixed run seed.
const RUN_SEED: int = 0x51A7E

# The save file the routing case writes, in the test user folder only.
const SAVE_NUMBER: int = 1

# Player phases the routing case presses End Turn for before giving up.
const MAX_PHASES: int = 60

# Frames left for the scene change to Results before the last checks.
const ROUTE_FRAMES: int = 3

var _failures: int = 0
var _passes: int = 0
var _skips: int = 0
var _frame: int = 0
var _route_frame: int = -1
var _before: Dictionary[String, String] = {}


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		print("--- Combat UI tests ---")
		root.get_node(^"NetLog").set(&"min_level", LOG_WARN)
		# Hashed before the first case (event bus plan, question 50): no case may change a
		# definition.
		_before = CatalogCases.hash_definitions(PackedStringArray())
		BattleViewCases.new(_check, root).run()
		if _start_route_case():
			_route_frame = _frame
			return false
	elif _route_frame > 0 and _frame < _route_frame + ROUTE_FRAMES:
		return false
	elif _route_frame > 0:
		_finish_route_case()
	_finish()
	return false


func _finish() -> void:
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			_before, CatalogCases.hash_definitions(PackedStringArray())
	)
	_check("definitions: none changed during the run (%d hashed)" % [_before.size()], (
			changed.is_empty()
	), ", ".join(changed))
	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)


# A new solo run enters the gameplay screen, which begins the M1 battle; the debug bar's Start
# and End Turn play it until it ends, and the screen ends it and routes to Results. Returns true
# when the scene change is under way, so the remaining checks wait a few frames.
func _start_route_case() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  screen: routing to Results needs a test user folder (see the class doc)")
		return false
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var router: Node = root.get_node(^"SceneRouter")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"start_new_solo_run", RUN_SEED)
	_check("screen: a new solo run starts", err == OK, error_string(err))
	var run: CampaignSession = service.get(&"session")
	if run == null:
		return false

	var scene: PackedScene = load(GAMEPLAY_SCENE)
	var screen: Node = scene.instantiate()
	root.add_child(screen)
	var view: BattleView = screen.call(&"get_view")
	var bar: BattleDebugBar = screen.call(&"get_debug_bar")
	var session: CombatSession = view.get_session()
	_check("screen: entering it begins the M1 battle", (
			run.encounter != null
			and session != null
			and session.setup.map.id == "m1_greybox"
			and saves.get(&"combat") != null
	))
	if session == null:
		screen.free()
		return false
	var sorted_ids: PackedStringArray = session.state.unit_ids()
	sorted_ids.sort()
	_check("screen: one token per unit, each on its tile", (
			view.token_ids() == sorted_ids
			and sorted_ids.size() == 7
			and view.mismatches().is_empty()
	), "%s; %s" % [view.token_ids(), view.mismatches()])

	var start: Button = bar.get_start_button()
	_check("screen: Start shows in the opening swap window", (
			start.visible == session.state.map.opening_swap_open
	))
	if start.visible:
		start.pressed.emit()
		BattleViewCases.settle(view)
	var end_turn: Button = bar.get_end_turn_button()
	for _phase: int in MAX_PHASES:
		if session.is_finished:
			break
		if end_turn.disabled:
			BattleViewCases.settle(view)
			if end_turn.disabled:
				break
		end_turn.pressed.emit()
		BattleViewCases.settle(view)
	_check("screen: End Turn alone plays the battle to its end", session.is_finished, (
			"turn %d" % [session.state.turn]
	))
	var screen_now: int = router.get(&"current_screen")
	var combat_left: Object = saves.get(&"combat")
	_check("screen: a finished battle is ended and goes to Results", (
			screen_now == SCREEN_RESULTS and run.encounter == null and combat_left == null
	), "screen %d, encounter %s" % [screen_now, run.encounter])
	screen.queue_free()
	return true


# After the scene change: Results is the current scene; then the save file is dropped.
func _finish_route_case() -> void:
	var shown: Node = current_scene
	_check("screen: Results is the scene shown", (
			shown != null and shown.scene_file_path.ends_with("results_screen.tscn")
	), shown.scene_file_path if shown != null else "no scene")
	var saves: Node = root.get_node(^"SaveService")
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _has_test_user_dir() -> bool:
	var custom_dir: bool = ProjectSettings.get_setting(
			"application/config/use_custom_user_dir", false
	)
	var dir_name: String = ProjectSettings.get_setting(
			"application/config/custom_user_dir_name", ""
	)
	return custom_dir and dir_name == "bandit_bash_tests"


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
