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

extends SceneTree
## Map set suite, boss repeat part (Powder Baron plan, D2): the Powder Baron's keep at floor 18
## played twice from the same seed against the AI, each play stopped after
## [code]MapSetBattleCases.REPEAT_PHASES[/code] player phases, and the fact logs compared
## (map_set_battle_cases.gd). map_set/boss plays the battle once to its end; two full plays in one
## part outlast the runner's per-suite limit under a full parallel run.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script[/code]
## [code]res://tests/map_set/boss_repeat/run_all.gd[/code][br]
## Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure. The cases run in
## [code]_init[/code], before autoloads exist, so nothing here may use them.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "The Powder Baron's keep from one seed twice, the same fact log"

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const MapSetBattleCases = preload("res://tests/map_set/map_set_battle_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Map set tests: boss battle repeated ---")
	# The battle cases time the map; this group is their catalog's load.
	GroupClock.lap("map_set_battle_cases: catalog")
	MapSetBattleCases.new(
			_check, CombatMapDefinition.CombatType.BOSS, "", MapSetBattleCases.Plays.REPEAT
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
