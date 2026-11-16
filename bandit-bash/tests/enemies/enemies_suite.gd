# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemies_suite.gd
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================

extends SceneTree
## What the enemies suites share: the AI and intents
## ([code]tests/enemies/ai/run_all.gd[/code]), the setup and the roster's AI
## ([code]tests/enemies/roster/run_all.gd[/code]) and the roster's battles
## ([code]tests/enemies/battles/run_all.gd[/code]). Each extends this script: the check counters,
## the summary line the runner reads, and the definitions hash checked at the end. The case files
## stay in [code]tests/enemies/[/code], one per topic; the parts are split to take about the same
## time.[br]
## The cases run in [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they
## exist from the first frame, and their names are unknown while this script compiles), so nothing
## here or in a case file may use them.

# Preloaded scripts used as types (gdscript.md, Naming): the content suite's hashing and the
# loadout fixture tree the definitions hash covers.
const CatalogCases = preload("res://tests/content/catalog_cases.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")

var _failures: int = 0
var _passes: int = 0

# The definitions' hashes before the first case (event bus plan, question 50).
var _before: Dictionary[String, String] = {}


# Prints the suite's heading and hashes every definition, so _finish() can check that no case
# changed one. Call before any case.
func _start(title: String) -> void:
	print("--- %s ---" % [title])
	_before = CatalogCases.hash_definitions([LoadoutCases.TREE])


# Checks the definitions are as _start() found them, prints the summary line and quits, with
# exit code 1 on any failure.
func _finish() -> void:
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			_before, CatalogCases.hash_definitions([LoadoutCases.TREE])
	)
	_check("definitions: none changed during the run (%d hashed)" % [_before.size()], (
			changed.is_empty()
	), ", ".join(changed))
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
