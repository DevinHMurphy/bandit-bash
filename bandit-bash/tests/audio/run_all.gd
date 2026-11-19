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
## Headless tests for the audio layer, a case file per topic (each one's class doc lists its
## checks): the cues and sound set (cue_cases.gd), the buses and volume settings
## (bus_cases.gd), the sound and music players (player_cases.gd), the interface sound hook
## (ui_hook_cases.gd), facts to cues and the music map (fact_cases.gd), and sounds never touching
## a seed (rng_cases.gd).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/audio/run_all.gd[/code][br]
## Headless runs use Godot's Dummy audio driver, which mixes without a sound device. The cases run
## on the first frame, when autoloads exist; the suite then waits for the playbacks it stopped to
## be freed, as one still held at quit reads as a leak, and quits. Prints PASS or FAIL per check
## and exits with code 1 if any fails.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Audio: cues, buses and settings, voices, music, UI hook, facts"

const GroupClock = preload("res://tests/group_clock.gd")
const CueCases = preload("res://tests/audio/cue_cases.gd")
const BusCases = preload("res://tests/audio/bus_cases.gd")
const PlayerCases = preload("res://tests/audio/player_cases.gd")
const UiHookCases = preload("res://tests/audio/ui_hook_cases.gd")
const FactCases = preload("res://tests/audio/fact_cases.gd")
const RngCases = preload("res://tests/audio/rng_cases.gd")

# The driver every headless run gets.
const HEADLESS_DRIVER: String = "Dummy"

# Longest wait for the audio thread to free stopped playbacks. Units: milliseconds.
const RELEASE_TIMEOUT_MSEC: int = 2000

var _failures: int = 0
var _passes: int = 0
var _frame: int = 0
var _player_cases: PlayerCases = null
var _rng_cases: RngCases = null
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
	_player_cases.free_nodes()
	_rng_cases.free_nodes()
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
	GroupClock.lap("cue_cases")
	CueCases.new(_check, root).run()
	GroupClock.lap("bus_cases")
	BusCases.new(_check, root).run()
	GroupClock.lap("player_cases")
	_player_cases = PlayerCases.new(_check, root)
	_player_cases.run()
	GroupClock.lap("ui_hook_cases")
	UiHookCases.new(_check, root).run()
	GroupClock.lap("fact_cases")
	FactCases.new(_check, root).run()
	GroupClock.lap("rng_cases")
	_rng_cases = RngCases.new(_check, root)
	_rng_cases.run()
	GroupClock.lap("release wait")
	_released = _player_cases.release()
	_released.append_array(_rng_cases.release())
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
