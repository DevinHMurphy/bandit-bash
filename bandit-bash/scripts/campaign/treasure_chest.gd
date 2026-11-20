# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     treasure_chest.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name TreasureChest
extends RefCounted
## One seat's chest at a Treasure node (game-vision.md, Campaign nodes; heirlooms.md, Tiers and
## sources): its size, which is its heirloom's tier, sometimes gold, and in a Large chest
## sometimes a Legendary item instead of the heirloom.
##
## [method roll] draws from the seat's [code]REWARD[/code] stream at the node, in order: the size
## ([method HeirloomDraw.roll_tier]), the gold chance and amount, a Large chest's Legendary chance
## and item, then the heirloom ([method HeirloomDraw.draw]) unless an item took its place. Rolled
## on entry by [OpenTreasureCommand] and saved in the seat's [member SeatRun.pending_offers] under
## [constant OFFER_KEY] before anything shows; [TreasureCommand] takes the whole chest or gives it
## up. The rare offset is neither read nor moved. Pure rules code.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The key of the chest in [member SeatRun.pending_offers].
const OFFER_KEY: String = "treasure"

## The chance a chest adds gold (game-vision.md, Economy: "half the chests add 20–60").[br]
## [b]Units:[/b] percent.
const GOLD_CHANCE: int = 50

## The least gold a chest that adds gold adds, whatever its size (game-vision.md, Economy).[br]
## [b]Units:[/b] gold.
const GOLD_MIN: int = 20

## The most gold a chest adds; every whole amount from [constant GOLD_MIN] to this is as likely.
## [b]Units:[/b] gold.
const GOLD_MAX: int = 60

## The chance a Large chest holds a Legendary item instead of its heirloom (heirlooms.md;
## weapons.md, Rarity). [b]Units:[/b] percent.
const LEGENDARY_CHANCE: int = 10

## Legendary items no chest holds. The Ring of Favor's effect is still open (game-vision.md, Open
## and unfinished: "needs a Legendary-sized effect"); lift it here once its effect is decided.
const LEGENDARY_EXCLUDED: PackedStringArray = ["ring_of_favor"]

## The name of each chest size, by its tier.
const SIZE_NAMES: Dictionary[String, String] = {
	ContentIds.HEIRLOOM_COMMON: "Small",
	ContentIds.HEIRLOOM_UNCOMMON: "Medium",
	ContentIds.HEIRLOOM_RARE: "Large",
}

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_TIER: String = "tier"
const _KEY_GOLD: String = "gold"
const _KEY_HEIRLOOM: String = "heirloom_id"
const _KEY_ITEM: String = "item"
const _KEY_DEFINITION: String = "definition_id"
const _KEY_INSTANCE: String = "instance_id"
const _KEY_RESOLVED: String = "is_resolved"
const _KEY_TAKEN: String = "is_taken"

## The chest's size, as its heirloom's tier: one of [constant HeirloomDraw.TIERS].
var tier: String = ContentIds.HEIRLOOM_COMMON

## Gold it adds when taken. [b]Units:[/b] gold. [b]0:[/b] none.
var gold: int = 0

## Content id of the heirloom it holds. [b]Empty:[/b] none (a Legendary item took its place, or
## no heirloom was left to draw).
var heirloom_id: String = ""

## The Legendary item it holds, with the instance id it gets when taken; null for none.
var item: ItemPick.Offer = null

## Whether the seat took the chest or gave it up.
var is_resolved: bool = false

## Whether the seat took it; false while open or after giving it up.
var is_taken: bool = false


## Writes this chest to [param seat_run]'s pending offers, replacing any there.
func store(seat_run: SeatRun) -> void:
	seat_run.pending_offers[OFFER_KEY] = capture()


## The chest's size name, such as [code]Large[/code].
func size_name() -> String:
	return SIZE_NAMES.get(tier, tier.capitalize())


## The chest as plain JSON.
func capture() -> Dictionary:
	var item_data: Dictionary = {}
	if item != null:
		item_data = {_KEY_DEFINITION: item.definition_id, _KEY_INSTANCE: item.instance_id}
	return {
		_KEY_TIER: tier,
		_KEY_GOLD: gold,
		_KEY_HEIRLOOM: heirloom_id,
		_KEY_ITEM: item_data,
		_KEY_RESOLVED: is_resolved,
		_KEY_TAKEN: is_taken,
	}


## A new chest for [param seat_run] from [param stream] (see the class doc), its item's id from
## [param ids]; [param is_coop] admits co-op-only heirlooms.
static func roll(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator,
		is_coop: bool
) -> TreasureChest:
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = HeirloomDraw.roll_tier(stream)
	if stream.roll_percent(GOLD_CHANCE):
		chest.gold = stream.randi_range(GOLD_MIN, GOLD_MAX)
	if chest.tier == ContentIds.HEIRLOOM_RARE and stream.roll_percent(LEGENDARY_CHANCE):
		var usable: Array[ItemDefinition] = usable_legendaries(seat_run, catalog)
		if not usable.is_empty():
			var found: ItemDefinition = usable[stream.pick_index(usable.size())]
			chest.item = ItemPick.Offer.new(found.id, ids.next_item_id(found.display_name))
	if chest.item == null:
		chest.heirloom_id = HeirloomDraw.draw(stream, seat_run, catalog, chest.tier, is_coop)
	return chest


## [param seat_run]'s chest waiting in its pending offers; null when it has none or its data is
## unusable (reported).
static func pending(seat_run: SeatRun) -> TreasureChest:
	if seat_run == null:
		return null
	var data: Variant = seat_run.pending_offers.get(OFFER_KEY, null)
	if data == null:
		return null
	var read: TreasureChest = restore(data as Dictionary) if data is Dictionary else null
	if read == null:
		push_error("TreasureChest: seat %d's chest is unusable - %s" % [seat_run.seat, data])
	return read


## Whether [param seat_run] has a chest it hasn't taken or given up.
static func is_open(seat_run: SeatRun) -> bool:
	var chest: TreasureChest = pending(seat_run)
	return chest != null and not chest.is_resolved


## The chest [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null for an unknown size, gold outside the rule's range, or an item without both ids.
static func restore(data: Dictionary) -> TreasureChest:
	var read_tier: Variant = data.get(_KEY_TIER)
	var read_gold: Variant = CampaignRunState.whole_number(data.get(_KEY_GOLD))
	var read_heirloom: Variant = data.get(_KEY_HEIRLOOM)
	var item_data: Variant = data.get(_KEY_ITEM)
	var resolved: Variant = data.get(_KEY_RESOLVED)
	var taken: Variant = data.get(_KEY_TAKEN)
	if (
			not read_tier is String or not HeirloomDraw.TIERS.has(read_tier as String)
			or read_gold == null or not read_heirloom is String or not item_data is Dictionary
			or not resolved is bool or not taken is bool
	):
		return null
	var amount: int = read_gold as int
	if amount != 0 and (amount < GOLD_MIN or amount > GOLD_MAX):
		return null
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = read_tier as String
	chest.gold = amount
	chest.heirloom_id = read_heirloom as String
	chest.is_resolved = resolved as bool
	chest.is_taken = taken as bool
	var written: Dictionary = item_data
	if not written.is_empty():
		var definition_id: Variant = written.get(_KEY_DEFINITION)
		var instance_id: Variant = written.get(_KEY_INSTANCE)
		if (
				not definition_id is String or (definition_id as String).is_empty()
				or not instance_id is String or (instance_id as String).is_empty()
		):
			return null
		chest.item = ItemPick.Offer.new(definition_id as String, instance_id as String)
	return chest


## The Legendary items a chest may hold for [param seat_run], in id order: every Legendary item
## in [param catalog] but [constant LEGENDARY_EXCLUDED] that a living unit can use (a weapon of a
## type the army wields, [method ItemPick.usable_weapon_types]; any other kind always).
static func usable_legendaries(
		seat_run: SeatRun, catalog: EffectCatalog.Index
) -> Array[ItemDefinition]:
	var kinds: Array[EffectCatalog.Kind] = [
		EffectCatalog.Kind.WEAPON,
		EffectCatalog.Kind.EQUIPMENT,
		EffectCatalog.Kind.TRINKET,
		EffectCatalog.Kind.CONSUMABLE,
	]
	var usable_types: PackedStringArray = ItemPick.usable_weapon_types(seat_run, catalog)
	var by_id: Dictionary[String, ItemDefinition] = {}
	for definition: ItemDefinition in ItemPools.items_of(catalog, kinds):
		if definition.rarity != ItemDefinition.Rarity.LEGENDARY:
			continue
		if LEGENDARY_EXCLUDED.has(definition.id):
			continue
		var weapon: WeaponDefinition = definition as WeaponDefinition
		if weapon != null and not usable_types.has(weapon.weapon_type):
			continue
		by_id[definition.id] = definition
	var sorted_ids: PackedStringArray = PackedStringArray(by_id.keys())
	sorted_ids.sort()
	var found: Array[ItemDefinition] = []
	for id: String in sorted_ids:
		found.append(by_id[id])
	return found
