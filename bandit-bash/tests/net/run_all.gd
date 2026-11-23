# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the network layer: the case files declaring this suite, which
## [code]tests/case_files.gd[/code] finds and runs in path order, each built with the root; each
## one's class doc lists its checks.[br]
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/net/run_all.gd[/code].
## Prints PASS, FAIL or SKIP per case and exits with code 1 if any fails. The cases run on the
## first frame, when autoloads exist, since some call [code]SteamNetwork[/code]; this script
## compiles before they are registered. The two-peer cases run every peer in this process, on the
## loopback in [code]tests/net/harness/[/code]; the ENet cases skip where they can't open a
## port, and two instances of the project play one battle (enet_dev_cases.gd).

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Net: contract, relay, mirrors, rejoin, overlay, sizes, ENet dev"

# Preloaded scripts used as types (gdscript.md, Naming): they have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")
const NetCaseBase = preload("res://tests/net/net_case_base.gd")

var _failures: int = 0
var _passes: int = 0
var _skips: int = 0
var _has_run: bool = false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	print("--- Net tests. Errors from seats, the harness and the relay below are expected. ---")
	for cases: RefCounted in CaseFiles.run(self, _check, root):
		if cases is NetCaseBase:
			var net_cases: NetCaseBase = cases
			_skips += net_cases.skip_count()
	GroupClock.stop()
	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)
	return false


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
