# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_instance.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name ItemInstance
extends RefCounted
## One item in a run: which definition it is, plus everything that belongs to this copy alone.
##
## The event bus plan's item contract (Definitions and instances) with its weapon prefix
## ([member prefix_id], amendment F16). The definition stays shared and read-only; this holds the
## differences, and all of it moves with the item between units, the convoy and maps. Its numbers
## are never stored: [Loadout] turns the definition into the combat state's weapon record and adds
## the prefix and [member stat_deltas] as modifiers sourced to them, so breakdowns name each one.
## [br]Plain data with ids only. [method capture] gives plain JSON (ids, deltas, counters; never a
## Resource) and [method restore] reads it back; the run flow (P08) stores it in its
## [code]roster[/code] section. Its effects' campaign-lane counters and charges are kept by
## effect id, written back after every battle ([method Loadout.LoadedUnit.write_back]).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## Instance id, such as [code]item:412[/code]; minted by the run's [InstanceIdAllocator] and never
## parsed.
var instance_id: String = ""

## Content id of its [ItemDefinition], such as [code]simple_bow[/code].
var definition_id: String = ""

## Content id of the [WeaponPrefixDefinition] a weapon rolled. [b]Empty:[/b] no prefix, the
## baseline.
var prefix_id: String = ""

## Content ids of standalone catalog effects added to this item, such as an event's
## [i]Infuse[/i]. They act as the item's own effects. [b]Empty:[/b] none.
var granted_effect_ids: PackedStringArray = []

## Permanent changes to this item's numbers, each with its source, such as AtkX +1 from Cavern of
## Echoing Steel. [b]Empty:[/b] none.
var stat_deltas: Array[StatDelta] = []

## Charges left of its effects whose charges last the whole run (campaign lane), by effect id: a
## Key's 2 uses. An effect with no entry has all its charges.
var charges: Dictionary[String, int] = {}

## Campaign-lane counters of its effects, by effect id. An effect with no entry is at 0.
var counters: Dictionary[String, int] = {}


func _init(id: String = "", definition: String = "") -> void:
	instance_id = id
	definition_id = definition


## Whether anything was added to it after it was made: granted effects or stat deltas. Its price
## and scrap value follow these (content catalog plan, question 8). A prefix doesn't count.
func is_modified() -> bool:
	return not granted_effect_ids.is_empty() or not stat_deltas.is_empty()


## This item as plain JSON, for the run flow's [code]roster[/code] section.
func capture() -> Dictionary:
	var deltas: Array = []
	for delta: StatDelta in stat_deltas:
		deltas.append(delta.capture())
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"prefix_id": prefix_id,
		"granted_effect_ids": Array(granted_effect_ids),
		"stat_deltas": deltas,
		"charges": charges.duplicate(),
		"counters": counters.duplicate(),
	}


## The item [param data] describes, as [method capture] wrote it; numbers come back as ints where
## they were ints. Null, with an error, when it isn't an item's data.
static func restore(data: Dictionary) -> ItemInstance:
	var id: Variant = data.get("instance_id")
	var definition: Variant = data.get("definition_id")
	if not (id is String and definition is String) or (id as String).is_empty():
		push_error("ItemInstance: not an item's data - %s" % [data])
		return null
	var item: ItemInstance = ItemInstance.new(id as String, definition as String)
	item.prefix_id = str(data.get("prefix_id", ""))
	var granted: Variant = data.get("granted_effect_ids", [])
	if granted is Array:
		for effect_id: Variant in granted as Array:
			item.granted_effect_ids.append(str(effect_id))
	var deltas: Variant = data.get("stat_deltas", [])
	if deltas is Array:
		for entry: Variant in deltas as Array:
			if entry is Dictionary:
				item.stat_deltas.append(StatDelta.restore(entry as Dictionary))
	item.charges = read_counts(data.get("charges", {}))
	item.counters = read_counts(data.get("counters", {}))
	return item


## [param value], a JSON object of whole numbers by string key, as typed counts; anything else
## reads as none. JSON gives every number back as a float, so each is converted here.
static func read_counts(value: Variant) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	if not value is Dictionary:
		return counts
	var source: Dictionary = value
	for key: Variant in source:
		var count: Variant = source[key]
		if count is int or count is float:
			counts[str(key)] = read_int(count)
	return counts


## [param value] as a whole number when it is a number (JSON gives every number back as a float);
## [param fallback] otherwise.
static func read_int(value: Variant, fallback: int = 0) -> int:
	if value is int:
		var whole: int = value
		return whole
	if value is float:
		var number: float = value
		return roundi(number)
	return fallback


## [param value] as a number when it is one; [param fallback] otherwise.
static func read_float(value: Variant, fallback: float = 0.0) -> float:
	if value is int or value is float:
		var number: float = value
		return number
	return fallback


## One permanent, sourced change to a value: "AtkX +1 (Cavern of Echoing Steel)", "+1 MGT (Dark
## Goblet)". Units and items both carry them.
class StatDelta:
	extends RefCounted

	## The value changed: a [CombatValue] or [DamageStage] key, such as
	## [constant CombatValue.Key.ATK_X]. A unit's growth deltas use a [enum CombatValue.Stat]
	## instead ([member UnitInstance.growth_deltas]).
	var key: int = 0
	## How much it adds; negative lowers.
	var amount: float = 0.0
	## Id of what made it: a content id (an event, a stat booster) or an instance id. Never parsed;
	## deltas with the same source and [member label] count as one source in breakdowns.
	var source_id: String = ""
	## The source's name in breakdowns, such as "Cavern of Echoing Steel".
	var label: String = ""

	func _init(
			value_key: int = 0, value: float = 0.0, source: String = "", source_label: String = ""
	) -> void:
		key = value_key
		amount = value
		source_id = source
		label = source_label

	## This delta as plain JSON.
	func capture() -> Dictionary:
		return {"key": key, "amount": amount, "source_id": source_id, "label": label}

	## The delta [param data] describes, as [method capture] wrote it.
	static func restore(data: Dictionary) -> StatDelta:
		return StatDelta.new(
				ItemInstance.read_int(data.get("key")),
				ItemInstance.read_float(data.get("amount")),
				str(data.get("source_id", "")),
				str(data.get("label", ""))
		)
