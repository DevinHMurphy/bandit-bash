# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     prices.gd
# Author:
# Created:  October 29, 2026
# Modified: November 16, 2026
# ==============================================================================

class_name Prices
extends RefCounted
## Buy prices of items, runes and heirlooms, and the value and scrap value of held items.
##
## Prices are never stored per item: one price per rarity per item kind ([constant ITEM_PRICES],
## items.md, Rarity and prices), a flat rune price, and one price per heirloom tier. Basic,
## Legendary and Unique items are never sold. There is no selling: an unwanted item is scrapped for
## a share of its value, the campaign value [constant CampaignValue.Key.SCRAP_PERCENT]. A held
## item's value ([method item_value]) adds its modification's points ([constant DELTA_POINTS],
## [member EffectDefinition.item_points]) at its kind's [method step_value]. These are list prices;
## shop discounts ([constant CampaignValue.Key.PRICE_PERCENT]) apply on top. Pure and static.
##
## @tutorial(Items, Rarity and prices): docs/design/items.md
## @tutorial(Heirlooms, Tiers and sources): docs/design/heirlooms.md

## The price of something never sold.
const NO_PRICE: int = -1

## Gold by [constant ContentIds.ITEM_KINDS] kind, then by sellable [enum ItemDefinition.Rarity]
## (items.md, "One price per rarity per kind", first pass).
const ITEM_PRICES: Dictionary[String, Dictionary] = {
	ContentIds.ITEM_WEAPON: {
		ItemDefinition.Rarity.COMMON: 40,
		ItemDefinition.Rarity.UNCOMMON: 60,
		ItemDefinition.Rarity.RARE: 200,
	},
	ContentIds.ITEM_EQUIPMENT: {
		ItemDefinition.Rarity.COMMON: 60,
		ItemDefinition.Rarity.UNCOMMON: 100,
		ItemDefinition.Rarity.RARE: 200,
	},
	ContentIds.ITEM_TRINKET: {
		ItemDefinition.Rarity.COMMON: 30,
		ItemDefinition.Rarity.UNCOMMON: 50,
		ItemDefinition.Rarity.RARE: 80,
	},
	ContentIds.ITEM_CONSUMABLE: {
		ItemDefinition.Rarity.COMMON: 25,
		ItemDefinition.Rarity.UNCOMMON: 50,
		ItemDefinition.Rarity.RARE: 100,
	},
}

## Gold for any rune at the Guildhall (items.md, Runes).
const RUNE_PRICE: int = 30

## Armory gold by heirloom tier (heirlooms.md, Tiers and sources). Starting and Commander
## Heirlooms are never sold, so they are not listed.
const HEIRLOOM_PRICES: Dictionary[String, int] = {
	ContentIds.HEIRLOOM_COMMON: 150,
	ContentIds.HEIRLOOM_UNCOMMON: 200,
	ContentIds.HEIRLOOM_RARE: 250,
	ContentIds.HEIRLOOM_SHOP: 150,
}

## Points per +1 damage on an item (unit-roster.md's prefix scale: 1 point = 1 Might).
const DAMAGE_POINTS: float = 1.0

## Points per +1 Might, Speed, Defense or Resistance on an item (unit-roster.md, Prefixes).
const STAT_POINTS: float = 1.0

## Points per +1 HP on an item: 2 HP = 1 point (unit-roster.md, Prefixes).
const HP_POINTS: float = 0.5

## Points per +1 Hit, crit chance or avoid on an item: 10 = 1 point (unit-roster.md, Prefixes).
const PERCENT_POINTS: float = 0.1

# ASSUMPTION: +1 AtkX = 3 points; a first value with no design basis, to tune in playtesting.
## Points per +1 attack per turn on an item.
const ATK_X_POINTS: float = 3.0

# ASSUMPTION: +1 Range = 2 points; a first value with no design basis, to tune in playtesting.
## Points per +1 longest range on an item. A change to the shortest range has no value.
const RANGE_POINTS: float = 2.0

# ASSUMPTION: +1 weight = -0.25 points; a first value with no design basis, to tune in playtesting.
## Points per +1 weight on an item: negative, since weight costs Attack Speed.
const WEIGHT_POINTS: float = -0.25

## Points per +1 of each value an item's [member ItemInstance.stat_deltas] can change, by
## [CombatValue] or [DamageStage] key. A key with no entry (Movement, Stance, Parry, CritX) has no
## value yet: [method delta_points] counts it as 0 and reports it.
const DELTA_POINTS: Dictionary[int, float] = {
	DamageStage.Key.ATTACK: DAMAGE_POINTS,
	CombatValue.Key.MGT: STAT_POINTS,
	CombatValue.Key.SPD: STAT_POINTS,
	CombatValue.Key.DEF: STAT_POINTS,
	CombatValue.Key.RES: STAT_POINTS,
	CombatValue.Key.HP: HP_POINTS,
	CombatValue.Key.HIT: PERCENT_POINTS,
	CombatValue.Key.CRIT_CHANCE: PERCENT_POINTS,
	CombatValue.Key.AVOID: PERCENT_POINTS,
	CombatValue.Key.ATK_X: ATK_X_POINTS,
	CombatValue.Key.RANGE_MAX: RANGE_POINTS,
	CombatValue.Key.NET_WEIGHT: WEIGHT_POINTS,
}

# The grid a modified value is snapped to before rounding, so float error in sums of tenths can't
# move an exact half of a gold to the wrong side.
const _GOLD_SNAP: float = 0.001


## Whether items of [param rarity] are ever sold: Common, Uncommon and Rare.
static func is_sellable(rarity: ItemDefinition.Rarity) -> bool:
	return (
			rarity == ItemDefinition.Rarity.COMMON
			or rarity == ItemDefinition.Rarity.UNCOMMON
			or rarity == ItemDefinition.Rarity.RARE
	)


## The list price of an item of [param kind] and [param rarity]; [constant NO_PRICE] when it is
## never sold or the kind is unknown.
static func buy_price(kind: String, rarity: ItemDefinition.Rarity) -> int:
	if not is_sellable(rarity) or not ITEM_PRICES.has(kind):
		return NO_PRICE
	var row: Dictionary = ITEM_PRICES[kind]
	var price: int = row.get(rarity, NO_PRICE)
	return price


## The list price of [param item] ([method buy_price]); [constant NO_PRICE] for a null item.
static func item_price(item: ItemDefinition) -> int:
	if item == null:
		return NO_PRICE
	return buy_price(item.kind, item.rarity)


## The Armory price of an heirloom of [param tier]; [constant NO_PRICE] for tiers never sold
## (starting, commander, and every curse tier).
static func heirloom_price(tier: String) -> int:
	var price: int = HEIRLOOM_PRICES.get(tier, NO_PRICE)
	return price


## The price scrapping counts from: the list price, with Legendary and Unique items at their kind's
## Rare price (items.md, Rarity and prices). [constant NO_PRICE] for Basic items or unknown kinds.
static func scrap_basis(kind: String, rarity: ItemDefinition.Rarity) -> int:
	if rarity == ItemDefinition.Rarity.LEGENDARY or rarity == ItemDefinition.Rarity.UNIQUE:
		return buy_price(kind, ItemDefinition.Rarity.RARE)
	return buy_price(kind, rarity)


## Gold for scrapping an item of [param kind] and [param rarity] at [param scrap_percent] percent
## of [method scrap_basis], rounded to the nearest whole gold (game-vision.md, Gold scale); gold is
## never negative, so halves round up. Pass the campaign's current
## [constant CampaignValue.Key.SCRAP_PERCENT]; Scrapper's Tongs raises it.
static func scrap_value(kind: String, rarity: ItemDefinition.Rarity, scrap_percent: float) -> int:
	var basis: int = scrap_basis(kind, rarity)
	# ASSUMPTION: an item with no scrap basis (Basic) scraps for 0; items.md prices no Basic item.
	if basis == NO_PRICE:
		return 0
	return roundi(basis * scrap_percent / 100.0)


## The scrap rate with no modifier: 20% of an item's price (items.md, Scrapping, Terraria's sell
## rate), the default base of [constant CampaignValue.Key.SCRAP_PERCENT].
static func default_scrap_percent() -> float:
	var percent: float = CampaignValue.DEFAULT_BASES[CampaignValue.Key.SCRAP_PERCENT]
	return percent


## Gold each modification point adds to an item of [param kind]: the kind's Common-to-Uncommon
## price gap in [constant ITEM_PRICES] (a weapon 20, equipment 40). 0 for an unknown kind.
static func step_value(kind: String) -> int:
	if not ITEM_PRICES.has(kind):
		return 0
	return (
			buy_price(kind, ItemDefinition.Rarity.UNCOMMON)
			- buy_price(kind, ItemDefinition.Rarity.COMMON)
	)


## What an unmodified item of [param kind] and [param rarity] is worth: [method scrap_basis], and
## 0 where that is [constant NO_PRICE] (Basic items, unknown kinds).
static func base_value(kind: String, rarity: ItemDefinition.Rarity) -> int:
	return maxi(scrap_basis(kind, rarity), 0)


## The points [param amount] of the value [param key] is worth ([constant DELTA_POINTS]). A key
## with no point value counts as 0, with an error, so an unpriced change is never silent.
static func delta_points(key: int, amount: float) -> float:
	if not DELTA_POINTS.has(key):
		var key_name: Variant = CombatValue.Key.find_key(key)
		if key_name == null:
			key_name = DamageStage.Key.find_key(key)
		push_error("Prices: no point value for delta key - %s (%d)" % [key_name, key])
		return 0.0
	return DELTA_POINTS[key] * amount


## The net points of [param item]'s modification: each stat delta ([method delta_points]) plus each
## granted effect's [member EffectDefinition.item_points], found in [param catalog] (a missing one
## counts 0). Its weapon prefix doesn't count. 0 for a null item.
static func modification_points(item: ItemInstance, catalog: EffectCatalog.Index) -> float:
	var points: float = 0.0
	if item == null:
		return points
	for delta: ItemInstance.StatDelta in item.stat_deltas:
		points += delta_points(delta.key, delta.amount)
	if catalog == null:
		return points
	for effect_id: String in item.granted_effect_ids:
		var effect: EffectDefinition = catalog.effect(effect_id)
		if effect != null:
			points += effect.item_points
	return points


## The gold [param item] is worth, its definition found in [param catalog]: [method base_value]
## plus [method modification_points] x [method step_value], rounded to the nearest gold, halves up
## (game-vision.md, Gold scale), and never below the unmodified value. An unmodified item is worth
## [method base_value]. Not a buy price: held items are never sold. 0 for a null or unknown item.
static func item_value(item: ItemInstance, catalog: EffectCatalog.Index) -> int:
	if item == null or catalog == null:
		return 0
	var definition: ItemDefinition = catalog.item(item.definition_id)
	if definition == null:
		return 0
	var base: int = base_value(definition.kind, definition.rarity)
	if not item.is_modified():
		return base
	var modified: float = base + modification_points(item, catalog) * step_value(definition.kind)
	# roundi rounds halves away from zero, which is up for every value the floor lets through.
	return maxi(roundi(snappedf(modified, _GOLD_SNAP)), base)


## Gold for scrapping [param item] at [param scrap_percent] percent of its [method item_value],
## rounded to the nearest whole gold, halves up. Equal to [method scrap_value] for an unmodified
## item. Pass the campaign's current [constant CampaignValue.Key.SCRAP_PERCENT].
static func item_scrap_value(
		item: ItemInstance, catalog: EffectCatalog.Index, scrap_percent: float
) -> int:
	return roundi(item_value(item, catalog) * scrap_percent / 100.0)
