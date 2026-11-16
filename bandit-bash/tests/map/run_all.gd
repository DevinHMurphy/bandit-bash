# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 27, 2026
# Modified: November 16, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the combat map: terrain definitions and loading a map scene into a
## [MapLayout] (layout_cases.gd); [MapGrid], [MapState], [Pathing] and the [CombatState] checks
## built on them (grid_cases.gd); [AutoDeploy] and the opening swap (deploy_cases.gd); [Objectives],
## run in a [CombatSession] (objective_cases.gd); [MapCheck] (check_cases.gd); the M1 map, its
## [MapMarker] nodes and a battle opened on it (m1_cases.gd); [MapObjects] (object_cases.gd);
## [Reinforcements] (reinforcement_cases.gd).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/map/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## them.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Combat maps: layout, grid, pathing, deploy, objectives, objects"

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const LayoutCases = preload("res://tests/map/layout_cases.gd")
const GridCases = preload("res://tests/map/grid_cases.gd")
const DeployCases = preload("res://tests/map/deploy_cases.gd")
const ObjectiveCases = preload("res://tests/map/objective_cases.gd")
const CheckCases = preload("res://tests/map/check_cases.gd")
const M1Cases = preload("res://tests/map/m1_cases.gd")
const ObjectCases = preload("res://tests/map/object_cases.gd")
const ReinforcementCases = preload("res://tests/map/reinforcement_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Combat map tests ---")
	GroupClock.lap("layout_cases")
	LayoutCases.new(_check).run()
	GroupClock.lap("grid_cases")
	GridCases.new(_check).run()
	GroupClock.lap("deploy_cases")
	DeployCases.new(_check).run()
	GroupClock.lap("objective_cases")
	ObjectiveCases.new(_check).run()
	GroupClock.lap("check_cases")
	CheckCases.new(_check).run()
	GroupClock.lap("m1_cases")
	M1Cases.new(_check).run()
	GroupClock.lap("object_cases")
	ObjectCases.new(_check).run()
	GroupClock.lap("reinforcement_cases")
	ReinforcementCases.new(_check).run()
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
