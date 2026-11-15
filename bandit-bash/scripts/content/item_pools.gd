# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_pools.gd
# Author:
# Created:  November 15, 2026
# Modified: November 15, 2026
# ==============================================================================

class_name ItemPools
extends RefCounted
## The pools loot and offers draw items from: the catalog's items of some kinds
## ([method items_of]), then one of a rarity the caller rolled ([method draw]), evenly in id order.
##
## Only the sellable rarities are ever drawn ([constant DRAWN_RARITIES]): Basic gear is starting
## kit only, Legendary items are only Treasure's Large-chest find, and Unique items only come from
## events (items.md, Rarity and prices). The combat item pick ([ItemPick]), container contents
## ([method MapObjects.roll]) and the Armory draw here, each from the stream its purpose owns, so
## the same stream state and catalog always give the same item. Adding or removing an item of a
## kind changes which item a seed draws from that kind's pools. Pure and static.
##
## @tutorial(Items, Rarity and prices): docs/design/items.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## The rarities a pool draws, lowest first: the order of a caller's rarity weights.
const DRAWN_RARITIES: Array[ItemDefinition.Rarity] = [
	ItemDefinition.Rarity.COMMON,
	ItemDefinition.Rarity.UNCOMMON,
	ItemDefinition.Rarity.RARE,
]


## Every item of [param kinds] in [param catalog]: kind by kind in the order given, each in id
## order. A kind includes its sub-kinds (weapons hold staves).
static func items_of(
		catalog: EffectCatalog.Index, kinds: Array[EffectCatalog.Kind]
) -> Array[ItemDefinition]:
	var found: Array[ItemDefinition] = []
	if catalog == null:
		return found
	for kind: EffectCatalog.Kind in kinds:
		for definition: Resource in catalog.all_of(kind):
			if definition is ItemDefinition:
				found.append(definition as ItemDefinition)
	return found


## The consumables among [param candidates] whose use kind is one of [param use_kinds], in order.
static func with_use_kinds(
		candidates: Array[ItemDefinition], use_kinds: PackedStringArray
) -> Array[ItemDefinition]:
	var found: Array[ItemDefinition] = []
	for definition: ItemDefinition in candidates:
		var consumable: ConsumableDefinition = definition as ConsumableDefinition
		if consumable != null and use_kinds.has(consumable.use_kind):
			found.append(definition)
	return found


## One item from [param candidates] not in [param excluded] (ids): of
## [code]DRAWN_RARITIES[rarity_index][/code], else each lower rarity, then each higher; within a
## rarity, of a weapon type in [param usable] when it names any and one exists, else of any type.
## Picks evenly with one draw, none when one item is left. Null, drawing nothing, when none is left.
static func draw(
		stream: RngStream,
		candidates: Array[ItemDefinition],
		rarity_index: int,
		excluded: Dictionary[String, bool] = {},
		usable: PackedStringArray = PackedStringArray()
) -> ItemDefinition:
	if stream == null:
		return null
	var start: int = clampi(rarity_index, 0, DRAWN_RARITIES.size() - 1)
	var order: Array[int] = []
	for index: int in range(start, -1, -1):
		order.append(index)
	for index: int in range(start + 1, DRAWN_RARITIES.size()):
		order.append(index)
	for index: int in order:
		var rarity: ItemDefinition.Rarity = DRAWN_RARITIES[index]
		var pool: Array[ItemDefinition] = of_rarity(candidates, rarity, excluded, usable)
		if pool.is_empty() and not usable.is_empty():
			pool = of_rarity(candidates, rarity, excluded)
		if not pool.is_empty():
			return pool[0 if pool.size() == 1 else stream.pick_index(pool.size())]
	return null


## The items among [param candidates] of [param rarity], not in [param excluded], and of a weapon
## type in [param usable] when it names any, in order. Always empty for a rarity outside
## [constant DRAWN_RARITIES], so no pool ever holds a Basic, Legendary or Unique item.
static func of_rarity(
		candidates: Array[ItemDefinition],
		rarity: ItemDefinition.Rarity,
		excluded: Dictionary[String, bool] = {},
		usable: PackedStringArray = PackedStringArray()
) -> Array[ItemDefinition]:
	var pool: Array[ItemDefinition] = []
	if not DRAWN_RARITIES.has(rarity):
		return pool
	for definition: ItemDefinition in candidates:
		if definition.rarity != rarity or excluded.has(definition.id):
			continue
		if not usable.is_empty():
			var weapon: WeaponDefinition = definition as WeaponDefinition
			if weapon == null or not usable.has(weapon.weapon_type):
				continue
		pool.append(definition)
	return pool


## One rune from [param catalog], evenly in id order (runes have no rarity); null, drawing
## nothing, when the catalog holds none or the stream is null.
static func draw_rune(stream: RngStream, catalog: EffectCatalog.Index) -> RuneDefinition:
	if stream == null or catalog == null:
		return null
	var runes: Array[Resource] = catalog.all_of(EffectCatalog.Kind.RUNE)
	if runes.is_empty():
		return null
	return runes[0 if runes.size() == 1 else stream.pick_index(runes.size())] as RuneDefinition
