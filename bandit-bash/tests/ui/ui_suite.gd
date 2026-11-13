# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ui_suite.gd
# Author:
# Created:  November 7, 2026
# Modified: November 12, 2026
# ==============================================================================

extends SceneTree
## What the three combat UI suites share (combat UI plan, P07): the board's
## ([code]tests/ui/board/run_all.gd[/code]), turn input's ([code]tests/ui/input/run_all.gd[/code])
## and the display's ([code]tests/ui/display/run_all.gd[/code]). Each extends this script: the
## check counters and the summary line the runner reads, the definitions hash every suite checks
## at its end, the test user folder guard, and pressing keys and clicking on the root viewport.
## The cases themselves stay in [code]tests/ui/battle/[/code], one file each, shared by the
## suites.[br]
## Never names an autoload, or the gameplay screen's class (whose script does): a suite compiles
## before autoloads are registered, so it reaches them as nodes and loads the screen at run
## time.[br]
## [b]Screen cases[/b] that drive the real [code]SaveService[/code], which writes save files, run
## only with a test user folder ([code]tools/run_tests.sh[/code] makes one; see
## [code]tests/sessions/run_all.gd[/code]) and are skipped otherwise.

const CatalogCases = preload("res://tests/content/catalog_cases.gd")

const GAMEPLAY_SCENE: String = "res://ui/battle/gameplay.tscn"

# NetLog.Level.WARN: a suite can't name the autoload (see the class doc).
const LOG_WARN: int = 1

# Any fixed run seed.
const RUN_SEED: int = 0x51A7E

# The save file the screen cases write, in the test user folder only.
const SAVE_NUMBER: int = 1

# The screen size the screen cases lay the screen out at: the project sets no window size, so this
# is Godot's default window and the base size of the canvas_items stretch.
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1152, 648)

var _failures: int = 0
var _passes: int = 0
var _skips: int = 0

# The definitions' hashes before the first case (event bus plan, question 50).
var _before: Dictionary[String, String] = {}


# Prints the suite's heading, quiets the log to warnings and hashes every definition, so
# _finish() can check that no case changed one. Call on the first frame, before any case.
func _start(title: String) -> void:
	print("--- %s ---" % [title])
	root.get_node(^"NetLog").set(&"min_level", LOG_WARN)
	_before = CatalogCases.hash_definitions(PackedStringArray())


# Checks the definitions are as _start() found them, prints the summary line and quits, with
# exit code 1 on any failure.
func _finish() -> void:
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			_before, CatalogCases.hash_definitions(PackedStringArray())
	)
	_check("definitions: none changed during the run (%d hashed)" % [_before.size()], (
			changed.is_empty()
	), ", ".join(changed))
	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)


# Counts a skipped case, printing why.
func _skip(case_name: String, reason: String) -> void:
	_skips += 1
	print("SKIP  %s: %s" % [case_name, reason])


# Whether this run uses a test user folder, which the screen cases need: a custom one whose name
# starts "bandit_bash_tests", as tools/run_tests.sh names each run's, so a real one is never used.
func _has_test_user_dir() -> bool:
	var custom_dir: bool = ProjectSettings.get_setting(
			"application/config/use_custom_user_dir", false
	)
	var dir_name: String = ProjectSettings.get_setting(
			"application/config/custom_user_dir_name", ""
	)
	return custom_dir and dir_name.begins_with("bandit_bash_tests")


# A press and release of key, by its physical position, as the input map binds it, and by its
# keycode, as Godot's built-in ui_cancel binds Esc.
func _press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = is_down
		root.push_input(event, true)


# A left click at point, in the root viewport's visible rect.
func _click(point: Vector2) -> void:
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_down
		root.push_input(click, true)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
