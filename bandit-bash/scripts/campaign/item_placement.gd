# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_placement.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ItemPlacement
extends RefCounted
## Where a newly gained item goes: equipped on a living unit that can use it, sent to the convoy,
## or scrapped for gold (items.md, Scrapping; unit-roster.md, Recruiting and item transfer).
##
## Equipping into a full slot sends the item there to the convoy or scraps it
## ([member is_displaced_scrapped]). The convoy holds [method convoy_capacity] items, a hard cap:
## an item entering a full convoy needs one of its items scrapped first ([member convoy_scrap_id]),
## and a convoy over the cap counts as full. A weapon goes only in the Weapon slot of a unit that
## can wield it ([method slot_for]); stowing one in the Pouch is left to re-gearing at Camps.
## [method validate], then [method apply], which records a fact for every change. Pure rules
## code, for every screen that hands out a new item.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-001 - Read the scrap rate from CampaignValue.Key.SCRAP_PERCENT once the campaign
## layer reads it (Scrapper's Tongs); the default rate stands in.

## Where the new item goes.
enum Destination {
	## Into the convoy.
	CONVOY = 0,
	## Into a slot of [member unit_id].
	EQUIP = 1,
	## Scrapped for [method scrap_value] gold; it never enters the roster.
	SCRAP = 2,
}

## Where the new item goes.
var destination: Destination = Destination.CONVOY

## Instance id of the living unit that equips it; used only by [constant Destination.EQUIP].
var unit_id: String = ""

## For [constant Destination.EQUIP] into a full slot: true scraps the item already there, false
## sends it to the convoy. Must be false when the slot is empty.
var is_displaced_scrapped: bool = false

## Instance id of the convoy item scrapped to make room. Needed exactly when an item must enter a
## full convoy (the new one, or the one it displaces); empty otherwise.
var convoy_scrap_id: String = ""


func _init(
		where: Destination = Destination.CONVOY,
		unit: String = "",
		scrap_displaced: bool = false,
		convoy_scrap: String = ""
) -> void:
	destination = where
	unit_id = unit
	is_displaced_scrapped = scrap_displaced
	convoy_scrap_id = convoy_scrap


## A short text for log lines, such as [code]equip on unit:3[/code].
func describe() -> String:
	var text: String = (Destination.find_key(destination) as String).to_lower()
	if destination == Destination.EQUIP:
		text += " on %s%s" % [unit_id, ", displaced scrapped" if is_displaced_scrapped else ""]
	if not convoy_scrap_id.is_empty():
		text += ", scrapping %s from the convoy" % [convoy_scrap_id]
	return text


## Whether this placement puts an item into [param seat_run]'s convoy: the new item, or the item
## it displaces when that one is kept.
func needs_convoy_room(seat_run: SeatRun, definition: ItemDefinition) -> bool:
	match destination:
		Destination.CONVOY:
			return true
		Destination.EQUIP:
			var unit: UnitInstance = seat_run.unit(unit_id)
			return (
					unit != null and definition != null and not is_displaced_scrapped
					and not item_in(unit, slot_for(definition)).is_empty()
			)
	return false


## Why the new item of [param definition] can't be placed so in [param seat_run] now; empty when
## it can. Changes nothing. [param catalog]: the content the seat's items and units come from.
func validate(
		seat_run: SeatRun, definition: ItemDefinition, catalog: EffectCatalog.Index
) -> String:
	if definition == null:
		return "the item isn't in the catalog"
	if destination == Destination.EQUIP:
		var problem: String = equip_problem(seat_run, unit_id, definition, catalog)
		if not problem.is_empty():
			return problem
		var held_id: String = item_in(seat_run.unit(unit_id), slot_for(definition))
		if is_displaced_scrapped and held_id.is_empty():
			return "%s's slot is empty, so nothing is displaced to scrap" % [unit_id]
	elif is_displaced_scrapped:
		return "only equipping displaces an item"
	var needs_room: bool = (
			needs_convoy_room(seat_run, definition) and is_convoy_full(seat_run, catalog)
	)
	if needs_room and convoy_scrap_id.is_empty():
		return "the convoy is full (%d of %d), so one of its items must be scrapped" % [
			seat_run.convoy.size(), convoy_capacity(seat_run, catalog),
		]
	if not needs_room and not convoy_scrap_id.is_empty():
		return "nothing needs room in the convoy, so nothing is scrapped from it"
	if needs_room and not seat_run.convoy.has(convoy_scrap_id):
		return "the convoy holds no %s" % [convoy_scrap_id]
	return ""


## Places the new [param item] in [param run]'s seat [param seat], once [method validate] passed:
## [constant CampaignFact.Kind.GAINED] when it enters the roster,
## [constant CampaignFact.Kind.ITEM_EQUIPPED] for each item moved into or out of a slot, and
## [constant CampaignFact.Kind.ITEM_SCRAPPED] for each item scrapped, its gold added.
func apply(
		run: CampaignRunState, seat: int, item: ItemInstance, catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var definition: ItemDefinition = catalog.item(item.definition_id)
	if destination == Destination.SCRAP:
		# An item scrapped at pickup records ITEM_SCRAPPED alone, never GAINED: it never enters
		# the roster, so nothing reacting to a gain sees it.
		_scrap(run, seat, item, catalog)
		return
	if not convoy_scrap_id.is_empty():
		var scrapped: ItemInstance = seat_run.items[convoy_scrap_id]
		seat_run.convoy.remove_at(seat_run.convoy.find(convoy_scrap_id))
		seat_run.items.erase(convoy_scrap_id)
		_scrap(run, seat, scrapped, catalog)
	seat_run.items[item.instance_id] = item
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, seat, item.instance_id)
	gained.definition_id = item.definition_id
	run.record(gained)
	if destination == Destination.CONVOY:
		seat_run.convoy.append(item.instance_id)
		return
	var unit: UnitInstance = seat_run.unit(unit_id)
	var slot: Loadout.Slot = slot_for(definition)
	var displaced_id: String = item_in(unit, slot)
	if not displaced_id.is_empty():
		var displaced: ItemInstance = seat_run.items[displaced_id]
		if is_displaced_scrapped:
			seat_run.items.erase(displaced_id)
			_scrap(run, seat, displaced, catalog)
		else:
			seat_run.convoy.append(displaced_id)
			var moved: CampaignFact = CampaignFact.new(
					CampaignFact.Kind.ITEM_EQUIPPED, seat, displaced_id
			)
			moved.definition_id = displaced.definition_id
			run.record(moved)
	put_item(unit, slot, item.instance_id)
	var equipped: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.ITEM_EQUIPPED, seat, item.instance_id
	)
	equipped.target_id = unit_id
	equipped.definition_id = item.definition_id
	run.record(equipped)


# Adds item's scrap gold (held_scrap_value, so a modified item pays more) and records
# ITEM_SCRAPPED. The caller takes it out of the roster first.
func _scrap(
		run: CampaignRunState, seat: int, item: ItemInstance, catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var definition: ItemDefinition = catalog.item(item.definition_id)
	var gold: int = held_scrap_value(item, catalog)
	seat_run.gold = maxi(seat_run.gold + gold, 0)
	var scrapped: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.ITEM_SCRAPPED, seat, item.instance_id
	)
	scrapped.definition_id = definition.id if definition != null else ""
	scrapped.amount = gold
	run.record(scrapped)


## The slot an item of [param definition] goes in when gained: a weapon or staff in the Weapon
## slot, equipment in the Equipment slot, a trinket or consumable in the Pouch.
static func slot_for(definition: ItemDefinition) -> Loadout.Slot:
	if definition is WeaponDefinition:
		return Loadout.Slot.WEAPON
	if definition is EquipmentDefinition:
		return Loadout.Slot.EQUIPMENT
	return Loadout.Slot.POUCH


## Instance id of the item in [param unit]'s [param slot]; empty for an empty slot or no unit.
static func item_in(unit: UnitInstance, slot: Loadout.Slot) -> String:
	if unit == null:
		return ""
	match slot:
		Loadout.Slot.WEAPON:
			return unit.weapon_id
		Loadout.Slot.EQUIPMENT:
			return unit.equipment_id
	return unit.pouch_id


## Puts the item [param item_id] in [param unit]'s [param slot], replacing whatever id was there;
## the caller keeps the roster whole ([SeatRun]'s invariant).
static func put_item(unit: UnitInstance, slot: Loadout.Slot, item_id: String) -> void:
	match slot:
		Loadout.Slot.WEAPON:
			unit.weapon_id = item_id
		Loadout.Slot.EQUIPMENT:
			unit.equipment_id = item_id
		Loadout.Slot.POUCH:
			unit.pouch_id = item_id


## The weapon types [param unit] can wield: its type's, and its upgrade's once upgraded (never a
## commander's). [b]Keep in step with[/b] [method Loadout.load_unit], which loads by the same rule.
static func weapon_types_of(unit: UnitInstance, catalog: EffectCatalog.Index) -> PackedStringArray:
	var unit_type: UnitTypeDefinition = unit.definition(catalog)
	if unit_type == null:
		return PackedStringArray()
	var types: PackedStringArray = unit_type.weapon_types.duplicate()
	if unit.is_upgraded and not unit_type.is_commander:
		for weapon_type: String in unit_type.upgrade_weapon_types:
			if not types.has(weapon_type):
				types.append(weapon_type)
	return types


## Why [param seat_run]'s unit [param unit] can't equip an item of [param definition]; empty
## when it can. Only living units equip; a weapon needs a type the unit can wield.
static func equip_problem(
		seat_run: SeatRun, unit: String, definition: ItemDefinition, catalog: EffectCatalog.Index
) -> String:
	var holder: UnitInstance = null
	for living: UnitInstance in seat_run.army:
		if living.instance_id == unit:
			holder = living
	if holder == null:
		return "seat %d has no living unit %s" % [seat_run.seat, unit]
	if definition is WeaponDefinition:
		var weapon: WeaponDefinition = definition
		if not weapon_types_of(holder, catalog).has(weapon.weapon_type):
			return "%s can't wield a %s" % [unit, weapon.weapon_type]
	return ""


## How many items [param seat_run]'s convoy holds: one per unit of its max army size
## ([method RunOperations.max_army_size]; game-vision.md, Run-wide resources), so Abundance and
## Muster Roll grow it too. 0 for a faction not in [param catalog].
static func convoy_capacity(seat_run: SeatRun, catalog: EffectCatalog.Index) -> int:
	return RunOperations.max_army_size(seat_run, catalog)


## Whether [param seat_run]'s convoy is at or over [method convoy_capacity].
static func is_convoy_full(seat_run: SeatRun, catalog: EffectCatalog.Index) -> bool:
	return seat_run.convoy.size() >= convoy_capacity(seat_run, catalog)


## The gold scrapping a fresh, unmodified item of [param definition] pays, such as an offer not
## yet taken ([method Prices.scrap_value] at the default rate); 0 for Basic items or no
## definition. For an item already held, use [method held_scrap_value].
static func scrap_value(definition: ItemDefinition) -> int:
	if definition == null:
		return 0
	# TODO(TOD-001): SCRAP_PERCENT through the campaign's values (Scrapper's Tongs).
	return Prices.scrap_value(definition.kind, definition.rarity, Prices.default_scrap_percent())


## The gold scrapping the held [param item] pays ([method Prices.item_scrap_value] at the default
## rate), so a modified item scraps for more; equal to [method scrap_value] for an unmodified one.
## 0 for Basic items, a null item or one not in [param catalog].
static func held_scrap_value(item: ItemInstance, catalog: EffectCatalog.Index) -> int:
	# TODO(TOD-001): SCRAP_PERCENT through the campaign's values (Scrapper's Tongs).
	return Prices.item_scrap_value(item, catalog, Prices.default_scrap_percent())
