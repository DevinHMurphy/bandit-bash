# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     armory_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Armory for tests/campaign/run_all.gd, on real runs from the real catalog: the stock's counts
## and odds over many seeds (3 / 2 / 1 / 2 items at 50 / 35 / 15, weapons the army wields, a pool
## heirloom at 50 / 33 / 17 and a Shop one), Merchant's Ledger, the empty-pool fallbacks; prices
## with and without Membership Seal; buying with a trade-in (a modified item worth more, a trade-in
## worth more than the price) or to the convoy; each refusal; a quit and Continue before and after
## buying; co-op's shared stock, first purchase wins, the unique heirloom's restock and gifting;
## and the purchase sounds, each once.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const CUES_PATH: String = "res://data/audio/maps/campaign_facts.tres"
const RUN_SEED: int = 4242

# Stocks rolled for the odds, and how far a share may stray from the rule's.
# Units: stocks; percentage points.
const ODDS_ROLLS: int = 3000
const ODDS_TOLERANCE: float = 2.5

const MERCHANTS_LEDGER: String = "merchants_ledger"
const MEMBERSHIP_SEAL: String = "membership_seal"
const BROTHERS_IN_ARMS: String = "brothers_in_arms"

# Gold a staged seat holds, enough for anything stocked. Units: gold.
const RICH: int = 1000

# A modification staged on a held weapon: +2 damage, 2 points at a weapon's step of 20 gold.
const MOD_DAMAGE: float = 2.0

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _played: Array[StringName] = []
var _session: CampaignSession = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_check("armory: the catalog loads", _catalog != null)
	if _catalog == null:
		return
	_test_counts_and_odds()
	_test_ledger()
	_test_empty_pools()
	_test_open_and_resume()
	_test_prices()
	_test_trade_in()
	_test_refusals()
	_test_coop()
	_test_sounds()


func _test_counts_and_odds() -> void:
	var run_state: CampaignRunState = Fixture.session(RUN_SEED).run
	var usable: PackedStringArray = ArmoryStock.usable_weapon_types(run_state, _catalog)
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var wrong: PackedStringArray = []
	var rarities: Dictionary[String, Dictionary] = {}
	var tiers: Dictionary[String, int] = {}
	var shop_slots: int = 0
	for roll_seed: int in ODDS_ROLLS:
		var stock: ArmoryStock = ArmoryStock.roll(
				RngStream.new(roll_seed), run_state, _catalog, ids
		)
		for category: String in ArmoryStock.ITEM_CATEGORIES:
			var indexes: PackedInt32Array = stock.indexes_of(category)
			if indexes.size() != ArmoryStock.ITEM_COUNTS[category]:
				wrong.append("%d %s" % [indexes.size(), category])
			var seen: Dictionary[String, bool] = {}
			for index: int in indexes:
				var entry: ArmoryStock.Entry = stock.entries[index]
				var item: ItemDefinition = _catalog.item(entry.definition_id)
				if item == null or seen.has(entry.definition_id) or entry.instance_id.is_empty():
					wrong.append("entry %s" % [entry.definition_id])
					continue
				seen[entry.definition_id] = true
				if not ItemPools.DRAWN_RARITIES.has(item.rarity):
					wrong.append("%s is %s" % [item.id, item.rarity])
				var weapon: WeaponDefinition = item as WeaponDefinition
				if weapon != null and not usable.has(weapon.weapon_type):
					wrong.append("%s isn't wielded" % [item.id])
			if not indexes.is_empty():
				var first: ItemDefinition = _catalog.item(stock.entries[indexes[0]].definition_id)
				if not rarities.has(category):
					rarities[category] = {}
				rarities[category][first.rarity] = rarities[category].get(first.rarity, 0) + 1
		var heirlooms: PackedInt32Array = stock.indexes_of(ArmoryStock.CATEGORY_HEIRLOOM)
		if heirlooms.size() != ArmoryStock.POOL_HEIRLOOMS + ArmoryStock.SHOP_HEIRLOOMS:
			wrong.append("%d heirlooms" % [heirlooms.size()])
		for index: int in heirlooms:
			var entry: ArmoryStock.Entry = stock.entries[index]
			var heirloom: HeirloomDefinition = _catalog.heirloom(entry.definition_id)
			if heirloom == null:
				wrong.append("heirloom %s" % [entry.definition_id])
			elif entry.is_shop_slot:
				shop_slots += 1
				if heirloom.tier != ContentIds.HEIRLOOM_SHOP:
					wrong.append("shop slot %s" % [heirloom.tier])
			else:
				tiers[heirloom.tier] = tiers.get(heirloom.tier, 0) + 1
	_check("stock: 3 weapons, 2 equipment, 1 trinket, 2 consumables, 2 heirlooms every roll", (
			wrong.is_empty() and shop_slots == ODDS_ROLLS
	), ", ".join(wrong.slice(0, 5)))
	var shares: PackedStringArray = []
	var is_close: bool = true
	var measured: int = 0
	for category: String in rarities:
		if not _has_every_rarity(category, usable):
			shares.append("%s skipped (a rarity has no item)" % [category])
			continue
		measured += 1
		for index: int in ItemPools.DRAWN_RARITIES.size():
			var rarity: ItemDefinition.Rarity = ItemPools.DRAWN_RARITIES[index]
			var share: float = 100.0 * (rarities[category].get(rarity, 0) as int) / ODDS_ROLLS
			shares.append("%s %d %.1f" % [category, rarity, share])
			is_close = (
					is_close
					and absf(share - ArmoryStock.RARITY_WEIGHTS[index]) <= ODDS_TOLERANCE
			)
	_check("odds: over %d seeds items are Common 50 / Uncommon 35 / Rare 15" % [ODDS_ROLLS], (
			is_close and measured > 0
	), ", ".join(shares))
	var tier_shares: PackedStringArray = []
	var tiers_close: bool = true
	for index: int in HeirloomDraw.TIERS.size():
		var tier: String = HeirloomDraw.TIERS[index]
		var share: float = 100.0 * tiers.get(tier, 0) / ODDS_ROLLS
		tier_shares.append("%s %.1f" % [tier, share])
		tiers_close = (
				tiers_close and absf(share - HeirloomDraw.TIER_WEIGHTS[index]) <= ODDS_TOLERANCE
		)
	_check("odds: the pool heirloom is Common 50 / Uncommon 33 / Rare 17; the other Shop tier", (
			tiers_close
	), ", ".join(tier_shares))
	var twin: ArmoryStock = ArmoryStock.roll(RngStream.new(7), run_state, _catalog, ids)
	var again: ArmoryStock = ArmoryStock.roll(RngStream.new(7), run_state, _catalog, ids)
	_check("stock: the same stream state rolls the same stock", (
			_definitions(twin) == _definitions(again)
	))


func _test_ledger() -> void:
	var run_state: CampaignRunState = Fixture.session(RUN_SEED).run
	var seat_run: SeatRun = run_state.seat_run(0)
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var plain: int = _item_count(ArmoryStock.roll(RngStream.new(3), run_state, _catalog, ids))
	seat_run.add_heirloom(MERCHANTS_LEDGER)
	var one: int = _item_count(ArmoryStock.roll(RngStream.new(3), run_state, _catalog, ids))
	seat_run.add_heirloom(MERCHANTS_LEDGER)
	var two: int = _item_count(ArmoryStock.roll(RngStream.new(3), run_state, _catalog, ids))
	_check("ledger: Merchant's Ledger stocks one more item per copy; no more heirlooms", (
			plain == 8 and one == 9 and two == 10
			and ArmoryStock.extra_items(run_state, _catalog) == 2
	), "%d / %d / %d" % [plain, one, two])
	var categories: Dictionary[String, int] = {}
	for roll_seed: int in ODDS_ROLLS:
		var stock: ArmoryStock = ArmoryStock.roll(
				RngStream.new(roll_seed), run_state, _catalog, ids
		)
		for category: String in ArmoryStock.ITEM_CATEGORIES:
			var extra: int = (
					stock.indexes_of(category).size() - ArmoryStock.ITEM_COUNTS[category]
			)
			categories[category] = categories.get(category, 0) + extra
	var total: int = 0
	for category: String in categories:
		total += categories[category]
	var weapons: int = categories.get(ArmoryStock.CATEGORY_WEAPON, 0)
	var weapon_share: float = 100.0 * weapons / maxi(total, 1)
	# Weapons are 3 of the 8 weights: 37.5%.
	_check("ledger: an extra item's category is rolled by the stock's own ratio", (
			total == ODDS_ROLLS * 2 and absf(weapon_share - 37.5) <= ODDS_TOLERANCE
	), "%s, weapons %.1f%%" % [categories, weapon_share])


func _test_empty_pools() -> void:
	var run_state: CampaignRunState = Fixture.session(RUN_SEED).run
	var seat_run: SeatRun = run_state.seat_run(0)
	for heirloom_id: String in HeirloomDraw.candidates(
			seat_run, _catalog, PackedStringArray([ContentIds.HEIRLOOM_SHOP]), false
	):
		seat_run.add_heirloom(heirloom_id)
	var stock: ArmoryStock = ArmoryStock.roll(
			RngStream.new(5), run_state, _catalog, InstanceIdAllocator.new()
	)
	var shop_entry: ArmoryStock.Entry = null
	for index: int in stock.indexes_of(ArmoryStock.CATEGORY_HEIRLOOM):
		if stock.entries[index].is_shop_slot:
			shop_entry = stock.entries[index]
	var shop_tier: String = (
			"" if shop_entry == null else _catalog.heirloom(shop_entry.definition_id).tier
	)
	_check("empty pool: with every Shop heirloom owned, its slot rolls from the main pool", (
			HeirloomDraw.TIERS.has(shop_tier)
			and not seat_run.heirloom_ids().has(shop_entry.definition_id)
	), shop_tier)
	for heirloom_id: String in HeirloomDraw.candidates(
			seat_run, _catalog, HeirloomDraw.TIERS, false
	):
		seat_run.add_heirloom(heirloom_id)
	var bare: ArmoryStock = ArmoryStock.roll(
			RngStream.new(5), run_state, _catalog, InstanceIdAllocator.new()
	)
	# Owning every Shop heirloom includes Merchant's Ledger: one more item.
	_check("empty pool: with every heirloom owned, none is stocked; the items still are", (
			bare.indexes_of(ArmoryStock.CATEGORY_HEIRLOOM).is_empty() and _item_count(bare) == 9
	), "%s, %d items" % [bare.heirloom_ids(), _item_count(bare)])


func _test_open_and_resume() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var outside: CampaignBatch = session.submit(OpenArmoryCommand.for_session(session, _catalog))
	_check("open: refused outside an Armory, changing nothing", (
			outside.is_rejected() and session.run.flow.shop_stock.is_empty()
	), outside.rejected_reason)
	_check("open: the map has an Armory route", Fixture.enter(session.run, _armory()))
	var opened: CampaignBatch = session.submit(OpenArmoryCommand.for_session(session, _catalog))
	var stock: ArmoryStock = ArmoryStock.pending(session.run)
	_check("open: the stock is rolled and saved before it shows, recording no fact", (
			not opened.is_rejected() and opened.facts.is_empty() and stock != null
			and not stock.entries.is_empty()
	), opened.rejected_reason)
	var again: CampaignBatch = session.submit(OpenArmoryCommand.for_session(session, _catalog))
	_check("open: a second open is refused, so the stock never rolls twice", again.is_rejected())
	var resumed: CampaignRunState = Fixture.through_json(session.run)
	var resumed_stock: ArmoryStock = ArmoryStock.pending(resumed) if resumed != null else null
	_check("resume (before buying): a quit and Continue shows the same stock", (
			resumed_stock != null
			and JSON.stringify(resumed_stock.capture()) == JSON.stringify(stock.capture())
	))
	session.run = resumed
	var reopened: CampaignBatch = session.submit(OpenArmoryCommand.for_session(session, _catalog))
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.gold = RICH
	var index: int = _first_affordable_item(session.run, 0)
	var unit_id: String = Armory.usable_units(
			seat_run, _catalog.item(stock.entries[index].definition_id), _catalog
	)[0]
	var bought: CampaignBatch = session.submit(_buy(session, 0, index, unit_id, true))
	var after: CampaignRunState = Fixture.through_json(session.run)
	var after_stock: ArmoryStock = ArmoryStock.pending(after) if after != null else null
	_check("resume (after buying): the entry stays sold, the gold and the item stay", (
			reopened.is_rejected()
			and not bought.is_rejected()
			and after_stock != null and after_stock.entries[index].buyer == 0
			and after.seat_run(0).gold == seat_run.gold
			and after.seat_run(0).items.has(stock.entries[index].instance_id)
	), bought.rejected_reason)
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("leave: always allowed, and clears the stock", (
			not left.is_rejected() and session.run.is_on_map()
			and not session.run.flow.shop_stock.has(ArmoryStock.OFFER_KEY)
	), left.rejected_reason)


func _test_prices() -> void:
	var session: CampaignSession = _at_armory()
	var seat_run: SeatRun = session.run.seat_run(0)
	var weapon: ArmoryStock.Entry = _item_entry(ItemDefinition.Rarity.COMMON, WeaponDefinition)
	var equipment: ArmoryStock.Entry = _item_entry(
			ItemDefinition.Rarity.UNCOMMON, EquipmentDefinition
	)
	var pool: ArmoryStock.Entry = _heirloom_entry(ContentIds.HEIRLOOM_RARE, false)
	var shop: ArmoryStock.Entry = _heirloom_entry(ContentIds.HEIRLOOM_SHOP, true)
	var listed: PackedInt32Array = [
		Armory.price(seat_run, weapon, _catalog),
		Armory.price(seat_run, equipment, _catalog),
		Armory.price(seat_run, pool, _catalog),
		Armory.price(seat_run, shop, _catalog),
	]
	_check("prices: list prices without a Seal (weapon 40, equipment 100, Rare 250, Shop 150)", (
			listed == PackedInt32Array([40, 100, 250, 150])
	), str(listed))
	seat_run.add_heirloom(MEMBERSHIP_SEAL)
	var sealed: PackedInt32Array = [
		Armory.price(seat_run, weapon, _catalog),
		Armory.price(seat_run, equipment, _catalog),
		Armory.price(seat_run, pool, _catalog),
		Armory.price(seat_run, shop, _catalog),
	]
	_check("prices: Membership Seal takes 20% off items and heirlooms alike", (
			sealed == PackedInt32Array([32, 80, 200, 120])
	), str(sealed))
	var trinket: ArmoryStock.Entry = _item_entry(ItemDefinition.Rarity.UNCOMMON, TrinketDefinition)
	var rounded: int = Armory.price(seat_run, trinket, _catalog)
	_check("prices: the Seal's price is whole gold (an Uncommon trinket, 50, costs 40)", (
			rounded == 40
	), str(rounded))


func _test_trade_in() -> void:
	var session: CampaignSession = _at_armory()
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.gold = RICH
	var unit: UnitInstance = seat_run.army[0]
	var common: WeaponDefinition = _wieldable(unit, ItemDefinition.Rarity.COMMON)
	var held: ItemInstance = _hold(session, unit, common)
	held.stat_deltas.append(
			ItemInstance.StatDelta.new(DamageStage.Key.ATTACK, MOD_DAMAGE, "test", "Test")
	)
	var plain_scrap: int = ItemPlacement.scrap_value(common, seat_run, _catalog)
	var modified_scrap: int = ItemPlacement.held_scrap_value(held, _catalog, seat_run)
	var stocked: ArmoryStock.Entry = _new_item(session, common.id)
	_stage(session, [stocked])
	var value: int = Armory.trade_in_value(seat_run, unit.instance_id, common, _catalog)
	var expected_cost: int = Armory.price(seat_run, stocked, _catalog) - modified_scrap
	var gold_before: int = seat_run.gold
	var bought: CampaignBatch = session.submit(_buy(session, 0, 0, unit.instance_id, true))
	var kinds: Array[CampaignFact.Kind] = Fixture.kinds(bought)
	_check("trade-in: a modified item trades in for its own, higher scrap value", (
			modified_scrap > plain_scrap and value == modified_scrap
	), "%d vs %d (%d)" % [modified_scrap, plain_scrap, value])
	_check("trade-in: the value comes off the price; ITEM_TRADED_IN, ITEM_BOUGHT, then the gain", (
			not bought.is_rejected()
			and kinds == [
				CampaignFact.Kind.ITEM_TRADED_IN, CampaignFact.Kind.ITEM_BOUGHT,
				CampaignFact.Kind.GAINED, CampaignFact.Kind.ITEM_EQUIPPED,
			]
			and bought.facts[0].amount == modified_scrap
			and bought.facts[1].amount == expected_cost
			and seat_run.gold == gold_before - expected_cost
			and (bought.facts[2].flags & CampaignFact.FLAG_BOUGHT) != 0
			and unit.weapon_id == stocked.instance_id
			and not seat_run.items.has(held.instance_id)
			and seat_run.convoy.is_empty()
			and Fixture.is_whole(seat_run)
	), "%s %s" % [bought.rejected_reason, kinds])
	var keeper: CampaignSession = _at_armory()
	var keeper_run: SeatRun = keeper.run.seat_run(0)
	keeper_run.gold = RICH
	var keeper_unit: UnitInstance = keeper_run.army[0]
	var old: ItemInstance = _hold(keeper, keeper_unit, common)
	var kept_entry: ArmoryStock.Entry = _new_item(keeper, common.id)
	_stage(keeper, [kept_entry])
	var keep_gold: int = keeper_run.gold
	var kept: CampaignBatch = keeper.submit(_buy(keeper, 0, 0, keeper_unit.instance_id, false))
	_check("convoy: the replaced item goes to the convoy and the full price is paid", (
			not kept.is_rejected()
			and Fixture.kinds(kept) == [
				CampaignFact.Kind.ITEM_BOUGHT, CampaignFact.Kind.GAINED,
				CampaignFact.Kind.ITEM_EQUIPPED, CampaignFact.Kind.ITEM_EQUIPPED,
			]
			and keeper_run.convoy.has(old.instance_id)
			and keeper_run.gold == keep_gold - Armory.price(keeper_run, kept_entry, _catalog)
			and Fixture.is_whole(keeper_run)
	), "%s %s" % [kept.rejected_reason, Fixture.kinds(kept)])
	var rich_trade: CampaignSession = _at_armory()
	var rich_run: SeatRun = rich_trade.run.seat_run(0)
	rich_run.add_heirloom(MEMBERSHIP_SEAL)
	rich_run.gold = 0
	var rich_unit: UnitInstance = rich_run.army[0]
	var rare: WeaponDefinition = _wieldable(rich_unit, ItemDefinition.Rarity.RARE)
	_hold(rich_trade, rich_unit, rare)
	var cheap: ArmoryStock.Entry = _new_item(rich_trade, common.id)
	_stage(rich_trade, [cheap])
	var gain: int = -Armory.cost(rich_run, cheap, rich_unit.instance_id, true, _catalog)
	var traded: CampaignBatch = rich_trade.submit(
			_buy(rich_trade, 0, 0, rich_unit.instance_id, true)
	)
	_check("trade-in: worth more than the price, the seat gains the difference (0 gold needed)", (
			rare != null and not traded.is_rejected() and gain > 0 and rich_run.gold == gain
			and traded.facts[1].amount == -gain
	), "%s, gained %d" % [traded.rejected_reason, rich_run.gold])


func _test_refusals() -> void:
	var session: CampaignSession = _at_armory()
	var seat_run: SeatRun = session.run.seat_run(0)
	var unit: UnitInstance = seat_run.army[0]
	var common: WeaponDefinition = _wieldable(unit, ItemDefinition.Rarity.COMMON)
	var unwieldable: WeaponDefinition = _unwieldable(session.run)
	var other: UnitInstance = _non_wielder(seat_run, common)
	var trinket_entry: ArmoryStock.Entry = _new_item(
			session, _item_entry(ItemDefinition.Rarity.COMMON, TrinketDefinition).definition_id
	)
	var heirloom: ArmoryStock.Entry = _heirloom_entry(ContentIds.HEIRLOOM_COMMON, false)
	_stage(session, [
		_new_item(session, common.id),
		_new_item(session, unwieldable.id if unwieldable != null else common.id),
		trinket_entry,
		heirloom,
	])
	seat_run.gold = 0
	var poor: String = Armory.entry_problem(session.run, 0, 0, _catalog)
	var poor_deal: CampaignBatch = session.submit(_buy(session, 0, 0, unit.instance_id, false))
	_check("refused: too little gold says so; the deal names the cost and the gold", (
			poor.contains("too little gold")
			and poor_deal.is_rejected() and poor_deal.rejected_reason.contains("not enough gold")
			and poor_deal.rejected_reason.contains("costs 40")
	), "%s / %s" % [poor, poor_deal.rejected_reason])
	seat_run.gold = RICH
	var useless: String = Armory.entry_problem(session.run, 0, 1, _catalog)
	_check("refused: a weapon no unit wields says no unit can use it", (
			unwieldable != null and useless.contains("no unit")
	), useless)
	var wrong_unit: CampaignBatch = session.submit(
			_buy(session, 0, 0, other.instance_id if other != null else "", false)
	)
	_check("refused: onto a unit that can't wield it, changing nothing", (
			other != null and wrong_unit.is_rejected()
			and wrong_unit.rejected_reason.contains("wield")
			and seat_run.gold == RICH
	), wrong_unit.rejected_reason)
	var empty_trade: CampaignBatch = session.submit(
			_buy(session, 0, 2, _empty_pouch(seat_run), true)
	)
	_check("refused: trading in an empty slot", (
			empty_trade.is_rejected() and empty_trade.rejected_reason.contains("empty")
	), empty_trade.rejected_reason)
	_hold(session, unit, common)
	while not ItemPlacement.is_convoy_full(seat_run, _catalog):
		Fixture.add_to_convoy(seat_run, common.id, session.ids)
	var full: CampaignBatch = session.submit(_buy(session, 0, 0, unit.instance_id, false))
	var traded: CampaignBatch = session.submit(_buy(session, 0, 0, unit.instance_id, true))
	_check("refused: the convoy full, the replaced item can only be traded in (then accepted)", (
			full.is_rejected() and full.rejected_reason.contains("convoy is full")
			and not traded.is_rejected()
	), "%s / %s" % [full.rejected_reason, traded.rejected_reason])
	var twice: CampaignBatch = session.submit(_buy(session, 0, 0, unit.instance_id, true))
	_check("refused: an entry already bought", (
			twice.is_rejected() and twice.rejected_reason.contains("bought it already")
	), twice.rejected_reason)
	seat_run.add_heirloom(heirloom.definition_id)
	var owned: String = Armory.entry_problem(session.run, 0, 3, _catalog)
	_check("refused: an heirloom the seat owns", owned.contains("own it already"), owned)
	var onto_unit: CampaignBatch = session.submit(_buy(session, 0, 3, unit.instance_id, false))
	_check("refused: an heirloom onto a unit", onto_unit.is_rejected(), onto_unit.rejected_reason)
	var map: CampaignSession = Fixture.session(RUN_SEED)
	var outside: String = Armory.entry_problem(map.run, 0, 0, _catalog)
	_check("refused: outside an Armory", outside.contains("isn't inside an Armory"), outside)


func _test_coop() -> void:
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	_check("co-op: the map has an Armory route", Fixture.enter(pair.run, _armory()))
	pair.submit(OpenArmoryCommand.for_session(pair, _catalog))
	var stock: ArmoryStock = ArmoryStock.pending(pair.run)
	var counts: PackedInt32Array = []
	for category: String in ArmoryStock.ITEM_CATEGORIES:
		counts.append(stock.indexes_of(category).size())
	counts.append(stock.indexes_of(ArmoryStock.CATEGORY_HEIRLOOM).size())
	_check("co-op: one shared stock, +1 of each category per extra player (4 / 3 / 2 / 3 / 3)", (
			counts == PackedInt32Array([4, 3, 2, 3, 3])
	), str(counts))
	for seat: int in pair.run.seat_numbers():
		pair.run.seat_run(seat).gold = RICH
	var index: int = _first_affordable_item(pair.run, 0)
	var definition: ItemDefinition = _catalog.item(stock.entries[index].definition_id)
	var first: CampaignBatch = pair.submit(_buy(
			pair, 0, index, Armory.usable_units(pair.run.seat_run(0), definition, _catalog)[0],
			false
	))
	var second: CampaignBatch = pair.submit(_buy(
			pair, 1, index, Armory.usable_units(pair.run.seat_run(1), definition, _catalog)[0],
			false
	))
	_check("co-op: the first confirmed purchase gets the item; the second is refused for free", (
			not first.is_rejected() and second.is_rejected()
			and second.rejected_reason.contains("sold")
			and pair.run.seat_run(1).gold == RICH
	), "%s / %s" % [first.rejected_reason, second.rejected_reason])
	var unique: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(unique.run, _armory())
	for seat: int in unique.run.seat_numbers():
		unique.run.seat_run(seat).gold = RICH
	var brothers: HeirloomDefinition = _catalog.heirloom(BROTHERS_IN_ARMS)
	var staged: ArmoryStock.Entry = ArmoryStock.Entry.new(
			ArmoryStock.CATEGORY_HEIRLOOM, BROTHERS_IN_ARMS, "", false
	)
	_stage(unique, [staged])
	var claimed: CampaignBatch = unique.submit(_buy(unique, 0, 0, "", false))
	var restocked: ArmoryStock.Entry = ArmoryStock.pending(unique.run).entries[0]
	var replacement: HeirloomDefinition = _catalog.heirloom(restocked.definition_id)
	_check("co-op: a unique heirloom goes to the first to claim it; its slot restocks", (
			brothers != null and brothers.has_effect_tag(EffectDefinition.Tag.UNIQUE)
			and not claimed.is_rejected()
			and unique.run.seat_run(0).heirloom_ids().has(BROTHERS_IN_ARMS)
			and restocked.definition_id != BROTHERS_IN_ARMS and not restocked.is_sold()
			and replacement != null and replacement.tier == brothers.tier
	), "%s -> %s" % [claimed.rejected_reason, restocked.definition_id])
	var other_buys: CampaignBatch = unique.submit(_buy(unique, 1, 0, "", false))
	_check("co-op: the other seat can buy the replacement", (
			not other_buys.is_rejected()
	), other_buys.rejected_reason)
	var leaked: int = 0
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	for roll_seed: int in ODDS_ROLLS:
		var rolled: ArmoryStock = ArmoryStock.roll(
				RngStream.new(roll_seed), unique.run, _catalog, ids
		)
		if rolled.heirloom_ids().has(BROTHERS_IN_ARMS):
			leaked += 1
	_check("co-op: a unique heirloom a seat owns is never stocked", leaked == 0, str(leaked))
	var gifting: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(gifting.run, _armory())
	var giver: SeatRun = gifting.run.seat_run(0)
	var gift: String = Fixture.add_to_convoy(giver, definition.id, gifting.ids)
	var gave: CampaignBatch = gifting.submit(GiftItemCommand.new(0, gift, 1))
	var receiver: SeatRun = gifting.run.seat_run(1)
	while not ItemPlacement.is_convoy_full(receiver, _catalog):
		Fixture.add_to_convoy(receiver, definition.id, gifting.ids)
	var spare: String = Fixture.add_to_convoy(giver, definition.id, gifting.ids)
	var refused: CampaignBatch = gifting.submit(GiftItemCommand.new(0, spare, 1))
	_check("co-op: gifting convoy to convoy works at the Armory, refused into a full convoy", (
			not gave.is_rejected() and receiver.items.has(gift)
			and Fixture.kinds(gave) == [CampaignFact.Kind.ITEM_GIFTED]
			and refused.is_rejected() and refused.rejected_reason.contains("full")
	), "%s / %s" % [gave.rejected_reason, refused.rejected_reason])


func _test_sounds() -> void:
	var session: CampaignSession = _listen(_at_armory())
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.gold = RICH
	var unit: UnitInstance = seat_run.army[0]
	var common: WeaponDefinition = _wieldable(unit, ItemDefinition.Rarity.COMMON)
	_hold(session, unit, common)
	_stage(session, [
		_new_item(session, common.id),
		_new_item(session, common.id),
		_heirloom_entry(ContentIds.HEIRLOOM_COMMON, false),
	])
	_step(session, _buy(session, 0, 0, unit.instance_id, false))
	_check("sounds: a purchase sounds item_buy once, never item_obtained", (
			_played == [&"item_buy"]
	), str(_played))
	_step(session, _buy(session, 0, 1, unit.instance_id, true))
	_check("sounds: a purchase with a trade-in sounds item_sell, then item_buy, once each", (
			_played == [&"item_sell", &"item_buy"]
	), str(_played))
	_step(session, _buy(session, 0, 2, "", false))
	_check("sounds: an heirloom bought sounds item_buy once", (
			_played == [&"item_buy"]
	), str(_played))


# A solo run inside an Armory with its stock rolled.
func _at_armory() -> CampaignSession:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(session.run, _armory())
	session.submit(OpenArmoryCommand.for_session(session, _catalog))
	return session


# Replaces session's stock with entries.
func _stage(session: CampaignSession, entries: Array) -> void:
	var stock: ArmoryStock = ArmoryStock.new()
	for entry: ArmoryStock.Entry in entries:
		stock.entries.append(entry)
	stock.store(session.run)


func _buy(
		session: CampaignSession, seat: int, index: int, unit_id: String, trade_in: bool
) -> ArmoryPurchaseCommand:
	return ArmoryPurchaseCommand.for_session(session, seat, index, unit_id, trade_in, _catalog)


# A stock entry for a new instance of definition_id.
func _new_item(session: CampaignSession, definition_id: String) -> ArmoryStock.Entry:
	return ArmoryStock.Entry.new(
			_category_of(_catalog.item(definition_id)), definition_id,
			session.ids.next_item_id(definition_id), false
	)


# A stock entry for the first item of rarity and script in the catalog (no instance minted).
func _item_entry(rarity: ItemDefinition.Rarity, script: Variant) -> ArmoryStock.Entry:
	var kinds: Array[EffectCatalog.Kind] = [
		EffectCatalog.Kind.WEAPON, EffectCatalog.Kind.EQUIPMENT,
		EffectCatalog.Kind.TRINKET, EffectCatalog.Kind.CONSUMABLE,
	]
	for resource: ItemDefinition in ItemPools.items_of(_catalog, kinds):
		if resource.rarity == rarity and is_instance_of(resource, script):
			return ArmoryStock.Entry.new(_category_of(resource), resource.id, "item:test", false)
	return null


func _heirloom_entry(tier: String, shop_slot: bool) -> ArmoryStock.Entry:
	var heirloom_id: String = HeirloomDraw.candidates(
			Fixture.session(RUN_SEED).run.seat_run(0), _catalog, PackedStringArray([tier]), false
	)[0]
	return ArmoryStock.Entry.new(ArmoryStock.CATEGORY_HEIRLOOM, heirloom_id, "", shop_slot)


func _category_of(definition: ItemDefinition) -> String:
	if definition is WeaponDefinition:
		return ArmoryStock.CATEGORY_WEAPON
	if definition is EquipmentDefinition:
		return ArmoryStock.CATEGORY_EQUIPMENT
	if definition is TrinketDefinition:
		return ArmoryStock.CATEGORY_TRINKET
	return ArmoryStock.CATEGORY_CONSUMABLE


# Puts a new item of definition in unit's slot for it, dropping what was there from the roster.
func _hold(
		session: CampaignSession, unit: UnitInstance, definition: ItemDefinition
) -> ItemInstance:
	var seat_run: SeatRun = session.run.seat_run(0)
	var slot: Loadout.Slot = ItemPlacement.slot_for(definition)
	var previous: String = ItemPlacement.item_in(unit, slot)
	if not previous.is_empty():
		seat_run.items.erase(previous)
	var item_id: String = session.ids.next_item_id(definition.id)
	var item: ItemInstance = ItemInstance.new(item_id, definition.id)
	seat_run.items[item_id] = item
	ItemPlacement.put_item(unit, slot, item_id)
	return item


# A weapon of rarity unit can wield; null for none.
func _wieldable(unit: UnitInstance, rarity: ItemDefinition.Rarity) -> WeaponDefinition:
	var types: PackedStringArray = ItemPlacement.weapon_types_of(unit, _catalog)
	for resource: ItemDefinition in ItemPools.items_of(_catalog, _weapon_kind()):
		var weapon: WeaponDefinition = resource as WeaponDefinition
		if weapon != null and weapon.rarity == rarity and types.has(weapon.weapon_type):
			return weapon
	return null


# A sellable weapon of a type no unit of run wields; null for none.
func _unwieldable(run_state: CampaignRunState) -> WeaponDefinition:
	var usable: PackedStringArray = ArmoryStock.usable_weapon_types(run_state, _catalog)
	for resource: ItemDefinition in ItemPools.items_of(_catalog, _weapon_kind()):
		var weapon: WeaponDefinition = resource as WeaponDefinition
		if (
				weapon != null and Prices.is_sellable(weapon.rarity)
				and not usable.has(weapon.weapon_type)
		):
			return weapon
	return null


# A living unit of seat_run that can't wield definition; null for none.
func _non_wielder(seat_run: SeatRun, definition: WeaponDefinition) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		if not ItemPlacement.weapon_types_of(unit, _catalog).has(definition.weapon_type):
			return unit
	return null


# A living unit with an empty Pouch, emptying the first unit's when none has one.
func _empty_pouch(seat_run: SeatRun) -> String:
	for unit: UnitInstance in seat_run.army:
		if unit.pouch_id.is_empty():
			return unit.instance_id
	var unit: UnitInstance = seat_run.army[0]
	seat_run.items.erase(unit.pouch_id)
	unit.pouch_id = ""
	return unit.instance_id


# The first unsold item entry seat can buy outright.
func _first_affordable_item(run_state: CampaignRunState, seat: int) -> int:
	var stock: ArmoryStock = ArmoryStock.pending(run_state)
	for index: int in stock.entries.size():
		if stock.entries[index].is_heirloom():
			continue
		if Armory.entry_problem(run_state, seat, index, _catalog).is_empty():
			return index
	return -1


# Whether category's pool (weapons the army wields) has an item of every drawn rarity.
func _has_every_rarity(category: String, usable: PackedStringArray) -> bool:
	var kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
	match category:
		ArmoryStock.CATEGORY_EQUIPMENT:
			kinds = [EffectCatalog.Kind.EQUIPMENT]
		ArmoryStock.CATEGORY_TRINKET:
			kinds = [EffectCatalog.Kind.TRINKET]
		ArmoryStock.CATEGORY_CONSUMABLE:
			kinds = [EffectCatalog.Kind.CONSUMABLE]
	var pool: Array[ItemDefinition] = ItemPools.items_of(_catalog, kinds)
	var wanted: PackedStringArray = PackedStringArray()
	if category == ArmoryStock.CATEGORY_WEAPON:
		wanted = usable
	var none: Dictionary[String, bool] = {}
	for rarity: ItemDefinition.Rarity in ItemPools.DRAWN_RARITIES:
		if ItemPools.of_rarity(pool, rarity, none, wanted).is_empty():
			return false
	return true


func _weapon_kind() -> Array[EffectCatalog.Kind]:
	var kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
	return kinds


func _item_count(stock: ArmoryStock) -> int:
	var count: int = 0
	for entry: ArmoryStock.Entry in stock.entries:
		if not entry.is_heirloom():
			count += 1
	return count


func _definitions(stock: ArmoryStock) -> PackedStringArray:
	var found: PackedStringArray = []
	for entry: ArmoryStock.Entry in stock.entries:
		found.append(entry.definition_id)
	return found


func _armory() -> CampaignGraph.NodeType:
	return CampaignGraph.NodeType.ARMORY


# Binds a fresh listener on session's bus, everything already logged counted as played.
func _listen(session: CampaignSession) -> CampaignSession:
	_session = session
	session.played_seq = session.run.fact_log.size()
	var listener: FactCueListener = FactCueListener.new(
			load(CUES_PATH) as FactCueMap, _on_cue
	)
	listener.bind_campaign(session.bus, _node_type)
	session.set_meta(&"listener", listener)
	return session


# Submits command and plays its facts, keeping only the cues they sound.
func _step(session: CampaignSession, command: CampaignCommand) -> void:
	_played.clear()
	var batch: CampaignBatch = session.submit(command)
	if batch.is_rejected():
		_check("%s is accepted" % [command.get_label()], false, batch.rejected_reason)
	CampaignPlayback.play_pending(session)


func _node_type(node_id: int) -> int:
	var graph: CampaignGraph = _session.run.graph
	return graph.type_of(node_id) if graph.has_node_id(node_id) else -1


func _on_cue(cue_id: StringName) -> void:
	_played.append(cue_id)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
