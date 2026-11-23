# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_hand_over.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventHandOver
extends RefCounted
## The hand-over when an event's recruit or revived unit takes the place of a unit in a full army
## (unit-roster.md, Recruiting and item transfer), with the Guildhall's places
## ([enum Guildhall.HandOver]): each of the leaving unit's items goes onto the unit joining (a
## weapon only if it wields the type), into the convoy, or is scrapped at the seat's rate. An item
## not named goes to the convoy ([member EventChoice.hand_over]).
##
## An item put on the unit joining sends what that unit held in the slot to the convoy, which must
## have room for it: the joining unit's own items get no place of their own, since a recruit's ids
## are minted only as it joins. The unit joining is a [RecruitOffer] (a recruit, or a fallen unit
## with its items); null while it isn't known. Pure and static.
##
## @tutorial(Events): docs/design/events.md


## Why seat [param seat]'s unit [param unit_id] can't leave the army for an event's newcomer,
## whatever its items: not a living unit, or the commander, in the words of
## [method RunOperations.dismiss_problem]. Empty when it can; the convoy's room is the hand-over's
## to settle ([method problem]).
static func leave_problem(run: CampaignRunState, seat: int, unit_id: String) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if EventOutcome.living_unit(seat_run, unit_id) == null:
		return "seat %d has no living unit %s" % [seat, unit_id]
	if unit_id == seat_run.commander_id:
		return "the commander never leaves the army"
	return ""


## Why [param hand_over] can't settle the items of [param leaving] as [param joining] takes its
## place in [param seat_run]'s army: an item that isn't the leaving unit's or a place that isn't
## one; an item for the unit joining while it isn't known, or a weapon it can't wield; or more for
## the convoy ([method convoy_count]) than it has room for. Empty when it can.
static func problem(
		seat_run: SeatRun,
		leaving: UnitInstance,
		joining: RecruitOffer,
		hand_over: Dictionary[String, int],
		catalog: EffectCatalog.Index
) -> String:
	var items: PackedStringArray = leaving.item_ids()
	for item_id: String in hand_over:
		if not items.has(item_id):
			return "%s isn't one of %s's items" % [item_id, leaving.instance_id]
		if not Guildhall.HandOver.values().has(hand_over[item_id]):
			return "%s has no place %d" % [item_id, hand_over[item_id]]
	for item_id: String in items:
		if place_of(hand_over, item_id) != Guildhall.HandOver.RECRUIT:
			continue
		if joining == null:
			return "the unit joining isn't known yet, so %s can't go on it" % [item_id]
		var definition: ItemDefinition = _definition(seat_run, item_id, catalog)
		if definition == null:
			return "%s's item isn't in the catalog" % [item_id]
		if not can_take(joining, definition, catalog):
			return "the unit joining can't wield a %s" % [
				(definition as WeaponDefinition).weapon_type,
			]
	var capacity: int = ItemPlacement.convoy_capacity(seat_run, catalog)
	var to_convoy: int = convoy_count(seat_run, leaving, joining, hand_over, catalog)
	if seat_run.convoy.size() + to_convoy > capacity:
		return "the convoy can't take %d more (%d of %d), so scrap some" % [
			to_convoy, seat_run.convoy.size(), capacity,
		]
	return ""


## Where [param hand_over] sends the item [param item_id]: its place, or the convoy.
static func place_of(hand_over: Dictionary[String, int], item_id: String) -> int:
	return hand_over.get(item_id, Guildhall.HandOver.CONVOY)


## How many items [param hand_over] adds to [param seat_run]'s convoy: each of [param leaving]'s
## items sent there, then each of [param joining]'s own it displaces ([method displaced]).
static func convoy_count(
		seat_run: SeatRun,
		leaving: UnitInstance,
		joining: RecruitOffer,
		hand_over: Dictionary[String, int],
		catalog: EffectCatalog.Index
) -> int:
	var count: int = 0
	for item_id: String in leaving.item_ids():
		if place_of(hand_over, item_id) == Guildhall.HandOver.CONVOY:
			count += 1
	return count + displaced(seat_run, leaving, joining, hand_over, catalog).size()


## The ids of [param joining]'s own items that [param hand_over] sends to the convoy: each one in
## a slot a leaving item goes into. Empty while the unit joining isn't known.
static func displaced(
		seat_run: SeatRun,
		leaving: UnitInstance,
		joining: RecruitOffer,
		hand_over: Dictionary[String, int],
		catalog: EffectCatalog.Index
) -> PackedStringArray:
	var found: PackedStringArray = []
	if joining == null:
		return found
	for item_id: String in leaving.item_ids():
		if place_of(hand_over, item_id) != Guildhall.HandOver.RECRUIT:
			continue
		var definition: ItemDefinition = _definition(seat_run, item_id, catalog)
		if definition == null:
			continue
		var own: String = ItemPlacement.item_in(joining.unit, ItemPlacement.slot_for(definition))
		if not own.is_empty() and not found.has(own):
			found.append(own)
	return found


## Whether [param joining] can use an item of [param definition] in its slot: a weapon needs a
## type it wields ([method ItemPlacement.weapon_types_of]); anything else fits.
static func can_take(
		joining: RecruitOffer, definition: ItemDefinition, catalog: EffectCatalog.Index
) -> bool:
	var weapon: WeaponDefinition = definition as WeaponDefinition
	return weapon == null or ItemPlacement.weapon_types_of(joining.unit, catalog).has(
			weapon.weapon_type
	)


## The suggested hand-over ("Best fit"), as the Guildhall's: each of [param leaving]'s items
## [param joining] can use onto it (when that displaces one of its own, only while the convoy has
## room for it), then the rest to the convoy while it has room, then scrapped.
static func best_fit(
		seat_run: SeatRun,
		leaving: UnitInstance,
		joining: RecruitOffer,
		catalog: EffectCatalog.Index
) -> Dictionary[String, int]:
	var choices: Dictionary[String, int] = {}
	var room: int = ItemPlacement.convoy_capacity(seat_run, catalog) - seat_run.convoy.size()
	for item_id: String in leaving.item_ids():
		var definition: ItemDefinition = _definition(seat_run, item_id, catalog)
		if joining == null or definition == null or not can_take(joining, definition, catalog):
			continue
		var own: String = ItemPlacement.item_in(joining.unit, ItemPlacement.slot_for(definition))
		if own.is_empty():
			choices[item_id] = Guildhall.HandOver.RECRUIT
		elif room > 0:
			choices[item_id] = Guildhall.HandOver.RECRUIT
			room -= 1
	for item_id: String in leaving.item_ids():
		if choices.has(item_id):
			continue
		choices[item_id] = Guildhall.HandOver.CONVOY if room > 0 else Guildhall.HandOver.SCRAP
		room -= 1
	return choices


## [param hand_over] as it travels: the convoy's entries dropped, since an item not named goes
## there, so a hand-over left as it opened is empty.
static func compact(hand_over: Dictionary[String, int]) -> Dictionary[String, int]:
	var kept: Dictionary[String, int] = {}
	for item_id: String in hand_over:
		if hand_over[item_id] != Guildhall.HandOver.CONVOY:
			kept[item_id] = hand_over[item_id]
	return kept


## Before seat [param seat]'s unit [param leaving_id] is dismissed, once [method problem] passed:
## each of its items [param hand_over] scraps is taken out and paid for
## ([method ItemPlacement.pay_scrap]), and each it gives the unit joining is taken out. Returns
## those, for [method hand_to]; the rest stay for the dismissal to send to the convoy. Nothing for
## no such unit.
static func set_aside(
		run: CampaignRunState,
		seat: int,
		leaving_id: String,
		hand_over: Dictionary[String, int],
		catalog: EffectCatalog.Index
) -> PackedStringArray:
	var taken: PackedStringArray = []
	var seat_run: SeatRun = run.seat_run(seat)
	var leaving: UnitInstance = EventOutcome.living_unit(seat_run, leaving_id)
	if leaving == null:
		return taken
	for item_id: String in leaving.item_ids():
		match place_of(hand_over, item_id):
			Guildhall.HandOver.SCRAP:
				_take_out(leaving, item_id)
				var item: ItemInstance = seat_run.items[item_id]
				seat_run.items.erase(item_id)
				ItemPlacement.pay_scrap(run, seat, item, catalog)
			Guildhall.HandOver.RECRUIT:
				_take_out(leaving, item_id)
				taken.append(item_id)
	return taken


## Once [param unit] has joined seat [param seat]'s army: each [param taken] item goes in its
## slot, what the unit held there first moving to the convoy, each with
## [constant CampaignFact.Kind.ITEM_EQUIPPED] (naming the unit for an item it now holds).
static func hand_to(
		run: CampaignRunState,
		seat: int,
		unit: UnitInstance,
		taken: PackedStringArray,
		catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	for item_id: String in taken:
		var item: ItemInstance = seat_run.items[item_id]
		var slot: Loadout.Slot = ItemPlacement.slot_for(catalog.item(item.definition_id))
		var own: String = ItemPlacement.item_in(unit, slot)
		if not own.is_empty():
			ItemPlacement.put_item(unit, slot, "")
			seat_run.convoy.append(own)
			var stored: CampaignFact = CampaignFact.new(CampaignFact.Kind.ITEM_EQUIPPED, seat, own)
			stored.definition_id = seat_run.items[own].definition_id
			run.record(stored)
		ItemPlacement.put_item(unit, slot, item_id)
		var equipped: CampaignFact = CampaignFact.new(
				CampaignFact.Kind.ITEM_EQUIPPED, seat, item_id
		)
		equipped.target_id = unit.instance_id
		equipped.definition_id = item.definition_id
		run.record(equipped)


# The definition of seat_run's item item_id; null for an unknown item or definition.
static func _definition(
		seat_run: SeatRun, item_id: String, catalog: EffectCatalog.Index
) -> ItemDefinition:
	var item: ItemInstance = seat_run.items.get(item_id, null)
	return null if item == null else catalog.item(item.definition_id)


# Empties whichever of unit's slots holds item_id.
static func _take_out(unit: UnitInstance, item_id: String) -> void:
	for slot: Loadout.Slot in [Loadout.Slot.WEAPON, Loadout.Slot.EQUIPMENT, Loadout.Slot.POUCH]:
		if ItemPlacement.item_in(unit, slot) == item_id:
			ItemPlacement.put_item(unit, slot, "")
