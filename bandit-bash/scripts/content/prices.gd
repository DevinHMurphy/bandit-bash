# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     prices.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name Prices
extends RefCounted
## Buy prices of items, runes and heirlooms, and the scrap value of items.
##
## Prices are never stored per item: one price per rarity per item kind ([constant ITEM_PRICES],
## items.md, Rarity and prices), a flat rune price, and one price per heirloom tier. Basic,
## Legendary and Unique items are never sold. There is no selling: an unwanted item is scrapped for
## a share of its price, the campaign value [constant CampaignValue.Key.SCRAP_PERCENT]. These are
## list prices; shop discounts ([constant CampaignValue.Key.PRICE_PERCENT]) apply on top. Pure and
## static; never instantiated.
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
