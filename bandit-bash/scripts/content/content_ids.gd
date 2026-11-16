# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     content_ids.gd
# Author:
# Created:  October 29, 2026
# Modified: November 15, 2026
# ==============================================================================

@tool
class_name ContentIds
extends RefCounted
## The fixed string id lists content uses: weapon types, tags, roles and every kind list.
##
## Saves and the wire carry these as plain strings, so a list can grow without breaking old data
## (content catalog plan, question 3). Every string id a definition holds must be in its list; the
## content test checks it. Ids are lowercase snake_case and never shown to players. Values that
## code branches on have a named constant, and their list is built from those constants.
## Every tag, and every id that has a named constant here, comes from that constant in code and
## tests, never a string literal; only the content suite's pinning test spells the values out.[br]
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

## Rune target kind: one unit, named by the cast (Mend, Aegis, Shatter, Clarity, Haste).
const RUNE_UNIT: String = "unit"

## Rune target kind: two of the caster's own units, named by the cast (Recall).
const RUNE_PAIR: String = "pair"

## Rune target kind: the map object on the tile the cast names (Spark).
const RUNE_OBJECT: String = "object"

## Rune target side: a unit of the player side, the caster's own or a teammate's.
const RUNE_SIDE_PLAYER: String = "player"

## Rune target side: an enemy unit.
const RUNE_SIDE_ENEMY: String = "enemy"

## Shape kind: the center tile only, whatever the size.
const SHAPE_TILE: String = "tile"

## Shape kind: every tile within the size by grid distance (tiles up plus tiles across).
const SHAPE_RADIUS: String = "radius"

## Shape kind: every tile within the size along both axes, a filled square.
const SHAPE_SQUARE: String = "square"

## Shape kind: the center's row and column, out to the size each way.
const SHAPE_CROSS: String = "cross"

## Weapon type: swords (game-vision.md, Weapons and equipment).
const WEAPON_SWORD: String = "sword"

## Weapon type: axes.
const WEAPON_AXE: String = "axe"

## Weapon type: lances.
const WEAPON_LANCE: String = "lance"

## Weapon type: bows. Every bow is effective against Fliers; the Short Quiver reads it.
const WEAPON_BOW: String = "bow"

## Weapon type: gauntlets.
const WEAPON_GAUNTLETS: String = "gauntlets"

## Weapon type: daggers.
const WEAPON_DAGGER: String = "dagger"

## Weapon type: anima tomes.
const WEAPON_ANIMA: String = "anima"

## Weapon type: holy tomes.
const WEAPON_HOLY: String = "holy"

## Weapon type: dark tomes.
const WEAPON_DARK: String = "dark"

## Weapon type: staves ([StaffDefinition]).
const WEAPON_STAFF: String = "staff"

## Unit tag: heavily armored. Auto-deployment puts Armored units in front.
const TAG_ARMORED: String = "armored"

## Unit tag: rides a mount, a horse or a flying one (the Hakkapel, the Freewing). A ground unit
## with it uses Mounted movement (unit-roster.md, Movement and tags).
const TAG_MOUNTED: String = "mounted"

## Unit tag: flies (the Freewing). The Simple Bow is effective against it.
const TAG_FLIER: String = "flier"

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

## Enemy target rule: the nearest foe it can hit (the Brute).
const TARGET_NEAREST_FOE: String = "nearest_foe"

## Enemy target rule: the foe in range with the lowest Defense (the Crossbowman).
const TARGET_LOWEST_DEFENSE: String = "lowest_defense"

## Enemy target rule: the ally missing the most HP (the Hedge Healer).
const TARGET_MOST_WOUNDED_ALLY: String = "most_wounded_ally"

## Enemy target rule: Exposed foes first, then the lowest HP (the Cutthroat).
const TARGET_EXPOSED_THEN_LOWEST_HP: String = "exposed_then_lowest_hp"

## Enemy target rule: holds its ground, attacking the foe it reaches with the least movement (the
## Duelist).
const TARGET_HOLDS_GROUND: String = "holds_ground"

## Enemy target rule: stays next to its pack's back-line ally, attacking from there (the
## Shieldbearer).
const TARGET_BACK_LINE_ALLY: String = "back_line_ally"

## Enemy target rule: the foe whose Curse catches the most player units (the Hexer).
const TARGET_MOST_CURSED: String = "most_cursed"

## Enemy target rule: stays within 2 tiles of the most allies (the Warcaller).
const TARGET_MOST_ALLIES_NEAR: String = "most_allies_near"

## Enemy target rule: back-line foes, whoever stands next to them (the Raider).
const TARGET_BACK_LINE_FOES: String = "back_line_foes"

## Enemy target rule: the lowest HP, advancing with its pack (the Hound).
const TARGET_PACK_LOWEST_HP: String = "pack_lowest_hp"

## Weapon types (game-vision.md, Weapons and equipment). A staff is a weapon type, so the same
## list names the folders under [code]data/items/weapons/[/code] and
## [code]data/prefixes/weapons/[/code].
const WEAPON_TYPES: PackedStringArray = [
	WEAPON_SWORD,
	WEAPON_AXE,
	WEAPON_LANCE,
	WEAPON_BOW,
	WEAPON_GAUNTLETS,
	WEAPON_DAGGER,
	WEAPON_ANIMA,
	WEAPON_HOLY,
	WEAPON_DARK,
	WEAPON_STAFF,
]

## Unit tags: what a unit is (unit-roster.md, Movement and tags). Terror is for enemies only.
const TAGS: PackedStringArray = [TAG_ARMORED, TAG_MOUNTED, TAG_FLIER, "terror"]

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

## How a rune is aimed: one unit, two of your units, or a map object (items.md, Runes). No rune
## has an area; a kind for one waits until content needs it.
const RUNE_TARGET_KINDS: PackedStringArray = [RUNE_UNIT, RUNE_PAIR, RUNE_OBJECT]

## Which side a [constant RUNE_UNIT] rune's unit is on. Breakables, of neither side, never are.
const RUNE_TARGET_SIDES: PackedStringArray = [RUNE_SIDE_PLAYER, RUNE_SIDE_ENEMY]

## Target shape kinds (content catalog plan, question 17). Directional shapes wait for content.
const SHAPE_KINDS: PackedStringArray = [SHAPE_TILE, SHAPE_RADIUS, SHAPE_SQUARE, SHAPE_CROSS]

## Enemy target rules: whom an enemy class's AI picks among its options (enemy-roster.md, Traits,
## behavior and intent). The AI branches on each, so each has a named constant. Only the rules of
## classes that exist are listed.
const TARGET_RULES: PackedStringArray = [
	TARGET_NEAREST_FOE,
	TARGET_LOWEST_DEFENSE,
	TARGET_MOST_WOUNDED_ALLY,
	TARGET_EXPOSED_THEN_LOWEST_HP,
	TARGET_HOLDS_GROUND,
	TARGET_BACK_LINE_ALLY,
	TARGET_MOST_CURSED,
	TARGET_MOST_ALLIES_NEAR,
	TARGET_BACK_LINE_FOES,
	TARGET_PACK_LOWEST_HP,
]


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
