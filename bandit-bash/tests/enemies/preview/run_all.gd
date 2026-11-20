# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tests/enemies/enemies_suite.gd"
## Enemies suite, preview part (move-preview.md, Correctness): the move preview's equality cases,
## every reachable tile of every player unit on seeded random boards previewed and re-planned in
## full, and its checking mode, on the real catalog. Its own part because the re-plans take about
## as long as each other part, and later preview steps rerun it before and after each layer. They
## are the case files declaring this part, which [code]tests/case_files.gd[/code] finds and runs
## in path order. The counters, the summary and the definitions check are the base's.[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/preview/run_all.gd[/code]
## [br]Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "The move preview equals a full re-plan on seeded random boards"


func _init() -> void:
	_start("Enemies tests: the move preview's equality")
	CaseFiles.run(self, _check)
	_finish()
