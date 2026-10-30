# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     timed_modifier.gd
# Author:
# Created:  October 26, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name TimedModifier
extends RefCounted
## A modifier one unit holds until an end or for a number of attacks: Momentum's "+15 Hit on its
## next attack this combat", War Horn's "+2 Attack until the end of the next phase".
##
## Session state, added by [AddTimedModifier] through [method EffectEngine.add_timed_modifier] and
## removed by [method EffectEngine.reach_boundary], whichever comes first: its end or its last use.
## Checked live on every query of its holder, never cached in a stat sheet.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Instance id of the unit holding it.
var holder_id: String = ""

## The change it makes while held.
var modifier: Modifier = null

## When it expires at the latest.
var end: AddTimedModifier.End = AddTimedModifier.End.THIS_EXCHANGE

## Attacks left before it expires; 0 when only [member end] limits it.
var uses_left: int = 0

## The session's phase it belongs to: the phase it was added in, or the next phase to start when
## it was added between phases.
var phase: int = 0

## The session's attack count when it was added. Only an attack started after that spends a use.
var attacks_before: int = 0

## Instance id of the effect that added it.
var source_effect_id: String = ""

## The index of the [AddTimedModifier] among that effect's operations: the
## [member CombatFact.key] of its gained and expired facts, so a mirror can tell apart two
## modifiers one effect gave the same unit.
var operation_index: int = 0


## A copy, for a sandbox. The modifier is shared: it never changes.
func copy() -> TimedModifier:
	var timed: TimedModifier = TimedModifier.new()
	timed.holder_id = holder_id
	timed.modifier = modifier
	timed.end = end
	timed.uses_left = uses_left
	timed.phase = phase
	timed.attacks_before = attacks_before
	timed.source_effect_id = source_effect_id
	timed.operation_index = operation_index
	return timed


## This timed modifier as plain JSON values, for snapshots and saves. [method from_capture]
## reverses it.
func capture() -> Dictionary:
	return {
		"holder_id": holder_id,
		"modifier": modifier.capture(),
		"end": AddTimedModifier.End.find_key(end) as String,
		"uses_left": uses_left,
		"phase": phase,
		"attacks_before": attacks_before,
		"source_effect_id": source_effect_id,
		"operation_index": operation_index,
	}


## A timed modifier from [method capture] output, also after a trip through JSON, where numbers
## arrive as floats. Returns [code]null[/code] when a field is missing or unknown.
static func from_capture(data: Dictionary) -> TimedModifier:
	var modifier_data: Variant = data.get("modifier", null)
	var end_name: String = str(data.get("end", ""))
	if not modifier_data is Dictionary or not AddTimedModifier.End.has(end_name):
		return null
	var held: Modifier = Modifier.from_capture(modifier_data as Dictionary)
	var counts: PackedInt32Array = []
	for field: String in ["uses_left", "phase", "attacks_before", "operation_index"]:
		var count: Variant = data.get(field, null)
		if not (count is float or count is int):
			return null
		var number: float = count
		counts.append(roundi(number))
	if held == null:
		return null
	var end_value: int = AddTimedModifier.End[end_name]
	var timed: TimedModifier = TimedModifier.new()
	timed.holder_id = str(data.get("holder_id", ""))
	timed.modifier = held
	timed.end = end_value as AddTimedModifier.End
	timed.uses_left = counts[0]
	timed.phase = counts[1]
	timed.attacks_before = counts[2]
	timed.operation_index = counts[3]
	timed.source_effect_id = str(data.get("source_effect_id", ""))
	return timed
