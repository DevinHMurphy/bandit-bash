# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the enemies: setup step 4 ([EnemySetup], enemy_setup_cases.gd).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## them. Each step's cases live in their own file; add a line per file here.

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const EnemySetupCases = preload("res://tests/enemies/enemy_setup_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Enemy tests ---")
	EnemySetupCases.new(_check).run()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
