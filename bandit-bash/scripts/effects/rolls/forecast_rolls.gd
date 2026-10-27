# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_rolls.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name ForecastRolls
extends RollSource
## The player forecast's rolls (event bus plan, question 8): every hit lands and every percent roll
## fails, so the forecast shows the damage of a hit and leaves chance-gated effects out of its
## totals. The records still carry every probability, for display and for the "25%: +X" lines.
## A random pick keeps the first candidate, and its record is marked
## [member RollRecord.is_placeholder] so the display calls it random (question 35).
##
## Draws nothing, so it is safe on any thread and never shifts a stream.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


## Keeps the first candidate and marks its record as a placeholder for a random pick.
func pick_index(count: int) -> int:
	var picked: int = super(count)
	if picked >= 0:
		records[-1].is_placeholder = true
	return picked


func _draw_hit_2rn(_hit_percent: int, _odds: float) -> bool:
	return true


func _draw_percent(_chance: int, _odds: float) -> bool:
	return false


func _draw_index(_count: int) -> int:
	return 0
