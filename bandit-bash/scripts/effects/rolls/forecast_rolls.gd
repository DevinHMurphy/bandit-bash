# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_rolls.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name ForecastRolls
extends RollSource
## The player forecast's rolls (event bus plan, question 8): every hit lands and every percent roll
## fails, so the forecast shows the damage of a hit and leaves chance-gated effects out of its
## totals. The records still carry every probability, for display and for the "25%: +X" lines.
##
## Draws nothing, so it is safe on any thread and never shifts a stream.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


func _draw_hit_2rn(_hit_percent: int, _odds: float) -> bool:
	return true


func _draw_percent(_chance: int, _odds: float) -> bool:
	return false


func _draw_index(_count: int) -> int:
	# ASSUMPTION: a forecast's random pick shows the first candidate; the plan says how hits and
	# chances forecast but not picks.
	return 0
