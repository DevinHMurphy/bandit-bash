# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_offer.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name StartingOffer
extends RefCounted
## One seat's starting heirloom offer: 3 of the 7 starting heirlooms (heirlooms.md, Starting
## heirlooms), each with its own offer rolled with it (the recruits, the weapons, Family Relic's
## heirloom), so a quit and Continue anywhere in it shows the same.
##
## [method roll] draws from the seat's [code]STARTING_OFFER[/code] stream at run start: the three
## heirlooms, then each one's part in offer order. [RunStart] stores it in the seat's
## [member SeatRun.pending_offers] under [constant OFFER_KEY] before the run's first save;
## [StartingHeirloomCommand] takes one, with its sub-choice, or skips when all three are refused
## ([method option_problem]). Until it is resolved the run can't choose its first node. Pure rules
## code; the faction and commander pickers it follows are skipped while the MVP has one of each.
##
## @tutorial(Heirlooms, Starting heirlooms): docs/design/heirlooms.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The key of the offer in [member SeatRun.pending_offers].
const OFFER_KEY: String = "starting_heirloom"

## Heirlooms offered (heirlooms.md: pick 1 of 3).
const OFFER_SIZE: int = 3

## [member taken] while the offer is open, or after a skip.
const NOT_TAKEN: int = -1

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_OPTIONS: String = "options"
const _KEY_HEIRLOOM: String = "heirloom_id"
const _KEY_RECRUITS: String = "recruits"
const _KEY_WEAPONS: String = "weapons"
const _KEY_DRAWN: String = "drawn_heirloom_id"
const _KEY_DEFINITION: String = "definition_id"
const _KEY_INSTANCE: String = "instance_id"
const _KEY_RESOLVED: String = "is_resolved"
const _KEY_TAKEN: String = "taken"

## The heirlooms offered, in the order drawn.
var options: Array[Option] = []

## Whether the seat took one, or skipped.
var is_resolved: bool = false

## The index in [member options] taken; [constant NOT_TAKEN] while open or after a skip.
var taken: int = NOT_TAKEN


## Writes this offer to [param seat_run]'s pending offers, replacing any there.
func store(seat_run: SeatRun) -> void:
	seat_run.pending_offers[OFFER_KEY] = capture()


## The offer as plain JSON.
func capture() -> Dictionary:
	var written: Array = []
	for option: Option in options:
		var recruits: Array = []
		for recruit: RecruitOffer in option.recruits:
			recruits.append(recruit.capture())
		var weapons: Array = []
		for weapon: ItemPick.Offer in option.weapons:
			weapons.append({
				_KEY_DEFINITION: weapon.definition_id, _KEY_INSTANCE: weapon.instance_id,
			})
		written.append({
			_KEY_HEIRLOOM: option.heirloom_id,
			_KEY_RECRUITS: recruits,
			_KEY_WEAPONS: weapons,
			_KEY_DRAWN: option.drawn_heirloom_id,
		})
	return {_KEY_OPTIONS: written, _KEY_RESOLVED: is_resolved, _KEY_TAKEN: taken}


## A new offer for [param seat_run] from [param stream] (see the class doc), ids from
## [param ids]; [param is_coop] lets Family Relic draw co-op heirlooms. Fewer than
## [constant OFFER_SIZE] options when the catalog has fewer starting heirlooms.
static func roll(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator,
		is_coop: bool
) -> StartingOffer:
	var offer: StartingOffer = StartingOffer.new()
	var left: PackedStringArray = pool(catalog)
	for _draw: int in OFFER_SIZE:
		if left.is_empty():
			break
		var heirloom_id: String = left[stream.pick_index(left.size())]
		left.remove_at(left.find(heirloom_id))
		offer.options.append(Option.new(heirloom_id))
	for option: Option in offer.options:
		var definition: StartingHeirloomDefinition = definition_of(option, catalog)
		match definition.bonus:
			StartingHeirloomDefinition.Bonus.RECRUIT, StartingHeirloomDefinition.Bonus.REPLACE:
				option.recruits = RecruitOffer.roll(
						stream, catalog, definition.offer_count, definition.is_prefix_positive,
						RecruitOffer.level_for(seat_run), ids
				)
			StartingHeirloomDefinition.Bonus.WEAPON:
				option.weapons = _roll_weapons(stream, seat_run, catalog, definition, ids)
			StartingHeirloomDefinition.Bonus.HEIRLOOM:
				option.drawn_heirloom_id = _draw_heirloom(
						stream, seat_run, catalog, definition.heirloom_tier, is_coop
				)
	offer.is_resolved = offer.options.is_empty()
	return offer


## [param seat_run]'s offer in its pending offers; null when it has none or its data is unusable
## (reported).
static func pending(seat_run: SeatRun) -> StartingOffer:
	if seat_run == null:
		return null
	var data: Variant = seat_run.pending_offers.get(OFFER_KEY, null)
	if data == null:
		return null
	var read: StartingOffer = restore(data as Dictionary) if data is Dictionary else null
	if read == null:
		push_error("StartingOffer: seat %d's offer is unusable - %s" % [seat_run.seat, data])
	return read


## Whether [param seat_run] has an offer still waiting for its choice.
static func is_open(seat_run: SeatRun) -> bool:
	var offer: StartingOffer = pending(seat_run)
	return offer != null and not offer.is_resolved


## The offer [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null for an option without an heirloom, an unusable recruit or weapon, or a taken index outside
## the options.
static func restore(data: Dictionary) -> StartingOffer:
	var written: Variant = data.get(_KEY_OPTIONS)
	var resolved: Variant = data.get(_KEY_RESOLVED)
	var taken_index: Variant = CampaignRunState.whole_number(data.get(_KEY_TAKEN))
	if not written is Array or not resolved is bool or taken_index == null:
		return null
	var offer: StartingOffer = StartingOffer.new()
	for entry: Variant in written as Array:
		var option: Option = _restore_option(entry)
		if option == null:
			return null
		offer.options.append(option)
	offer.is_resolved = resolved as bool
	offer.taken = taken_index as int
	if offer.taken != NOT_TAKEN and (offer.taken < 0 or offer.taken >= offer.options.size()):
		return null
	return offer


## Ids of every starting heirloom in [param catalog] (tier [code]starting[/code]), in id order.
static func pool(catalog: EffectCatalog.Index) -> PackedStringArray:
	var found: PackedStringArray = []
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.HEIRLOOM):
		if resource is StartingHeirloomDefinition:
			var starting: StartingHeirloomDefinition = resource
			if starting.tier == ContentIds.HEIRLOOM_STARTING:
				found.append(starting.id)
	found.sort()
	return found


## [param option]'s heirloom in [param catalog]; null when it isn't a starting heirloom there.
static func definition_of(
		option: Option, catalog: EffectCatalog.Index
) -> StartingHeirloomDefinition:
	return catalog.heirloom(option.heirloom_id) as StartingHeirloomDefinition


## Why [param option] can't be taken by seat [param seat] of [param run] now, whatever its
## sub-choice: its bonus has nothing to give (no room for a recruit, no unit to upgrade or
## replace, no weapon or heirloom drawn). Empty when it can.
static func option_problem(
		run: CampaignRunState, seat: int, option: Option, catalog: EffectCatalog.Index
) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	var definition: StartingHeirloomDefinition = definition_of(option, catalog)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if definition == null:
		return "\"%s\" isn't a starting heirloom in the catalog" % [option.heirloom_id]
	match definition.bonus:
		StartingHeirloomDefinition.Bonus.RECRUIT:
			if option.recruits.is_empty():
				return "there is no unit to recruit"
			var limit: int = RunOperations.max_army_size(
					seat_run, catalog, PackedStringArray([option.heirloom_id])
			)
			if seat_run.army.size() >= limit:
				return "the army has no room for a recruit (%d of %d)" % [
					seat_run.army.size(), limit,
				]
		StartingHeirloomDefinition.Bonus.REPLACE:
			if option.recruits.is_empty():
				return "there is no unit to recruit"
			if eligible_units(run, seat, catalog, true).is_empty():
				return "no unit but the commander can be replaced"
		StartingHeirloomDefinition.Bonus.UPGRADE:
			if eligible_units(run, seat, catalog, false).is_empty():
				return "no unit can be upgraded (the commander never is)"
		StartingHeirloomDefinition.Bonus.WEAPON:
			if option.weapons.is_empty():
				return "the army can use no %s weapon" % [
					(ItemDefinition.Rarity.find_key(definition.item_rarity) as String).capitalize(),
				]
		StartingHeirloomDefinition.Bonus.HEIRLOOM:
			if option.drawn_heirloom_id.is_empty():
				return "no %s heirloom is left to draw" % [definition.heirloom_tier.capitalize()]
	return ""


## The living units of seat [param seat] its sub-choice may name: those
## [method RunOperations.dismiss_problem] lets leave when [param is_replacing], else those
## [method RunOperations.upgrade_problem] lets be upgraded, in roster order.
static func eligible_units(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index, is_replacing: bool
) -> PackedStringArray:
	var found: PackedStringArray = []
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return found
	for unit: UnitInstance in seat_run.army:
		var problem: String = (
				RunOperations.dismiss_problem(run, seat, unit.instance_id, catalog) if is_replacing
				else RunOperations.upgrade_problem(run, seat, unit.instance_id, catalog)
		)
		if problem.is_empty():
			found.append(unit.instance_id)
	return found


# Up to the heirloom's offer_count weapons of its rarity the army can use (ItemPick's reading:
# staves count, and so does the commander), each of a type not yet offered while one is left,
# then of any type; never the same weapon twice. Types and weapons evenly, in id order.
static func _roll_weapons(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		definition: StartingHeirloomDefinition,
		ids: InstanceIdAllocator
) -> Array[ItemPick.Offer]:
	var usable: PackedStringArray = ItemPick.usable_weapon_types(seat_run, catalog)
	var by_type: Dictionary[String, Array] = {}
	var weapon_kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
	for item: ItemDefinition in ItemPools.items_of(catalog, weapon_kinds):
		var weapon: WeaponDefinition = item as WeaponDefinition
		if weapon == null or weapon.rarity != definition.item_rarity:
			continue
		if not usable.has(weapon.weapon_type):
			continue
		if not by_type.has(weapon.weapon_type):
			by_type[weapon.weapon_type] = []
		by_type[weapon.weapon_type].append(weapon)
	var types: PackedStringArray = PackedStringArray(by_type.keys())
	types.sort()
	var used: PackedStringArray = []
	var offers: Array[ItemPick.Offer] = []
	for _offer: int in definition.offer_count:
		var fresh: PackedStringArray = []
		var stocked: PackedStringArray = []
		for weapon_type: String in types:
			if (by_type[weapon_type] as Array).is_empty():
				continue
			stocked.append(weapon_type)
			if not used.has(weapon_type):
				fresh.append(weapon_type)
		var choices: PackedStringArray = fresh if not fresh.is_empty() else stocked
		if choices.is_empty():
			break
		var picked_type: String = choices[stream.pick_index(choices.size())]
		var stock: Array = by_type[picked_type]
		var picked: WeaponDefinition = stock[stream.pick_index(stock.size())]
		stock.erase(picked)
		used.append(picked_type)
		offers.append(ItemPick.Offer.new(picked.id, ids.next_item_id(picked.display_name)))
	return offers


# One heirloom of tier, evenly in id order, that seat_run doesn't own (offers never duplicate one,
# heirlooms.md), co-op ones only in co-op; never a curse or a starting heirloom. Empty for none.
static func _draw_heirloom(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		tier: String,
		is_coop: bool
) -> String:
	var owned: PackedStringArray = seat_run.heirloom_ids()
	var found: PackedStringArray = []
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.HEIRLOOM):
		var heirloom: HeirloomDefinition = resource as HeirloomDefinition
		if heirloom == null or heirloom is CurseDefinition or heirloom.tier != tier:
			continue
		if owned.has(heirloom.id) or (heirloom.is_coop_only and not is_coop):
			continue
		found.append(heirloom.id)
	if found.is_empty():
		return ""
	found.sort()
	return found[stream.pick_index(found.size())]


static func _restore_option(entry: Variant) -> Option:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var heirloom_id: Variant = data.get(_KEY_HEIRLOOM)
	var recruits: Variant = data.get(_KEY_RECRUITS)
	var weapons: Variant = data.get(_KEY_WEAPONS)
	var drawn: Variant = data.get(_KEY_DRAWN)
	if (
			not heirloom_id is String or (heirloom_id as String).is_empty()
			or not recruits is Array or not weapons is Array or not drawn is String
	):
		return null
	var option: Option = Option.new(heirloom_id as String)
	option.drawn_heirloom_id = drawn as String
	for recruit_data: Variant in recruits as Array:
		var recruit: RecruitOffer = null
		if recruit_data is Dictionary:
			recruit = RecruitOffer.restore(recruit_data as Dictionary)
		if recruit == null:
			return null
		option.recruits.append(recruit)
	for weapon_data: Variant in weapons as Array:
		if not weapon_data is Dictionary:
			return null
		var definition_id: Variant = (weapon_data as Dictionary).get(_KEY_DEFINITION)
		var instance_id: Variant = (weapon_data as Dictionary).get(_KEY_INSTANCE)
		if (
				not definition_id is String or (definition_id as String).is_empty()
				or not instance_id is String or (instance_id as String).is_empty()
		):
			return null
		option.weapons.append(ItemPick.Offer.new(definition_id as String, instance_id as String))
	return option


## One heirloom offered and the part of it rolled with it.
class Option:
	extends RefCounted

	## Content id of its [StartingHeirloomDefinition].
	var heirloom_id: String = ""
	## The units a recruit or replace bonus offers, in the order rolled. Empty for other bonuses.
	var recruits: Array[RecruitOffer] = []
	## The weapons a weapon bonus offers, each with the instance id it gets when taken.
	var weapons: Array[ItemPick.Offer] = []
	## The heirloom a heirloom bonus gives; hidden until taken. Empty for other bonuses.
	var drawn_heirloom_id: String = ""

	func _init(id: String = "") -> void:
		heirloom_id = id
