# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seat_run.gd
# Author:
# Created:  November 13, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name SeatRun
extends RefCounted
## One seat's part of a run: its roster (army, convoy, fallen units), heirlooms, rune slots and
## economy. Every seat has its own; only the map, floor, Unknown odds and shop stock are shared
## ([CampaignRunState], [RunFlow]).
##
## Pure data with ids only, saved per player as four sections: [code]roster[/code],
## [code]heirlooms[/code] (with the seat's [member value_changes]), [code]runes[/code] and
## [code]economy[/code], each through its
## [code]capture_*[/code] and [code]restore_*[/code] pair. A restore checks everything first and
## changes nothing on error. [b]Roster invariant:[/b] [member items] holds exactly the items in the
## army's and fallen units' slots and the convoy, each in one place; a fallen unit keeps its items
## until they are taken.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
## @tutorial(Save system design): docs/design/save-system.md

## Rune slots per seat (game-vision.md, Run-wide resources).
const RUNE_SLOT_COUNT: int = 3

## [member rare_offset] at run start and after a Rare offer shows (campaign and run flow plan,
## Item pick rarity).[br]
## [b]Units:[/b] percentage points.
const RARE_OFFSET_START: int = -5

## The highest [member rare_offset] reaches (campaign and run flow plan, Item pick rarity).[br]
## [b]Units:[/b] percentage points.
const RARE_OFFSET_CAP: int = 40

# The sections' keys. Never change them: saved runs are read by these names.
const _KEY_FACTION: String = "faction_id"
const _KEY_COMMANDER: String = "commander_id"
const _KEY_ARMY: String = "army"
const _KEY_CONVOY: String = "convoy"
const _KEY_FALLEN: String = "fallen"
const _KEY_ITEMS: String = "items"
const _KEY_ENTRIES: String = "entries"
const _KEY_HEIRLOOM: String = "heirloom_id"
const _KEY_COUNTERS: String = "counters"
const _KEY_CHARGES: String = "charges"
const _KEY_SLOTS: String = "slots"
const _KEY_INSTANCE: String = "instance_id"
const _KEY_DEFINITION: String = "definition_id"
const _KEY_GOLD: String = "gold"
const _KEY_RARE_OFFSET: String = "rare_offset"
const _KEY_PENDING_OFFERS: String = "pending_offers"
const _KEY_VALUE_CHANGES: String = "value_changes"
const _KEY_VALUE_KEY: String = "key"
const _KEY_AMOUNT: String = "amount"
const _KEY_SOURCE: String = "source_id"
const _KEY_LABEL: String = "label"

## The seat this belongs to; solo is 0.
var seat: int = 0

## Content id of the seat's [FactionDefinition], such as [code]mercenary[/code].
var faction_id: String = ""

## Instance id of the commander, one of [member army]. [b]Empty:[/b] the army has none.
var commander_id: String = ""

## The living units in roster order, the commander first.
var army: Array[UnitInstance] = []

## Instance ids of the items in the convoy, in the order they arrived.
var convoy: PackedStringArray = []

## Units that fell, in the order they fell, each still holding its items.
var fallen: Array[UnitInstance] = []

## Every item instance the seat holds, by instance id: in a unit's slot (living or fallen) or in
## the convoy.
var items: Dictionary[String, ItemInstance] = {}

## Heirlooms and curses the seat owns, in the order gained. A second copy is a second entry, and
## both apply.
var heirlooms: Array[OwnedHeirloom] = []

## Permanent changes to the seat's own campaign values that no heirloom carries, in the order made,
## such as an event's +1 max army size (the Company Charter). [RunOperations] adds each to the
## seat's value reads. Saved with the heirlooms.
var value_changes: Array[ValueChange] = []

## The rune slots, always [constant RUNE_SLOT_COUNT] of them; an empty slot has empty ids.
var rune_slots: Array[RuneSlot] = []

## Gold the seat holds.[br]
## [b]Units:[/b] gold. Never below 0.
var gold: int = 0

## Added to an item pick's Rare chance, taken from Common, between [constant RARE_OFFSET_START]
## and [constant RARE_OFFSET_CAP].[br]
## [b]Units:[/b] percentage points.
var rare_offset: int = RARE_OFFSET_START

## This seat's rolled offers waiting for a choice (an item pick, the starting heirloom, a
## Treasure), as plain JSON in the shape each offer's rules define. [b]Empty:[/b] none.
var pending_offers: Dictionary = {}


func _init(seat_number: int = 0) -> void:
	seat = seat_number
	rune_slots = _empty_slots()


## The unit [param unit_id], living or fallen; null when the seat has none.
func unit(unit_id: String) -> UnitInstance:
	for candidate: UnitInstance in army + fallen:
		if candidate.instance_id == unit_id:
			return candidate
	return null


## Content ids of every owned heirloom and curse in gain order, a repeated id once per copy.
func heirloom_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for owned: OwnedHeirloom in heirlooms:
		ids.append(owned.heirloom_id)
	return ids


## Adds a copy of the heirloom or curse [param heirloom_id], with fresh counters and charges.
func add_heirloom(heirloom_id: String) -> OwnedHeirloom:
	var owned: OwnedHeirloom = OwnedHeirloom.new(heirloom_id)
	heirlooms.append(owned)
	return owned


## The roster as plain JSON, for the [code]roster[/code] section.
func capture_roster() -> Dictionary:
	var item_data: Dictionary = {}
	for item_id: String in items:
		item_data[item_id] = items[item_id].capture()
	return {
		_KEY_FACTION: faction_id,
		_KEY_COMMANDER: commander_id,
		_KEY_ARMY: _capture_units(army),
		_KEY_CONVOY: Array(convoy),
		_KEY_FALLEN: _capture_units(fallen),
		_KEY_ITEMS: item_data,
	}


## Takes the roster [param data], as [method capture_roster] wrote it. Returns
## [constant ERR_INVALID_DATA], changing nothing, for a malformed unit or item, a repeated unit id,
## a commander outside the army, or an item that is missing, held twice or held by nobody.
func restore_roster(data: Dictionary) -> Error:
	var faction: Variant = data.get(_KEY_FACTION)
	var commander: Variant = data.get(_KEY_COMMANDER)
	var item_data: Variant = data.get(_KEY_ITEMS)
	var convoy_data: Variant = data.get(_KEY_CONVOY)
	if (
			not faction is String or (faction as String).is_empty() or not commander is String
			or not item_data is Dictionary or not convoy_data is Array
	):
		return _refuse("roster", data)
	var read_army: Array[UnitInstance] = _restore_units(data.get(_KEY_ARMY))
	var read_fallen: Array[UnitInstance] = _restore_units(data.get(_KEY_FALLEN))
	var read_items: Dictionary[String, ItemInstance] = _restore_items(item_data as Dictionary)
	var read_convoy: PackedStringArray = []
	for item_id: Variant in convoy_data as Array:
		if not item_id is String:
			return _refuse("roster", data)
		read_convoy.append(item_id as String)
	if (
			read_army.size() != _array_size(data.get(_KEY_ARMY))
			or read_fallen.size() != _array_size(data.get(_KEY_FALLEN))
			or read_items.size() != (item_data as Dictionary).size()
			or not _is_roster_whole(read_army, read_fallen, read_items, read_convoy)
			or not _is_commander_in(commander as String, read_army)
	):
		return _refuse("roster", data)

	faction_id = faction as String
	commander_id = commander as String
	army = read_army
	fallen = read_fallen
	items = read_items
	convoy = read_convoy
	return OK


## Adds a permanent change of [param amount] to the seat's campaign value [param key]
## ([enum CampaignValue.Key]), sourced to [param source_id] and named [param label] in breakdowns.
func add_value_change(
		key: int, amount: float, source_id: String, label: String
) -> ValueChange:
	var change: ValueChange = ValueChange.new(key, amount, source_id, label)
	value_changes.append(change)
	return change


## The heirlooms and [member value_changes] as plain JSON, for the [code]heirlooms[/code]
## section; each change names its key as saved data does ([method Modifier.key_id]).
func capture_heirlooms() -> Dictionary:
	var entries: Array = []
	for owned: OwnedHeirloom in heirlooms:
		entries.append({
			_KEY_HEIRLOOM: owned.heirloom_id,
			_KEY_COUNTERS: owned.counters.duplicate(),
			_KEY_CHARGES: owned.charges.duplicate(),
		})
	var changes: Array = []
	for change: ValueChange in value_changes:
		changes.append({
			_KEY_VALUE_KEY: Modifier.key_id(change.key),
			_KEY_AMOUNT: change.amount,
			_KEY_SOURCE: change.source_id,
			_KEY_LABEL: change.label,
		})
	return {_KEY_ENTRIES: entries, _KEY_VALUE_CHANGES: changes}


## Takes the heirloom [param data], as [method capture_heirlooms] wrote it, copies included; data
## without value changes (a version 1 section) has none. Returns [constant ERR_INVALID_DATA],
## changing nothing, for an entry without a content id, or a change whose key isn't a campaign
## value or whose amount isn't a number.
func restore_heirlooms(data: Dictionary) -> Error:
	var entries: Variant = data.get(_KEY_ENTRIES)
	var change_data: Variant = data.get(_KEY_VALUE_CHANGES, [])
	if not entries is Array or not change_data is Array:
		return _refuse("heirlooms", data)
	var read: Array[OwnedHeirloom] = []
	for entry: Variant in entries as Array:
		if not entry is Dictionary:
			return _refuse("heirlooms", data)
		var entry_data: Dictionary = entry
		var heirloom_id: Variant = entry_data.get(_KEY_HEIRLOOM)
		if not heirloom_id is String or (heirloom_id as String).is_empty():
			return _refuse("heirlooms", data)
		var owned: OwnedHeirloom = OwnedHeirloom.new(heirloom_id as String)
		owned.counters = ItemInstance.read_counts(entry_data.get(_KEY_COUNTERS, {}))
		owned.charges = ItemInstance.read_counts(entry_data.get(_KEY_CHARGES, {}))
		read.append(owned)
	var read_changes: Array[ValueChange] = []
	for entry: Variant in change_data as Array:
		var change: ValueChange = (
				ValueChange.restore(entry as Dictionary) if entry is Dictionary else null
		)
		if change == null:
			return _refuse("heirlooms", data)
		read_changes.append(change)
	heirlooms = read
	value_changes = read_changes
	return OK


## The rune slots as plain JSON, for the [code]runes[/code] section: an empty slot is
## [code]{}[/code].
func capture_runes() -> Dictionary:
	var slots: Array = []
	for slot: RuneSlot in rune_slots:
		if slot.is_empty():
			slots.append({})
		else:
			slots.append({_KEY_INSTANCE: slot.instance_id, _KEY_DEFINITION: slot.definition_id})
	return {_KEY_SLOTS: slots}


## Takes the rune [param data], as [method capture_runes] wrote it. Returns
## [constant ERR_INVALID_DATA], changing nothing, unless there are exactly
## [constant RUNE_SLOT_COUNT] slots, each empty or naming a rune, and no rune is in two.
func restore_runes(data: Dictionary) -> Error:
	var slots: Variant = data.get(_KEY_SLOTS)
	if not slots is Array or (slots as Array).size() != RUNE_SLOT_COUNT:
		return _refuse("runes", data)
	var read: Array[RuneSlot] = []
	var seen: Dictionary[String, bool] = {}
	for entry: Variant in slots as Array:
		if not entry is Dictionary:
			return _refuse("runes", data)
		var slot_data: Dictionary = entry
		if slot_data.is_empty():
			read.append(RuneSlot.new())
			continue
		var instance_id: Variant = slot_data.get(_KEY_INSTANCE)
		var definition_id: Variant = slot_data.get(_KEY_DEFINITION)
		if (
				not instance_id is String or (instance_id as String).is_empty()
				or not definition_id is String or (definition_id as String).is_empty()
				or seen.has(instance_id as String)
		):
			return _refuse("runes", data)
		seen[instance_id as String] = true
		read.append(RuneSlot.new(instance_id as String, definition_id as String))
	rune_slots = read
	return OK


## The economy as plain JSON, for the [code]economy[/code] section.
func capture_economy() -> Dictionary:
	return {
		_KEY_GOLD: gold,
		_KEY_RARE_OFFSET: rare_offset,
		_KEY_PENDING_OFFERS: pending_offers.duplicate(true),
	}


## Takes the economy [param data], as [method capture_economy] wrote it. Returns
## [constant ERR_INVALID_DATA], changing nothing, for gold below 0 or a rare offset outside
## [constant RARE_OFFSET_START] to [constant RARE_OFFSET_CAP], or either not a whole number.
func restore_economy(data: Dictionary) -> Error:
	var read_gold: Variant = CampaignRunState.whole_number(data.get(_KEY_GOLD))
	var offset: Variant = CampaignRunState.whole_number(data.get(_KEY_RARE_OFFSET))
	var offers: Variant = data.get(_KEY_PENDING_OFFERS)
	if (
			read_gold == null or (read_gold as int) < 0
			or offset == null
			or (offset as int) < RARE_OFFSET_START or (offset as int) > RARE_OFFSET_CAP
			or not offers is Dictionary
	):
		return _refuse("economy", data)
	gold = read_gold as int
	rare_offset = offset as int
	pending_offers = (offers as Dictionary).duplicate(true)
	return OK


func _refuse(what: String, data: Dictionary) -> Error:
	push_error("SeatRun: seat %d's %s data is unusable - %s" % [seat, what, data])
	return ERR_INVALID_DATA


# True when every unit id is used once, and every slot and convoy id names an item that sits in
# exactly one place, with no item left in none.
func _is_roster_whole(
		units: Array[UnitInstance],
		fallen_units: Array[UnitInstance],
		held: Dictionary[String, ItemInstance],
		in_convoy: PackedStringArray
) -> bool:
	var unit_ids: Dictionary[String, bool] = {}
	var placed: Dictionary[String, bool] = {}
	var places: PackedStringArray = in_convoy.duplicate()
	for each: UnitInstance in units + fallen_units:
		if unit_ids.has(each.instance_id):
			return false
		unit_ids[each.instance_id] = true
		places.append_array(each.item_ids())
	for item_id: String in places:
		if not held.has(item_id) or placed.has(item_id):
			return false
		placed[item_id] = true
	return placed.size() == held.size()


func _is_commander_in(unit_id: String, units: Array[UnitInstance]) -> bool:
	if unit_id.is_empty():
		return true
	for each: UnitInstance in units:
		if each.instance_id == unit_id:
			return true
	return false


static func _empty_slots() -> Array[RuneSlot]:
	var slots: Array[RuneSlot] = []
	for index: int in RUNE_SLOT_COUNT:
		slots.append(RuneSlot.new())
	return slots


static func _capture_units(units: Array[UnitInstance]) -> Array:
	var captured: Array = []
	for each: UnitInstance in units:
		captured.append(each.capture())
	return captured


# Every unit in value; a malformed entry is left out, which the caller detects by size.
static func _restore_units(value: Variant) -> Array[UnitInstance]:
	var units: Array[UnitInstance] = []
	if not value is Array:
		return units
	for entry: Variant in value as Array:
		if entry is Dictionary:
			var restored: UnitInstance = UnitInstance.restore(entry as Dictionary)
			if restored != null:
				units.append(restored)
	return units


# Every item in data whose key is its own instance id; others are left out, which the caller
# detects by size.
static func _restore_items(data: Dictionary) -> Dictionary[String, ItemInstance]:
	var restored_items: Dictionary[String, ItemInstance] = {}
	for key: Variant in data:
		var entry: Variant = data[key]
		if not key is String or not entry is Dictionary:
			continue
		var item: ItemInstance = ItemInstance.restore(entry as Dictionary)
		if item != null and item.instance_id == key:
			restored_items[key as String] = item
	return restored_items


# -1 for anything that isn't an Array, so it never matches a restored count.
static func _array_size(value: Variant) -> int:
	return (value as Array).size() if value is Array else -1


## One owned copy of a heirloom or curse, with its campaign-lane state.
class OwnedHeirloom:
	extends RefCounted

	## Content id of its [HeirloomDefinition] or [CurseDefinition].
	var heirloom_id: String = ""
	## Campaign-lane counters of its effects, by effect id. An effect with no entry is at 0.
	var counters: Dictionary[String, int] = {}
	## Charges left of its run-long effects, by effect id. An effect with no entry has them all.
	var charges: Dictionary[String, int] = {}

	func _init(id: String = "") -> void:
		heirloom_id = id


## One permanent change to a seat's campaign value, made by an event rather than carried by an
## heirloom: added to the value, as a modifier named after its source.
class ValueChange:
	extends RefCounted

	## The [enum CampaignValue.Key] changed, such as [constant CampaignValue.Key.MAX_ARMY_SIZE].
	var key: int = CampaignValue.Key.MAX_ARMY_SIZE
	## The change, added to the value; negative lowers it. [b]Units:[/b] the key's own.
	var amount: float = 0.0
	## Content id of what made it, such as an event's id. Never parsed.
	var source_id: String = ""
	## Display name of what made it, as breakdowns name it.
	var label: String = ""

	func _init(
			value_key: int = CampaignValue.Key.MAX_ARMY_SIZE,
			change: float = 0.0,
			source: String = "",
			source_label: String = ""
	) -> void:
		key = value_key
		amount = change
		source_id = source
		label = source_label

	## The change [param data] describes, as [method SeatRun.capture_heirlooms] wrote it; null
	## when its key isn't a campaign value, its amount isn't a number, or a name isn't text.
	static func restore(data: Dictionary) -> ValueChange:
		var value_key: int = Modifier.key_from_id(str(data.get(_KEY_VALUE_KEY, "")))
		var number: Variant = data.get(_KEY_AMOUNT)
		var source: Variant = data.get(_KEY_SOURCE)
		var source_label: Variant = data.get(_KEY_LABEL)
		if (
				not CampaignValue.Key.values().has(value_key)
				or not (number is float or number is int)
				or not source is String or not source_label is String
		):
			return null
		var change: float = number
		return ValueChange.new(value_key, change, source as String, source_label as String)


## One rune slot: the rune's instance id and content id, both empty when the slot is.
class RuneSlot:
	extends RefCounted

	## The rune's instance id, such as [code]rune:5[/code]; the id combat casts it by.
	var instance_id: String = ""
	## Content id of its [RuneDefinition].
	var definition_id: String = ""

	func _init(rune_instance_id: String = "", rune_definition_id: String = "") -> void:
		instance_id = rune_instance_id
		definition_id = rune_definition_id

	## Whether no rune is in the slot.
	func is_empty() -> bool:
		return instance_id.is_empty()
