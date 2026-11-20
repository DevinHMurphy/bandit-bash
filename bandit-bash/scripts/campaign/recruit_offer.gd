# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     recruit_offer.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name RecruitOffer
extends RefCounted
## A unit offered or granted before it joins an army: its [UnitInstance] and the gear it brings
## (unit-roster.md, Recruiting and item transfer). [RunOperations] adds it to a seat.
##
## [method make] builds one at a level ([method level_for]: the army's average, rounded down),
## its stats for the levels above 1 from its average growths, as enemies grow, so a preview shows
## the real stats; it carries its type's starting weapon and nothing else. [method roll] draws
## offers from the non-commander unit types, evenly, no type twice in one offer. Ids are minted
## as it is made, so a saved offer keeps them. Plain data, saved by [method capture]; pure rules
## code.
##
## @tutorial(Unit roster, Recruiting): docs/design/unit-roster.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# The source id of the stat deltas a recruit's levels above 1 add. Never parsed.
const _LEVEL_SOURCE: String = "recruit_level"

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_UNIT: String = "unit"
const _KEY_ITEMS: String = "items"

const _PERCENT: float = 100.0

## The unit; it joins with this instance id.
var unit: UnitInstance = null

## The items it carries, by instance id: exactly the ones in its slots.
var items: Dictionary[String, ItemInstance] = {}


## This recruit as plain JSON.
func capture() -> Dictionary:
	var item_data: Dictionary = {}
	for item_id: String in items:
		item_data[item_id] = items[item_id].capture()
	return {_KEY_UNIT: unit.capture(), _KEY_ITEMS: item_data}


## A new recruit of the unit type [param type_id] with [param prefix_id] (empty: none) at
## [param level], ids from [param ids]; null for a type [param catalog] lacks or a commander's.
static func make(
		catalog: EffectCatalog.Index,
		type_id: String,
		prefix_id: String,
		level: int,
		ids: InstanceIdAllocator
) -> RecruitOffer:
	var unit_type: UnitTypeDefinition = catalog.unit_type(type_id)
	if unit_type == null or unit_type.is_commander:
		return null
	var made: RecruitOffer = RecruitOffer.new()
	made.unit = UnitInstance.new(ids.next_unit_id(unit_type.display_name), type_id)
	made.unit.prefix_id = prefix_id
	made.unit.level = maxi(level, 1)
	var levels_gained: int = made.unit.level - 1
	for stat: int in unit_type.growths:
		var gain: int = floori(float(made.unit.growth(catalog, stat) * levels_gained) / _PERCENT)
		if gain != 0:
			made.unit.stat_deltas.append(ItemInstance.StatDelta.new(
					CombatValue.STAT_KEYS[stat], float(gain), _LEVEL_SOURCE,
					"Level %d" % [made.unit.level]
			))
	var weapon: ItemDefinition = catalog.item(unit_type.starting_weapon_id)
	if weapon != null:
		var item: ItemInstance = ItemInstance.new(
				ids.next_item_id(weapon.display_name), weapon.id
		)
		made.items[item.instance_id] = item
		made.unit.weapon_id = item.instance_id
	return made


## Up to [param count] recruits at [param level] from [param stream]: per offer a unit type not
## yet offered ([method pool], evenly), then its prefix, a +1 or +2 one when
## [param is_prefix_positive] ([method UnitPrefixDefinition.roll_elite]), else none. Fewer when the
## pool runs out.
static func roll(
		stream: RngStream,
		catalog: EffectCatalog.Index,
		count: int,
		is_prefix_positive: bool,
		level: int,
		ids: InstanceIdAllocator
) -> Array[RecruitOffer]:
	var offered: Array[RecruitOffer] = []
	var left: PackedStringArray = pool(catalog)
	for _offer: int in count:
		if left.is_empty():
			break
		var type_id: String = left[stream.pick_index(left.size())]
		left.remove_at(left.find(type_id))
		var prefix_id: String = (
				UnitPrefixDefinition.roll_elite(stream, catalog) if is_prefix_positive
				else UnitPrefixDefinition.NO_PREFIX
		)
		var made: RecruitOffer = make(catalog, type_id, prefix_id, level, ids)
		if made != null:
			offered.append(made)
	return offered


## Ids of every unit type a recruit can be, in id order: each non-commander type in
## [param catalog] (no faction gates a type yet).
static func pool(catalog: EffectCatalog.Index) -> PackedStringArray:
	var found: PackedStringArray = []
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.UNIT_TYPE):
		var unit_type: UnitTypeDefinition = resource as UnitTypeDefinition
		if unit_type != null and not unit_type.is_commander:
			found.append(unit_type.id)
	found.sort()
	return found


## The level a recruit joins [param seat_run]'s army at: its living units' average level, rounded
## down, the commander included; 1 for an empty army.
static func level_for(seat_run: SeatRun) -> int:
	if seat_run.army.is_empty():
		return 1
	var total: int = 0
	for each: UnitInstance in seat_run.army:
		total += each.level
	return maxi(floori(float(total) / seat_run.army.size()), 1)


## The recruit [param data] describes, as [method capture] wrote it; null when its unit or an
## item is unusable, or its items aren't exactly the ones in its slots.
static func restore(data: Dictionary) -> RecruitOffer:
	var unit_data: Variant = data.get(_KEY_UNIT)
	var item_data: Variant = data.get(_KEY_ITEMS)
	if not unit_data is Dictionary or not item_data is Dictionary:
		return null
	var made: RecruitOffer = RecruitOffer.new()
	made.unit = UnitInstance.restore(unit_data as Dictionary)
	if made.unit == null:
		return null
	for key: Variant in item_data as Dictionary:
		var entry: Variant = (item_data as Dictionary)[key]
		var item: ItemInstance = (
				ItemInstance.restore(entry as Dictionary) if entry is Dictionary else null
		)
		if item == null or not key is String or item.instance_id != key:
			return null
		made.items[key as String] = item
	var held: PackedStringArray = made.unit.item_ids()
	if held.size() != made.items.size():
		return null
	for item_id: String in held:
		if not made.items.has(item_id):
			return null
	return made
