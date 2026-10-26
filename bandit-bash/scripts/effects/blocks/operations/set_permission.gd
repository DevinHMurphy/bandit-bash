# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     set_permission.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name SetPermission
extends EffectOperation
## An always-on grant or denial of a permission: "allow May Move After Acting", "deny Stat Can
## Grow".
##
## Any denial beats any grant, so a curse or a boss trait can't be quietly cancelled. Becomes a
## [Modifier] with mode [constant Modifier.GRANT] or [constant Modifier.DENY].
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The permission key: a [enum CombatValue.Permission] or [enum CampaignValue.Permission] value.
@export var permission: int = 0

## [b]On:[/b] grants the permission. [b]Off:[/b] denies it.
@export var allow: bool = true


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "permission":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.permission_key_hint()


func describe() -> String:
	var mode: Modifier.Mode = Modifier.Mode.GRANT if allow else Modifier.Mode.DENY
	return EffectDefinition.describe_modifier(permission, mode, 0.0)
