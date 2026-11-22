# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_model.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name GuildhallModel
extends RefCounted
## What the Guildhall's screens show, read from the run: a rune's name and text, prices and
## refusals as a card shows them, and the names of the items in a hand-over. Prices and refusals
## come from [Guildhall]'s rules, never worked out here; in co-op a refusal names the teammate it
## is about. Presentation only; static, never instantiated.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The name of each hand-over place on its button, by [enum Guildhall.HandOver].
const PLACE_NAMES: Dictionary[int, String] = {
	Guildhall.HandOver.RECRUIT: "Recruit",
	Guildhall.HandOver.CONVOY: "Convoy",
	Guildhall.HandOver.SCRAP: "Scrap",
}


## The rune [param rune_id]'s name; its id when [param catalog] lacks it.
static func rune_name(rune_id: String, catalog: EffectCatalog.Index) -> String:
	var rune: RuneDefinition = catalog.rune(rune_id)
	return rune_id if rune == null else rune.display_name


## The rune [param rune_id]'s text, one line per effect; "Not in the catalog" when it is missing.
static func rune_details(rune_id: String, catalog: EffectCatalog.Index) -> String:
	var rune: RuneDefinition = catalog.rune(rune_id)
	if rune == null:
		return "Not in the catalog"
	return "\n".join(rune.describe())


## [param paid] gold as a card shows it: [code]32 gold (40 listed)[/code] when a discount changed
## it from [param listed], else [code]40 gold[/code]; [code]Free[/code] for 0.
static func price_text(paid: int, listed: float) -> String:
	if paid == 0:
		return "Free"
	var listed_gold: int = ValueBreakdown.round_to_int(listed, ValueBreakdown.Rounding.HALF_UP)
	if paid != listed_gold:
		return "%d gold (%d listed)" % [paid, listed_gold]
	return "%d gold" % [paid]


## Why seat [param seat] can't buy stock entry [param index] of [param run], as its card says it
## ([method Guildhall.entry_problem]): an entry a teammate bought reads "bought by" them, and in
## co-op every seat the rules name reads as its player. Empty when it can be bought.
static func entry_refusal(
		run: CampaignRunState, seat: int, index: int, catalog: EffectCatalog.Index
) -> String:
	var buyer: String = bought_by(run, seat, index)
	if not buyer.is_empty():
		return buyer
	var problem: String = Guildhall.entry_problem(run, seat, index, catalog)
	return CampaignLink.name_seats(problem) if run.seat_numbers().size() > 1 else problem


## "bought by Player 2" when a teammate of seat [param seat] bought stock entry [param index] of
## [param run]; empty when nobody did, the seat itself did, or there is no such entry.
static func bought_by(run: CampaignRunState, seat: int, index: int) -> String:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	if stock == null or index < 0 or index >= stock.entries.size():
		return ""
	var entry: GuildhallStock.Entry = stock.entries[index]
	if not entry.is_sold() or entry.buyer == seat:
		return ""
	return "bought by %s" % [CampaignLink.seat_name(entry.buyer)]


## The price line of stock entry [param index] for seat [param seat] of [param run]
## ([method price_text]); empty for no such entry.
static func entry_price_text(
		run: CampaignRunState, seat: int, index: int, catalog: EffectCatalog.Index
) -> String:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	var seat_run: SeatRun = run.seat_run(seat)
	if stock == null or seat_run == null or index < 0 or index >= stock.entries.size():
		return ""
	var entry: GuildhallStock.Entry = stock.entries[index]
	if entry.is_recruit():
		var prefix_id: String = entry.recruit.unit.prefix_id
		return price_text(
				Guildhall.recruit_price(seat_run, prefix_id, catalog),
				Guildhall.unit_value(prefix_id, catalog)
		)
	return price_text(Guildhall.rune_price(seat_run, catalog), float(Prices.RUNE_PRICE))


## The name of the item [param item_id] in a hand-over, read from [param seat_run]'s items or
## [param joining]'s, with whose it is: [code]Iron Sword (Archer's)[/code].
static func hand_over_item_name(
		item_id: String,
		seat_run: SeatRun,
		joining: RecruitOffer,
		owner_name: String,
		catalog: EffectCatalog.Index
) -> String:
	var item: ItemInstance = joining.items.get(item_id, seat_run.items.get(item_id, null))
	if item == null:
		return item_id
	var item_name: String = ArmoryModel.held_name(item, catalog)
	if joining.items.has(item_id):
		return "%s (the recruit's own)" % [item_name]
	return "%s (%s's)" % [item_name, owner_name]
