# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
@abstract
class_name ItemDefinition
extends EffectCarrierDefinition
## Base for every item: weapons and staves, equipment, trinkets and consumables.
##
## Content data under [code]res://data/items/[/code], read-only at runtime. Its
## [member EffectCarrierDefinition.effects] are the item's own effects; per-item changes (granted
## effects, stat deltas, uses left) live on the item's instance. Prices are never stored per item:
## [Prices] looks them up by [member kind] and [member rarity].
##
## @tutorial(Items): docs/design/items.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## How rare an item is, which sets its price and where it can be found (items.md, Rarity and
## prices). Saved as an int: [b]append only[/b], with explicit values.
enum Rarity {
	## Starting gear and recruits' gear only: never loot, stock or sold.
	BASIC = 0,
	## Sold, and found in rewards and chests.
	COMMON = 1,
	## Sold, and found in rewards and chests.
	UNCOMMON = 2,
	## Sold; found in events and rare rewards.
	RARE = 3,
	## Never sold: the rare Large-chest find, in about 3% of runs.
	LEGENDARY = 4,
	## Only from events or another unique source: never in shops, chests, rewards or Treasure.
	UNIQUE = 5,
}

## How rare the item is. [b]Basic, Legendary, Unique:[/b] never sold ([method Prices.is_sellable]).
@export var rarity: Rarity = Rarity.BASIC

## Weight against Constitution for Attack Speed, counted only from the Weapon and Equipment slots.
## Pouch items are weightless, so trinkets and consumables keep 0.[br]
## [b]Units:[/b] weight points.
@export_range(0, 30, 1, "or_greater") var weight: int = 0

# ASSUMPTION: items carry tags, as the plan's Definitions table names, but no list of item tags
# exists yet, so the content test can't check them until one does.
## Item tags. [b]Empty:[/b] none; no MVP item has one.
@export var tags: PackedStringArray = []

## Which price row and folder the item belongs to, from [constant ContentIds.ITEM_KINDS]. Set by
## the item's class, never authored: a staff is a weapon, an ingredient a consumable.
var kind: String:
	get:
		return _get_kind()


## The item kind of this class, one of [constant ContentIds.ITEM_KINDS].
@abstract func _get_kind() -> String
