# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     armory_stock.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name ArmoryStock
extends RefCounted
## One Armory visit's stock, shared by every seat (game-vision.md, Campaign nodes and Co-op
## ownership); each entry sells once, to the first confirmed purchase ([Armory]).
##
## [method roll] draws it all from the node's shared [code]SHOP_STOCK[/code] stream, in order:
## each item category's count ([constant ITEM_COUNTS], +1 per extra seat), each item's rarity
## ([constant RARITY_WEIGHTS]) then the item ([method ItemPools.draw]: no repeat in a category,
## weapons of the armies' types while one is left); one extra item per point of every seat's
## [constant CampaignValue.Key.ARMORY_STOCK], its category rolled by [constant ITEM_COUNTS]; then
## the pool heirlooms (+1 per extra seat) and the Shop one. Saved in [member RunFlow.shop_stock]
## under [constant OFFER_KEY] when the Armory opens ([OpenArmoryCommand]), cleared on leaving.
## The rare offset is neither read nor moved. Pure rules code.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The key of the stock in [member RunFlow.shop_stock].
const OFFER_KEY: String = "armory"

## An entry's category: weapons and staves.
const CATEGORY_WEAPON: String = "weapon"
## An entry's category: equipment.
const CATEGORY_EQUIPMENT: String = "equipment"
## An entry's category: a trinket.
const CATEGORY_TRINKET: String = "trinket"
## An entry's category: consumables, ingredients included (items.md, Ingredients).
const CATEGORY_CONSUMABLE: String = "consumable"
## An entry's category: an heirloom.
const CATEGORY_HEIRLOOM: String = "heirloom"

## The item categories, in the order they are rolled and shown.
const ITEM_CATEGORIES: PackedStringArray = [
	CATEGORY_WEAPON, CATEGORY_EQUIPMENT, CATEGORY_TRINKET, CATEGORY_CONSUMABLE,
]

## Items stocked per category in solo (game-vision.md, Armory): also the weights an extra item's
## category is rolled by. [b]Units:[/b] items.
const ITEM_COUNTS: Dictionary[String, int] = {
	CATEGORY_WEAPON: 3,
	CATEGORY_EQUIPMENT: 2,
	CATEGORY_TRINKET: 1,
	CATEGORY_CONSUMABLE: 2,
}

## Heirlooms from the main pool in solo, each of a tier rolled Common 50 / Uncommon 33 / Rare 17
## ([method HeirloomDraw.roll_tier]). [b]Units:[/b] heirlooms.
const POOL_HEIRLOOMS: int = 1

## Shop-tier heirlooms stocked (heirlooms.md, Tiers and sources). [b]Units:[/b] heirlooms.
const SHOP_HEIRLOOMS: int = 1

## Entries each seat past the first adds to every item category and to the pool heirlooms
## (game-vision.md, Co-op ownership). [b]Units:[/b] entries.
const EXTRA_PER_SEAT: int = 1

## The chance of each of [constant ItemPools.DRAWN_RARITIES] for a stocked item (game-vision.md,
## Armory: Common 50 / Uncommon 35 / Rare 15). [b]Units:[/b] percent.
const RARITY_WEIGHTS: PackedInt32Array = [50, 35, 15]

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_ENTRIES: String = "entries"
const _KEY_CATEGORY: String = "category"
const _KEY_DEFINITION: String = "definition_id"
const _KEY_INSTANCE: String = "instance_id"
const _KEY_SHOP_SLOT: String = "is_shop_slot"
const _KEY_BUYER: String = "buyer"

const _ALL_CATEGORIES: PackedStringArray = [
	CATEGORY_WEAPON, CATEGORY_EQUIPMENT, CATEGORY_TRINKET, CATEGORY_CONSUMABLE, CATEGORY_HEIRLOOM,
]

## Everything stocked, items by category in [constant ITEM_CATEGORIES] order, then heirlooms.
var entries: Array[Entry] = []


## Writes this stock to [param run]'s shared shop stock, replacing any there.
func store(run: CampaignRunState) -> void:
	run.flow.shop_stock[OFFER_KEY] = capture()


## The ids of every stocked heirloom, sold ones included.
func heirloom_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for entry: Entry in entries:
		if entry.is_heirloom():
			ids.append(entry.definition_id)
	return ids


## The indexes in [member entries] of [param category]'s entries, in order.
func indexes_of(category: String) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for index: int in entries.size():
		if entries[index].category == category:
			found.append(index)
	return found


## The stock as plain JSON.
func capture() -> Dictionary:
	var written: Array = []
	for entry: Entry in entries:
		written.append({
			_KEY_CATEGORY: entry.category,
			_KEY_DEFINITION: entry.definition_id,
			_KEY_INSTANCE: entry.instance_id,
			_KEY_SHOP_SLOT: entry.is_shop_slot,
			_KEY_BUYER: entry.buyer,
		})
	return {_KEY_ENTRIES: written}


## A new stock for [param run]'s seats from [param stream] (see the class doc), each item's
## instance id minted from [param ids].
static func roll(
		stream: RngStream,
		run: CampaignRunState,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator
) -> ArmoryStock:
	var stock: ArmoryStock = ArmoryStock.new()
	var extra: int = maxi(run.seat_numbers().size() - 1, 0) * EXTRA_PER_SEAT
	var usable: PackedStringArray = usable_weapon_types(run, catalog)
	var by_category: Dictionary[String, Array] = {}
	var offered: Dictionary[String, Dictionary] = {}
	for category: String in ITEM_CATEGORIES:
		by_category[category] = []
		offered[category] = {}
		for _item: int in ITEM_COUNTS[category] + extra:
			_stock_item(stream, category, catalog, usable, ids, by_category, offered)
	var weights: PackedInt32Array = []
	for category: String in ITEM_CATEGORIES:
		weights.append(ITEM_COUNTS[category])
	for _item: int in extra_items(run, catalog):
		var picked: int = stream.pick_weighted(weights)
		var category: String = ITEM_CATEGORIES[maxi(picked, 0)]
		_stock_item(stream, category, catalog, usable, ids, by_category, offered)
	for category: String in ITEM_CATEGORIES:
		for entry: Entry in by_category[category]:
			stock.entries.append(entry)
	for _heirloom: int in POOL_HEIRLOOMS + extra:
		var tier: String = HeirloomDraw.roll_tier(stream)
		_stock_heirloom(stock, stream, run, catalog, PackedStringArray([tier]), false)
	for _heirloom: int in SHOP_HEIRLOOMS:
		_stock_heirloom(
				stock, stream, run, catalog, PackedStringArray([ContentIds.HEIRLOOM_SHOP]), true
		)
	return stock


## [param run]'s stock waiting in its shared shop stock; null when none is rolled, or its data is
## unusable (reported).
static func pending(run: CampaignRunState) -> ArmoryStock:
	if run == null:
		return null
	var data: Variant = run.flow.shop_stock.get(OFFER_KEY, null)
	if data == null:
		return null
	var read: ArmoryStock = restore(data as Dictionary) if data is Dictionary else null
	if read == null:
		push_error("ArmoryStock: the Armory's stock is unusable - %s" % [data])
	return read


## The stock [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null for an unknown category, an entry without its ids (an heirloom has no instance id) or a
## buyer below [constant Entry.NOT_SOLD].
static func restore(data: Dictionary) -> ArmoryStock:
	var written: Variant = data.get(_KEY_ENTRIES)
	if not written is Array:
		return null
	var stock: ArmoryStock = ArmoryStock.new()
	for value: Variant in written as Array:
		if not value is Dictionary:
			return null
		var entry_data: Dictionary = value
		var category: Variant = entry_data.get(_KEY_CATEGORY)
		var definition_id: Variant = entry_data.get(_KEY_DEFINITION)
		var instance_id: Variant = entry_data.get(_KEY_INSTANCE)
		var shop_slot: Variant = entry_data.get(_KEY_SHOP_SLOT)
		var buyer: Variant = CampaignRunState.whole_number(entry_data.get(_KEY_BUYER))
		if (
				not category is String or not _ALL_CATEGORIES.has(category as String)
				or not definition_id is String or (definition_id as String).is_empty()
				or not instance_id is String or not shop_slot is bool
				or buyer == null or (buyer as int) < Entry.NOT_SOLD
		):
			return null
		var entry: Entry = Entry.new(
				category as String, definition_id as String, instance_id as String,
				shop_slot as bool
		)
		entry.buyer = buyer as int
		if entry.is_heirloom() != entry.instance_id.is_empty():
			return null
		stock.entries.append(entry)
	return stock


## The weapon types any of [param run]'s seats' living units can use, sorted
## ([method ItemPick.usable_weapon_types] across seats): the shared stock's weapon pool.
static func usable_weapon_types(
		run: CampaignRunState, catalog: EffectCatalog.Index
) -> PackedStringArray:
	var types: PackedStringArray = []
	for seat: int in run.seat_numbers():
		for weapon_type: String in ItemPick.usable_weapon_types(run.seat_run(seat), catalog):
			if not types.has(weapon_type):
				types.append(weapon_type)
	types.sort()
	return types


## The extra items every seat's [constant CampaignValue.Key.ARMORY_STOCK] adds (Merchant's
## Ledger), each seat's rounded and never below 0. [b]Units:[/b] items.
static func extra_items(run: CampaignRunState, catalog: EffectCatalog.Index) -> int:
	var count: int = 0
	for seat: int in run.seat_numbers():
		var value: float = RunOperations.campaign_value(
				run.seat_run(seat), catalog, CampaignValue.Key.ARMORY_STOCK
		)
		count += maxi(roundi(value), 0)
	return count


## Ids of the heirlooms of [param tiers] the shared stock may hold, sorted: one some seat may be
## given ([method HeirloomDraw.candidates]: not owned by every seat, co-op-only ones only in
## co-op), never a unique one a seat owns ([method unique_owner]) or one in [param stocked].
static func heirloom_candidates(
		run: CampaignRunState,
		catalog: EffectCatalog.Index,
		tiers: PackedStringArray,
		stocked: PackedStringArray
) -> PackedStringArray:
	var is_coop: bool = run.seat_numbers().size() > 1
	var found: PackedStringArray = []
	for seat: int in run.seat_numbers():
		for heirloom_id: String in HeirloomDraw.candidates(
				run.seat_run(seat), catalog, tiers, is_coop
		):
			if found.has(heirloom_id) or stocked.has(heirloom_id):
				continue
			if unique_owner(run, catalog, heirloom_id) != CampaignFact.NO_SEAT:
				continue
			found.append(heirloom_id)
	found.sort()
	return found


## The seat that owns [param heirloom_id] when it is unique (its effects carry
## [constant EffectDefinition.Tag.UNIQUE]: one owner per co-op campaign);
## [constant CampaignFact.NO_SEAT] when it isn't unique or nobody owns it.
static func unique_owner(
		run: CampaignRunState, catalog: EffectCatalog.Index, heirloom_id: String
) -> int:
	var heirloom: HeirloomDefinition = catalog.heirloom(heirloom_id)
	if heirloom == null or not heirloom.has_effect_tag(EffectDefinition.Tag.UNIQUE):
		return CampaignFact.NO_SEAT
	for seat: int in run.seat_numbers():
		if run.seat_run(seat).heirloom_ids().has(heirloom_id):
			return seat
	return CampaignFact.NO_SEAT


## Another heirloom of [param tier] for a slot whose unique heirloom was just bought
## ([method heirloom_candidates], none already stocked), from [param stream]; empty, drawing
## nothing, when none is left.
static func replacement(
		stream: RngStream,
		run: CampaignRunState,
		catalog: EffectCatalog.Index,
		tier: String,
		stocked: PackedStringArray
) -> String:
	var found: PackedStringArray = heirloom_candidates(
			run, catalog, PackedStringArray([tier]), stocked
	)
	if found.is_empty():
		return ""
	return found[stream.pick_index(found.size())]


# Appends one item of category to by_category from stream: its rarity, then the item, a weapon of
# a usable type while one is left (game-vision.md, Empty offer pools: then any type). Nothing is
# appended, and no item is drawn, when the category is used up.
static func _stock_item(
		stream: RngStream,
		category: String,
		catalog: EffectCatalog.Index,
		usable: PackedStringArray,
		ids: InstanceIdAllocator,
		by_category: Dictionary[String, Array],
		offered: Dictionary[String, Dictionary]
) -> void:
	var kinds: Array[EffectCatalog.Kind] = [_kind_of(category)]
	var candidates: Array[ItemDefinition] = ItemPools.items_of(catalog, kinds)
	var excluded: Dictionary[String, bool] = {}
	excluded.assign(offered[category])
	var rarity_index: int = maxi(stream.pick_weighted(RARITY_WEIGHTS), 0)
	var found: ItemDefinition = null
	if category == CATEGORY_WEAPON and not usable.is_empty():
		var wieldable: Array[ItemDefinition] = []
		for definition: ItemDefinition in candidates:
			var weapon: WeaponDefinition = definition as WeaponDefinition
			if weapon != null and usable.has(weapon.weapon_type):
				wieldable.append(definition)
		found = ItemPools.draw(stream, wieldable, rarity_index, excluded)
	if found == null:
		found = ItemPools.draw(stream, candidates, rarity_index, excluded)
	if found == null:
		return
	offered[category][found.id] = true
	by_category[category].append(Entry.new(
			category, found.id, ids.next_item_id(found.display_name), false
	))


static func _kind_of(category: String) -> EffectCatalog.Kind:
	match category:
		CATEGORY_EQUIPMENT:
			return EffectCatalog.Kind.EQUIPMENT
		CATEGORY_TRINKET:
			return EffectCatalog.Kind.TRINKET
		CATEGORY_CONSUMABLE:
			return EffectCatalog.Kind.CONSUMABLE
	return EffectCatalog.Kind.WEAPON


# Appends to stock one heirloom of tiers (the whole main pool when they have none left:
# game-vision.md, Empty offer pools), none already stocked; nothing, drawing nothing, when none is
# left at all.
static func _stock_heirloom(
		stock: ArmoryStock,
		stream: RngStream,
		run: CampaignRunState,
		catalog: EffectCatalog.Index,
		tiers: PackedStringArray,
		is_shop_slot: bool
) -> void:
	var stocked: PackedStringArray = stock.heirloom_ids()
	var found: PackedStringArray = heirloom_candidates(run, catalog, tiers, stocked)
	if found.is_empty():
		found = heirloom_candidates(run, catalog, HeirloomDraw.TIERS, stocked)
	if found.is_empty():
		return
	stock.entries.append(Entry.new(
			CATEGORY_HEIRLOOM, found[stream.pick_index(found.size())], "", is_shop_slot
	))


## One stocked item or heirloom.
class Entry:
	extends RefCounted

	## [member buyer] while nobody has bought it.
	const NOT_SOLD: int = -1

	## One of the stock's categories, such as [constant ArmoryStock.CATEGORY_WEAPON].
	var category: String = ""
	## Content id of its [ItemDefinition] or [HeirloomDefinition].
	var definition_id: String = ""
	## The instance id minted for an item, used once it is bought; empty for an heirloom.
	var instance_id: String = ""
	## Whether it fills the Shop-tier heirloom slot (from the main pool once the Shop tier is out).
	var is_shop_slot: bool = false
	## The seat that bought it; [constant NOT_SOLD] while it is for sale.
	var buyer: int = NOT_SOLD

	func _init(
			entry_category: String = "",
			entry_definition_id: String = "",
			entry_instance_id: String = "",
			shop_slot: bool = false
	) -> void:
		category = entry_category
		definition_id = entry_definition_id
		instance_id = entry_instance_id
		is_shop_slot = shop_slot

	## Whether it is an heirloom.
	func is_heirloom() -> bool:
		return category == ArmoryStock.CATEGORY_HEIRLOOM

	## Whether a seat bought it.
	func is_sold() -> bool:
		return buyer != NOT_SOLD
