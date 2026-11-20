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
## Event screen suite: the case files declaring it, run in path order by
## [code]tests/case_files.gd[/code] on the first frame, each listing its checks in its class doc,
## with shared setup in event_screen_fixture.gd. The panel's cases drive every option kind by
## keyboard, mouse and pad over runs built in memory; the screen's cases use the real save and
## router, so they need a test user folder (see the base) and are skipped without one.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/events/run_all.gd[/code].
## Prints one PASS, FAIL or SKIP line per check and
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "The event screen: every option kind by key, mouse, pad; votes"

var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_start("Event screen tests")
		# The cases lay out and click at the base viewport, so the window is that size.
		root.size = BASE_SCREEN_SIZE
		_run_case_files()
		_finish()
	return false
