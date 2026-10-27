# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the combat core: its state and grid (state_cases.gd), the exchange
## (exchange_cases.gd), and Shove and splash (shove_cases.gd), run on the stub grid and the real
## effect engine.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/combat/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Autoloads don't exist in
## [code]--script[/code] mode, so nothing here may use them.

const StateCases: GDScript = preload("res://tests/combat/state_cases.gd")
const ExchangeCases: GDScript = preload("res://tests/combat/exchange_cases.gd")
const ShoveCases: GDScript = preload("res://tests/combat/shove_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Combat core tests ---")
	for cases_script: GDScript in [StateCases, ExchangeCases, ShoveCases]:
		# Variant: the case scripts have no class name to type them with.
		var cases: Variant = cases_script.new(_check)
		cases.run()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
