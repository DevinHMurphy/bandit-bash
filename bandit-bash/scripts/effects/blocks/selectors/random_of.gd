# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     random_of.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name RandomOf
extends TargetSelector
## Selects one unit at random from another selector's units: "a random one of your units" (Haunted).
##
## [b]Randomness goes through the roll source[/b] (one [code]pick_index[/code] over the
## candidates), never a stream or the global RNG, so the forecast and the AI see the pick and its
## odds. This block holds no random state.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The units picked from. [b]Null:[/b] a content error (selects nothing).
@export var from: TargetSelector = null


func describe() -> String:
	return "a random one of %s" % ["?" if from == null else from.describe()]


## One [method RollSource.pick_index] over [member from]'s units; nothing, and no roll, when it
## selects none.
func select(ctx: EffectContext) -> PackedStringArray:
	if from == null:
		return PackedStringArray()
	var candidates: PackedStringArray = from.select(ctx)
	if candidates.is_empty() or ctx.engine.rolls == null:
		return PackedStringArray()
	var picked: int = ctx.engine.rolls.pick_index(candidates.size())
	return PackedStringArray([candidates[picked]])
