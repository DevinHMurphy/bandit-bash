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
## Headless tests for the audio layer: the cues and sound set, the buses and volume settings, the
## sound and music players, the interface sound hook, facts to cues and the music map, and sounds
## never touching a seed. They are the case files declaring this suite, built with the root, which
## [code]tests/case_files.gd[/code] finds and runs in path order; each one's class doc lists its
## checks.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/audio/run_all.gd[/code][br]
## Headless runs use Godot's Dummy audio driver, which mixes without a sound device. The cases run
## on the first frame, when autoloads exist; the suite then waits for the playbacks freed by each
## file's [code]release()[/code], if it has one, as one held at quit reads as a leak, calls each
## [code]free_nodes()[/code] and quits. Prints PASS or FAIL per check; exits 1 if any fails.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Audio: cues, buses and settings, voices, music, UI hook, facts"

const GroupClock = preload("res://tests/group_clock.gd")
const CaseFiles = preload("res://tests/case_files.gd")

# The driver every headless run gets.
const HEADLESS_DRIVER: String = "Dummy"

# Longest wait for the audio thread to free stopped playbacks. Units: milliseconds.
const RELEASE_TIMEOUT_MSEC: int = 2000

var _failures: int = 0
var _passes: int = 0
var _frame: int = 0
var _cases: Array[RefCounted] = []
var _released: Array[WeakRef] = []
var _release_started_msec: int = 0
var _is_done: bool = false


func _process(_delta: float) -> bool:
	if _is_done:
		return false
	_frame += 1
	if _frame == 1:
		_run_cases()
		return false
	var is_waiting: bool = Time.get_ticks_msec() - _release_started_msec < RELEASE_TIMEOUT_MSEC
	if is_waiting and _is_any_alive():
		return false
	_check(
			"cleanup: every playback the cases stopped was freed",
			not _is_any_alive(),
			"%d still held" % [_alive_count()],
	)
	_is_done = true
	for cases: RefCounted in _cases:
		if cases.has_method(&"free_nodes"):
			cases.call(&"free_nodes")
	GroupClock.stop()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)
	return false


func _run_cases() -> void:
	print("--- Audio tests. An error for a missing cue below is expected. ---")
	GroupClock.lap("driver")
	_check(
			"driver: a headless run plays on the %s audio driver" % [HEADLESS_DRIVER],
			AudioServer.get_driver_name() == HEADLESS_DRIVER,
			AudioServer.get_driver_name(),
	)
	_cases = CaseFiles.run(self, _check, root)
	GroupClock.lap("release wait")
	for cases: RefCounted in _cases:
		if cases.has_method(&"release"):
			var released: Array[WeakRef] = cases.call(&"release")
			_released.append_array(released)
	_release_started_msec = Time.get_ticks_msec()


func _is_any_alive() -> bool:
	return _alive_count() > 0


func _alive_count() -> int:
	var count: int = 0
	for ref: WeakRef in _released:
		if ref.get_ref() != null:
			count += 1
	return count


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
