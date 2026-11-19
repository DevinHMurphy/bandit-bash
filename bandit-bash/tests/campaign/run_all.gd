# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 12, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the campaign layer: the map graph, its generator and rules data, the run
## state, its commands and save sections, the battle bridge and the XP tally, a won combat's
## rewards, and placing a new item. They are the case files declaring this suite, which
## [code]tests/case_files.gd[/code] finds and runs in path order; each one's class doc lists its
## checks. Touches no save files.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/campaign/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## rules or bad run data log errors on purpose; only FAIL lines mean a problem.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Campaign map, run state, battle bridge, rewards and placement"

# Preloaded scripts used as types (gdscript.md, Naming): they have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Campaign tests. Errors from the generator and the run data are expected. ---")
	CaseFiles.run(self, _check)
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
