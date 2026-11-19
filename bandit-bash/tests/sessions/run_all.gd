# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 28, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the sessions layer: the case files declaring this suite, which
## [code]tests/case_files.gd[/code] finds and runs in path order, built with the root when they
## take it; each one's class doc lists its checks, and a [code]sessions_case_base.gd[/code] file's
## skips join the suite's. Every catalog definition and loadout fixture is hashed before the first
## case and after the last; any change fails.[br]
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/sessions/run_all.gd[/code].
## Prints PASS or FAIL per case and exits with code 1 if any fails. The cases run on the first
## frame, when autoloads exist; this script compiles before they are registered, so it reaches
## them as nodes.[br]
## [b]Lifecycle cases[/b] write save files, so they run only in a test user folder, one with a
## folder on its path whose name starts [code]bandit_bash_tests[/code], and are skipped otherwise;
## [code]tools/run_tests.sh[/code] gives each suite its own, and fails a suite that skips them.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Commands, sessions, saving, resuming, logging, wire format"

# Preloaded scripts used as types (gdscript.md, Naming): the content suite's hashing, the loadout
# fixture tree the definitions hash covers, the group timer, the case finder and the lifecycle
# cases' base (no class name).
const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")
const CatalogCases = preload("res://tests/content/catalog_cases.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")
const SessionsCaseBase = preload("res://tests/sessions/sessions_case_base.gd")

var _failures: int = 0
var _passes: int = 0
var _skips: int = 0
var _has_run: bool = false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	print("--- Sessions tests. Warnings and errors from rejected commands are expected. ---")
	root.get_node(^"NetLog").set(&"min_level", SessionsCaseBase.LOG_WARN)
	# Hashed before any case loads a definition (event bus plan, question 50).
	var before: Dictionary[String, String] = CatalogCases.hash_definitions([LoadoutCases.TREE])

	for cases: RefCounted in CaseFiles.run(self, _check, root):
		if cases is SessionsCaseBase:
			var lifecycle: SessionsCaseBase = cases
			_skips += lifecycle.skip_count()

	GroupClock.lap("definitions check")
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			before, CatalogCases.hash_definitions([LoadoutCases.TREE])
	)
	_check("definitions: none changed during the run (%d hashed)" % [before.size()], (
			changed.is_empty()
	), ", ".join(changed))
	GroupClock.stop()

	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)
	return false


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
