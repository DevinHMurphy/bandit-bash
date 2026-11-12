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
## Headless tests for the RNG streams, a case file per topic (each one's class doc lists its
## checks): keys and the SplitMix64 mixer (key_cases.gd), streams (stream_cases.gd), a run's
## registry (registry_cases.gd), its save sections (rng_section_cases.gd) and the run seed
## (run_seed_cases.gd). The save sections through the real [code]SaveService[/code] are in the
## sessions suite's lifecycle cases.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/rng/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## input make the RNG classes log errors on purpose; only FAIL lines mean a problem.

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const KeyCases = preload("res://tests/rng/key_cases.gd")
const StreamCases = preload("res://tests/rng/stream_cases.gd")
const RegistryCases = preload("res://tests/rng/registry_cases.gd")
const RngSectionCases = preload("res://tests/rng/rng_section_cases.gd")
const RunSeedCases = preload("res://tests/rng/run_seed_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print(
			"--- RNG tests. Errors from RngStream, RngStreams, RngSaveSection and RunSeed below"
			+ " are expected. ---"
	)

	KeyCases.new(_check).run()
	StreamCases.new(_check).run()
	RegistryCases.new(_check).run()
	RngSectionCases.new(_check).run()
	RunSeedCases.new(_check).run()

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
