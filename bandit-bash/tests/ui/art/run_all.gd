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
## Board art suite (P15 UL2): sprites, item icons, terrain tiles, map object and intent art, a
## thrown keg's fuse, and the item pick row's icon, in the case files declaring this suite (run
## through the base; each one's class doc lists its checks). The shared helpers are
## [code]tests/ui/ui_suite.gd[/code]'s.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/art/run_all.gd[/code].
## Prints one PASS or FAIL line per check and [code]--- N passed, M failed, K skipped ---[/code];
## exits with code 1 on any failure. Needs no test user folder: nothing is saved.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Board art: sprites, item icons, terrain, objects, intents, fuse"

var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_start("Board art tests")
		_run_case_files()
		_finish()
	return false
