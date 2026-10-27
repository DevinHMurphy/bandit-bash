# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     owner.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name Owner
extends TargetSelector
## Selects the unit that owns the effect: the unit holding the item, or the unit with the trait.
##
## Effect text leaves this target out ("gain 3 Block"). An army-owned effect (a heirloom) has no
## owning unit; it selects through the fact or an area instead.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


func describe() -> String:
	return "this unit"


func is_owner() -> bool:
	return true


func select(ctx: EffectContext) -> PackedStringArray:
	var holder: String = ctx.owner_unit_id()
	if not ctx.engine.state.has_unit(holder):
		return PackedStringArray()
	return PackedStringArray([holder])
