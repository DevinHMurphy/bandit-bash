# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/ui/ui_suite.gd"
## Victory sequence suite (P15 UL5): its parts, apart from the screens, in the case files
## declaring this suite (run through the base; each one's class doc lists its checks). The model's
## XP before the combat, fallen lines and stats; the reward list; the XP bar; the recap's rows,
## fills and level-ups; then, over a few frames so layout settles, a long recap scrolled by a pad,
## driven through the [code]victory_cases.gd[/code] file the finder built. The
## whole sequence on the real screens, by keyboard, mouse and pad with a quit and Continue, is
## [code]tests/ui/campaign/[/code]'s. The shared helpers are [code]tests/ui/ui_suite.gd[/code]'s.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/victory/run_all.gd[/code].
## Prints one PASS or FAIL line per check and [code]--- N passed, M failed, K skipped ---[/code];
## exits with code 1 on any failure. Needs no test user folder: nothing is saved.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Victory sequence parts: model, rewards, XP bar, recap, pad scroll"

# Preloaded script used as a type (gdscript.md, Naming): the scroll case's driver.
const VictoryCases = preload("res://tests/ui/victory/victory_cases.gd")

# Frames left between the scroll case's steps for layout and focus to settle.
const SETTLE_FRAMES: int = 3

var _frame: int = 0
var _cases: VictoryCases = null
var _old_root_size: Vector2i = Vector2i.ZERO


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_start("Victory sequence tests")
		_old_root_size = root.size
		root.size = BASE_SCREEN_SIZE
		for cases: RefCounted in _run_case_files():
			if cases is VictoryCases:
				_cases = cases
		GroupClock.lap("recap pad scroll")
		if _cases == null:
			_check("victory: victory_cases.gd ran, to drive the scroll case", false)
			root.size = _old_root_size
			_finish()
			# Past every later step, so no frame reaches the missing driver.
			_frame = 1 + SETTLE_FRAMES * 2
			return false
		_cases.begin_scroll()
		return false
	if _frame == 1 + SETTLE_FRAMES:
		_cases.press_down()
		return false
	if _frame == 1 + SETTLE_FRAMES * 2:
		_cases.finish_scroll()
		root.size = _old_root_size
		_finish()
	return false
