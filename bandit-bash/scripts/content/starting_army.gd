# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_army.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name StartingArmy
extends RefCounted
## A faction's starting army as run data: its commander and starting units as [UnitInstance]s and
## their gear as [ItemInstance]s (game-vision.md, Run structure; content catalog plan, question 10).
##
## [method build] reads the [FactionDefinition] from the [EffectCatalog.Index] it is given and
## mints every id from the allocator it is given, so the run start (P08) and tests build the same
## army. The commander comes first and carries its type's starting weapon; each starting unit
## follows in the faction's order with its [member FactionDefinition.starting_gear] entry, or its
## type's starting weapon when it has none. Every unit starts at level 1 and full HP, with no
## prefix and no upgrade. Slot fit is checked by the content test and [Loadout], not here.[br]
## Bad data (an unknown id) is reported in [member problems] and skipped, never guessed at. Plain
## data: the run flow copies it into its roster, and nothing here is saved by itself.
##
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

# Positions in a FactionDefinition.starting_gear entry.
const _WEAPON_SLOT: int = 0
const _EQUIPMENT_SLOT: int = 1
const _POUCH_SLOT: int = 2

## The units in roster order, the commander first.
var units: Array[UnitInstance] = []

## The item instances [member units] carry, by instance id.
var items: Dictionary[String, ItemInstance] = {}

## Instance id of the commander. [b]Empty:[/b] the faction's commander isn't in the catalog.
var commander_id: String = ""

## Content ids of the army's heirlooms at run start: the commander's Commander Heirloom, such as
## [code]iron_heart[/code]. [b]Empty:[/b] none.
var heirloom_ids: PackedStringArray = []

## What was wrong with the data, one line each. The army still builds, without the bad part.
var problems: PackedStringArray = []


## Builds the starting army of the faction [param faction_id] from [param catalog], ids from
## [param ids]. An unknown faction gives an empty army with one problem.
static func build(
		catalog: EffectCatalog.Index, faction_id: String, ids: InstanceIdAllocator
) -> StartingArmy:
	var army: StartingArmy = StartingArmy.new()
	var faction: FactionDefinition = catalog.faction(faction_id)
	if faction == null:
		army.problems.append("faction \"%s\" is not in the catalog" % [faction_id])
		return army

	var commander: UnitInstance = _add_unit(army, catalog, faction.commander_id, ids)
	if commander != null:
		var commander_type: UnitTypeDefinition = catalog.unit_type(faction.commander_id)
		commander.weapon_id = _add_item(army, catalog, commander_type.starting_weapon_id, ids)
		army.commander_id = commander.instance_id
		if not commander_type.commander_heirloom_id.is_empty():
			army.heirloom_ids.append(commander_type.commander_heirloom_id)

	for index: int in faction.starting_unit_type_ids.size():
		var type_id: String = faction.starting_unit_type_ids[index]
		var unit: UnitInstance = _add_unit(army, catalog, type_id, ids)
		if unit == null:
			continue
		if index >= faction.starting_gear.size():
			var unit_type: UnitTypeDefinition = catalog.unit_type(type_id)
			unit.weapon_id = _add_item(army, catalog, unit_type.starting_weapon_id, ids)
			continue
		var gear: PackedStringArray = faction.starting_gear[index]
		unit.weapon_id = _add_item(army, catalog, _slot(gear, _WEAPON_SLOT), ids)
		unit.equipment_id = _add_item(army, catalog, _slot(gear, _EQUIPMENT_SLOT), ids)
		unit.pouch_id = _add_item(army, catalog, _slot(gear, _POUCH_SLOT), ids)
	return army


# A new unit of the type [param type_id], appended to the army; null, reported, when the catalog
# has no such type.
static func _add_unit(
		army: StartingArmy, catalog: EffectCatalog.Index, type_id: String, ids: InstanceIdAllocator
) -> UnitInstance:
	var unit_type: UnitTypeDefinition = catalog.unit_type(type_id)
	if unit_type == null:
		army.problems.append("unit type \"%s\" is not in the catalog" % [type_id])
		return null
	var unit: UnitInstance = UnitInstance.new(ids.next_unit_id(unit_type.display_name), type_id)
	army.units.append(unit)
	return unit


# A new item of [param definition_id] in the army's items; its instance id, or empty for an empty
# slot or an id the catalog doesn't have (reported).
static func _add_item(
		army: StartingArmy,
		catalog: EffectCatalog.Index,
		definition_id: String,
		ids: InstanceIdAllocator
) -> String:
	if definition_id.is_empty():
		return ""
	var definition: ItemDefinition = catalog.item(definition_id)
	if definition == null:
		army.problems.append("item \"%s\" is not in the catalog" % [definition_id])
		return ""
	var item: ItemInstance = ItemInstance.new(
			ids.next_item_id(definition.display_name), definition_id
	)
	army.items[item.instance_id] = item
	return item.instance_id


static func _slot(gear: PackedStringArray, slot: int) -> String:
	return gear[slot] if slot < gear.size() else ""
