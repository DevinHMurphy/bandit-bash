# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 27, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the combat core: its state and grid, the exchange, Shove and splash and the
## support actions on the stub grid and the real effect engine, and the turn loop, commands,
## forecast and AI summary in a [CombatSession] on a small real map. They are the case files
## declaring this suite, which [code]tests/case_files.gd[/code] finds and runs in path order; each
## one's class doc lists its checks. Every catalog definition and loadout fixture is hashed before
## the first case and after the last, and the run fails if any changed.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/combat/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## them.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Combat rules: grid, exchanges, Shove, support, turns, forecasts"

# Preloaded scripts used as types (gdscript.md, Naming): they have no class name. The content
# suite's two give the definitions hash.
const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")
const CatalogCases = preload("res://tests/content/catalog_cases.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Combat core tests ---")
	# Hashed before the first case (event bus plan, question 50): combat reads definitions through
	# the loadout, so no case may change one.
	var before: Dictionary[String, String] = CatalogCases.hash_definitions([LoadoutCases.TREE])
	CaseFiles.run(self, _check)
	GroupClock.lap("definitions check")
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			before, CatalogCases.hash_definitions([LoadoutCases.TREE])
	)
	_check("definitions: none changed during the run (%d hashed)" % [before.size()], (
			changed.is_empty()
	), ", ".join(changed))
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
