# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_pick.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name ItemPick
extends RefCounted
## One seat's item pick after a won Standard or Key combat: take one of the offers, or skip.
##
## [method roll] draws from the seat's [code]REWARD[/code] stream: the slot kind, then per offer
## its rarity (with the rare offset, [method rarity_weights]), for a weapon whether it must be
## army-usable, and the item, evenly. Only Common, Uncommon and Rare items are offered, all
## different; a usable weapon falls back to any type, an empty rarity to the next lower, then the
## higher ones; a short kind offers fewer. The offset moves per offer ([method next_offset]). Each
## offer's instance id is minted as it is rolled. Saved in [member SeatRun.pending_offers] under
## [constant OFFER_KEY]; [ItemPickCommand] takes or skips it. Pure rules code.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The kind every offer of a pick shares. Saved by name ([constant SLOT_IDS]), so values may be
## renumbered, never renamed without a migration.
enum Slot {
	## Weapons and staves.
	WEAPON,
	## Equipment.
	EQUIPMENT,
	## Trinkets and consumables, ingredients included.
	POUCH,
}

## The key of a pick in [member SeatRun.pending_offers].
const OFFER_KEY: String = "item_pick"

## The saved name of each [enum Slot]. Never change one: saved runs are read by these names.
const SLOT_IDS: Dictionary[Slot, String] = {
	Slot.WEAPON: "weapon",
	Slot.EQUIPMENT: "equipment",
	Slot.POUCH: "pouch",
}

## The rarities a pick offers, in [method CombatRewardRules.rarity_table]'s order.
const OFFERED_RARITIES: Array[ItemDefinition.Rarity] = [
	ItemDefinition.Rarity.COMMON,
	ItemDefinition.Rarity.UNCOMMON,
	ItemDefinition.Rarity.RARE,
]

## [member taken] while the pick is skipped or not yet resolved.
const NOT_TAKEN: int = -1

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_SLOT: String = "slot"
const _KEY_OFFERS: String = "offers"
const _KEY_DEFINITION: String = "definition_id"
const _KEY_INSTANCE: String = "instance_id"
const _KEY_RESOLVED: String = "is_resolved"
const _KEY_TAKEN: String = "taken"

## The kind every offer shares.
var slot: Slot = Slot.WEAPON

## The items offered, in the order rolled.
var offers: Array[Offer] = []

## Whether the seat took or skipped it. A pick with no offers is resolved from the start.
var is_resolved: bool = false

## The index in [member offers] taken; [constant NOT_TAKEN] when skipped or still open.
var taken: int = NOT_TAKEN


## Writes this pick to [param seat_run]'s pending offers, replacing any there.
func store(seat_run: SeatRun) -> void:
	seat_run.pending_offers[OFFER_KEY] = capture()


## The pick as plain JSON.
func capture() -> Dictionary:
	var written: Array = []
	for offer: Offer in offers:
		written.append({_KEY_DEFINITION: offer.definition_id, _KEY_INSTANCE: offer.instance_id})
	return {
		_KEY_SLOT: SLOT_IDS[slot],
		_KEY_OFFERS: written,
		_KEY_RESOLVED: is_resolved,
		_KEY_TAKEN: taken,
	}


## A new pick for [param seat_run] after a won combat of [param combat_type], drawn from
## [param stream] (see the class doc); it moves the seat's [member SeatRun.rare_offset] and mints
## each offer's id from [param ids]. Null for a Boss combat or no offers to make.
static func roll(
		stream: RngStream,
		combat_type: CombatMapDefinition.CombatType,
		seat_run: SeatRun,
		rules: CombatRewardRules,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator
) -> ItemPick:
	if (
			combat_type == CombatMapDefinition.CombatType.BOSS
			or stream == null or rules == null or catalog == null or ids == null
			or rules.offer_count <= 0
	):
		return null
	var pick: ItemPick = ItemPick.new()
	var slot_index: int = stream.pick_weighted(rules.slot_weights())
	if slot_index < 0:
		return null
	pick.slot = slot_index as Slot
	var candidates: Array[ItemDefinition] = items_for(pick.slot, catalog)
	var usable: PackedStringArray = usable_weapon_types(seat_run, catalog)
	var table: PackedInt32Array = rules.rarity_table(combat_type)
	var offered: Dictionary[String, bool] = {}
	for _offer: int in rules.offer_count:
		var rarity_index: int = stream.pick_weighted(rarity_weights(table, seat_run.rare_offset))
		var needs_usable: bool = (
				pick.slot == Slot.WEAPON and stream.roll_percent(rules.usable_weapon_chance)
		)
		var found: ItemDefinition = _draw(
				stream,
				candidates,
				offered,
				maxi(rarity_index, 0),
				usable if needs_usable else PackedStringArray()
		)
		if found == null:
			break
		offered[found.id] = true
		pick.offers.append(Offer.new(found.id, ids.next_item_id(found.display_name)))
		seat_run.rare_offset = next_offset(seat_run.rare_offset, found.rarity, rules)
	pick.is_resolved = pick.offers.is_empty()
	return pick


## [param seat_run]'s pick waiting in its pending offers; null when it has none or its data is
## unusable (reported).
static func pending(seat_run: SeatRun) -> ItemPick:
	var data: Variant = seat_run.pending_offers.get(OFFER_KEY, null)
	if data == null:
		return null
	var read: ItemPick = restore(data as Dictionary) if data is Dictionary else null
	if read == null:
		push_error("ItemPick: seat %d's item pick is unusable - %s" % [seat_run.seat, data])
	return read


## The pick [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null for an unknown slot, an offer without ids, or a taken index outside the offers.
static func restore(data: Dictionary) -> ItemPick:
	var slot_key: Variant = SLOT_IDS.find_key(data.get(_KEY_SLOT))
	var written: Variant = data.get(_KEY_OFFERS)
	var resolved: Variant = data.get(_KEY_RESOLVED)
	var taken_index: Variant = CampaignRunState.whole_number(data.get(_KEY_TAKEN))
	if slot_key == null or not written is Array or not resolved is bool or taken_index == null:
		return null
	var pick: ItemPick = ItemPick.new()
	pick.slot = slot_key as Slot
	for entry: Variant in written as Array:
		if not entry is Dictionary:
			return null
		var definition_id: Variant = (entry as Dictionary).get(_KEY_DEFINITION)
		var instance_id: Variant = (entry as Dictionary).get(_KEY_INSTANCE)
		if (
				not definition_id is String or (definition_id as String).is_empty()
				or not instance_id is String or (instance_id as String).is_empty()
		):
			return null
		pick.offers.append(Offer.new(definition_id as String, instance_id as String))
	pick.is_resolved = resolved as bool
	pick.taken = taken_index as int
	if pick.taken != NOT_TAKEN and (pick.taken < 0 or pick.taken >= pick.offers.size()):
		return null
	return pick


## Every item of [param slot]'s kind in [param catalog], in id order: weapons (staves included),
## equipment, or trinkets then consumables.
static func items_for(slot_kind: Slot, catalog: EffectCatalog.Index) -> Array[ItemDefinition]:
	var kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
	if slot_kind == Slot.EQUIPMENT:
		kinds = [EffectCatalog.Kind.EQUIPMENT]
	elif slot_kind == Slot.POUCH:
		kinds = [EffectCatalog.Kind.TRINKET, EffectCatalog.Kind.CONSUMABLE]
	var found: Array[ItemDefinition] = []
	for kind: EffectCatalog.Kind in kinds:
		for definition: Resource in catalog.all_of(kind):
			if definition is ItemDefinition:
				found.append(definition as ItemDefinition)
	return found


## The weapon types [param seat_run]'s living army can use: each unit's type's, and its upgrade's
## once upgraded (never a commander's), sorted.
static func usable_weapon_types(
		seat_run: SeatRun, catalog: EffectCatalog.Index
) -> PackedStringArray:
	var types: PackedStringArray = []
	for unit: UnitInstance in seat_run.army:
		var unit_type: UnitTypeDefinition = unit.definition(catalog)
		if unit_type == null:
			continue
		var own: PackedStringArray = unit_type.weapon_types.duplicate()
		if unit.is_upgraded and not unit_type.is_commander:
			own.append_array(unit_type.upgrade_weapon_types)
		for weapon_type: String in own:
			if not types.has(weapon_type):
				types.append(weapon_type)
	types.sort()
	return types


## [param table]'s Common, Uncommon and Rare chances with [param offset] added to Rare: taken from
## Common, and from Uncommon once Common is used up; a negative offset goes back to Common. No
## chance goes below 0.
static func rarity_weights(table: PackedInt32Array, offset: int) -> PackedInt32Array:
	var common: int = maxi(table[0], 0)
	var uncommon: int = maxi(table[1], 0)
	var rare: int = maxi(table[2], 0)
	var shift: int = clampi(offset, -rare, common + uncommon)
	rare += shift
	if shift >= 0:
		var from_common: int = mini(shift, common)
		common -= from_common
		uncommon -= shift - from_common
	else:
		common -= shift
	return PackedInt32Array([common, uncommon, rare])


## The rare offset after an offer of [param rarity] shows: up by
## [member CombatRewardRules.rare_offset_step] for Common, to [constant SeatRun.RARE_OFFSET_CAP]
## at most; back to [constant SeatRun.RARE_OFFSET_START] for Rare; unchanged otherwise.
static func next_offset(
		offset: int, rarity: ItemDefinition.Rarity, rules: CombatRewardRules
) -> int:
	match rarity:
		ItemDefinition.Rarity.COMMON:
			return mini(offset + rules.rare_offset_step, SeatRun.RARE_OFFSET_CAP)
		ItemDefinition.Rarity.RARE:
			return SeatRun.RARE_OFFSET_START
	return offset


# One item from candidates not in offered: at the rarity of OFFERED_RARITIES[rarity_index], else
# each lower rarity, then each higher; within a rarity, of a usable type when usable names any
# and one exists. Null when none is left.
static func _draw(
		stream: RngStream,
		candidates: Array[ItemDefinition],
		offered: Dictionary[String, bool],
		rarity_index: int,
		usable: PackedStringArray
) -> ItemDefinition:
	var order: Array[int] = []
	for index: int in range(rarity_index, -1, -1):
		order.append(index)
	for index: int in range(rarity_index + 1, OFFERED_RARITIES.size()):
		order.append(index)
	for index: int in order:
		var rarity: ItemDefinition.Rarity = OFFERED_RARITIES[index]
		var pool: Array[ItemDefinition] = _of_rarity(candidates, offered, rarity, usable)
		if pool.is_empty() and not usable.is_empty():
			pool = _of_rarity(candidates, offered, rarity, PackedStringArray())
		if not pool.is_empty():
			return pool[0 if pool.size() == 1 else stream.pick_index(pool.size())]
	return null


static func _of_rarity(
		candidates: Array[ItemDefinition],
		offered: Dictionary[String, bool],
		rarity: ItemDefinition.Rarity,
		usable: PackedStringArray
) -> Array[ItemDefinition]:
	var pool: Array[ItemDefinition] = []
	for definition: ItemDefinition in candidates:
		if definition.rarity != rarity or offered.has(definition.id):
			continue
		if not usable.is_empty():
			var weapon: WeaponDefinition = definition as WeaponDefinition
			if weapon == null or not usable.has(weapon.weapon_type):
				continue
		pool.append(definition)
	return pool


## One item offered: its content id and the instance id it gets when taken.
class Offer:
	extends RefCounted

	## Content id of its [ItemDefinition].
	var definition_id: String = ""
	## The instance id minted for it, used once it is taken.
	var instance_id: String = ""

	func _init(item_definition_id: String = "", item_instance_id: String = "") -> void:
		definition_id = item_definition_id
		instance_id = item_instance_id
