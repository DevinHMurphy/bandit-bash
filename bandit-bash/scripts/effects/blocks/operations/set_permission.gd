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
## Grow (SPD)".
##
## Any denial beats any grant, so a curse or a boss trait can't be quietly cancelled. Becomes a
## [Modifier] with mode [constant Modifier.GRANT] or [constant Modifier.DENY]
## ([method make_modifier]).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The permission key: a [enum CombatValue.Permission] or [enum CampaignValue.Permission] value.
@export var permission: int = 0

## [b]On:[/b] grants the permission. [b]Off:[/b] denies it.
@export var allow: bool = true

## The stat a per-stat permission names, such as SPD for Training Weights' Stat Can Grow.
##
## [b]None:[/b] the permission isn't per stat. Ignored by every other permission.
@export var stat: int = Modifier.NO_STAT


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "permission":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.permission_key_hint()
	elif property["name"] == "stat":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.stat_hint()


func describe() -> String:
	return EffectDefinition.describe_modifier(permission, _mode(), 0.0, stat)


## Always-on permissions are read by queries, not applied: this only reports a content error.
func apply(ctx: EffectContext) -> void:
	ctx.engine.diagnostics.append(
			"SetPermission: %s applies only on an Always effect" % [ctx.instance.instance_id]
	)


## This operation as a [Modifier] sourced to [param instance].
func make_modifier(instance: EffectInstance) -> Modifier:
	var modifier: Modifier = Modifier.new(
			permission, _mode(), 0.0, instance.source_kind, instance.instance_id, instance.label
	)
	modifier.stat = stat
	return modifier


func _mode() -> Modifier.Mode:
	return Modifier.Mode.GRANT if allow else Modifier.Mode.DENY
