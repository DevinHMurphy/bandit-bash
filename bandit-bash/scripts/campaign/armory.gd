# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     armory.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name Armory
extends RefCounted
## The Armory's rules (game-vision.md, Campaign nodes; items.md, Scrapping): prices, trade-ins and
## purchases from its shared [ArmoryStock]. There is no sell screen.
##
## A seat's price is the list price ([Prices]) times its
## [constant CampaignValue.Key.PRICE_PERCENT] (Membership Seal), halves up. An item is bought onto
## a living unit that can use it, into the slot [method ItemPlacement.slot_for] names; the item
## there is traded in (its held scrap value at the seat's rate comes off the price, so a modified
## item is worth more) or sent to the convoy, refused when that is full. An heirloom joins the
## seat's heirlooms, refused when it owns one, or another seat owns a unique one. Every entry sells
## once; in co-op a bought unique heirloom's slot restocks ([method ArmoryStock.replacement]).
## Each [code]*_problem[/code] check changes nothing. Pure and static.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

const _PERCENT: float = 100.0


## Whether [param run] is inside an Armory node.
static func is_at_armory(run: CampaignRunState) -> bool:
	return (
			run != null and run.flow.stage == RunFlow.Stage.NODE
			and run.graph != null and run.graph.has_node_id(run.node)
			and run.graph.type_of(run.node) == CampaignGraph.NodeType.ARMORY
	)


## The share of list prices [param seat_run] pays ([constant CampaignValue.Key.PRICE_PERCENT]: 100,
## less 20 per Membership Seal). [b]Units:[/b] percent; never below 0.
static func price_percent(seat_run: SeatRun, catalog: EffectCatalog.Index) -> float:
	return maxf(
			RunOperations.campaign_value(seat_run, catalog, CampaignValue.Key.PRICE_PERCENT), 0.0
	)


## The list price of [param entry]: its item's ([method Prices.item_price]) or its heirloom's
## tier's ([method Prices.heirloom_price]); [constant Prices.NO_PRICE] when it isn't sold or isn't
## in [param catalog].
static func list_price(entry: ArmoryStock.Entry, catalog: EffectCatalog.Index) -> int:
	if entry.is_heirloom():
		var heirloom: HeirloomDefinition = catalog.heirloom(entry.definition_id)
		return Prices.NO_PRICE if heirloom == null else Prices.heirloom_price(heirloom.tier)
	return Prices.item_price(catalog.item(entry.definition_id))


## What [param seat_run] pays for [param entry] before any trade-in: [method list_price] times
## [method price_percent], rounded to the nearest gold, halves up (game-vision.md, Gold scale).
## [constant Prices.NO_PRICE] when it isn't sold. [b]Units:[/b] gold.
static func price(
		seat_run: SeatRun, entry: ArmoryStock.Entry, catalog: EffectCatalog.Index
) -> int:
	var listed: int = list_price(entry, catalog)
	if listed == Prices.NO_PRICE:
		return Prices.NO_PRICE
	return maxi(ValueBreakdown.round_to_int(
			listed * price_percent(seat_run, catalog) / _PERCENT, ValueBreakdown.Rounding.HALF_UP
	), 0)


## The item in the slot of [param seat_run]'s unit [param unit_id] an item of [param definition]
## goes in; null for an empty slot or no such unit.
static func replaced_item(
		seat_run: SeatRun, unit_id: String, definition: ItemDefinition
) -> ItemInstance:
	if seat_run == null or definition == null:
		return null
	var held_id: String = ItemPlacement.item_in(
			seat_run.unit(unit_id), ItemPlacement.slot_for(definition)
	)
	return seat_run.items.get(held_id, null) if not held_id.is_empty() else null


## The gold trading in the item [method replaced_item] names takes off the price: its
## [method ItemPlacement.held_scrap_value] at [param seat_run]'s rate (Scrapper's Tongs counts).
## 0 for an empty slot. [b]Units:[/b] gold.
static func trade_in_value(
		seat_run: SeatRun, unit_id: String, definition: ItemDefinition, catalog: EffectCatalog.Index
) -> int:
	var held: ItemInstance = replaced_item(seat_run, unit_id, definition)
	return 0 if held == null else ItemPlacement.held_scrap_value(held, catalog, seat_run)


## What [param seat_run] pays for [param entry] onto its unit [param unit_id], the replaced item
## traded in when [param is_traded_in]: [method price] less [method trade_in_value]. Negative when
## the trade-in is worth more: the seat gains the difference. [b]Units:[/b] gold.
static func cost(
		seat_run: SeatRun,
		entry: ArmoryStock.Entry,
		unit_id: String,
		is_traded_in: bool,
		catalog: EffectCatalog.Index
) -> int:
	var paid: int = price(seat_run, entry, catalog)
	if is_traded_in and not entry.is_heirloom():
		paid -= trade_in_value(seat_run, unit_id, catalog.item(entry.definition_id), catalog)
	return paid


## Why seat [param seat] can't buy stock entry [param index] at all now, whatever unit and deal it
## picks: no Armory, seat or entry; sold; not for sale; an heirloom it owns, or a unique one another
## seat owns; an item no living unit can use; or too little gold even at the best trade-in. Short,
## for a card. Empty when some purchase of it can pass [method purchase_problem].
static func entry_problem(
		run: CampaignRunState, seat: int, index: int, catalog: EffectCatalog.Index
) -> String:
	var problem: String = _offer_problem(run, seat, index, catalog)
	if not problem.is_empty():
		return problem
	var seat_run: SeatRun = run.seat_run(seat)
	var entry: ArmoryStock.Entry = ArmoryStock.pending(run).entries[index]
	var cheapest: int = price(seat_run, entry, catalog)
	if not entry.is_heirloom():
		var definition: ItemDefinition = catalog.item(entry.definition_id)
		var best_trade_in: int = 0
		for unit_id: String in usable_units(seat_run, definition, catalog):
			best_trade_in = maxi(
					best_trade_in, trade_in_value(seat_run, unit_id, definition, catalog)
			)
		cheapest -= best_trade_in
	return "" if cheapest <= seat_run.gold else "too little gold"


## Why seat [param seat] can't buy stock entry [param index] now onto its unit [param unit_id],
## trading in the replaced item when [param is_traded_in] (else it goes to the convoy): any
## [method entry_problem] but gold; for an heirloom, a unit or a trade-in named; for an item, a unit
## that can't equip it, a trade-in of an empty slot, a full convoy; then too little gold. Empty when
## it can.
static func purchase_problem(
		run: CampaignRunState,
		seat: int,
		index: int,
		unit_id: String,
		is_traded_in: bool,
		catalog: EffectCatalog.Index
) -> String:
	var problem: String = _offer_problem(run, seat, index, catalog)
	if not problem.is_empty():
		return problem
	var seat_run: SeatRun = run.seat_run(seat)
	var entry: ArmoryStock.Entry = ArmoryStock.pending(run).entries[index]
	if entry.is_heirloom():
		if not unit_id.is_empty() or is_traded_in:
			return "an heirloom joins the heirlooms, so it goes on no unit and trades nothing in"
		return _gold_problem(seat_run, cost(seat_run, entry, unit_id, false, catalog))
	var definition: ItemDefinition = catalog.item(entry.definition_id)
	problem = ItemPlacement.equip_problem(seat_run, unit_id, definition, catalog)
	if not problem.is_empty():
		return problem
	var held: ItemInstance = replaced_item(seat_run, unit_id, definition)
	if is_traded_in and held == null:
		return "that slot is empty, so nothing is traded in"
	if not is_traded_in and held != null and ItemPlacement.is_convoy_full(seat_run, catalog):
		return "the convoy is full (%d of %d), so the replaced item can only be traded in" % [
			seat_run.convoy.size(), ItemPlacement.convoy_capacity(seat_run, catalog),
		]
	return _gold_problem(seat_run, cost(seat_run, entry, unit_id, is_traded_in, catalog))


## The living units of [param seat_run] that can equip an item of [param definition], in roster
## order ([method ItemPlacement.equip_problem]).
static func usable_units(
		seat_run: SeatRun, definition: ItemDefinition, catalog: EffectCatalog.Index
) -> PackedStringArray:
	var found: PackedStringArray = []
	if seat_run == null or definition == null:
		return found
	for unit: UnitInstance in seat_run.army:
		if ItemPlacement.equip_problem(seat_run, unit.instance_id, definition, catalog).is_empty():
			found.append(unit.instance_id)
	return found


## Buys stock entry [param index] for seat [param seat], once [method purchase_problem] passed.
## An item: [constant CampaignFact.Kind.ITEM_TRADED_IN] when the replaced one is traded in,
## [constant CampaignFact.Kind.ITEM_BOUGHT], then its placement's facts
## ([method ItemPlacement.apply]). An heirloom: ITEM_BOUGHT, then
## [method RunOperations.grant_heirloom]'s facts. Every [constant CampaignFact.Kind.GAINED] carries
## [constant CampaignFact.FLAG_BOUGHT]. A unique heirloom bought in co-op restocks its slot from
## [param stream].
static func buy(
		run: CampaignRunState,
		seat: int,
		index: int,
		unit_id: String,
		is_traded_in: bool,
		catalog: EffectCatalog.Index,
		stream: RngStream
) -> void:
	var stock: ArmoryStock = ArmoryStock.pending(run)
	var entry: ArmoryStock.Entry = stock.entries[index]
	var seat_run: SeatRun = run.seat_run(seat)
	var paid: int = cost(seat_run, entry, unit_id, is_traded_in, catalog)
	var first: int = run.fact_log.size()
	entry.buyer = seat
	if entry.is_heirloom():
		seat_run.gold = maxi(seat_run.gold - paid, 0)
		run.record(_bought(seat, entry, paid))
		RunOperations.grant_heirloom(run, seat, entry.definition_id, catalog)
		_restock_unique(run, stock, entry, catalog, stream)
	else:
		if is_traded_in:
			_trade_in(run, seat, unit_id, catalog.item(entry.definition_id), catalog)
		seat_run.gold = maxi(seat_run.gold - paid, 0)
		run.record(_bought(seat, entry, paid))
		ItemPlacement.new(ItemPlacement.Destination.EQUIP, unit_id).apply(
				run, seat, ItemInstance.new(entry.instance_id, entry.definition_id), catalog
		)
	for fact: CampaignFact in run.fact_log.slice(first):
		if fact.kind == CampaignFact.Kind.GAINED:
			fact.flags |= CampaignFact.FLAG_BOUGHT
	stock.store(run)


# Why seat can't buy entry index whatever unit, deal or gold: everything entry_problem checks but
# gold.
static func _offer_problem(
		run: CampaignRunState, seat: int, index: int, catalog: EffectCatalog.Index
) -> String:
	if not is_at_armory(run):
		return "the run isn't inside an Armory"
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	var stock: ArmoryStock = ArmoryStock.pending(run)
	if stock == null:
		return "the Armory's stock isn't rolled"
	if index < 0 or index >= stock.entries.size():
		return "the Armory stocks no entry %d" % [index]
	var entry: ArmoryStock.Entry = stock.entries[index]
	if entry.is_sold():
		return "it is sold" if entry.buyer != seat else "you bought it already"
	if list_price(entry, catalog) == Prices.NO_PRICE:
		return "it isn't for sale"
	if entry.is_heirloom():
		if seat_run.heirloom_ids().has(entry.definition_id):
			return "you own it already"
		var owner: int = ArmoryStock.unique_owner(run, catalog, entry.definition_id)
		if owner != CampaignFact.NO_SEAT:
			return "it is unique, and seat %d owns it" % [owner]
		return ""
	if seat_run.items.has(entry.instance_id):
		return "the seat already holds %s" % [entry.instance_id]
	if usable_units(seat_run, catalog.item(entry.definition_id), catalog).is_empty():
		return "no unit can use it"
	return ""


static func _gold_problem(seat_run: SeatRun, needed: int) -> String:
	if needed <= seat_run.gold:
		return ""
	return "not enough gold (it costs %d, you have %d)" % [needed, seat_run.gold]


static func _bought(seat: int, entry: ArmoryStock.Entry, paid: int) -> CampaignFact:
	var bought: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.ITEM_BOUGHT, seat, entry.instance_id
	)
	bought.definition_id = entry.definition_id
	bought.amount = paid
	return bought


# Takes the item in unit_id's slot for definition out of the roster for its trade-in value, which
# the purchase's cost already counts: ITEM_TRADED_IN.
static func _trade_in(
		run: CampaignRunState,
		seat: int,
		unit_id: String,
		definition: ItemDefinition,
		catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var held: ItemInstance = replaced_item(seat_run, unit_id, definition)
	var value: int = trade_in_value(seat_run, unit_id, definition, catalog)
	ItemPlacement.put_item(seat_run.unit(unit_id), ItemPlacement.slot_for(definition), "")
	seat_run.items.erase(held.instance_id)
	var traded: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.ITEM_TRADED_IN, seat, held.instance_id
	)
	traded.definition_id = held.definition_id
	traded.amount = value
	run.record(traded)


# In co-op, a bought unique heirloom's slot is offered again with another of its tier, for sale;
# with none left it stays sold (game-vision.md, Co-op ownership). Rolling it records no fact, as
# rolling the stock records none.
static func _restock_unique(
		run: CampaignRunState,
		stock: ArmoryStock,
		entry: ArmoryStock.Entry,
		catalog: EffectCatalog.Index,
		stream: RngStream
) -> void:
	var heirloom: HeirloomDefinition = catalog.heirloom(entry.definition_id)
	if (
			run.seat_numbers().size() < 2 or stream == null or heirloom == null
			or not heirloom.has_effect_tag(EffectDefinition.Tag.UNIQUE)
	):
		return
	var replacement: String = ArmoryStock.replacement(
			stream, run, catalog, heirloom.tier, stock.heirloom_ids()
	)
	if replacement.is_empty():
		return
	entry.definition_id = replacement
	entry.buyer = ArmoryStock.Entry.NOT_SOLD
