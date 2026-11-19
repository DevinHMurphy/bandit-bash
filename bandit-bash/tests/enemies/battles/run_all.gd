# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 16, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/enemies/enemies_suite.gd"
## Enemies suite, battles part (enemies and AI plan, P05): the roster's five packs each played
## headless to the end against the Mercenary army, alone in its part because these battles take
## about as long as each other part. They are the case files declaring this part, which
## [code]tests/case_files.gd[/code] finds and runs in path order. The counters, the summary and the
## definitions check are the base's.[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/battles/run_all.gd[/code]
## [br]Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "The enemy roster's five packs, each played to the end"


func _init() -> void:
	_start("Enemies tests: the roster's battles")
	CaseFiles.run(self, _check)
	_finish()
