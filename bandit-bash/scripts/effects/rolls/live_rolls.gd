# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     live_rolls.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name LiveRolls
extends RollSource
## Real resolution's rolls, drawn only from the [RngStream] given at construction: the seat's
## [code]COMBAT_ROLLS[/code] stream (RNG streams plan, need R-N1).
##
## A 2RN hit always draws two d100, a percent roll one, a pick one (none for a single candidate),
## so the stream advances the same way whatever the odds. Main thread only: the stream is the
## session's live state, which no sandbox may touch.
##
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

var _stream: RngStream = null


func _init(stream: RngStream) -> void:
	_stream = stream


# Two d100; a hit if their integer average is below hit_percent, i.e. their sum is below twice it.
func _draw_hit_2rn(hit_percent: int, _odds: float) -> bool:
	var first: int = _stream.randi_range(0, _D100 - 1)
	var second: int = _stream.randi_range(0, _D100 - 1)
	return first + second < 2 * hit_percent


func _draw_percent(chance: int, _odds: float) -> bool:
	return _stream.roll_percent(chance)


func _draw_index(count: int) -> int:
	return _stream.pick_index(count)
