# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stat_of.gd
# Author:
# Created:  October 26, 2026
# Modified: November 20, 2026
# ==============================================================================

@tool
class_name StatOf
extends ValueSource
## A unit's current value of a key, or a share of it: "this unit's Movement", "10% of this unit's
## HP" (the Sunshard Band's heal).
##
## Read through the session's stat read API, exact, with every modifier included; a share is
## rounded half up, as the Feast's heal is (P08 question 9).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The value key read: a [CombatValue], [DamageStage] or [CampaignValue] key.
@export var key: int = 0

## Whose value is read. [b]Null:[/b] the effect's owner. A selector that picks several units is a
## content error.
@export var subject: TargetSelector = null

## The share of the value given.[br]
## [b]Units:[/b] percent of the value, rounded half up to a whole number. [b]100:[/b] the value
## itself, exact and unrounded. [b]0:[/b] always 0.
@export_range(0, 100, 1, "or_greater") var percent: int = 100


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectTerms.value_key_hint()


func describe() -> String:
	var whose: String = "this unit" if subject == null else subject.describe()
	var text: String = "%s's %s" % [whose, EffectTerms.text_name(key)]
	if percent != 100:
		text = "%d%% of %s" % [percent, text]
	return text


## The first selected unit's value of [member key], exact, or its [member percent] share rounded
## half up; 0 when none is selected.
func evaluate(ctx: EffectContext) -> float:
	var value: float = _read(ctx)
	if percent == 100:
		return value
	return float(ValueBreakdown.round_to_int(
			value * percent / 100.0, ValueBreakdown.Rounding.HALF_UP
	))


# The first selected unit's value of key, exact; 0 when none is selected.
func _read(ctx: EffectContext) -> float:
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
