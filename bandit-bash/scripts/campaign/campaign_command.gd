# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 23, 2026
# ==============================================================================

@abstract
class_name CampaignCommand
extends RefCounted
## One request from a seat to its run's campaign layer: choosing a node, leaving one.
##
## The campaign counterpart of [Command]. [method CampaignSession.submit] stamps it on arrival
## and [method CampaignRunState.resolve] checks it against the run as it is then, never as it was
## when sent: so the first arrival wins (two seats choosing on one floor, a shop item two seats
## want), and a rejected command changes nothing and costs nothing. Resolving is rules code: pure,
## never awaits, and records every change as a [CampaignFact] ([method CampaignRunState.record]).
## [br][b]On the wire[/b] ([method to_wire], [method from_wire]) a command carries only its
## sender's input, as plain values, under its type's [method get_wire_type] name: never the
## streams, allocator, pool or catalog the host fills in. A new command type declares a
## [code]WIRE_TYPE[/code] and adds itself to [code]_of_wire_type()[/code].
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# Slots every wire array starts with: type, seat, arrival.
const _COMMON_FIELDS: int = 3

# What an index field with no "none" constant of its own holds until set. Readers accept it, so
# every command's default round-trips; validate() refuses it with a reason.
const _NO_INDEX: int = -1

# Slots of an ItemPlacement on the wire: destination, unit, displaced scrapped, convoy scrap.
const _PLACEMENT_FIELDS: int = 4

# Slots of an EventChoice on the wire: unit, weapon, placements, rune discard slot, replaced unit,
# hand-over.
const _CHOICE_FIELDS: int = 6

## The seat that sent it. The host sets it from the connection, never from the message.
var seat: int = -1

## Arrival stamp, set by [method CampaignSession.submit]: the host's order of arrival. 0 until then.
var arrival: int = 0


## A short name for log lines, such as [code]choose node[/code].
func get_label() -> String:
	return "campaign command"


## Why the command can't resolve on [param run] now; empty when it can. Changes nothing.
func validate(_run: CampaignRunState) -> String:
	return ""


## Resolves the command on [param run] once [method validate] passed, recording a fact for every
## change.
@abstract func resolve(run: CampaignRunState) -> void


## The name this command type goes by on the wire, one [method from_wire] knows; empty for a type
## that is never sent. [b]Never change a name:[/b] peers and repro dumps know the type by it, and
## [NetContract]'s fingerprint covers it.
func get_wire_type() -> String:
	return ""


## This command as an Array of plain values, for RPCs and repro dumps:
## [code][wire type, seat, arrival, its type's fields...][/code]. [method from_wire] reverses it.
## Empty, with an error, for a type with no wire name. The slot order is a network contract: a
## type appends new fields at the end only, and readers refuse any other length.
func to_wire() -> Array:
	var wire_type: String = get_wire_type()
	if wire_type.is_empty():
		push_error("CampaignCommand: %s has no wire type" % [get_label()])
		return []
	var data: Array = [wire_type, seat, arrival]
	data.append_array(_wire_fields())
	return data


# Its type's fields, after the common ones: ids, indices, ints, bools, strings and Arrays of them,
# never an object. A type with fields overrides this and _read_wire_fields() together.
func _wire_fields() -> Array:
	return []


# Sets its type's fields from values _wire_fields() wrote, whole-number floats included. Returns
# false when they don't fit, logging nothing: from_wire() logs once.
func _read_wire_fields(values: Array) -> bool:
	return values.is_empty()


## Rebuilds a command from [method to_wire] output, also after a trip through JSON, where numbers
## arrive as floats. Its host-side objects stay unset for the host to fill in, as it fills its own
## seat's commands. Returns [code]null[/code], with one error, for an unknown type, a wrong length
## or value type, a number that isn't whole, or a value out of range.
static func from_wire(data: Array) -> CampaignCommand:
	if data.size() < _COMMON_FIELDS or not data[0] is String:
		push_error("CampaignCommand: malformed wire data - %s" % [data])
		return null
	var command: CampaignCommand = _of_wire_type(data[0] as String)
	if command == null:
		push_error("CampaignCommand: unknown wire type - %s" % [data])
		return null
	var sender: Variant = _wire_at_least(data[1], CampaignFact.NO_SEAT)
	var stamp: Variant = _wire_at_least(data[2], 0)
	if (
			sender == null
			or stamp == null
			or not command._read_wire_fields(data.slice(_COMMON_FIELDS))
	):
		push_error("CampaignCommand: wire data out of range - %s" % [data])
		return null
	command.seat = sender
	command.arrival = stamp
	return command


# A new command of the type named on the wire; null for an unknown name.
static func _of_wire_type(wire_type: String) -> CampaignCommand:
	match wire_type:
		ChooseNodeCommand.WIRE_TYPE:
			return ChooseNodeCommand.new()
		LeaveNodeCommand.WIRE_TYPE:
			return LeaveNodeCommand.new()
		StartingHeirloomCommand.WIRE_TYPE:
			return StartingHeirloomCommand.new()
		ItemPickCommand.WIRE_TYPE:
			return ItemPickCommand.new()
		KeyHeirloomCommand.WIRE_TYPE:
			return KeyHeirloomCommand.new()
		OpenTreasureCommand.WIRE_TYPE:
			return OpenTreasureCommand.new()
		TreasureCommand.WIRE_TYPE:
			return TreasureCommand.new()
		FeastCommand.WIRE_TYPE:
			return FeastCommand.new()
		TrainCommand.WIRE_TYPE:
			return TrainCommand.new()
		RegearCommand.WIRE_TYPE:
			return RegearCommand.new()
		GiftItemCommand.WIRE_TYPE:
			return GiftItemCommand.new()
		ScrapItemCommand.WIRE_TYPE:
			return ScrapItemCommand.new()
		OpenArmoryCommand.WIRE_TYPE:
			return OpenArmoryCommand.new()
		ArmoryPurchaseCommand.WIRE_TYPE:
			return ArmoryPurchaseCommand.new()
		OpenGuildhallCommand.WIRE_TYPE:
			return OpenGuildhallCommand.new()
		GuildhallPurchaseCommand.WIRE_TYPE:
			return GuildhallPurchaseCommand.new()
		PrefixRerollCommand.WIRE_TYPE:
			return PrefixRerollCommand.new()
		ResolveUnknownCommand.WIRE_TYPE:
			return ResolveUnknownCommand.new()
		OpenEventCommand.WIRE_TYPE:
			return OpenEventCommand.new()
		EventChooserCommand.WIRE_TYPE:
			return EventChooserCommand.new()
		EventVoteCommand.WIRE_TYPE:
			return EventVoteCommand.new()
		EventOptionCommand.WIRE_TYPE:
			return EventOptionCommand.new()
		RouteVoteCommand.WIRE_TYPE:
			return RouteVoteCommand.new()
		ProposeSwapCommand.WIRE_TYPE:
			return ProposeSwapCommand.new()
		AnswerSwapCommand.WIRE_TYPE:
			return AnswerSwapCommand.new()
		WithdrawSwapCommand.WIRE_TYPE:
			return WithdrawSwapCommand.new()
		ForfeitCommand.WIRE_TYPE:
			return ForfeitCommand.new()
	return null


# value as an int when it is one, or when it is a whole float within JSON's exact range (it went
# through JSON); null otherwise.
# NOTE: The same rule as Command._wire_int(); keep the two in step.
static func _wire_int(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var number: float = value
	if number != floorf(number) or absf(number) > CampaignFact.MAX_EXACT_JSON_INT:
		return null
	return int(number)


# value as an int (see _wire_int()) when it is at least lowest; null otherwise.
static func _wire_at_least(value: Variant, lowest: int) -> Variant:
	var number: Variant = _wire_int(value)
	if number == null or (number as int) < lowest:
		return null
	return number


# value as an int (see _wire_int()) when it is one of an enum's values; null otherwise.
static func _wire_enum(value: Variant, enum_values: Array) -> Variant:
	var number: Variant = _wire_int(value)
	if number == null or not enum_values.has(number):
		return null
	return number


# placement as wire values: [] for none, else [destination, unit, displaced scrapped, convoy
# scrap]. _is_placement_wire() and _placement_of_wire() read it.
static func _placement_to_wire(placement: ItemPlacement) -> Array:
	if placement == null:
		return []
	return [
		placement.destination,
		placement.unit_id,
		placement.is_displaced_scrapped,
		placement.convoy_scrap_id,
	]


# Whether value is what _placement_to_wire() writes, none included.
static func _is_placement_wire(value: Variant) -> bool:
	if not value is Array:
		return false
	var values: Array = value
	if values.is_empty():
		return true
	return (
			values.size() == _PLACEMENT_FIELDS
			and _wire_enum(values[0], ItemPlacement.Destination.values()) != null
			and values[1] is String
			and values[2] is bool
			and values[3] is String
	)


# The placement values holds once _is_placement_wire() passed; null for none.
static func _placement_of_wire(values: Array) -> ItemPlacement:
	if values.is_empty():
		return null
	var destination: int = _wire_int(values[0])
	var unit: String = values[1]
	var is_scrapped: bool = values[2]
	var convoy_scrap: String = values[3]
	return ItemPlacement.new(
			destination as ItemPlacement.Destination, unit, is_scrapped, convoy_scrap
	)


# choice as wire values: [] for none, else [unit, weapon, [[block index, placement]...], rune
# discard slot, replaced unit, [[item id, HandOver]...]], placements and hand-over in their own
# order. _is_choice_wire() and _choice_of_wire() read it.
static func _choice_to_wire(choice: EventChoice) -> Array:
	if choice == null:
		return []
	var placements: Array = []
	for block: int in choice.placements:
		placements.append([block, _placement_to_wire(choice.placements[block])])
	var handed: Array = []
	for item_id: String in choice.hand_over:
		handed.append([item_id, choice.hand_over[item_id]])
	return [
		choice.unit_id,
		choice.weapon_id,
		placements,
		choice.rune_discard_slot,
		choice.replaced_id,
		handed,
	]


# Whether value is what _choice_to_wire() writes, none included: each block index once, from 0,
# each with a placement; each handed-over item id once, with a Guildhall.HandOver place.
static func _is_choice_wire(value: Variant) -> bool:
	if not value is Array:
		return false
	var values: Array = value
	if values.is_empty():
		return true
	if (
			values.size() != _CHOICE_FIELDS
			or not values[0] is String
			or not values[1] is String
			or not values[2] is Array
			or _wire_at_least(values[3], EventChoice.NO_SLOT) == null
			or not values[4] is String
			or not values[5] is Array
	):
		return false
	var blocks: Array = []
	for entry: Variant in values[2] as Array:
		if not entry is Array or (entry as Array).size() != 2:
			return false
		var pair: Array = entry
		var block: Variant = _wire_at_least(pair[0], 0)
		if (
				block == null or blocks.has(block)
				or not _is_placement_wire(pair[1]) or (pair[1] as Array).is_empty()
		):
			return false
		blocks.append(block)
	var items: Array = []
	for entry: Variant in values[5] as Array:
		if not entry is Array or (entry as Array).size() != 2:
			return false
		var handed: Array = entry
		if (
				not handed[0] is String or items.has(handed[0])
				or _wire_enum(handed[1], Guildhall.HandOver.values()) == null
		):
			return false
		items.append(handed[0])
	return true


# The choice values holds once _is_choice_wire() passed; null for none.
static func _choice_of_wire(values: Array) -> EventChoice:
	if values.is_empty():
		return null
	var unit: String = values[0]
	var weapon: String = values[1]
	var choice: EventChoice = EventChoice.new(unit, weapon)
	for entry: Variant in values[2] as Array:
		var pair: Array = entry
		var block: int = _wire_int(pair[0])
		choice.placements[block] = _placement_of_wire(pair[1] as Array)
	choice.rune_discard_slot = _wire_int(values[3])
	choice.replaced_id = values[4]
	for entry: Variant in values[5] as Array:
		var handed: Array = entry
		choice.hand_over[handed[0] as String] = _wire_int(handed[1])
	return choice
