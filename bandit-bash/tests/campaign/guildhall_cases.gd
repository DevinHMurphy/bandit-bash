# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Guildhall for tests/campaign/run_all.gd, on real runs from the real catalog: the stock (3
## recruits of different types and 2 different runes, Guild Charter's extra recruit), rolled and
## saved before it shows and the same after a quit and Continue; recruit and rune prices with and
## without Membership Seal; a recruit matching its preview at the army's average level; a full
## army's replacement with its hand-over and each hand-over refusal; Muster Roll's extra slot;
## runes into a free slot or discarding one; re-roll prices and their repeat rise, Tinker's Token's
## free re-roll; each refusal; co-op's shared stock, first purchase wins, per-seat re-rolls and
## gifting; and the purchase sounds, each once.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const CUES_PATH: String = "res://data/audio/maps/campaign_facts.tres"
const RUN_SEED: int = 4242

const GUILD_CHARTER: String = "guild_charter"
const MEMBERSHIP_SEAL: String = "membership_seal"
const TINKERS_TOKEN: String = "tinkers_token"
const MUSTER_ROLL: String = "muster_roll"

# Stocks rolled for the count and repeat checks. Units: stocks.
const STOCK_ROLLS: int = 300

# Gold a staged seat holds, enough for anything stocked. Units: gold.
const RICH: int = 1000

# Recruit prices by prefix tier, -2 to +2 (unit-roster.md: 40 × 0.5 / 0.75 / 1 / 1.3 / 1.8), and
# with Membership Seal's 80%, halves up. Units: gold.
const RECRUIT_PRICES: Dictionary[int, int] = {-2: 20, -1: 30, 0: 40, 1: 52, 2: 72}
const SEAL_RECRUIT_PRICES: Dictionary[int, int] = {-2: 16, -1: 24, 0: 32, 1: 42, 2: 58}

# A rune's price, and with Membership Seal. Units: gold.
const RUNE_PRICE: int = 30
const SEAL_RUNE_PRICE: int = 24

# Re-roll prices of an unprefixed unit: 40 / 3 = 13.33, +50% of that per paid repeat (13, 20,
# 27), and the first with Membership Seal (10.67). Units: gold.
const REROLL_PRICES: PackedInt32Array = [13, 20, 27]
const SEAL_REROLL_PRICE: int = 11

# The army level staged for the recruit-level case.
const STAGED_LEVEL: int = 3

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _played: Array[StringName] = []
var _session: CampaignSession = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_check("guildhall: the catalog loads", _catalog != null)
	if _catalog == null:
		return
	_test_stock()
	_test_open_and_resume()
	_test_prices()
	_test_recruit_into_room()
	_test_muster_roll()
	_test_replace()
	_test_hand_over_refusals()
	_test_runes()
	_test_rerolls()
	_test_refusals()
	_test_coop()
	_test_sounds()


func _test_stock() -> void:
	var run_state: CampaignRunState = Fixture.session(RUN_SEED).run
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var wrong: PackedStringArray = []
	var prefixed: int = 0
	for roll_seed: int in STOCK_ROLLS:
		var stock: GuildhallStock = GuildhallStock.roll(
				RngStream.new(roll_seed), run_state, _catalog, ids
		)
		var recruits: PackedInt32Array = stock.indexes_of(GuildhallStock.CATEGORY_RECRUIT)
		var runes: PackedInt32Array = stock.indexes_of(GuildhallStock.CATEGORY_RUNE)
		if recruits.size() != GuildhallStock.RECRUITS or runes.size() != GuildhallStock.RUNES:
			wrong.append("%d recruits, %d runes" % [recruits.size(), runes.size()])
		var types: Dictionary[String, bool] = {}
		for index: int in recruits:
			var entry: GuildhallStock.Entry = stock.entries[index]
			var unit_type: UnitTypeDefinition = _catalog.unit_type(entry.definition_id)
			if unit_type == null or unit_type.is_commander or types.has(entry.definition_id):
				wrong.append("recruit %s" % [entry.definition_id])
			types[entry.definition_id] = true
			if entry.recruit.unit.level != 1 or entry.recruit.unit.weapon_id.is_empty():
				wrong.append("%s isn't a level-1 recruit with its weapon" % [entry.instance_id])
			if not entry.recruit.unit.prefix_id.is_empty():
				prefixed += 1
		var rune_ids: Dictionary[String, bool] = {}
		for index: int in runes:
			var rune: GuildhallStock.Entry = stock.entries[index]
			if _catalog.rune(rune.definition_id) == null or rune_ids.has(rune.definition_id):
				wrong.append("rune %s" % [rune.definition_id])
			rune_ids[rune.definition_id] = true
	_check("stock: 3 recruits of different types and 2 different runes every roll", (
			wrong.is_empty()
	), ", ".join(wrong.slice(0, 5)))
	# The recruit odds roll no prefix 30% of the time; prefixed ones are the rest, far above 0.
	_check("stock: recruits roll prefixes at the recruit odds (most have one)", (
			prefixed * 2 > STOCK_ROLLS * GuildhallStock.RECRUITS
	), "%d of %d" % [prefixed, STOCK_ROLLS * GuildhallStock.RECRUITS])
	run_state.seat_run(0).add_heirloom(GUILD_CHARTER)
	var charter: GuildhallStock = GuildhallStock.roll(RngStream.new(1), run_state, _catalog, ids)
	_check("GUILDHALL_RECRUITS: Guild Charter offers one more recruit", (
			charter.indexes_of(GuildhallStock.CATEGORY_RECRUIT).size()
					== GuildhallStock.RECRUITS + 1
	))


func _test_open_and_resume() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var outside: CampaignBatch = session.submit(
			OpenGuildhallCommand.for_session(session, _catalog)
	)
	_check("open: refused outside a Guildhall, changing nothing", (
			outside.is_rejected() and session.run.flow.shop_stock.is_empty()
	), outside.rejected_reason)
	_check("open: the map has a Guildhall route", Fixture.enter(session.run, _guildhall()))
	var opened: CampaignBatch = session.submit(OpenGuildhallCommand.for_session(session, _catalog))
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	_check("open: the stock is rolled and saved before it shows, recording no fact", (
			not opened.is_rejected() and opened.facts.is_empty() and stock != null
			and not stock.entries.is_empty()
	), opened.rejected_reason)
	var again: CampaignBatch = session.submit(OpenGuildhallCommand.for_session(session, _catalog))
	_check("open: a second open is refused, so the stock never rolls twice", again.is_rejected())
	var resumed: CampaignRunState = Fixture.through_json(session.run)
	var resumed_stock: GuildhallStock = (
			GuildhallStock.pending(resumed) if resumed != null else null
	)
	_check("resume (before buying): a quit and Continue shows the same stock", (
			resumed_stock != null
			and JSON.stringify(resumed_stock.capture()) == JSON.stringify(stock.capture())
	))
	session.run = resumed
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.gold = RICH
	var rune_index: int = stock.indexes_of(GuildhallStock.CATEGORY_RUNE)[0]
	var bought: CampaignBatch = session.submit(_buy(0, rune_index))
	session.submit(PrefixRerollCommand.for_session(session, 0, _first_non_commander(seat_run)))
	var after: CampaignRunState = Fixture.through_json(session.run)
	var after_stock: GuildhallStock = GuildhallStock.pending(after) if after != null else null
	_check("resume (after buying): the rune stays sold and held, the re-roll count and gold stay", (
			not bought.is_rejected()
			and after_stock != null and after_stock.entries[rune_index].buyer == 0
			and after_stock.rerolls_of(0).paid == 1
			and after.seat_run(0).gold == seat_run.gold
			and after.seat_run(0).rune_slots[0].instance_id
					== stock.entries[rune_index].instance_id
	), bought.rejected_reason)
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("leave: always allowed, and clears the stock", (
			not left.is_rejected() and session.run.is_on_map()
			and not session.run.flow.shop_stock.has(GuildhallStock.OFFER_KEY)
	), left.rejected_reason)


func _test_prices() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var prices: Dictionary[int, int] = {}
	var sealed: Dictionary[int, int] = {}
	for tier: int in RECRUIT_PRICES:
		prices[tier] = Guildhall.recruit_price(seat_run, _prefix_of_tier(tier), _catalog)
	var rune: int = Guildhall.rune_price(seat_run, _catalog)
	seat_run.add_heirloom(MEMBERSHIP_SEAL)
	for tier: int in RECRUIT_PRICES:
		sealed[tier] = Guildhall.recruit_price(seat_run, _prefix_of_tier(tier), _catalog)
	var sealed_rune: int = Guildhall.rune_price(seat_run, _catalog)
	_check("price: a recruit is 40 × its prefix's multiplier (20 / 30 / 40 / 52 / 72)", (
			prices == RECRUIT_PRICES
	), str(prices))
	_check("price: Membership Seal takes 20% off recruits, halves up", (
			sealed == SEAL_RECRUIT_PRICES
	), str(sealed))
	_check("price: a rune is 30, 24 with Membership Seal", (
			rune == RUNE_PRICE and sealed_rune == SEAL_RUNE_PRICE
	), "%d, %d" % [rune, sealed_rune])


func _test_recruit_into_room() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	_make_room(seat_run)
	for unit: UnitInstance in seat_run.army:
		unit.level = STAGED_LEVEL
	var index: int = _recruit_index(session.run)
	var preview: RecruitOffer = Guildhall.recruit_for(session.run, 0, index, _catalog)
	var price: int = Guildhall.recruit_price(seat_run, preview.unit.prefix_id, _catalog)
	var gold_before: int = seat_run.gold
	var size_before: int = seat_run.army.size()
	var batch: CampaignBatch = session.submit(_buy(0, index))
	var joined: UnitInstance = seat_run.unit(preview.unit.instance_id)
	_check("recruit: joins the army with its weapon; UNIT_BOUGHT then UNIT_RECRUITED", (
			not batch.is_rejected()
			and Fixture.kinds(batch) == [
				CampaignFact.Kind.UNIT_BOUGHT, CampaignFact.Kind.UNIT_RECRUITED,
			]
			and seat_run.army.size() == size_before + 1
			and joined != null and seat_run.items.has(joined.weapon_id)
			and Fixture.is_whole(seat_run)
	), batch.rejected_reason)
	_check("recruit: the price is paid, and the fact carries it", (
			seat_run.gold == gold_before - price and batch.facts[0].amount == price
	), "%d -> %d, %d" % [gold_before, seat_run.gold, price])
	_check("recruit: joins at the army's average level, matching its preview's stats", (
			joined != null and joined.level == STAGED_LEVEL
			and _stats_text(joined) == _stats_text(preview.unit)
	), "" if joined == null else "%s vs %s" % [_stats_text(joined), _stats_text(preview.unit)])
	var resumed: CampaignRunState = Fixture.through_json(session.run)
	_check("resume (after recruiting): the recruit is on the roster with its stats", (
			resumed != null
			and _stats_text(resumed.seat_run(0).unit(preview.unit.instance_id))
					== _stats_text(preview.unit)
	))


func _test_muster_roll() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var full: bool = Guildhall.is_army_full(session.run, 0, _catalog)
	var index: int = _recruit_index(session.run)
	var none: Dictionary[String, int] = {}
	var refused: String = Guildhall.recruit_problem(session.run, 0, index, "", none, _catalog)
	seat_run.add_heirloom(MUSTER_ROLL)
	var batch: CampaignBatch = session.submit(_buy(0, index))
	_check("Muster Roll: a full army of 4 needs a replacement; with it the recruit fills slot 5", (
			full and not refused.is_empty()
			and not batch.is_rejected()
			and seat_run.army.size() == RunOperations.max_army_size(seat_run, _catalog)
			and seat_run.army.size() == 5
	), "%s; %s" % [refused, batch.rejected_reason])


func _test_replace() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var index: int = _recruit_index(session.run)
	var commander: CampaignBatch = session.submit(_buy(0, index, seat_run.commander_id))
	_check("replace: the commander can't be replaced", (
			commander.is_rejected() and commander.rejected_reason.contains("commander")
	), commander.rejected_reason)
	var leaving: UnitInstance = seat_run.army[1]
	var leaving_items: PackedStringArray = leaving.item_ids()
	var plan: Dictionary[String, int] = Guildhall.best_fit(
			session.run, 0, index, leaving.instance_id, _catalog
	)
	var preview: RecruitOffer = Guildhall.recruit_for(session.run, 0, index, _catalog)
	var size_before: int = seat_run.army.size()
	var convoy_before: int = seat_run.convoy.size()
	var batch: CampaignBatch = session.submit(_buy(0, index, leaving.instance_id, plan))
	var joined: UnitInstance = seat_run.unit(preview.unit.instance_id)
	var kinds: Array[CampaignFact.Kind] = Fixture.kinds(batch)
	var placed: bool = true
	var to_convoy: int = 0
	for item_id: String in plan:
		match plan[item_id]:
			Guildhall.HandOver.RECRUIT:
				placed = placed and joined != null and joined.item_ids().has(item_id)
			Guildhall.HandOver.CONVOY:
				to_convoy += 1
				placed = placed and seat_run.convoy.has(item_id)
			Guildhall.HandOver.SCRAP:
				placed = placed and not seat_run.items.has(item_id)
	_check("replace: Best fit names a place for every item handed over", (
			leaving_items.size() > 0 and _covers(plan, leaving_items)
	), str(plan))
	_check("replace: the unit leaves, the recruit takes its place, the army's size stays", (
			not batch.is_rejected()
			and seat_run.unit(leaving.instance_id) == null
			and joined != null and seat_run.army.size() == size_before
			and kinds[0] == CampaignFact.Kind.UNIT_BOUGHT
			and kinds.has(CampaignFact.Kind.UNIT_DISMISSED)
			and kinds.has(CampaignFact.Kind.UNIT_RECRUITED)
	), batch.rejected_reason)
	_check("replace: each item went where the hand-over said; the roster stays whole", (
			placed and seat_run.convoy.size() == convoy_before + to_convoy
			and Fixture.is_whole(seat_run)
	), str(plan))
	var scrapping: CampaignSession = _at_guildhall()
	var scrapper: SeatRun = scrapping.run.seat_run(0)
	var other: UnitInstance = scrapper.army[1]
	var scrap_all: Dictionary[String, int] = {}
	for item_id: String in other.item_ids():
		scrap_all[item_id] = Guildhall.HandOver.SCRAP
	var gold_before: int = scrapper.gold
	var price: int = Guildhall.recruit_price(
			scrapper, Guildhall.recruit_for(scrapping.run, 0, index, _catalog).unit.prefix_id,
			_catalog
	)
	var scrapped: CampaignBatch = scrapping.submit(_buy(0, index, other.instance_id, scrap_all))
	var paid_back: int = 0
	for fact: CampaignFact in scrapped.facts:
		if fact.kind == CampaignFact.Kind.ITEM_SCRAPPED:
			paid_back += fact.amount
	_check("replace: scrapping every item pays each item's scrap value; the convoy is untouched", (
			not scrapped.is_rejected()
			and scrapper.gold == gold_before - price + paid_back
			and Fixture.is_whole(scrapper)
	), scrapped.rejected_reason)


func _test_hand_over_refusals() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var index: int = _recruit_index(session.run)
	var leaving: UnitInstance = seat_run.army[1]
	var joining: RecruitOffer = Guildhall.recruit_for(session.run, 0, index, _catalog)
	var none: Dictionary[String, int] = {}
	var missing: String = Guildhall.recruit_problem(
			session.run, 0, index, leaving.instance_id, none, _catalog
	)
	_check("hand-over: refused while an item of the leaving unit has no place", (
			missing.contains("needs a place")
	), missing)
	var all_convoy: Dictionary[String, int] = {}
	for item_id: String in leaving.item_ids():
		all_convoy[item_id] = Guildhall.HandOver.CONVOY
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	while not ItemPlacement.is_convoy_full(seat_run, _catalog):
		Fixture.add_to_convoy(seat_run, _catalog.unit_type(
				seat_run.army[0].unit_type_id
		).starting_weapon_id, ids)
	var full: String = Guildhall.recruit_problem(
			session.run, 0, index, leaving.instance_id, all_convoy, _catalog
	)
	_check("hand-over: the convoy option is refused when it can't take them", (
			full.contains("convoy")
	), full)
	var own_weapon: String = joining.unit.weapon_id
	var two: Dictionary[String, int] = {}
	for item_id: String in leaving.item_ids():
		two[item_id] = Guildhall.HandOver.SCRAP
	var weapon_id: String = leaving.weapon_id
	var problem: String = ""
	if not weapon_id.is_empty() and not own_weapon.is_empty():
		two[weapon_id] = Guildhall.HandOver.RECRUIT
		problem = Guildhall.recruit_problem(
				session.run, 0, index, leaving.instance_id, two, _catalog
		)
	var wield_case: bool = problem.contains("both go") or problem.contains("can't wield")
	_check("hand-over: two items for the recruit's Weapon slot, or an unwieldable weapon, refused", (
			wield_case
	), problem)


func _test_runes() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	var runes: PackedInt32Array = stock.indexes_of(GuildhallStock.CATEGORY_RUNE)
	var named: CampaignBatch = session.submit(_buy(0, runes[0], "", {}, 1))
	_check("rune: naming a slot to discard is refused while one is free", named.is_rejected())
	var gold_before: int = seat_run.gold
	var bought: CampaignBatch = session.submit(_buy(0, runes[0]))
	_check("rune: goes in the first free slot; RUNE_BOUGHT, then GAINED marked bought", (
			not bought.is_rejected()
			and Fixture.kinds(bought) == [CampaignFact.Kind.RUNE_BOUGHT, CampaignFact.Kind.GAINED]
			and (bought.facts[1].flags & CampaignFact.FLAG_BOUGHT) != 0
			and seat_run.rune_slots[0].instance_id == stock.entries[runes[0]].instance_id
			and seat_run.gold == gold_before - RUNE_PRICE
	), bought.rejected_reason)
	var ids: InstanceIdAllocator = session.ids
	for slot: int in SeatRun.RUNE_SLOT_COUNT:
		if seat_run.rune_slots[slot].is_empty():
			seat_run.rune_slots[slot] = SeatRun.RuneSlot.new(ids.next_rune_id("mend"), "mend")
	var unnamed: CampaignBatch = session.submit(_buy(0, runes[1]))
	_check("rune: with every slot full, a slot must be named", unnamed.is_rejected())
	var held: SeatRun.RuneSlot = seat_run.rune_slots[2]
	var swapped: CampaignBatch = session.submit(_buy(0, runes[1], "", {}, 2))
	_check("rune: the named slot's rune is discarded (RUNE_DISCARDED) and the new one takes it", (
			not swapped.is_rejected()
			and Fixture.kinds(swapped).has(CampaignFact.Kind.RUNE_DISCARDED)
			and swapped.facts[1].actor_id == held.instance_id
			and seat_run.rune_slots[2].instance_id == stock.entries[runes[1]].instance_id
	), swapped.rejected_reason)


func _test_rerolls() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var unit_id: String = _first_non_commander(seat_run)
	var unit: UnitInstance = seat_run.unit(unit_id)
	unit.prefix_id = UnitPrefixDefinition.NO_PREFIX
	var prices: PackedInt32Array = []
	var changed: bool = true
	for repeat: int in REROLL_PRICES.size():
		unit.prefix_id = UnitPrefixDefinition.NO_PREFIX
		prices.append(Guildhall.reroll_price(session.run, 0, unit_id, _catalog))
		var batch: CampaignBatch = session.submit(
				PrefixRerollCommand.for_session(session, 0, unit_id, _catalog)
		)
		changed = (
				changed and not batch.is_rejected() and not unit.prefix_id.is_empty()
				and batch.facts[0].kind == CampaignFact.Kind.PREFIX_REROLLED
				and batch.facts[0].definition_id == unit.prefix_id
		)
	_check("re-roll: ⅓ of the unit's value, +50% of that per repeat here (13, 20, 27)", (
			prices == REROLL_PRICES
	), str(prices))
	_check("re-roll: always changes the prefix (an unprefixed unit gains one)", changed)
	var before: String = unit.prefix_id
	var again: CampaignBatch = session.submit(
			PrefixRerollCommand.for_session(session, 0, unit_id, _catalog)
	)
	_check("re-roll: never lands on the same prefix", (
			not again.is_rejected() and unit.prefix_id != before
	))
	var commander: CampaignBatch = session.submit(
			PrefixRerollCommand.for_session(session, 0, seat_run.commander_id, _catalog)
	)
	_check("re-roll: a commander is refused", commander.is_rejected(), commander.rejected_reason)
	var token: CampaignSession = _at_guildhall()
	var holder: SeatRun = token.run.seat_run(0)
	holder.add_heirloom(TINKERS_TOKEN)
	var token_unit: String = _first_non_commander(holder)
	holder.unit(token_unit).prefix_id = UnitPrefixDefinition.NO_PREFIX
	var free: int = Guildhall.reroll_price(token.run, 0, token_unit, _catalog)
	var gold_before: int = holder.gold
	token.submit(PrefixRerollCommand.for_session(token, 0, token_unit, _catalog))
	holder.unit(token_unit).prefix_id = UnitPrefixDefinition.NO_PREFIX
	var next: int = Guildhall.reroll_price(token.run, 0, token_unit, _catalog)
	_check("FREE_REROLLS: Tinker's Token's first re-roll is free and doesn't raise the next", (
			free == 0 and holder.gold == gold_before and next == REROLL_PRICES[0]
	), "%d, %d" % [free, next])
	holder.add_heirloom(MEMBERSHIP_SEAL)
	token.submit(PrefixRerollCommand.for_session(token, 0, token_unit, _catalog))
	var sealed: CampaignSession = _at_guildhall()
	var sealed_seat: SeatRun = sealed.run.seat_run(0)
	sealed_seat.add_heirloom(MEMBERSHIP_SEAL)
	var sealed_unit: String = _first_non_commander(sealed_seat)
	sealed_seat.unit(sealed_unit).prefix_id = UnitPrefixDefinition.NO_PREFIX
	var sealed_price: int = Guildhall.reroll_price(sealed.run, 0, sealed_unit, _catalog)
	_check("re-roll: Membership Seal takes 20% off (13.33 -> 11)", (
			sealed_price == SEAL_REROLL_PRICE
	), str(sealed_price))
	_test_reroll_hp()


func _test_reroll_hp() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var unit_id: String = _first_non_commander(seat_run)
	var unit: UnitInstance = seat_run.unit(unit_id)
	var full_ok: bool = true
	var hurt_ok: bool = true
	for attempt: int in REROLL_PRICES.size() * 2:
		unit.hp = UnitInstance.FULL_HP
		session.submit(PrefixRerollCommand.for_session(session, 0, unit_id, _catalog))
		full_ok = full_ok and unit.hp == UnitInstance.FULL_HP
		var old_max: int = unit.stats(_catalog).get_int(CombatValue.Key.HP)
		unit.hp = maxi(old_max - 3, 1)
		var hp_before: int = unit.hp
		seat_run.gold = RICH
		session.submit(PrefixRerollCommand.for_session(session, 0, unit_id, _catalog))
		var new_max: int = unit.stats(_catalog).get_int(CombatValue.Key.HP)
		var expected: int = hp_before
		if new_max > old_max:
			expected = hp_before + new_max - old_max
		elif hp_before > new_max:
			expected = maxi(new_max, 1)
		hurt_ok = hurt_ok and unit.hp == expected
	_check("re-roll: a unit at full stays full; a hurt one gains a max-HP rise, capped on a loss", (
			full_ok and hurt_ok
	))


func _test_refusals() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	_make_room(seat_run)
	seat_run.gold = 0
	var index: int = _recruit_index(session.run)
	var poor: CampaignBatch = session.submit(_buy(0, index))
	_check("refusal: too little gold says the price and the gold, changing nothing", (
			poor.is_rejected() and poor.rejected_reason.contains("not enough gold")
			and GuildhallStock.pending(session.run).entries[index].buyer == -1
	), poor.rejected_reason)
	_check("refusal: the card says too little gold", (
			Guildhall.entry_problem(session.run, 0, index, _catalog) == "too little gold"
	))
	seat_run.gold = RICH
	session.submit(_buy(0, index))
	var twice: CampaignBatch = session.submit(_buy(0, index))
	_check("refusal: a bought entry says so", (
			twice.is_rejected() and twice.rejected_reason == "you bought it already"
	), twice.rejected_reason)
	var room: CampaignBatch = session.submit(_buy(0, _recruit_index(session.run), "x", {}))
	_check("refusal: naming a unit while the army has room", (
			room.is_rejected()
	), room.rejected_reason)
	var gone: CampaignSession = Fixture.session(RUN_SEED)
	var outside: CampaignBatch = gone.submit(_buy(0, 0))
	_check("refusal: outside a Guildhall", outside.is_rejected(), outside.rejected_reason)


func _test_coop() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(session.run, _guildhall())
	session.submit(OpenGuildhallCommand.for_session(session, _catalog))
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	_check("co-op: one shared stock, one more recruit and rune per extra seat", (
			stock != null
			and stock.indexes_of(GuildhallStock.CATEGORY_RECRUIT).size()
					== GuildhallStock.RECRUITS + 1
			and stock.indexes_of(GuildhallStock.CATEGORY_RUNE).size() == GuildhallStock.RUNES + 1
	))
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).gold = RICH
	var rune: int = stock.indexes_of(GuildhallStock.CATEGORY_RUNE)[0]
	var first: CampaignBatch = session.submit(_buy(1, rune))
	var second: CampaignBatch = session.submit(_buy(0, rune))
	_check("co-op: the first confirmed purchase gets it; the second is refused, costing nothing", (
			not first.is_rejected() and second.is_rejected()
			and second.rejected_reason == "it is sold"
			and session.run.seat_run(0).gold == RICH
	), second.rejected_reason)
	_make_room(session.run.seat_run(0))
	session.run.seat_run(1).army[0].level = STAGED_LEVEL
	for unit: UnitInstance in session.run.seat_run(1).army:
		unit.level = STAGED_LEVEL
	var index: int = _recruit_index(session.run)
	var for_zero: RecruitOffer = Guildhall.recruit_for(session.run, 0, index, _catalog)
	var for_one: RecruitOffer = Guildhall.recruit_for(session.run, 1, index, _catalog)
	_check("co-op: a recruit joins at its buyer's army's level", (
			for_zero.unit.level == 1 and for_one.unit.level == STAGED_LEVEL
	), "%d, %d" % [for_zero.unit.level, for_one.unit.level])
	var one_unit: String = _first_non_commander(session.run.seat_run(1))
	session.submit(PrefixRerollCommand.for_session(session, 1, one_unit, _catalog))
	stock = GuildhallStock.pending(session.run)
	_check("co-op: re-rolls are counted per seat", (
			stock.rerolls_of(1).paid == 1 and stock.rerolls_of(0).paid == 0
	))
	var gift_id: String = Fixture.add_to_convoy(session.run.seat_run(0), _catalog.unit_type(
			session.run.seat_run(0).army[0].unit_type_id
	).starting_weapon_id, session.ids)
	var gift: GiftItemCommand = GiftItemCommand.new(0, gift_id, 1)
	gift.catalog = _catalog
	var gave: CampaignBatch = session.submit(gift)
	_check("co-op: gifting works at a Guildhall", (
			not gave.is_rejected() and session.run.seat_run(1).convoy.has(gift_id)
	), gave.rejected_reason)


func _test_sounds() -> void:
	var session: CampaignSession = _listen(_at_guildhall())
	var listener: FactCueListener = session.get_meta(&"listener")
	var chosen: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_CHOSEN, 0)
	chosen.amount = session.run.node
	_check("sound: entering a Guildhall plays recruit_map_enter", (
			listener.cue_for_campaign(chosen) == &"recruit_map_enter"
	), str(listener.cue_for_campaign(chosen)))
	var seat_run: SeatRun = session.run.seat_run(0)
	_make_room(seat_run)
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	_step(session, _buy(0, _recruit_index(session.run)))
	var recruit_cues: Array[StringName] = _played.duplicate()
	_step(session, _buy(0, stock.indexes_of(GuildhallStock.CATEGORY_RUNE)[0]))
	var rune_cues: Array[StringName] = _played.duplicate()
	_step(session, PrefixRerollCommand.for_session(
			session, 0, _first_non_commander(seat_run), _catalog
	))
	var reroll_cues: Array[StringName] = _played.duplicate()
	var once: Array[StringName] = [&"item_buy"]
	_check("sound: a recruit, a rune and a re-roll each play item_buy once", (
			recruit_cues == once and rune_cues == once and reroll_cues == once
	), "%s / %s / %s" % [recruit_cues, rune_cues, reroll_cues])


# A solo run inside a Guildhall with its stock rolled and gold enough for anything.
func _at_guildhall() -> CampaignSession:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(session.run, _guildhall())
	session.submit(OpenGuildhallCommand.for_session(session, _catalog))
	session.run.seat_run(0).gold = RICH
	return session


func _buy(
		seat: int,
		index: int,
		replaced_id: String = "",
		hand_over: Dictionary = {},
		discard_slot: int = Guildhall.NO_SLOT
) -> GuildhallPurchaseCommand:
	var command: GuildhallPurchaseCommand = GuildhallPurchaseCommand.new(seat, index)
	command.replaced_id = replaced_id
	command.hand_over.assign(hand_over)
	command.discard_slot = discard_slot
	command.catalog = _catalog
	return command


# Dismisses seat_run's last non-commander unit, its items dropped from the roster, so the army has
# room for one recruit.
func _make_room(seat_run: SeatRun) -> void:
	var unit: UnitInstance = seat_run.army[seat_run.army.size() - 1]
	for item_id: String in unit.item_ids():
		seat_run.items.erase(item_id)
	seat_run.army.erase(unit)


func _recruit_index(run_state: CampaignRunState) -> int:
	var stock: GuildhallStock = GuildhallStock.pending(run_state)
	for index: int in stock.indexes_of(GuildhallStock.CATEGORY_RECRUIT):
		if not stock.entries[index].is_sold():
			return index
	return -1


func _first_non_commander(seat_run: SeatRun) -> String:
	return Guildhall.replaceable_units(seat_run)[0]


func _prefix_of_tier(tier: int) -> String:
	if tier == 0:
		return UnitPrefixDefinition.NO_PREFIX
	return UnitPrefixDefinition.of_tier(_catalog, tier)[0].id


func _covers(plan: Dictionary[String, int], items: PackedStringArray) -> bool:
	for item_id: String in items:
		if not plan.has(item_id):
			return false
	return true


func _stats_text(unit: UnitInstance) -> String:
	if unit == null:
		return ""
	var sheet: StatSheet = unit.stats(_catalog)
	var parts: PackedStringArray = []
	for key: int in RecruitOfferCard.SHOWN_STATS:
		parts.append("%s %d" % [RecruitOfferCard.SHOWN_STATS[key], sheet.get_int(key)])
	return " ".join(parts)


func _guildhall() -> CampaignGraph.NodeType:
	return CampaignGraph.NodeType.GUILDHALL


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
