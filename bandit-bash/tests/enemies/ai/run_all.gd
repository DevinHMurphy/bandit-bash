# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 30, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/enemies/enemies_suite.gd"
## Enemies suite, AI part (enemies and AI plan, P05): the enemy AI and its intents on the loadout
## fixture tree's enemy classes, and a headless M1 battle on the real catalog. They are the case
## files declaring this part, which [code]tests/case_files.gd[/code] finds and runs in path order;
## a file whose [code]_init[/code] needs a second argument gets the fixture catalog. The counters,
## the summary and the definitions check are the base's.[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/ai/run_all.gd[/code][br]
## Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure. Each step's cases
## live in their own file in [code]tests/enemies/[/code]; a new file goes to the part it keeps
## closest in time to the others.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Enemy AI and intents, and a headless battle on the M1 map"


func _init() -> void:
	_start("Enemies tests: AI, intents and the M1 battle")
	GroupClock.lap("fixture catalog load")
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	CaseFiles.run(self, _check, catalog)
	_finish()
