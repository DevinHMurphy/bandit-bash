# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name Guildhall
extends RefCounted
## The Guildhall's rules (game-vision.md, Campaign nodes and Economy; unit-roster.md, Prefixes and
## Recruiting): prices, recruits with their hand-over, runes and prefix re-rolls, from its shared
## [GuildhallStock]. Every price is a list price times the seat's
## [constant CampaignValue.Key.PRICE_PERCENT] (Membership Seal), rounded once, halves up.
##
## A recruit joins at the buyer's army's average level ([method recruit_for]); a full army names a
## unit to replace (never the commander), and the leaving unit's items are handed over
## ([enum HandOver]). A rune goes in an empty slot, or one the buyer names is discarded. A re-roll
## changes only a living non-commander unit's prefix; the first
## [constant CampaignValue.Key.FREE_REROLLS] each visit are free and don't raise the price. Each
## [code]*_problem[/code] check changes nothing. Pure and static.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Where one of the items in a hand-over goes when a recruit replaces a unit.
enum HandOver {
	## Into the recruit's slot for it ([method ItemPlacement.slot_for]); the recruit's own items
	## stay there by default.
	RECRUIT = 0,
	## Into the seat's convoy.
	CONVOY = 1,
	## Scrapped for its held scrap value at the seat's rate.
	SCRAP = 2,
}

## A recruit's list price before its prefix (unit-roster.md, Prefixes: 40 × the multiplier), the
## same for every unit type. [b]Units:[/b] gold.
const RECRUIT_BASE_PRICE: int = 40

## A unit's value multiplier by its prefix's tier, 0 for no prefix (unit-roster.md, Prefixes):
## it sets a recruit's price and a re-roll's. [b]Units:[/b] times the base price.
const VALUE_MULTIPLIERS: Dictionary[int, float] = {
	-2: 0.5,
	-1: 0.75,
	0: 1.0,
	1: 1.3,
	2: 1.8,
}

## A re-roll's base price is the unit's value divided by this (Terraria's reforge: one third).
const REROLL_VALUE_DIVISOR: float = 3.0

## What each paid re-roll before it at this visit adds to a re-roll's base price (game-vision.md,
## Economy: +50%). [b]Units:[/b] percent of the base price.
const REROLL_REPEAT_PERCENT: float = 50.0

## The source id the Guildhall's facts name in [member CampaignFact.definition_id] where a source
## is asked for (a recruit's arrival, a dismissal). Never parsed.
const SOURCE_ID: String = "guildhall"

## [code]buy_rune[/code]'s slot when no rune is discarded.
const NO_SLOT: int = -1

const _PERCENT: float = 100.0


## Whether [param run] is inside a Guildhall node, or an Unknown node that became one
## ([method CampaignRunState.node_type]).
static func is_at_guildhall(run: CampaignRunState) -> bool:
	return (
			run != null and run.flow.stage == RunFlow.Stage.NODE
			and run.graph != null and run.graph.has_node_id(run.node)
			and run.node_type() == CampaignGraph.NodeType.GUILDHALL
	)


## The tier of the unit prefix [param prefix_id] ([member UnitPrefixDefinition.tier]); 0 for no
## prefix or one not in [param catalog].
static func prefix_tier(prefix_id: String, catalog: EffectCatalog.Index) -> int:
	if prefix_id == UnitPrefixDefinition.NO_PREFIX:
		return 0
	var prefix: UnitPrefixDefinition = catalog.unit_prefix(prefix_id)
	return 0 if prefix == null else prefix.tier


## A unit's value with the prefix [param prefix_id]: [constant RECRUIT_BASE_PRICE] times its
## tier's [constant VALUE_MULTIPLIERS]. Exact, unrounded. [b]Units:[/b] gold.
static func unit_value(prefix_id: String, catalog: EffectCatalog.Index) -> float:
	return RECRUIT_BASE_PRICE * VALUE_MULTIPLIERS.get(prefix_tier(prefix_id, catalog), 1.0)


## What [param seat_run] pays for the recruit with the prefix [param prefix_id]:
## [method unit_value] times its price percent, halves up. [b]Units:[/b] gold.
static func recruit_price(
		seat_run: SeatRun, prefix_id: String, catalog: EffectCatalog.Index
) -> int:
	return _priced(seat_run, unit_value(prefix_id, catalog), catalog)


## What [param seat_run] pays for a rune: [constant Prices.RUNE_PRICE] times its price percent,
## halves up. [b]Units:[/b] gold.
static func rune_price(seat_run: SeatRun, catalog: EffectCatalog.Index) -> int:
	return _priced(seat_run, float(Prices.RUNE_PRICE), catalog)


## The free re-rolls seat [param seat] has left at this visit: its
## [constant CampaignValue.Key.FREE_REROLLS] (Tinker's Token), rounded, less those used; never
## below 0. 0 with no stock. [b]Units:[/b] re-rolls.
static func free_rerolls_left(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index
) -> int:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	var seat_run: SeatRun = run.seat_run(seat) if run != null else null
	if stock == null or seat_run == null:
		return 0
	var allowed: int = maxi(roundi(RunOperations.campaign_value(
			seat_run, catalog, CampaignValue.Key.FREE_REROLLS
	)), 0)
	return maxi(allowed - stock.rerolls_of(seat).free, 0)


## What seat [param seat] pays to re-roll the prefix of its unit [param unit_id] now: 0 while a
## free re-roll is left, else [method unit_value] ÷ [constant REROLL_VALUE_DIVISOR], plus
## [constant REROLL_REPEAT_PERCENT] of that per paid re-roll before it this visit, times its price
## percent, halves up. [constant Prices.NO_PRICE] for no such unit or stock. [b]Units:[/b] gold.
static func reroll_price(
		run: CampaignRunState, seat: int, unit_id: String, catalog: EffectCatalog.Index
) -> int:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	var seat_run: SeatRun = run.seat_run(seat) if run != null else null
	var unit: UnitInstance = _living(seat_run, unit_id)
	if stock == null or unit == null:
		return Prices.NO_PRICE
	if free_rerolls_left(run, seat, catalog) > 0:
		return 0
	var repeats: float = 1.0 + stock.rerolls_of(seat).paid * REROLL_REPEAT_PERCENT / _PERCENT
	var base: float = unit_value(unit.prefix_id, catalog) / REROLL_VALUE_DIVISOR
	return _priced(seat_run, base * repeats, catalog)


## Stock entry [param index]'s recruit as it would join seat [param seat]'s army now: leveled to
## [method RecruitOffer.level_for], so a seat's preview is its purchase. Null for no stock, entry
## or seat, a rune, or a recruit that won't level.
static func recruit_for(
		run: CampaignRunState, seat: int, index: int, catalog: EffectCatalog.Index
) -> RecruitOffer:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	var seat_run: SeatRun = run.seat_run(seat) if run != null else null
	if stock == null or seat_run == null or index < 0 or index >= stock.entries.size():
		return null
	var entry: GuildhallStock.Entry = stock.entries[index]
	if not entry.is_recruit():
		return null
	return entry.recruit.leveled(RecruitOffer.level_for(seat_run), catalog)


## Whether seat [param seat]'s army is full, so a recruit must replace a unit
## ([method RunOperations.max_army_size], Muster Roll counting).
static func is_army_full(run: CampaignRunState, seat: int, catalog: EffectCatalog.Index) -> bool:
	var seat_run: SeatRun = run.seat_run(seat)
	return (
			seat_run != null
			and seat_run.army.size() >= RunOperations.max_army_size(seat_run, catalog)
	)


## Why seat [param seat] can't buy stock entry [param index] at all now, whatever it names: no
## Guildhall, seat or entry; sold; a full army with no unit that can leave; or too little gold.
## Short, for a card. Empty when some purchase of it can pass.
static func entry_problem(
		run: CampaignRunState, seat: int, index: int, catalog: EffectCatalog.Index
) -> String:
	var problem: String = _offer_problem(run, seat, index)
	if not problem.is_empty():
		return problem
	var seat_run: SeatRun = run.seat_run(seat)
	var entry: GuildhallStock.Entry = GuildhallStock.pending(run).entries[index]
	var price: int = rune_price(seat_run, catalog)
	if entry.is_recruit():
		price = recruit_price(seat_run, entry.recruit.unit.prefix_id, catalog)
		if is_army_full(run, seat, catalog) and replaceable_units(seat_run).is_empty():
			return "no unit can make room"
	return "" if price <= seat_run.gold else "too little gold"


## The living units of [param seat_run] a recruit may replace, in roster order: every one but the
## commander.
static func replaceable_units(seat_run: SeatRun) -> PackedStringArray:
	var found: PackedStringArray = []
	if seat_run == null:
		return found
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id:
			found.append(unit.instance_id)
	return found


## The items a recruit replacing seat [param seat]'s unit [param replaced_id] hands over, by
## instance id: the leaving unit's (Weapon, Equipment, Pouch), then [param joining]'s own. Empty
## for no such unit.
static func hand_over_items(
		run: CampaignRunState, seat: int, replaced_id: String, joining: RecruitOffer
) -> PackedStringArray:
	var found: PackedStringArray = []
	var leaving: UnitInstance = _living(run.seat_run(seat), replaced_id)
	if leaving == null or joining == null:
		return found
	found.append_array(leaving.item_ids())
	found.append_array(joining.unit.item_ids())
	return found


## The suggested hand-over ("Best fit") when stock entry [param index]'s recruit replaces seat
## [param seat]'s unit [param replaced_id]: each of the leaving unit's items the recruit can use
## into its slot (displacing the recruit's own to the convoy, or scrapping it when that is full),
## then the rest to the convoy while it has room, then scrapped. Empty when no hand-over applies.
static func best_fit(
		run: CampaignRunState,
		seat: int,
		index: int,
		replaced_id: String,
		catalog: EffectCatalog.Index
) -> Dictionary[String, int]:
	var choices: Dictionary[String, int] = {}
	var seat_run: SeatRun = run.seat_run(seat) if run != null else null
	var joining: RecruitOffer = recruit_for(run, seat, index, catalog)
	var leaving: UnitInstance = _living(seat_run, replaced_id)
	if joining == null or leaving == null:
		return choices
	var taken: Dictionary[Loadout.Slot, bool] = {}
	var room: int = ItemPlacement.convoy_capacity(seat_run, catalog) - seat_run.convoy.size()
	var displaced: PackedStringArray = []
	for item_id: String in leaving.item_ids():
		var definition: ItemDefinition = catalog.item(seat_run.items[item_id].definition_id)
		var slot: Loadout.Slot = ItemPlacement.slot_for(definition)
		if definition != null and not taken.has(slot) and _can_take(joining, definition, catalog):
			taken[slot] = true
			choices[item_id] = HandOver.RECRUIT
			var own: String = ItemPlacement.item_in(joining.unit, slot)
			if not own.is_empty():
				displaced.append(own)
	for item_id: String in leaving.item_ids() + displaced:
		if choices.has(item_id):
			continue
		choices[item_id] = HandOver.CONVOY if room > 0 else HandOver.SCRAP
		room -= 1
	return choices


## Why seat [param seat] can't buy stock entry [param index], a recruit, now: any offer problem;
## a full army with no unit named (or the commander, or no such living unit), or room left with
## one named; a recruit whose ids the seat holds; then the [param hand_over] (see
## [method hand_over_problem]); then too little gold. Empty when it can.
static func recruit_problem(
		run: CampaignRunState,
		seat: int,
		index: int,
		replaced_id: String,
		hand_over: Dictionary[String, int],
		catalog: EffectCatalog.Index
) -> String:
	var problem: String = _offer_problem(run, seat, index)
	if not problem.is_empty():
		return problem
	var seat_run: SeatRun = run.seat_run(seat)
	var entry: GuildhallStock.Entry = GuildhallStock.pending(run).entries[index]
	if not entry.is_recruit():
		return "entry %d is a rune, not a recruit" % [index]
	var joining: RecruitOffer = recruit_for(run, seat, index, catalog)
	if joining == null:
		return "the recruit's unit type isn't in the catalog"
	if seat_run.unit(joining.unit.instance_id) != null:
		return "the seat already has a unit %s" % [joining.unit.instance_id]
	var limit: int = RunOperations.max_army_size(seat_run, catalog)
	if seat_run.army.size() < limit:
		if not replaced_id.is_empty():
			return "the army has room (%d of %d), so no unit is replaced" % [
				seat_run.army.size(), limit,
			]
		if not hand_over.is_empty():
			return "no unit is replaced, so nothing is handed over"
	else:
		if replaced_id.is_empty():
			return "the army is full (%d of %d), so a unit must be replaced" % [
				seat_run.army.size(), limit,
			]
		if replaced_id == seat_run.commander_id:
			return "the commander never leaves the army"
		if _living(seat_run, replaced_id) == null:
			return "seat %d has no living unit %s" % [seat, replaced_id]
		problem = hand_over_problem(run, seat, replaced_id, joining, hand_over, catalog)
		if not problem.is_empty():
			return problem
	return _gold_problem(seat_run, recruit_price(seat_run, joining.unit.prefix_id, catalog))


## Why [param hand_over] (item id to [enum HandOver]) can't settle the items when [param joining]
## replaces seat [param seat]'s unit [param replaced_id]: a leaving item with no place or an item
## not handed over; a weapon the recruit can't wield sent to it; two items for one of its slots;
## or more items for the convoy than it has room for. The recruit's own items stay unless named.
## Empty when it can.
static func hand_over_problem(
		run: CampaignRunState,
		seat: int,
		replaced_id: String,
		joining: RecruitOffer,
		hand_over: Dictionary[String, int],
		catalog: EffectCatalog.Index
) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if _living(seat_run, replaced_id) == null or joining == null:
		return "seat %d has no living unit %s" % [seat, replaced_id]
	var items: PackedStringArray = hand_over_items(run, seat, replaced_id, joining)
	for item_id: String in hand_over:
		if not items.has(item_id):
			return "%s isn't one of the items handed over" % [item_id]
		if not HandOver.values().has(hand_over[item_id]):
			return "%s has no place %d" % [item_id, hand_over[item_id]]
	var filled: Dictionary[Loadout.Slot, String] = {}
	var to_convoy: int = 0
	for item_id: String in items:
		var is_own: bool = joining.items.has(item_id)
		if not is_own and not hand_over.has(item_id):
			return "every item of %s needs a place: %s has none" % [replaced_id, item_id]
		var place: int = hand_over.get(item_id, HandOver.RECRUIT)
		var item: ItemInstance = joining.items[item_id] if is_own else seat_run.items[item_id]
		var definition: ItemDefinition = catalog.item(item.definition_id)
		if place == HandOver.CONVOY:
			to_convoy += 1
		if place != HandOver.RECRUIT:
			continue
		if definition == null:
			return "%s's item isn't in the catalog" % [item_id]
		if not is_own and not _can_take(joining, definition, catalog):
			return "the recruit can't wield a %s" % [(definition as WeaponDefinition).weapon_type]
		var slot: Loadout.Slot = ItemPlacement.slot_for(definition)
		if filled.has(slot):
			return "%s and %s can't both go in the recruit's %s slot" % [
				filled[slot], item_id, Loadout.Slot.find_key(slot),
			]
		filled[slot] = item_id
	var capacity: int = ItemPlacement.convoy_capacity(seat_run, catalog)
	if seat_run.convoy.size() + to_convoy > capacity:
		return "the convoy can't take %d more (%d of %d), so scrap some" % [
			to_convoy, seat_run.convoy.size(), capacity,
		]
	return ""


## Why seat [param seat] can't buy stock entry [param index], a rune, now: any offer problem; every
## slot full and no slot named to discard, or a slot named while one is free; then too little gold.
## Empty when it can.
static func rune_problem(
		run: CampaignRunState,
		seat: int,
		index: int,
		discard_slot: int,
		catalog: EffectCatalog.Index
) -> String:
	var problem: String = _offer_problem(run, seat, index)
	if not problem.is_empty():
		return problem
	var seat_run: SeatRun = run.seat_run(seat)
	var entry: GuildhallStock.Entry = GuildhallStock.pending(run).entries[index]
	if entry.is_recruit():
		return "entry %d is a recruit, not a rune" % [index]
	if catalog.rune(entry.definition_id) == null:
		return "rune \"%s\" isn't in the catalog" % [entry.definition_id]
	var is_full: bool = empty_rune_slot(seat_run) < 0
	if is_full and (discard_slot < 0 or discard_slot >= SeatRun.RUNE_SLOT_COUNT):
		return "every rune slot is full, so one rune must be discarded"
	if not is_full and discard_slot != NO_SLOT:
		return "a rune slot is free, so nothing is discarded"
	return _gold_problem(seat_run, rune_price(seat_run, catalog))


## Why seat [param seat] can't re-roll the prefix of its unit [param unit_id] now: no Guildhall,
## seat or stock; not a living unit; a commander (never prefixed); then too little gold. Empty
## when it can.
static func reroll_problem(
		run: CampaignRunState, seat: int, unit_id: String, catalog: EffectCatalog.Index
) -> String:
	if not is_at_guildhall(run):
		return "the run isn't inside a Guildhall"
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if GuildhallStock.pending(run) == null:
		return "the Guildhall's stock isn't rolled"
	var unit: UnitInstance = _living(seat_run, unit_id)
	if unit == null:
		return "seat %d has no living unit %s" % [seat, unit_id]
	var unit_type: UnitTypeDefinition = unit.definition(catalog)
	if unit_type == null:
		return "%s's unit type isn't in the catalog" % [unit_id]
	if unit_type.is_commander:
		return "a commander never has a prefix"
	return _gold_problem(seat_run, reroll_price(run, seat, unit_id, catalog))


## The index of [param seat_run]'s first empty rune slot; -1 when every slot holds a rune.
static func empty_rune_slot(seat_run: SeatRun) -> int:
	for index: int in seat_run.rune_slots.size():
		if seat_run.rune_slots[index].is_empty():
			return index
	return -1


## Buys stock entry [param index], a recruit, for seat [param seat], once
## [method recruit_problem] passed: [constant CampaignFact.Kind.UNIT_BOUGHT], then, replacing
## [param replaced_id], the [param hand_over]'s scraps, the dismissal
## ([method RunOperations.replace]: the convoy's items), the recruit's own items moved, and the
## leaving items it takes; else [method RunOperations.recruit].
static func buy_recruit(
		run: CampaignRunState,
		seat: int,
		index: int,
		replaced_id: String,
		hand_over: Dictionary[String, int],
		catalog: EffectCatalog.Index
) -> void:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	var entry: GuildhallStock.Entry = stock.entries[index]
	var seat_run: SeatRun = run.seat_run(seat)
	var joining: RecruitOffer = recruit_for(run, seat, index, catalog)
	var paid: int = recruit_price(seat_run, joining.unit.prefix_id, catalog)
	entry.buyer = seat
	seat_run.gold = maxi(seat_run.gold - paid, 0)
	var bought: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.UNIT_BOUGHT, seat, joining.unit.instance_id
	)
	bought.definition_id = joining.unit.unit_type_id
	bought.amount = paid
	run.record(bought)
	if replaced_id.is_empty():
		RunOperations.recruit(run, seat, joining, SOURCE_ID)
		stock.store(run)
		return
	var leaving: UnitInstance = _living(seat_run, replaced_id)
	var taken: PackedStringArray = []
	for item_id: String in leaving.item_ids():
		match hand_over.get(item_id, HandOver.CONVOY):
			HandOver.SCRAP:
				_take_out(leaving, item_id)
				var item: ItemInstance = seat_run.items[item_id]
				seat_run.items.erase(item_id)
				ItemPlacement.pay_scrap(run, seat, item, catalog)
			HandOver.RECRUIT:
				_take_out(leaving, item_id)
				taken.append(item_id)
	RunOperations.replace(run, seat, replaced_id, joining, SOURCE_ID)
	var recruit: UnitInstance = joining.unit
	for item_id: String in joining.items:
		match hand_over.get(item_id, HandOver.RECRUIT):
			HandOver.CONVOY:
				_take_out(recruit, item_id)
				seat_run.convoy.append(item_id)
				var stored: CampaignFact = CampaignFact.new(
						CampaignFact.Kind.ITEM_EQUIPPED, seat, item_id
				)
				stored.definition_id = seat_run.items[item_id].definition_id
				run.record(stored)
			HandOver.SCRAP:
				_take_out(recruit, item_id)
				var own: ItemInstance = seat_run.items[item_id]
				seat_run.items.erase(item_id)
				ItemPlacement.pay_scrap(run, seat, own, catalog)
	for item_id: String in taken:
		var item: ItemInstance = seat_run.items[item_id]
		ItemPlacement.put_item(
				recruit, ItemPlacement.slot_for(catalog.item(item.definition_id)), item_id
		)
		var equipped: CampaignFact = CampaignFact.new(
				CampaignFact.Kind.ITEM_EQUIPPED, seat, item_id
		)
		equipped.target_id = recruit.instance_id
		equipped.definition_id = item.definition_id
		run.record(equipped)
	stock.store(run)


## Buys stock entry [param index], a rune, for seat [param seat], once [method rune_problem]
## passed: [constant CampaignFact.Kind.RUNE_BOUGHT], the rune in [param discard_slot]
## discarded ([constant CampaignFact.Kind.RUNE_DISCARDED]) when every slot is full, then
## [constant CampaignFact.Kind.GAINED] with [constant CampaignFact.FLAG_BOUGHT].
static func buy_rune(
		run: CampaignRunState,
		seat: int,
		index: int,
		discard_slot: int,
		catalog: EffectCatalog.Index
) -> void:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	var entry: GuildhallStock.Entry = stock.entries[index]
	var seat_run: SeatRun = run.seat_run(seat)
	var paid: int = rune_price(seat_run, catalog)
	entry.buyer = seat
	seat_run.gold = maxi(seat_run.gold - paid, 0)
	var bought: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.RUNE_BOUGHT, seat, entry.instance_id
	)
	bought.definition_id = entry.definition_id
	bought.amount = paid
	run.record(bought)
	var slot: int = empty_rune_slot(seat_run)
	if slot < 0:
		slot = discard_slot
		var old: SeatRun.RuneSlot = seat_run.rune_slots[slot]
		var discarded: CampaignFact = CampaignFact.new(
				CampaignFact.Kind.RUNE_DISCARDED, seat, old.instance_id
		)
		discarded.definition_id = old.definition_id
		discarded.amount = slot
		run.record(discarded)
	seat_run.rune_slots[slot] = SeatRun.RuneSlot.new(entry.instance_id, entry.definition_id)
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, seat, entry.instance_id)
	gained.definition_id = entry.definition_id
	gained.flags |= CampaignFact.FLAG_BOUGHT
	run.record(gained)
	stock.store(run)


## Re-rolls the prefix of seat [param seat]'s unit [param unit_id] from [param stream] (its
## [code]PREFIX_REROLL[/code] stream; [method UnitPrefixDefinition.reroll], never the same result),
## once [method reroll_problem] passed: [constant CampaignFact.Kind.PREFIX_REROLLED] for its price,
## then [constant CampaignFact.Kind.HP_CHANGED] when current HP moved: a max-HP gain raises a hurt
## unit's HP by as much, a loss caps it at the new max (at least 1); a unit at full stays full.
static func reroll(
		run: CampaignRunState,
		seat: int,
		unit_id: String,
		catalog: EffectCatalog.Index,
		stream: RngStream
) -> void:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	var seat_run: SeatRun = run.seat_run(seat)
	var unit: UnitInstance = _living(seat_run, unit_id)
	var paid: int = reroll_price(run, seat, unit_id, catalog)
	var counts: GuildhallStock.Rerolls = stock.rerolls_of(seat)
	if free_rerolls_left(run, seat, catalog) > 0:
		counts.free += 1
	else:
		counts.paid += 1
	stock.rerolls[seat] = counts
	var old_max: int = unit.stats(catalog).get_int(CombatValue.Key.HP)
	unit.prefix_id = UnitPrefixDefinition.reroll(stream, catalog, unit.prefix_id)
	seat_run.gold = maxi(seat_run.gold - paid, 0)
	var rerolled: CampaignFact = CampaignFact.new(CampaignFact.Kind.PREFIX_REROLLED, seat, unit_id)
	rerolled.definition_id = unit.prefix_id
	rerolled.amount = paid
	run.record(rerolled)
	stock.store(run)
	var new_max: int = unit.stats(catalog).get_int(CombatValue.Key.HP)
	if unit.hp == UnitInstance.FULL_HP or new_max == old_max:
		return
	var before: int = unit.hp
	if new_max > old_max:
		unit.hp += new_max - old_max
	else:
		unit.hp = clampi(unit.hp, 1, maxi(new_max, 1))
	if unit.hp == before:
		return
	var healed: CampaignFact = CampaignFact.new(CampaignFact.Kind.HP_CHANGED, seat, unit_id)
	healed.amount = unit.hp - before
	healed.definition_id = SOURCE_ID
	run.record(healed)


# Why seat can't buy entry index whatever it names, deal or gold: no Guildhall, seat, stock or
# entry, or sold.
static func _offer_problem(run: CampaignRunState, seat: int, index: int) -> String:
	if not is_at_guildhall(run):
		return "the run isn't inside a Guildhall"
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	var stock: GuildhallStock = GuildhallStock.pending(run)
	if stock == null:
		return "the Guildhall's stock isn't rolled"
	if index < 0 or index >= stock.entries.size():
		return "the Guildhall stocks no entry %d" % [index]
	var entry: GuildhallStock.Entry = stock.entries[index]
	if entry.is_sold():
		return "it is sold" if entry.buyer != seat else "you bought it already"
	return ""


static func _gold_problem(seat_run: SeatRun, needed: int) -> String:
	if needed <= seat_run.gold:
		return ""
	return "not enough gold (it costs %d, you have %d)" % [needed, seat_run.gold]


# listed gold times seat_run's price percent, rounded to the nearest gold, halves up, never below 0.
static func _priced(seat_run: SeatRun, listed: float, catalog: EffectCatalog.Index) -> int:
	return maxi(ValueBreakdown.round_to_int(
			listed * Armory.price_percent(seat_run, catalog) / _PERCENT,
			ValueBreakdown.Rounding.HALF_UP
	), 0)


# Whether joining can use an item of definition in its slot: a weapon needs a type it wields.
static func _can_take(
		joining: RecruitOffer, definition: ItemDefinition, catalog: EffectCatalog.Index
) -> bool:
	var weapon: WeaponDefinition = definition as WeaponDefinition
	return weapon == null or ItemPlacement.weapon_types_of(joining.unit, catalog).has(
			weapon.weapon_type
	)


# Empties whichever of unit's slots holds item_id.
static func _take_out(unit: UnitInstance, item_id: String) -> void:
	for slot: Loadout.Slot in [Loadout.Slot.WEAPON, Loadout.Slot.EQUIPMENT, Loadout.Slot.POUCH]:
		if ItemPlacement.item_in(unit, slot) == item_id:
			ItemPlacement.put_item(unit, slot, "")


static func _living(seat_run: SeatRun, unit_id: String) -> UnitInstance:
	if seat_run == null:
		return null
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == unit_id:
			return unit
	return null
