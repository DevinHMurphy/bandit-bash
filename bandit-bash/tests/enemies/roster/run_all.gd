# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================

extends "res://tests/enemies/enemies_suite.gd"
## Enemies suite, setup and roster part (enemies and AI plan, P05): setup step 4 ([EnemySetup],
## [code]enemy_setup_cases.gd[/code]), the reinforcement waves' groups and the Hunted curse's extra
## enemies (steps 5 and 6, [code]reinforcement_setup_cases.gd[/code]), the roster's behaviors and
## packs ([code]roster_ai_cases.gd[/code]) and the AI's map objects
## ([code]object_ai_cases.gd[/code]). The counters, the summary and the definitions check are the
## base's.[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/roster/run_all.gd[/code]
## [br]Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Enemy setup, reinforcement waves, roster AI and map objects"

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const EnemySetupCases = preload("res://tests/enemies/enemy_setup_cases.gd")
const ObjectAiCases = preload("res://tests/enemies/object_ai_cases.gd")
const ReinforcementSetupCases = preload("res://tests/enemies/reinforcement_setup_cases.gd")
const RosterAiCases = preload("res://tests/enemies/roster_ai_cases.gd")


func _init() -> void:
	_start("Enemies tests: setup, the roster's AI and map objects")
	GroupClock.lap("enemy_setup_cases")
	EnemySetupCases.new(_check).run()
	GroupClock.lap("reinforcement_setup_cases")
	ReinforcementSetupCases.new(_check).run()
	GroupClock.lap("roster_ai_cases")
	RosterAiCases.new(_check).run()
	GroupClock.lap("object_ai_cases")
	ObjectAiCases.new(_check).run()
	_finish()
