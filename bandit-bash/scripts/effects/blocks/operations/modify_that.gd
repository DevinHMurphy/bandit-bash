# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     modify_that.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name ModifyThat
extends EffectOperation
## An inline change to the action in flight: "×0.5 Multipliers stage for that hit", "that attack
## gains lifesteal", "-1 to that Block gain".
##
## [b]Inline:[/b] runs at the trigger point, before the amount is committed, so it is allowed only
## on a trigger with an inline window (Attack made, Hit, Crit, Healed, Darkness damage taken,
## Block gained). Flags only turn on, never off, so the order of inline operations can't matter.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## What part of the action changes. Saved as an int: [b]append only[/b].
enum What {
	## A value key of that attack or hit, such as a damage stage, Hit or Damage Type.
	VALUE = 0,
	## The amount itself: that heal, that Block gain, that darkness damage.
	AMOUNT = 1,
	## A flag on that attack or hit.
	FLAG = 2,
}

## A flag an inline operation turns on. Saved as an int: [b]append only[/b].
enum Flag {
	## That attack heals the attacker for the damage it deals to HP (Block absorbed doesn't count).
	LIFESTEAL = 0,
	## That hit skips the Mitigation stage.
	SKIP_MITIGATION = 1,
}

## What "that" names in effect text, per trigger with an inline window.
const THAT_TEXT: Dictionary[int, String] = {
	EffectDefinition.Trigger.ATTACK_MADE: "that attack",
	EffectDefinition.Trigger.HIT_DEALT: "that hit",
	EffectDefinition.Trigger.HIT_TAKEN: "that hit",
	EffectDefinition.Trigger.CRIT_DEALT: "that hit",
	EffectDefinition.Trigger.CRIT_TAKEN: "that hit",
	EffectDefinition.Trigger.HEALED: "that heal",
	EffectDefinition.Trigger.HEALED_AN_ALLY: "that heal",
	EffectDefinition.Trigger.DARKNESS_DAMAGE_TAKEN: "that darkness damage",
	EffectDefinition.Trigger.BLOCK_GAINED: "that Block gain",
}

## What part of the action changes.
@export var what: What = What.VALUE

## The value key changed when [member what] is [constant VALUE]; ignored otherwise.
@export var key: int = 0

## How [member value] changes the key or the amount. Ignored for [constant FLAG].
@export var mode: Modifier.Mode = Modifier.Mode.ADD

## The addend, factor or replacement. Ignored for [constant FLAG]. An amount stays exact through
## its window and is rounded once when applied.
@export var value: float = 0.0

## The flag turned on when [member what] is [constant FLAG]; ignored otherwise.
@export var flag: Flag = Flag.LIFESTEAL


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.value_key_hint()


func describe() -> String:
	return describe_for_trigger(EffectDefinition.Trigger.ALWAYS)


func describe_for_trigger(trigger: EffectDefinition.Trigger) -> String:
	var noun: String = _noun(trigger)
	match what:
		What.AMOUNT:
			return "%s to %s" % [_amount_change(), noun]
		What.FLAG:
			if flag == Flag.LIFESTEAL:
				return "%s gains lifesteal" % [noun]
			return "%s skips Mitigation" % [noun]
	return "%s for %s" % [EffectDefinition.describe_modifier(key, mode, value), noun]


func is_inline() -> bool:
	return true


func _amount_change() -> String:
	var number: String = EffectDefinition.format_number(absf(value))
	match mode:
		Modifier.Mode.ADD:
			return "%s%s" % ["-" if value < 0.0 else "+", number]
		Modifier.Mode.MULTIPLY:
			return "×%s" % [EffectDefinition.format_number(value)]
		Modifier.Mode.FLOOR:
			return "at least %s" % [number]
		Modifier.Mode.CAP:
			return "at most %s" % [number]
	return "set %s" % [EffectDefinition.format_number(value)]


static func _noun(trigger: EffectDefinition.Trigger) -> String:
	return THAT_TEXT.get(trigger, "that action")
