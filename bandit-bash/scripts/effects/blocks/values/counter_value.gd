# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     counter_value.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name CounterValue
extends ValueSource
## The current count of this effect's counter in one lane: "its count this combat".
##
## Read from the effect's runtime instance, which holds one count per lane.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The lane whose count is read.
@export var lane: EffectDefinition.Lane = EffectDefinition.Lane.COMBAT


func describe() -> String:
	return "its count %s" % [EffectDefinition.LANE_TEXT[lane]]


func evaluate(ctx: EffectContext) -> float:
	return 0.0 if ctx.instance == null else float(ctx.instance.get_counter(lane))
