# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     modify_value.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name ModifyValue
extends EffectOperation
## An always-on modifier on a value key: "+8 Combat Gold", "-2 Speed", "Range Max 2 instead of its
## base".
##
## Used by effects with trigger Always. Without conditions it is part of the owner's cached stat
## sheet; with While conditions it is checked live on every query. Becomes a [Modifier] sourced
## to the carrier at runtime.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The value key changed: a [CombatValue], [DamageStage] or [CampaignValue] key.
@export var key: int = 0

## How [member value] changes the key. Permission modes don't apply here; use [SetPermission].
@export var mode: Modifier.Mode = Modifier.Mode.ADD

## The addend, factor (+20% is 1.2), bound or replacement, in the key's own units. For an
## enum-valued key such as Damage Type, the enum value.
@export var value: float = 0.0


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.value_key_hint()


func describe() -> String:
	return EffectDefinition.describe_modifier(key, mode, value)
