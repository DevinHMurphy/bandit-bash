# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_unit_state.gd
# Author:
# Created:  October 27, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name CombatUnitState
extends RefCounted
## One unit's state on one map: where it stands, its HP, Block and Stance, and what it has done
## this turn and phase.
##
## Plain data with ids only, owned by [CombatState]; [Loadout] builds it from a unit's instance.
## Maximum HP, maximum Stance and every combat value are queries ([method EffectEngine.stats]),
## never stored here. Rules code changes HP, Block and Stance only through the effect engine's
## resource paths and the combat core's damage rules, which emit the facts. [method capture] and
## [method from_capture] carry it as plain JSON into snapshots and the [code]combat_state[/code]
## save section ([CombatStateSection]).
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md
## @tutorial(Save system design): docs/design/save-system.md

## Instance id, such as [code]unit:57[/code]. Never parsed.
var id: String = ""

## The unit's side.
var side: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

## The seat controlling it; [code]-1[/code] for an enemy.
var seat: int = -1

## The tile it stands on. Kept after a defeat, though [method CombatState.tile_of] then answers
## [constant CombatFact.NO_TILE].
var tile: Vector2i = CombatFact.NO_TILE

## How it crosses terrain: walking distance and where a shove may land it.
var movement_type: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT

## What the unit is, from [constant ContentIds.TAGS], such as [code]flier[/code]: weapon
## effectiveness and conditions test them. [Loadout] checks them against the list.
var tags: PackedStringArray = []

## Content id of the unit's type, such as [code]archer[/code], for conditions that test it.
var unit_type: String = ""

## What its unit type is for, from [constant ContentIds.ROLES], such as [code]shover[/code],
## which auto-deployment reads. [b]Empty:[/b] no role (commanders).
var role: String = ""

## Current HP.
var hp: int = 0

## Current Block.
var block: int = 0

## Current Stance. 0 is Exposed.
var stance: int = 0

## Whether it took its action this phase, which ends its turn.
var has_acted: bool = false

## Tiles moved during its current turn ("moved N+ tiles").
var tiles_moved: int = 0

## Movement cost spent this turn; a second move's budget is MOVEMENT less this.
var movement_spent: int = 0

## Whether a second move after acting is allowed and not yet taken
## ([constant CombatValue.Permission.MAY_MOVE_AFTER_ACTING]).
var is_second_move_pending: bool = false

## Whether it was shoved this phase: a unit can be shoved once per phase.
var has_been_shoved: bool = false

## Whether its free Sidearm swap is spent this unit turn.
var has_used_sidearm: bool = false

## Instance id of the weapon in its Weapon slot; empty when it holds none.
var equipped_weapon_id: String = ""

## Instance id of the weapon stowed in its Pouch; empty when none.
var stowed_weapon_id: String = ""

## Instance id of the gear in its Equipment slot; empty when none. Its weight and bonuses are its
## effects, so nothing here reads it.
var equipment_id: String = ""

## Instance id of the consumable or trinket in its Pouch; empty when none. A Pouch holds one item,
## or a stowed weapon instead.
var pouch_item_id: String = ""

## The weight of each item in its Pouch, a stowed weapon included:
## [constant CampaignValue.Key.POUCH_ITEM_WEIGHT] of its army, read at battle start. 0 unless a
## curse says otherwise (Heavy Pack: 2).
var pouch_item_weight: int = 0

## Growth changes gained this battle, in percentage points by [enum CombatValue.Stat] (an eaten
## ingredient's +5% RES growth). They change nothing in battle; the battle-end bridge (EB6) writes
## them to the roster.
var growth_changes: Dictionary[int, int] = {}

## Whether it was defeated. A defeated unit stays in [CombatState], so its side and seat stay
## readable, but it is off the map.
var is_defeated: bool = false


## A copy sharing nothing mutable, for a sandbox.
func copy() -> CombatUnitState:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.side = side
	unit.seat = seat
	unit.tile = tile
	unit.movement_type = movement_type
	unit.tags = tags.duplicate()
	unit.unit_type = unit_type
	unit.role = role
	unit.hp = hp
	unit.block = block
	unit.stance = stance
	unit.has_acted = has_acted
	unit.tiles_moved = tiles_moved
	unit.movement_spent = movement_spent
	unit.is_second_move_pending = is_second_move_pending
	unit.has_been_shoved = has_been_shoved
	unit.has_used_sidearm = has_used_sidearm
	unit.equipped_weapon_id = equipped_weapon_id
	unit.stowed_weapon_id = stowed_weapon_id
	unit.equipment_id = equipment_id
	unit.pouch_item_id = pouch_item_id
	unit.pouch_item_weight = pouch_item_weight
	unit.growth_changes = growth_changes.duplicate()
	unit.is_defeated = is_defeated
	return unit


## How many items its Pouch holds, a stowed weapon included.
func pouch_count() -> int:
	return (0 if pouch_item_id.is_empty() else 1) + (0 if stowed_weapon_id.is_empty() else 1)


## Every field as plain JSON values: enums by name, the tile as [code][x, y][/code], growth
## changes by stat name. [method from_capture] reverses it.
func capture() -> Dictionary:
	var growths: Dictionary = {}
	var stats: Array = growth_changes.keys()
	stats.sort()
	for stat: Variant in stats:
		growths[CombatValue.Stat.find_key(stat) as String] = growth_changes[stat]
	return {
		"id": id,
		"side": CombatFact.CombatSide.find_key(side) as String,
		"seat": seat,
		"tile": [tile.x, tile.y],
		"movement_type": CombatGrid.MovementType.find_key(movement_type) as String,
		"tags": Array(tags),
		"unit_type": unit_type,
		"role": role,
		"hp": hp,
		"block": block,
		"stance": stance,
		"has_acted": has_acted,
		"tiles_moved": tiles_moved,
		"movement_spent": movement_spent,
		"is_second_move_pending": is_second_move_pending,
		"has_been_shoved": has_been_shoved,
		"has_used_sidearm": has_used_sidearm,
		"equipped_weapon_id": equipped_weapon_id,
		"stowed_weapon_id": stowed_weapon_id,
		"equipment_id": equipment_id,
		"pouch_item_id": pouch_item_id,
		"pouch_item_weight": pouch_item_weight,
		"growth_changes": growths,
		"is_defeated": is_defeated,
	}


## A unit from [method capture] output, also after a trip through JSON, where numbers arrive as
## floats. Returns [code]null[/code] when a field is missing, of the wrong type, not a whole
## number, or names an unknown enum value; the caller reports it.
static func from_capture(data: Dictionary) -> CombatUnitState:
	var side_name: String = str(data.get("side", ""))
	var movement_name: String = str(data.get("movement_type", ""))
	var tile_data: Variant = data.get("tile", null)
	var tag_data: Variant = data.get("tags", null)
	var growth_data: Variant = data.get("growth_changes", null)
	if (
			not data.get("id", null) is String
			or (data["id"] as String).is_empty()
			or not CombatFact.CombatSide.has(side_name)
			or not CombatGrid.MovementType.has(movement_name)
			or not tile_data is Array
			or (tile_data as Array).size() != 2
			or not tag_data is Array
			or not growth_data is Dictionary
	):
		return null
	var numbers: Dictionary[String, int] = {}
	for field: String in [
		"seat", "hp", "block", "stance", "tiles_moved", "movement_spent", "pouch_item_weight",
	]:
		var number: Variant = _whole(data.get(field, null))
		if number == null:
			return null
		numbers[field] = number
	var flags: Dictionary[String, bool] = {}
	for field: String in [
		"has_acted",
		"is_second_move_pending",
		"has_been_shoved",
		"has_used_sidearm",
		"is_defeated",
	]:
		if not data.get(field, null) is bool:
			return null
		flags[field] = data[field]
	var texts: Dictionary[String, String] = {}
	for field: String in [
		"unit_type", "role", "equipped_weapon_id", "stowed_weapon_id", "equipment_id",
		"pouch_item_id",
	]:
		if not data.get(field, null) is String:
			return null
		texts[field] = data[field]
	var tile_parts: Array = tile_data
	var x: Variant = _whole(tile_parts[0])
	var y: Variant = _whole(tile_parts[1])
	if x == null or y == null:
		return null

	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = data["id"]
	var side_value: int = CombatFact.CombatSide[side_name]
	unit.side = side_value as CombatFact.CombatSide
	var movement_value: int = CombatGrid.MovementType[movement_name]
	unit.movement_type = movement_value as CombatGrid.MovementType
	unit.tile = Vector2i(x as int, y as int)
	# Untyped: the parts come from JSON and are checked entry by entry.
	for tag: Variant in tag_data:
		if not tag is String:
			return null
		unit.tags.append(tag as String)
	var by_stat: Dictionary = growth_data
	for stat_name: Variant in by_stat:
		var points: Variant = _whole(by_stat[stat_name])
		if not CombatValue.Stat.has(stat_name) or points == null:
			return null
		var stat_value: int = CombatValue.Stat[stat_name]
		unit.growth_changes[stat_value] = points
	unit.seat = numbers["seat"]
	unit.hp = numbers["hp"]
	unit.block = numbers["block"]
	unit.stance = numbers["stance"]
	unit.tiles_moved = numbers["tiles_moved"]
	unit.movement_spent = numbers["movement_spent"]
	unit.pouch_item_weight = numbers["pouch_item_weight"]
	unit.has_acted = flags["has_acted"]
	unit.is_second_move_pending = flags["is_second_move_pending"]
	unit.has_been_shoved = flags["has_been_shoved"]
	unit.has_used_sidearm = flags["has_used_sidearm"]
	unit.is_defeated = flags["is_defeated"]
	unit.unit_type = texts["unit_type"]
	unit.role = texts["role"]
	unit.equipped_weapon_id = texts["equipped_weapon_id"]
	unit.stowed_weapon_id = texts["stowed_weapon_id"]
	unit.equipment_id = texts["equipment_id"]
	unit.pouch_item_id = texts["pouch_item_id"]
	return unit


# value as an int when it is one, or a whole float within JSON's exact range; null otherwise.
# NOTE: The same rule as CombatSession._wire_int; keep them in step.
static func _whole(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var number: float = value
	if number != floorf(number) or absf(number) > CombatFact.MAX_EXACT_JSON_INT:
		return null
	return int(number)
