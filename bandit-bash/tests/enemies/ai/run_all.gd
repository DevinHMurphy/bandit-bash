# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 30, 2026
# Modified: November 16, 2026
# ==============================================================================

extends "res://tests/enemies/enemies_suite.gd"
## Enemies suite, AI part (enemies and AI plan, P05): the enemy AI ([code]ai_cases.gd[/code]) and
## its intents ([code]intent_cases.gd[/code]) on the loadout fixture tree's enemy classes, and a
## headless M1 battle on the real catalog ([code]m1_battle_cases.gd[/code]). The counters, the
## summary and the definitions check are the base's.[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/ai/run_all.gd[/code][br]
## Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure. Each step's cases
## live in their own file in [code]tests/enemies/[/code]; a new file goes to the part it keeps
## closest in time to the others.

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const AiCases = preload("res://tests/enemies/ai_cases.gd")
const IntentCases = preload("res://tests/enemies/intent_cases.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")


func _init() -> void:
	_start("Enemies tests: AI, intents and the M1 battle")
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	AiCases.new(_check, catalog).run()
	IntentCases.new(_check, catalog).run()
	M1BattleCases.new(_check).run()
	_finish()
