# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ui_suite.gd
# Author:
# Created:  November 7, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## What the UI suites share: the combat UI's board ([code]tests/ui/board/run_all.gd[/code]), turn
## input ([code]tests/ui/input/run_all.gd[/code]) and display
## ([code]tests/ui/display/run_all.gd[/code]), and the campaign screens
## ([code]tests/ui/campaign/run_all.gd[/code]). Each extends this script: the check counters and
## the summary line the runner reads, the definitions hash checked at the end, the group timer
## (laps per case file and phase; [method _finish] stops it), running the case files that declare
## the suite, the test user folder guard, pressing keys and clicking on the root viewport, and
## entering a new run's first node. The combat cases stay in [code]tests/ui/battle/[/code].[br]
## Never names an autoload, or a class whose script does (the screens', [RunScreen]): a suite
## compiles before autoloads are registered, so it reaches them as nodes and loads screens at run
## time.[br]
## [b]Screen cases[/b] that drive the real [code]SaveService[/code], which writes save files, run
## only with a test user folder ([code]tools/run_tests.sh[/code] makes one; see
## [code]tests/sessions/run_all.gd[/code]) and are skipped otherwise.

const CaseFiles = preload("res://tests/case_files.gd")
const CatalogCases = preload("res://tests/content/catalog_cases.gd")
const GroupClock = preload("res://tests/group_clock.gd")

const GAMEPLAY_SCENE: String = "res://ui/battle/gameplay.tscn"

# NetLog.Level.WARN: a suite can't name the autoload (see the class doc).
const LOG_WARN: int = 1

# Any fixed run seed.
const RUN_SEED: int = 0x51A7E

# The save file the screen cases write, in the test user folder only.
const SAVE_NUMBER: int = 1

# The screen size the screen cases lay the screen out at: the project's base viewport, the size
# the canvas_items stretch lays every screen out at.
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1280, 720)

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


# Checks the definitions are as _start() found them, closes the last test group, prints the
# summary line and quits, with exit code 1 on any failure.
func _finish() -> void:
	GroupClock.lap("definitions check")
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			_before, CatalogCases.hash_definitions(PackedStringArray())
	)
	_check("definitions: none changed during the run (%d hashed)" % [_before.size()], (
			changed.is_empty()
	), ", ".join(changed))
	GroupClock.stop()
	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)


# Runs the case files declaring this suite, in path order (tests/case_files.gd), built with the
# root when they take it; one declaring NEEDS_TEST_USER_FOLDER is skipped without one. Returns
# the built files in that order.
func _run_case_files() -> Array[RefCounted]:
	return CaseFiles.run(self, _check, root, _has_test_user_dir(), _skip)


# Counts a skipped case, printing why.
func _skip(case_name: String, reason: String) -> void:
	_skips += 1
	print("SKIP  %s: %s" % [case_name, reason])


# Whether this run uses a test user folder, which the screen cases need: one with a folder on its
# path whose name starts "bandit_bash_tests", as tools/run_tests.sh gives each suite (and a manual
# override.cfg may name), so a real one is never used. Reads the folder Godot actually resolved.
func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# Enters the new run's first floor-1 node, a Standard combat, as choosing it on the campaign map
# would: the battle screen begins a battle only with the run inside a combat node.
func _enter_first_node() -> void:
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = service.get(&"session")
	if run == null or run.run == null:
		return
	service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))


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
