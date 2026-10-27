# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_fact.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name CampaignFact
extends RefCounted
## One thing that happened on the campaign layer of a run, in the past tense.
##
## The campaign counterpart of [CombatFact], played through [CampaignBus]: rules code creates it,
## effects react to it through the campaign's effect engine, and presentation plays it on every
## peer. Facts carry ids, never objects or Resources ([method to_wire]). Ids are opaque: never
## parse them.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## What happened. Sent over the network as an int: [b]append only[/b], with explicit values.
enum Kind {
	## The seat gained the heirloom or item named by [member definition_id]; the actor is its new
	## instance, if it has one.
	GAINED = 0,
	## A combat ended for the seat, won or lost.
	COMBAT_ENDED = 1,
	## The actor leveled up; its new stats are committed.
	LEVELED_UP = 2,
	## The effect named by [member source_effect_id] fired.
	EFFECT_ACTIVATED = 3,
	## A counter of the effect named by [member source_effect_id] changed.
	COUNTER_CHANGED = 4,
}

## [member seat] when a fact belongs to no single player.
const NO_SEAT: int = -1

# Slot types of the wire array, in to_wire() order: i = int, s = String.
const WIRE_PATTERN: String = "iiisssisi"

# Largest integer a JSON number (a double) holds exactly, 2^53. A wire array that went through JSON
# arrives with float numbers; anything beyond this lost precision on the way.
const MAX_EXACT_JSON_INT: float = 9007199254740992.0

## What happened.
var kind: Kind = Kind.GAINED

## Position in the run's campaign fact log. 0 until the campaign session assigns it.
var seq: int = 0

## The player the fact belongs to, or [constant NO_SEAT].
var seat: int = NO_SEAT

## Instance id of the unit or item the kind is about. Empty when none.
var actor_id: String = ""

## Instance id of the other party. Empty when none.
var target_id: String = ""

## Content id of the definition involved, such as a gained heirloom. Empty when none.
var definition_id: String = ""

## The fact's main quantity, such as gold or a counter value. 0 when none.
var amount: int = 0

## Instance id of the effect that caused this fact, or the effect an [constant EFFECT_ACTIVATED]
## or [constant COUNTER_CHANGED] fact is about. Empty when no effect is involved.
var source_effect_id: String = ""

## Bit set of extra details. No bits are defined yet.
var flags: int = 0


func _init(fact_kind: Kind, fact_seat: int = NO_SEAT, fact_actor_id: String = "") -> void:
	kind = fact_kind
	seat = fact_seat
	actor_id = fact_actor_id


## This fact as an Array of primitives, for RPCs and repro dumps. [method from_wire] reverses it.
##
## The slot order is a network contract: append new fields at the end only.
func to_wire() -> Array:
	return [
		kind,
		seq,
		seat,
		actor_id,
		target_id,
		definition_id,
		amount,
		source_effect_id,
		flags,
	]


## One log line, without NetLog's prefix, shaped like [method CombatFact.to_log_line]:[br]
## [code]c#12 GAINED seat 0 item:412 (Iron Axe) definition iron_axe[/code]
##
## Empty fields are left out, and the amount prints only when it is non-zero.
## [param describe]: turns an id into display text; when invalid, ids print bare.
func to_log_line(describe: Callable = Callable()) -> String:
	var parts: PackedStringArray = ["c#%d %s" % [seq, _kind_name()]]
	if seat != NO_SEAT:
		parts.append("seat %d" % [seat])
	if not actor_id.is_empty():
		parts.append(_describe_id(actor_id, describe))
	if not target_id.is_empty():
		parts.append("->")
		parts.append(_describe_id(target_id, describe))
	if not definition_id.is_empty():
		parts.append("definition %s" % [definition_id])
	if amount != 0:
		parts.append("amount %d" % [amount])
	if not source_effect_id.is_empty():
		parts.append("effect %s" % [_describe_id(source_effect_id, describe)])
	if flags != 0:
		parts.append("flags 0x%x" % [flags])
	return " ".join(parts)


func _kind_name() -> String:
	var key: Variant = Kind.find_key(kind)
	return "KIND_%d" % [kind] if key == null else (key as String)


func _describe_id(id: String, describe: Callable) -> String:
	if not describe.is_valid():
		return id
	var text: String = describe.call(id)
	return text


## Rebuilds a fact from [method to_wire] output, including after a trip through JSON.
##
## Returns [code]null[/code] (with a warning) when [param data] has the wrong length, a wrong
## type, a non-whole number, a negative [member seq], a [member seat] below [constant NO_SEAT],
## or an unknown [enum Kind].
static func from_wire(data: Array) -> CampaignFact:
	var values: Array = _normalize_wire(data, WIRE_PATTERN)
	if values.is_empty():
		push_warning("CampaignFact: malformed wire data - %s" % [data])
		return null

	var kind_value: int = values[0]
	var seq_value: int = values[1]
	var seat_value: int = values[2]
	if not Kind.values().has(kind_value) or seq_value < 0 or seat_value < NO_SEAT:
		push_warning("CampaignFact: wire data out of range - %s" % [data])
		return null

	var fact: CampaignFact = CampaignFact.new(kind_value as Kind, seat_value, values[3] as String)
	fact.seq = seq_value
	fact.target_id = values[4]
	fact.definition_id = values[5]
	fact.amount = values[6]
	fact.source_effect_id = values[7]
	fact.flags = values[8]
	return fact


# Checks data against pattern and converts whole floats (from JSON) to int. Returns [] if invalid.
# NOTE: The same check as CombatFact._normalize_wire; keep the two in step.
static func _normalize_wire(data: Array, pattern: String) -> Array:
	if data.size() != pattern.length():
		return []
	var values: Array = []
	for i: int in data.size():
		var value: Variant = data[i]
		if pattern[i] == "s":
			if typeof(value) != TYPE_STRING:
				return []
			values.append(value)
		elif typeof(value) == TYPE_INT:
			values.append(value)
		elif typeof(value) == TYPE_FLOAT:
			var number: float = value
			if number != floorf(number) or absf(number) > MAX_EXACT_JSON_INT:
				return []
			values.append(int(number))
		else:
			return []
	return values
