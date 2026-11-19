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
## Headless tests for the RNG streams: keys and the SplitMix64 mixer, streams, a run's registry,
## its save sections and the run seed. They are the case files declaring this suite, which
## [code]tests/case_files.gd[/code] finds and runs in path order; each one's class doc lists its
## checks. The save sections through the real [code]SaveService[/code] are in the sessions suite's
## lifecycle cases.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/rng/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## input make the RNG classes log errors on purpose; only FAIL lines mean a problem.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Seeded random streams: keys, streams, registry, saves, seeds"

# Preloaded scripts used as types (gdscript.md, Naming): they have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print(
			"--- RNG tests. Errors from RngStream, RngStreams, RngSaveSection and RunSeed below"
			+ " are expected. ---"
	)
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
