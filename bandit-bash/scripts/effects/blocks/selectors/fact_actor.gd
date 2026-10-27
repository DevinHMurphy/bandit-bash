# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_actor.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name FactActor
extends TargetSelector
## Selects the triggering fact's actor: the unit the trigger is about ("that unit").
##
## For Hit taken that is the unit hit; for Healed, the unit healed ([member CombatFact.actor_id]).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


func describe() -> String:
	return "that unit"


func select(ctx: EffectContext) -> PackedStringArray:
	if ctx.fact == null or not ctx.engine.state.has_unit(ctx.fact.actor_id):
		return PackedStringArray()
	return PackedStringArray([ctx.fact.actor_id])
