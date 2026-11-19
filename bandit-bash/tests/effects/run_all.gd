# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 26, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the event bus and effects layer: facts, buses and the tracer, value queries,
## effect text and the effect engine, run on the test-only map in harness/. They are the case
## files declaring this suite, which [code]tests/case_files.gd[/code] finds and runs in path order;
## each one's class doc lists its checks.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/effects/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in broken
## wire data make the fact classes log warnings on purpose; only FAIL lines mean a problem.[br]
## The cases run in [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they
## exist from the first frame, and their names are unknown while this script compiles), so nothing
## here may use them.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Event bus, facts, value queries and the effect engine"

# Preloaded scripts used as types (gdscript.md, Naming): they have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Event bus tests. Warnings from CombatFact and CampaignFact below are expected. ---")
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
