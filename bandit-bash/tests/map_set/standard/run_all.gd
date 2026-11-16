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

extends SceneTree
## Map set suite, standard part (combat map plan, MP10): every shipped map and the map pools
## (map_set_cases.gd), and a headless battle against the AI on each standard map
## (map_set_battle_cases.gd). The key maps' battles are the map_set/key suite: a battle per map
## takes minutes, the runner limits each suite's time, and suites run in parallel.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/map_set/standard/run_all.gd[/code]
## [br]Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## them.

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const MapSetCases = preload("res://tests/map_set/map_set_cases.gd")
const MapSetBattleCases = preload("res://tests/map_set/map_set_battle_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Map set tests: maps, pools and standard battles ---")
	MapSetCases.new(_check).run()
	MapSetBattleCases.new(_check, CombatMapDefinition.CombatType.STANDARD).run()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
