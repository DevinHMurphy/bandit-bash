# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     add_timed_modifier.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name AddTimedModifier
extends EffectOperation
## Gives units a modifier that lasts until an end, or for a number of uses: Momentum's "+15 Hit on
## its next attack this combat", War Horn's "+2 Attack until the end of the next phase".
##
## Queued. The modifier is session state; whichever comes first, its end or its last use, removes
## it. A use is spent when the holder's next attack that started after the modifier was added
## finishes, counters included, hit or miss.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## When the modifier expires. Saved as an int: [b]append only[/b].
enum End {
	## After Combat of the exchange it was added in.
	THIS_EXCHANGE = 0,
	## Phase End of the phase it was added in.
	UNTIL_PHASE_END = 1,
	## Phase End of the phase after the one it was added in.
	END_OF_NEXT_PHASE = 2,
	## Battle end.
	THIS_COMBAT = 3,
}

## Effect-text words for each end.
const END_TEXT: Dictionary[int, String] = {
	End.THIS_EXCHANGE: "this exchange",
	End.UNTIL_PHASE_END: "until Phase End",
	End.END_OF_NEXT_PHASE: "until the end of the next phase",
	End.THIS_COMBAT: "this combat",
}

## Who gets the modifier. [b]Null:[/b] the effect's owner.
@export var target: TargetSelector = null

## The value or permission key changed.
@export var key: int = 0

## How [member value] changes the key; [constant Modifier.GRANT] and [constant Modifier.DENY]
## make a timed permission.
@export var mode: Modifier.Mode = Modifier.Mode.ADD

## The addend, factor, bound or replacement, in the key's own units. Ignored by permission modes.
@export var value: float = 0.0

## When the modifier expires at the latest.
@export var end: End = End.THIS_EXCHANGE

## Attacks it lasts for. [b]0:[/b] no limit, only [member end]. [b]1:[/b] "next attack".
@export_range(0, 99) var uses: int = 0


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = "%s,%s" % [
			EffectTerms.value_key_hint(),
			EffectTerms.permission_key_hint(),
		]


func describe() -> String:
	var change: String = EffectTerms.describe_modifier(key, mode, value)
	var duration: String = END_TEXT[end]
	if uses == 1:
		duration = "on its next attack %s" % [duration]
	elif uses > 1:
		duration = "on its next %d attacks %s" % [uses, duration]
	var to_owner: bool = target == null or target.is_owner()
	if mode == Modifier.Mode.GRANT or mode == Modifier.Mode.DENY:
		var who: String = "" if to_owner else " for %s" % [target.describe()]
		return "%s%s %s" % [change, who, duration]
	if to_owner:
		return "gain %s %s" % [change, duration]
	return "give %s %s %s" % [target.describe(), change, duration]


## Gives each target the modifier through [method EffectEngine.add_timed_modifier].
func apply(ctx: EffectContext) -> void:
	var instance: EffectInstance = ctx.instance
	for unit_id: String in _targets(target, ctx):
		var modifier: Modifier = Modifier.new(
				key, mode, value, instance.source_kind, instance.instance_id, instance.label
		)
		ctx.engine.add_timed_modifier(unit_id, modifier, end, uses, instance.instance_id)
