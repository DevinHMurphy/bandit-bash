# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     xp_bar.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name XpBar
extends HBoxContainer
## One unit's XP bar in the victory recap: its level, a bar toward the next level and the XP
## count, filling from the XP it had before the combat to what it has now.
##
## The fill is linear, wraps at each level reached (the level label steps up with it), and takes
## √(XP gained) ÷ [member fill_divisor] seconds after [member fill_delay], then holds for
## [member hold_time] (Godot_FE's results bar). It runs on time handed to [method step], already
## scaled by the playback speed, so speed, fast-forward and skip are the caller's, and tests can
## step it. [method finish] jumps to the end.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## Wait before the bar starts filling.[br]
## [b]Units:[/b] seconds of playback time. [b]0.0:[/b] it fills at once.
@export_range(0.0, 2.0, 0.05) var fill_delay: float = 0.2

## The fill lasts √(XP gained) ÷ this; higher fills faster (6.0: 100 XP in about 1.7 s).[br]
## [b]Units:[/b] divisor of √XP, giving seconds of playback time.
@export_range(1.0, 30.0, 0.5) var fill_divisor: float = 6.0

## How long the full bar stays before the next one starts.[br]
## [b]Units:[/b] seconds of playback time. [b]0.0:[/b] the next starts at once.
@export_range(0.0, 2.0, 0.05) var hold_time: float = 0.3

var _per_level: int = 1
var _level_before: int = 0
var _start_xp: float = 0.0
var _gain: int = 0
var _elapsed: float = 0.0
var _is_running: bool = false
# Levels the shown XP has passed since the start level.
var _levels_passed: int = 0

@onready var _level_label: Label = %Level
@onready var _bar: ProgressBar = %Bar
@onready var _count_label: Label = %Count


## Shows [param xp] of [param per_level] at [param level], still.
func show_still(level: int, xp: int, per_level: int) -> void:
	_per_level = maxi(per_level, 1)
	_level_before = level
	_start_xp = float(xp)
	_gain = 0
	_is_running = false
	_show_progress(float(xp))


## Shows the state before the combat ([param level_before], [param xp_before]) and readies a fill
## of [param gain] XP; [method step] plays it.
func prepare(level_before: int, xp_before: int, gain: int, per_level: int) -> void:
	show_still(level_before, xp_before, per_level)
	_gain = maxi(gain, 0)
	_elapsed = 0.0
	_is_running = true


## Plays [param delta] seconds of playback time; returns whether the fill (or its hold) still runs.
func step(delta: float) -> bool:
	if not _is_running:
		return false
	_elapsed += maxf(delta, 0.0)
	var fill: float = fill_duration()
	var moving: float = clampf(_elapsed - fill_delay, 0.0, fill)
	var share: float = 1.0 if fill <= 0.0 else moving / fill
	_show_progress(_start_xp + _gain * share)
	if _elapsed >= fill_delay + fill + hold_time:
		_is_running = false
	return _is_running


## Ends the fill at once, the bar full to its end.
func finish() -> void:
	_is_running = false
	_show_progress(_start_xp + _gain)


## Whether a fill is playing.
func is_running() -> bool:
	return _is_running


## The fill's length for the prepared gain, before the delay and hold.[br]
## [b]Units:[/b] seconds of playback time.
func fill_duration() -> float:
	return sqrt(float(_gain)) / fill_divisor


## The level shown now, for tests.
func get_shown_level() -> int:
	return _level_before + _levels_passed


## The XP toward the next level shown now, for tests.
func get_shown_xp() -> int:
	return int(_bar.value)


# Shows total XP counted from the start level: the bar wraps at each level reached.
func _show_progress(total: float) -> void:
	_levels_passed = floori(total / _per_level)
	var into_level: float = total - _levels_passed * _per_level
	_bar.max_value = _per_level
	_bar.value = into_level
	_level_label.text = "Lv %d" % [_level_before + _levels_passed]
	_count_label.text = "%d / %d XP" % [int(into_level), _per_level]
