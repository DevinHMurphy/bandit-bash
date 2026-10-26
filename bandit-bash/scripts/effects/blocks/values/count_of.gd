# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     count_of.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name CountOf
extends ValueSource
## A count of the units a selector picks: "the number of adjacent allies" (Phalanx).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The units counted. [b]Null:[/b] a content error (counts 0).
@export var selector: TargetSelector = null

## Amount per unit counted. [b]1:[/b] the count itself.
@export var each: float = 1.0


func describe() -> String:
	var counted: String = "the number of %s" % ["?" if selector == null else selector.describe()]
	if is_equal_approx(each, 1.0):
		return counted
	return "%s × %s" % [EffectDefinition.format_number(each), counted]
