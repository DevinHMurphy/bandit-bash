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
## Enemies suite, battles part (enemies and AI plan, P05): the roster's five packs each played
## headless to the end against the Mercenary army ([code]roster_battle_cases.gd[/code]), alone in
## its part because these battles take about as long as each other part. The counters, the
## summary and the definitions check are the base's.[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/battles/run_all.gd[/code]
## [br]Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure.

# Preloaded script used as a type (gdscript.md, Naming): the cases have no class name.
const RosterBattleCases = preload("res://tests/enemies/roster_battle_cases.gd")


func _init() -> void:
	_start("Enemies tests: the roster's battles")
	RosterBattleCases.new(_check).run()
	_finish()
