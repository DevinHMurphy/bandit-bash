# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     counter_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name CounterCondition
extends EffectCondition
## Passes on every Nth matching event, or on the first one, counted in one lane.
##
## "Every 10th Hit taken this combat", "First Hit dealt this combat". The count lives on the
## effect's runtime instance, one per lane, and shows on its card ("Bulwark 7/10 this combat").
## [EffectDefinition] puts this block's words before the trigger and its lane after the scope.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## How the counter passes. Saved as an int: [b]append only[/b].
enum Mode {
	## Passes when the count reaches [member count], then the count starts over.
	EVERY_NTH = 0,
	## Passes on the first matching event only, once per lane period.
	FIRST = 1,
}

## How the counter passes.
@export var mode: Mode = Mode.EVERY_NTH

## N for "every Nth": matching events per pass. Ignored by [constant FIRST].
##
## [b]1:[/b] passes on every event, which needs no counter at all.
@export_range(1, 1000) var count: int = 1

## When the count resets: every battle or once per run.
@export var lane: EffectDefinition.Lane = EffectDefinition.Lane.COMBAT


func describe() -> String:
	return "%s time %s" % [describe_count().to_lower(), EffectDefinition.LANE_TEXT[lane]]


## The words before the trigger: "Every 10th" or "First".
func describe_count() -> String:
	if mode == Mode.FIRST:
		return "First"
	return "Every %s" % [EffectDefinition.ordinal(count)]


func names_this_unit() -> bool:
	return false


## Advances the effect's counter in [member lane] and passes when it completes: on the Nth event
## (then starts over) or, for [constant FIRST], on the first event of the lane's period. Records
## each change. Never passes or changes during a value query.
func test(ctx: EffectContext) -> bool:
	if ctx.is_query or ctx.instance == null:
		return false
	var current: int = ctx.instance.get_counter(lane)
	if mode == Mode.FIRST:
		if current > 0:
			return false
		ctx.instance.set_counter(lane, 1)
		ctx.engine.counter_changed(ctx.instance, lane)
		return true
	current += 1
	var completed: bool = current >= count
	ctx.instance.set_counter(lane, 0 if completed else current)
	ctx.engine.counter_changed(ctx.instance, lane)
	return completed
