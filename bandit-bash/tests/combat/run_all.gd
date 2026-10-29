# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 27, 2026
# Modified: October 28, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the combat core: its state and grid (state_cases.gd), the exchange
## (exchange_cases.gd), Shove and splash (shove_cases.gd), and the support actions
## (support_cases.gd), run on the stub grid and the real effect engine; and the turn loop and
## commands (turn_cases.gd), run in a [CombatSession] on a small real map.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/combat/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## them.

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const StateCases = preload("res://tests/combat/state_cases.gd")
const ExchangeCases = preload("res://tests/combat/exchange_cases.gd")
const ShoveCases = preload("res://tests/combat/shove_cases.gd")
const SupportCases = preload("res://tests/combat/support_cases.gd")
const TurnCases = preload("res://tests/combat/turn_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Combat core tests ---")
	StateCases.new(_check).run()
	ExchangeCases.new(_check).run()
	ShoveCases.new(_check).run()
	SupportCases.new(_check).run()
	TurnCases.new(_check).run()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
