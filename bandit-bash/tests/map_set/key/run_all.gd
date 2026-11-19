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

extends SceneTree
## Map set suite, key part (combat map plan, MP10): a headless battle against the AI on each key
## map but the Gatehouse at step 3, played twice to compare fact logs (map_set_battle_cases.gd).
## The Gatehouse is map_set/key_gatehouse; the maps' and pools' checks and the standard maps'
## battles are map_set/standard: a battle per map takes minutes, the runner limits each suite's
## time, and suites run in parallel.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/map_set/key/run_all.gd[/code][br]
## Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## them.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "An AI battle on each key map but the Gatehouse, played twice"

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const MapSetBattleCases = preload("res://tests/map_set/map_set_battle_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Map set tests: key battles ---")
	# The battle cases time each map; this group is their catalog's load.
	GroupClock.lap("map_set_battle_cases: catalog")
	MapSetBattleCases.new(_check, CombatMapDefinition.CombatType.KEY).run()
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
