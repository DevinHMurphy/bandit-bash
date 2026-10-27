# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     target_selector.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
@abstract
class_name TargetSelector
extends Resource
## Base for who an operation affects: the owner, a fact's units, an area, a scope, a random pick.
##
## Subclasses are inspector blocks inside operations and value sources; read-only at runtime.
## Positional selectors never reach across parallel maps.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


## The units this selects, as a noun phrase for effect text, such as "adjacent allies".
@abstract func describe() -> String


## Whether this selects the effect's owner, so effect text can leave the target out.
func is_owner() -> bool:
	return false


## The instance ids this selects for [param ctx]'s effect and fact, in the state's unit order.
## Selects only units and objects on the map; may be empty.
@abstract func select(ctx: EffectContext) -> PackedStringArray
