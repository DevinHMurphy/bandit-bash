# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     command_target.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name CommandTarget
extends TargetSelector
## Selects the unit a command names: the target of a cast rune ("heal the target for 10", Mend) or
## of a used Pouch item.
##
## Read from [member EffectContext.command_target_id]; selects nothing outside a command or when
## the target has left the map.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


func describe() -> String:
	return "the target"


func select(ctx: EffectContext) -> PackedStringArray:
	if not ctx.engine.state.has_unit(ctx.command_target_id):
		return PackedStringArray()
	return PackedStringArray([ctx.command_target_id])
