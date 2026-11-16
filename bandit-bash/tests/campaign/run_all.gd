# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 12, 2026
# Modified: November 16, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the campaign layer, a case file per topic (each one's class doc lists its
## checks): the map graph, its generator and its rules data (map_cases.gd), the run state, its
## commands and its save sections (run_state_cases.gd), the battle bridge, the XP tally and
## their sections (battle_bridge_cases.gd), a won combat's rewards (reward_cases.gd), and placing
## a new item and reading the report (placement_cases.gd). Touches no save files.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/campaign/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## rules or bad run data log errors on purpose; only FAIL lines mean a problem.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Campaign map, run state, battle bridge, rewards and placement"

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const MapCases = preload("res://tests/campaign/map_cases.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")
const BattleBridgeCases = preload("res://tests/campaign/battle_bridge_cases.gd")
const RewardCases = preload("res://tests/campaign/reward_cases.gd")
const PlacementCases = preload("res://tests/campaign/placement_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Campaign tests. Errors from the generator and the run data are expected. ---")

	GroupClock.lap("map_cases")
	MapCases.new(_check).run()
	GroupClock.lap("run_state_cases")
	RunStateCases.new(_check).run()
	GroupClock.lap("battle_bridge_cases")
	BattleBridgeCases.new(_check).run()
	GroupClock.lap("reward_cases")
	RewardCases.new(_check).run()
	GroupClock.lap("placement_cases")
	PlacementCases.new(_check).run()
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
