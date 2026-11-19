# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 18, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## Map set suite, boss part (Powder Baron plan, D2): a headless battle against the AI on the
## Powder Baron's keep at floor 18, played once to its end (map_set_battle_cases.gd). Its own part
## because a battle on the larger boss map takes minutes, and the runner limits each suite's time;
## the same-seed comparison is map_set/boss_repeat, so neither part plays the battle twice.
##
## Case files declaring this part run first, through [code]tests/case_files.gd[/code].[br]
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script[/code]
## [code]res://tests/map_set/boss/run_all.gd[/code][br]
## Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure. The cases run in
## [code]_init[/code], before autoloads exist, so nothing here may use them.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "An AI battle on the Powder Baron's keep, played to its end"

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")
const MapSetBattleCases = preload("res://tests/map_set/map_set_battle_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Map set tests: boss battle ---")
	CaseFiles.run(self, _check)
	# The battle cases time the map; this group is their catalog's load.
	GroupClock.lap("map_set_battle_cases: catalog")
	MapSetBattleCases.new(
			_check, CombatMapDefinition.CombatType.BOSS, "", MapSetBattleCases.Plays.FIRST
	).run()
	GroupClock.stop()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
