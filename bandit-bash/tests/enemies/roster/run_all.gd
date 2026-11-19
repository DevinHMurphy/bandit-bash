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
## Enemies suite, setup and roster part (enemies and AI plan, P05): [EnemySetup], the
## reinforcement waves and the Hunted curse's extra enemies, the roster's behaviors and packs, the
## AI's map objects, elites, mini-bosses and the Powder Baron. They are the case files declaring
## this part, which [code]tests/case_files.gd[/code] finds and runs in path order; each one's class
## doc lists its checks. The counters, the summary and the definitions check are the base's.[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/roster/run_all.gd[/code]
## [br]Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = (
		"Enemy setup, reinforcement waves, roster AI, map objects, elites, mini-bosses and the boss"
)


func _init() -> void:
	_start("Enemies tests: setup, the roster's AI and map objects")
	CaseFiles.run(self, _check)
	_finish()
