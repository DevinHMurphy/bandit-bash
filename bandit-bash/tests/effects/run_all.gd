# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 26, 2026
# Modified: November 9, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the event bus and effects layer, a case file per topic (each one's class
## doc lists its checks): facts (fact_cases.gd), buses and the tracer (bus_cases.gd), value
## queries (value_cases.gd), effect text (describe_cases.gd), and the effect engine
## (engine_cases.gd, golden_cases.gd, sandbox_cases.gd, stats_cases.gd), run on the test-only map
## in harness/.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/effects/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in broken
## wire data make the fact classes log warnings on purpose; only FAIL lines mean a problem.[br]
## The cases run in [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they
## exist from the first frame, and their names are unknown while this script compiles), so nothing
## here may use them.

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const FactCases = preload("res://tests/effects/fact_cases.gd")
const BusCases = preload("res://tests/effects/bus_cases.gd")
const ValueCases = preload("res://tests/effects/value_cases.gd")
const DescribeCases = preload("res://tests/effects/describe_cases.gd")
const EngineCases = preload("res://tests/effects/engine_cases.gd")
const GoldenCases = preload("res://tests/effects/golden_cases.gd")
const SandboxCases = preload("res://tests/effects/sandbox_cases.gd")
const StatsCases = preload("res://tests/effects/stats_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Event bus tests. Warnings from CombatFact and CampaignFact below are expected. ---")

	FactCases.new(_check).run()
	BusCases.new(_check).run()
	ValueCases.new(_check).run()
	DescribeCases.new(_check).run()
	EngineCases.new(_check).run()
	GoldenCases.new(_check).run()
	SandboxCases.new(_check).run()
	StatsCases.new(_check).run()

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
