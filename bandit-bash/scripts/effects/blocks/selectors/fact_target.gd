# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_target.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name FactTarget
extends TargetSelector
## Selects the other party of the triggering fact ("the other unit"): the attacker for Hit taken,
## the shover for Shoved ([member CombatFact.target_id]). Selects nothing when the fact has none.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


func describe() -> String:
	return "the other unit"


func select(ctx: EffectContext) -> PackedStringArray:
	if ctx.fact == null or not ctx.engine.state.has_unit(ctx.fact.target_id):
		return PackedStringArray()
	return PackedStringArray([ctx.fact.target_id])
