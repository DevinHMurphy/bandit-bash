# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 12, 2026
# Modified: November 13, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the campaign layer, a case file per topic (each one's class doc lists its
## checks): the map graph, its generator and its rules data (map_cases.gd), and the run state,
## its commands and its save sections (run_state_cases.gd). Touches no save files.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/campaign/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## rules or bad run data log errors on purpose; only FAIL lines mean a problem.

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const MapCases = preload("res://tests/campaign/map_cases.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Campaign tests. Errors from the generator and the run data are expected. ---")

	MapCases.new(_check).run()
	RunStateCases.new(_check).run()

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
