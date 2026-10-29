# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     modify_value.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name ModifyValue
extends EffectOperation
## An always-on modifier on a value key: "+8 Combat Gold", "-2 SPD", "Range Max 2 instead of its
## base".
##
## Used by effects with trigger Always. Without conditions it is part of the owner's cached stat
## sheet; with While conditions it is checked live on every query. Becomes a [Modifier] sourced
## to the carrier at runtime ([method make_modifier]).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The value key changed: a [CombatValue], [DamageStage] or [CampaignValue] key.
@export var key: int = 0

## How [member value] changes the key. Permission modes don't apply here; use [SetPermission].
@export var mode: Modifier.Mode = Modifier.Mode.ADD

## The addend, factor (+20% is 1.2), bound or replacement, in the key's own units. For an
## enum-valued key such as Damage Type, the enum value.
@export var value: float = 0.0

## The stat a per-stat key changes, such as MGT for Training Weights' Level Up Guaranteed Gains.
##
## [b]None:[/b] the key isn't per stat. Ignored by every other key.
@export var stat: int = Modifier.NO_STAT


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectTerms.value_key_hint()
	elif property["name"] == "stat":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectTerms.stat_hint()


func describe() -> String:
	return EffectTerms.describe_modifier(key, mode, value, stat)


## Always-on modifiers are read by value queries, not applied: this only reports a content error.
func apply(ctx: EffectContext) -> void:
	ctx.engine.diagnostics.append(
			"ModifyValue: %s applies only on an Always effect" % [ctx.instance.instance_id]
	)


## This operation as a [Modifier] sourced to [param instance].
func make_modifier(instance: EffectInstance) -> Modifier:
	var modifier: Modifier = Modifier.new(
			key, mode, value, instance.source_kind, instance.instance_id, instance.label
	)
	modifier.stat = stat
	return modifier
