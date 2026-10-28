# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the combat map: terrain definitions and loading a map scene into a
## [MapLayout] (layout_cases.gd); [MapGrid], [MapState], [Pathing] and the [CombatState] checks
## built on them (grid_cases.gd); [AutoDeploy] and the opening swap (deploy_cases.gd).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/map/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Autoloads don't exist in
## [code]--script[/code] mode, so nothing here may use them.

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const LayoutCases = preload("res://tests/map/layout_cases.gd")
const GridCases = preload("res://tests/map/grid_cases.gd")
const DeployCases = preload("res://tests/map/deploy_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Combat map tests ---")
	LayoutCases.new(_check).run()
	GridCases.new(_check).run()
	DeployCases.new(_check).run()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
