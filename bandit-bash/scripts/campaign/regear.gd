# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     regear.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name Regear
extends RefCounted
## Re-gearing at a Camp (game-vision.md, Inventory: gear changes freely there, alongside Feast or
## Train): one move takes an item from a living unit's slot, a fallen unit's slot (fallen units
## only give items up) or the convoy, to a living unit's slot or the convoy.
##
## A slot takes what it holds in battle ([method fits], as [method Loadout.load_unit] loads): a
## weapon the unit can wield in Weapon or stowed in the Pouch, equipment in Equipment, a trinket
## or consumable in the Pouch. Moving onto a filled slot swaps: the item there goes where the
## moved one came from, when it fits there; a fallen unit takes nothing back. The convoy refuses an
## item once full ([method ItemPlacement.is_convoy_full]). A unit may be left unarmed. Every move
## records [constant CampaignFact.Kind.ITEM_EQUIPPED] per item moved. Pure and static.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md


## Why seat [param seat] can't move its item [param item_id] to its living unit
## [param unit_id]'s [param slot] (empty [param unit_id]: the convoy) now. Empty when it can.
static func move_problem(
		run: CampaignRunState,
		seat: int,
		item_id: String,
		unit_id: String,
		slot: Loadout.Slot,
		catalog: EffectCatalog.Index
) -> String:
	if not Camp.is_at_camp(run):
		return "gear changes only at a Camp"
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	var from: Place = locate(seat_run, item_id)
	if from == null:
		return "seat %d holds no %s" % [seat, item_id]
	var definition: ItemDefinition = catalog.item(seat_run.items[item_id].definition_id)
	if definition == null:
		return "%s isn't in the catalog" % [item_id]
	if unit_id.is_empty():
		if from.unit == null:
			return "%s is in the convoy already" % [item_id]
		if ItemPlacement.is_convoy_full(seat_run, catalog):
			return "the convoy is full (%d of %d)" % [
				seat_run.convoy.size(), ItemPlacement.convoy_capacity(seat_run, catalog),
			]
		return ""
	var target: UnitInstance = _living(seat_run, unit_id)
	if target == null:
		return "seat %d has no living unit %s" % [seat, unit_id]
	if from.unit == target and from.slot == slot:
		return "%s is in that slot already" % [item_id]
	var problem: String = fit_problem(target, slot, definition, catalog)
	if not problem.is_empty():
		return problem
	var occupant_id: String = ItemPlacement.item_in(target, slot)
	if occupant_id.is_empty():
		return ""
	if from.unit == null:
		return ""
	if from.is_fallen:
		return "a fallen unit takes nothing back, so the slot must be empty"
	var occupant: ItemDefinition = catalog.item(seat_run.items[occupant_id].definition_id)
	var back: String = fit_problem(from.unit, from.slot, occupant, catalog)
	if not back.is_empty():
		return "the item there can't go back: %s" % [back]
	return ""


## Moves seat [param seat]'s item [param item_id] there, once [method move_problem] passed,
## swapping with the item in a filled slot.
static func move(
		run: CampaignRunState,
		seat: int,
		item_id: String,
		unit_id: String,
		slot: Loadout.Slot
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var from: Place = locate(seat_run, item_id)
	_take_from(seat_run, from, item_id)
	if unit_id.is_empty():
		seat_run.convoy.append(item_id)
		_record(run, seat_run, item_id, "")
		return
	var target: UnitInstance = _living(seat_run, unit_id)
	var occupant_id: String = ItemPlacement.item_in(target, slot)
	ItemPlacement.put_item(target, slot, item_id)
	_record(run, seat_run, item_id, unit_id)
	if occupant_id.is_empty():
		return
	if from.unit == null:
		seat_run.convoy.append(occupant_id)
		_record(run, seat_run, occupant_id, "")
		return
	ItemPlacement.put_item(from.unit, from.slot, occupant_id)
	_record(run, seat_run, occupant_id, from.unit.instance_id)


## Why [param unit]'s [param slot] can't hold an item of [param definition] (see the class doc).
## Empty when it can.
static func fit_problem(
		unit: UnitInstance,
		slot: Loadout.Slot,
		definition: ItemDefinition,
		catalog: EffectCatalog.Index
) -> String:
	if definition == null:
		return "the item isn't in the catalog"
	var weapon: WeaponDefinition = definition as WeaponDefinition
	if weapon != null and not ItemPlacement.weapon_types_of(unit, catalog).has(weapon.weapon_type):
		return "%s can't wield a %s" % [unit.instance_id, weapon.weapon_type]
	match slot:
		Loadout.Slot.WEAPON:
			if weapon == null:
				return "only a weapon goes in the Weapon slot"
		Loadout.Slot.EQUIPMENT:
			if not definition is EquipmentDefinition:
				return "only equipment goes in the Equipment slot"
		Loadout.Slot.POUCH:
			if definition is EquipmentDefinition:
				return "equipment doesn't go in the Pouch"
	return ""


## Whether [param unit]'s [param slot] can hold an item of [param definition].
static func fits(
		unit: UnitInstance,
		slot: Loadout.Slot,
		definition: ItemDefinition,
		catalog: EffectCatalog.Index
) -> bool:
	return fit_problem(unit, slot, definition, catalog).is_empty()


## Where [param seat_run] holds [param item_id]: a living or fallen unit's slot, or the convoy
## ([member Place.unit] null); null when it holds no such item.
static func locate(seat_run: SeatRun, item_id: String) -> Place:
	if seat_run == null or not seat_run.items.has(item_id):
		return null
	if seat_run.convoy.has(item_id):
		return Place.new(null, Loadout.Slot.WEAPON, false)
	for unit: UnitInstance in seat_run.army + seat_run.fallen:
		for slot: Loadout.Slot in [Loadout.Slot.WEAPON, Loadout.Slot.EQUIPMENT, Loadout.Slot.POUCH]:
			if ItemPlacement.item_in(unit, slot) == item_id:
				return Place.new(unit, slot, seat_run.fallen.has(unit))
	return null


static func _take_from(seat_run: SeatRun, from: Place, item_id: String) -> void:
	if from.unit == null:
		seat_run.convoy.remove_at(seat_run.convoy.find(item_id))
		return
	ItemPlacement.put_item(from.unit, from.slot, "")


static func _record(
		run: CampaignRunState, seat_run: SeatRun, item_id: String, unit_id: String
) -> void:
	var moved: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.ITEM_EQUIPPED, seat_run.seat, item_id
	)
	moved.target_id = unit_id
	moved.definition_id = seat_run.items[item_id].definition_id
	run.record(moved)


static func _living(seat_run: SeatRun, unit_id: String) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == unit_id:
			return unit
	return null


## Where an item sits: [member unit]'s [member slot], or the convoy when [member unit] is null.
class Place:
	extends RefCounted

	## The unit holding it, living or fallen; null for the convoy.
	var unit: UnitInstance = null
	## Its slot on [member unit]; meaningless for the convoy.
	var slot: Loadout.Slot = Loadout.Slot.WEAPON
	## Whether [member unit] is fallen.
	var is_fallen: bool = false

	func _init(holder: UnitInstance, held_in: Loadout.Slot, fallen: bool) -> void:
		unit = holder
		slot = held_in
		is_fallen = fallen
