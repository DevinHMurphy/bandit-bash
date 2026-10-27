# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stat_of.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name StatOf
extends ValueSource
## A unit's current value of a key: "this unit's Movement".
##
## Read through the session's stat read API, exact, with every modifier included.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The value key read: a [CombatValue], [DamageStage] or [CampaignValue] key.
@export var key: int = 0

## Whose value is read. [b]Null:[/b] the effect's owner. A selector that picks several units is a
## content error.
@export var subject: TargetSelector = null


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.value_key_hint()


func describe() -> String:
	var whose: String = "this unit" if subject == null else subject.describe()
	return "%s's %s" % [whose, EffectDefinition.key_name(key)]


## The first selected unit's value of [member key], exact; 0 when none is selected.
func evaluate(ctx: EffectContext) -> float:
	var units: PackedStringArray = PackedStringArray([ctx.owner_unit_id()])
	if subject != null:
		units = subject.select(ctx)
	if units.is_empty() or units[0].is_empty():
		return 0.0
	if units.size() > 1:
		ctx.engine.diagnostics.append(
				"StatOf: the subject selector picked %d units" % [units.size()]
		)
	return ctx.engine.stats(units[0]).get_value(key, ctx)
