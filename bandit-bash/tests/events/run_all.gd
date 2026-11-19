# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## Headless tests for event outcomes, a case file per topic (each one's class doc lists its
## checks): every outcome block against a real run state (outcome_cases.gd), option requirements
## and event data (requirement_cases.gd), the weapon modification with test-only prefixes
## (weapon_prefix_cases.gd), and the resolver's all-or-nothing rule, curses and RNG use
## (resolver_cases.gd). Shared setup is in event_fixture.gd. Touches no save files.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/events/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Refused options log
## nothing; only FAIL lines mean a problem.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Event outcome blocks, requirements, weapon prefixes, resolver"

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const OutcomeCases = preload("res://tests/events/outcome_cases.gd")
const RequirementCases = preload("res://tests/events/requirement_cases.gd")
const WeaponPrefixCases = preload("res://tests/events/weapon_prefix_cases.gd")
const ResolverCases = preload("res://tests/events/resolver_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Event tests. ---")

	GroupClock.lap("outcome_cases")
	OutcomeCases.new(_check).run()
	GroupClock.lap("requirement_cases")
	RequirementCases.new(_check).run()
	GroupClock.lap("weapon_prefix_cases")
	WeaponPrefixCases.new(_check).run()
	GroupClock.lap("resolver_cases")
	ResolverCases.new(_check).run()
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
