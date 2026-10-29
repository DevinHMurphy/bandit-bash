# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     content_ids.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name ContentIds
extends RefCounted
## The fixed string id lists content uses: weapon types, tags, roles and every kind list.
##
## Saves and the wire carry these as plain strings, so a list can grow without breaking old data
## (content catalog plan, question 3). Every string id a definition holds must be in its list; the
## content test checks it. Ids are lowercase snake_case and never shown to players. Values that
## code branches on have a named constant, and their list is built from those constants.[br]
## [method apply_hint] turns a list into an inspector dropdown for the definitions' exports.
## Pure and static; never instantiated.
##
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## Weapon item kind: weapons and staves (items.md, "Weapon or staff").
const ITEM_WEAPON: String = "weapon"

## Equipment item kind: the Equipment slot's gear, shields included.
const ITEM_EQUIPMENT: String = "equipment"

## Trinket item kind: a small passive Pouch item.
const ITEM_TRINKET: String = "trinket"

## Consumable item kind: Pouch items that are used, ingredients included (items.md, "Consumable or
## ingredient").
const ITEM_CONSUMABLE: String = "consumable"

## Heirloom tier: the Common pool (heirlooms.md, Tiers and sources).
const HEIRLOOM_COMMON: String = "common"

## Heirloom tier: the Uncommon pool.
const HEIRLOOM_UNCOMMON: String = "uncommon"

## Heirloom tier: the Rare pool.
const HEIRLOOM_RARE: String = "rare"

## Heirloom tier: economy heirlooms sold only at the Armory.
const HEIRLOOM_SHOP: String = "shop"

## Heirloom tier: offered only at run start, outside the pool.
const HEIRLOOM_STARTING: String = "starting"

## Heirloom tier: a commander's own heirloom, such as Iron Heart; never offered.
const HEIRLOOM_COMMANDER: String = "commander"

## Shape kind: the center tile only, whatever the size.
const SHAPE_TILE: String = "tile"

## Shape kind: every tile within the size by grid distance (tiles up plus tiles across).
const SHAPE_RADIUS: String = "radius"

## Shape kind: every tile within the size along both axes, a filled square.
const SHAPE_SQUARE: String = "square"

## Shape kind: the center's row and column, out to the size each way.
const SHAPE_CROSS: String = "cross"

## Unit tag: heavily armored. Auto-deployment puts Armored units in front.
const TAG_ARMORED: String = "armored"

## Unit role: the shove specialist (the Ward). Auto-deployment puts it in front.
const ROLE_SHOVER: String = "shover"

## Staff kind: gives Block (Shelter).
const STAFF_BLOCK: String = "block"

## Staff kind: heals (Minor Heal).
const STAFF_HEAL: String = "heal"

## Staff kind: attacks like a weapon and never counters (Harm, Ruin).
const STAFF_ATTACK: String = "attack"

## Staff kind: a status staff, a stub until status effects exist.
const STAFF_STATUS: String = "status"

## Weapon types (game-vision.md, Weapons and equipment). A staff is a weapon type, so the same
## list names the folders under [code]data/items/weapons/[/code] and
## [code]data/prefixes/weapons/[/code].
const WEAPON_TYPES: PackedStringArray = [
	"sword",
	"axe",
	"lance",
	"bow",
	"gauntlets",
	"dagger",
	"anima",
	"holy",
	"dark",
	"staff",
]

## Unit tags: what a unit is (unit-roster.md, Movement and tags). Terror is for enemies only.
const TAGS: PackedStringArray = [TAG_ARMORED, "mounted", "flier", "terror"]

## Unit roles: what a unit type is for (unit-roster.md, the MVP roster's Role column).
## Auto-deployment looks for [code]shover[/code].
const ROLES: PackedStringArray = [
	"sword",
	"axe",
	"lance",
	"bow",
	"fist",
	"dagger",
	"support",
	"mounted",
	"flier",
	"armored",
	ROLE_SHOVER,
	"anima",
	"dark",
	"holy",
]

## Item kinds: the price table's rows (items.md, Rarity and prices) and the item folders.
const ITEM_KINDS: PackedStringArray = [ITEM_WEAPON, ITEM_EQUIPMENT, ITEM_TRINKET, ITEM_CONSUMABLE]

## What a staff does (weapons.md, Staves). Status staves are stubs until status effects exist.
const STAFF_KINDS: PackedStringArray = [STAFF_BLOCK, STAFF_HEAL, STAFF_ATTACK, STAFF_STATUS]

## How a consumable is used (items.md, Consumables; content catalog plan, question 5).
const CONSUMABLE_USE_KINDS: PackedStringArray = [
	"heal",
	"block",
	"full_heal",
	"key",
	"lockpick",
	"stat_booster",
	"ingredient",
]

## Equipment categories (game-vision.md, Weapons and equipment; items.md, Equipment).
const EQUIPMENT_CATEGORIES: PackedStringArray = [
	"cloak",
	"armor",
	"band",
	"quiver",
	"coating",
	"shield",
	"unique",
]

## Heirloom tiers (heirlooms.md): the three pool tiers, Shop, and the starting and Commander
## Heirlooms outside the pool.
const HEIRLOOM_TIERS: PackedStringArray = [
	HEIRLOOM_COMMON,
	HEIRLOOM_UNCOMMON,
	HEIRLOOM_RARE,
	HEIRLOOM_SHOP,
	HEIRLOOM_STARTING,
	HEIRLOOM_COMMANDER,
]

# ASSUMPTION: "army" is a kind; the plan names three kinds, heirlooms.md gives Muster Roll "Army".
## Heirloom kinds (heirlooms.md, the Kind column).
const HEIRLOOM_KINDS: PackedStringArray = ["profile", "behavior", "economy", "army"]

## Curse tiers, matched to the size of an event option's reward (events.md, Curses).
const CURSE_TIERS: PackedStringArray = ["minor", "major", "severe"]

## How a rune picks its targets (content catalog plan, questions 12 and 16): a tile the player
## picks with the rune's shape around it, its own random selector, or two of your units (Recall).
const RUNE_TARGET_KINDS: PackedStringArray = ["area", "random", "pair"]

## Target shape kinds (content catalog plan, question 17). Directional shapes wait for content.
const SHAPE_KINDS: PackedStringArray = [SHAPE_TILE, SHAPE_RADIUS, SHAPE_SQUARE, SHAPE_CROSS]


## Turns [param ids] into an inspector dropdown on [param property], from a definition's
## [code]_validate_property[/code]: a single choice for a [String] export, a list of choices for a
## [PackedStringArray] export. The value stored is the id itself, never an index.
static func apply_hint(property: Dictionary, ids: PackedStringArray) -> void:
	var options: String = ",".join(ids)
	if property["type"] == TYPE_PACKED_STRING_ARRAY:
		property["hint"] = PROPERTY_HINT_TYPE_STRING
		property["hint_string"] = "%d/%d:%s" % [TYPE_STRING, PROPERTY_HINT_ENUM, options]
		return
	property["hint"] = PROPERTY_HINT_ENUM
	property["hint_string"] = options
