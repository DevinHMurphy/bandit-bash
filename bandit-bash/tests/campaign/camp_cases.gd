# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camp_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The Camp for tests/campaign/run_all.gd, on real runs from the real catalog: the Feast's heal
## (35% of max HP, halves up, never past full, Cursed Blood halving it); cooking an ingredient from
## the convoy or a Pouch (every living unit's next level-up, Hit at once, the ingredient used up);
## Train through RunOperations (the commander and an upgraded unit refused); one choice per visit
## and Leave waiting for it; re-gearing (swaps, stowing, refusals, a fallen unit's items, outside a
## Camp); scrapping from the convoy with and without Scrapper's Tongs, at pickup too; a quit and
## Continue before and after the choice; co-op's per-seat choices, stacking heals, the cook's own
## gains, and convoy-to-convoy gifting.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 4242

const HEARTBEET: String = "heartbeet"
const HAWKWEED: String = "hawkweed"
const POTION: String = "potion"
const SIMPLE_BOW: String = "simple_bow"
const SIMPLE_SWORD: String = "simple_sword"
const IRON_SHIELD: String = "iron_shield"
const LUCKY_COIN: String = "lucky_coin"
const CURSED_BLOOD: String = "cursed_blood"
const SCRAPPERS_TONGS: String = "scrappers_tongs"

# The army's roster order in a new Mercenary run.
const COMMANDER: int = 0
const HAKKAPEL: int = 1
const ARCHER: int = 2
const MEDIC: int = 3

var _report: Callable
var _catalog: EffectCatalog.Index = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_check("camp: the catalog loads", _catalog != null)
	if _catalog == null:
		return
	_test_feast_heal()
	_test_cooking()
	_test_train()
	_test_one_choice_and_leave()
	_test_regear()
	_test_scrapping()
	_test_resume()
	_test_coop()
	_test_gifting()


func _test_feast_heal() -> void:
	var session: CampaignSession = _at_camp()
	var seat_run: SeatRun = session.run.seat_run(0)
	var archer: UnitInstance = seat_run.army[ARCHER]
	var medic: UnitInstance = seat_run.army[MEDIC]
	var archer_max: int = _max_hp(archer)
	var medic_max: int = _max_hp(medic)
	archer.hp = 1
	medic.hp = medic_max - 1
	var expected: int = ValueBreakdown.round_to_int(
			archer_max * 0.35, ValueBreakdown.Rounding.HALF_UP
	)
	var feast: CampaignBatch = session.submit(FeastCommand.new(0))
	_check("feast: FEAST_HELD, then each hurt unit heals 35% of max HP, halves up", (
			not feast.is_rejected()
			and feast.facts[0].kind == CampaignFact.Kind.FEAST_HELD
			and feast.facts[0].actor_id.is_empty()
			and archer.hp == 1 + expected
			and _hp_facts(feast) == 2
	), "%s; archer %d of %d (+%d expected)" % [
		feast.rejected_reason, archer.hp, archer_max, expected,
	])
	_check("feast: never past full; a unit at full gains nothing and stays at full", (
			medic.hp == UnitInstance.FULL_HP
			and seat_run.army[COMMANDER].hp == UnitInstance.FULL_HP
			and _hp_fact_for(feast, medic.instance_id) == 1
	), "medic %d; fact %d" % [medic.hp, _hp_fact_for(feast, medic.instance_id)])
	var cursed: CampaignSession = _at_camp()
	var cursed_run: SeatRun = cursed.run.seat_run(0)
	cursed_run.add_heirloom(CURSED_BLOOD)
	var cursed_archer: UnitInstance = cursed_run.army[ARCHER]
	cursed_archer.hp = 1
	var halved: int = ValueBreakdown.round_to_int(
			archer_max * 0.35 * 0.5, ValueBreakdown.Rounding.HALF_UP
	)
	cursed.submit(FeastCommand.new(0))
	_check("feast: Cursed Blood halves it (healing received, read outside battle)", (
			cursed_archer.hp == 1 + halved
			and is_equal_approx(
					RunOperations.healing_received_percent(cursed_run, cursed_archer, _catalog),
					50.0
			)
	), "archer %d (+%d expected)" % [cursed_archer.hp, halved])


func _test_cooking() -> void:
	var session: CampaignSession = _at_camp()
	var seat_run: SeatRun = session.run.seat_run(0)
	var beet: String = Fixture.add_to_convoy(seat_run, HEARTBEET, session.ids)
	var potion: String = Fixture.add_to_convoy(seat_run, POTION, session.ids)
	var refused: CampaignBatch = session.submit(FeastCommand.new(0, potion))
	_check("cook: a consumable that isn't an ingredient is refused", refused.is_rejected())
	_check("cook: the convoy's and Pouches' ingredients are offered", (
			Camp.ingredients(seat_run, _catalog) == PackedStringArray([beet])
	), str(Camp.ingredients(seat_run, _catalog)))
	var cooked: CampaignBatch = session.submit(FeastCommand.new(0, beet))
	var gains_ok: bool = true
	for unit: UnitInstance in seat_run.army:
		var gain: UnitInstance.PendingGain = (
				unit.pending_gains[0] if unit.pending_gains.size() == 1 else null
		)
		gains_ok = gains_ok and gain != null and gain.stat == CombatValue.Stat.HP
		gains_ok = gains_ok and gain.amount == 2 and gain.remaining == 1
		gains_ok = gains_ok and gain.source_id == HEARTBEET
	_check("cook: Heartbeet is used up; every living unit's next level-up gains +2 HP", (
			not cooked.is_rejected()
			and cooked.facts[0].actor_id == beet
			and cooked.facts[0].definition_id == HEARTBEET
			and not seat_run.items.has(beet)
			and not seat_run.convoy.has(beet)
			and gains_ok
			and _kind_count(cooked, CampaignFact.Kind.UNIT_CHANGED) == seat_run.army.size()
			and Fixture.is_whole(seat_run)
	), cooked.rejected_reason)
	var stats: StatSheet = seat_run.army[ARCHER].stats(_catalog)
	var hp_before: int = stats.get_int(CombatValue.Key.HP)
	LevelUp.gain_xp(
			seat_run.army[ARCHER], 100, null, RngStream.new(1), _catalog,
			CombatRewardRules.load_default()
	)
	_check("cook: the gain lands on the next level-up and is gone after it", (
			seat_run.army[ARCHER].pending_gains.is_empty()
			and seat_run.army[ARCHER].stats(_catalog).get_int(CombatValue.Key.HP) >= hp_before + 2
	))
	var hit: CampaignSession = _at_camp()
	var hit_run: SeatRun = hit.run.seat_run(0)
	var weed: String = Fixture.add_to_convoy(hit_run, HAWKWEED, hit.ids)
	ItemPlacement.put_item(hit_run.army[ARCHER], Loadout.Slot.POUCH, "")
	hit_run.convoy.remove_at(hit_run.convoy.find(weed))
	var old_pouch: String = hit_run.army[HAKKAPEL].pouch_id
	hit_run.items.erase(old_pouch)
	ItemPlacement.put_item(hit_run.army[HAKKAPEL], Loadout.Slot.POUCH, weed)
	var hit_before: int = hit_run.army[COMMANDER].stats(_catalog).get_int(CombatValue.Key.HIT)
	var hawk: CampaignBatch = hit.submit(FeastCommand.new(0, weed))
	_check("cook: Hawkweed from a Pouch gives every living unit +5 Hit at once", (
			not hawk.is_rejected()
			and hit_run.army[HAKKAPEL].pouch_id.is_empty()
			and hit_run.army[COMMANDER].stats(_catalog).get_int(CombatValue.Key.HIT)
					== hit_before + 5
			and hit_run.army[COMMANDER].pending_gains.is_empty()
	), hawk.rejected_reason)


func _test_train() -> void:
	var session: CampaignSession = _at_camp()
	var seat_run: SeatRun = session.run.seat_run(0)
	var commander: CampaignBatch = session.submit(
			TrainCommand.new(0, seat_run.army[COMMANDER].instance_id)
	)
	_check("train: the commander is refused, with the reason", (
			commander.is_rejected() and commander.rejected_reason.contains("commander")
	), commander.rejected_reason)
	var archer: UnitInstance = seat_run.army[ARCHER]
	var trained: CampaignBatch = session.submit(TrainCommand.new(0, archer.instance_id))
	_check("train: the archer is upgraded through RunOperations (UNIT_UPGRADED by camp_train)", (
			not trained.is_rejected()
			and archer.is_upgraded
			and trained.facts[0].kind == CampaignFact.Kind.UNIT_UPGRADED
			and trained.facts[0].definition_id == Camp.TRAIN_SOURCE
			and Camp.choice_of(seat_run) == Camp.Choice.TRAIN
	), trained.rejected_reason)
	var none_left: CampaignSession = _at_camp()
	for unit: UnitInstance in none_left.run.seat_run(0).army:
		unit.is_upgraded = true
	_check("train: refused, saying why, when no unit can be upgraded", (
			not Camp.train_option_problem(none_left.run, 0, _catalog).is_empty()
			and Camp.feast_problem(none_left.run, 0, "", _catalog).is_empty()
	), Camp.train_option_problem(none_left.run, 0, _catalog))


func _test_one_choice_and_leave() -> void:
	var session: CampaignSession = _at_camp()
	var early: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	session.submit(FeastCommand.new(0))
	var second: CampaignBatch = session.submit(
			TrainCommand.new(0, session.run.seat_run(0).army[ARCHER].instance_id)
	)
	var feast_again: CampaignBatch = session.submit(FeastCommand.new(0))
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("choice: one per visit; Leave waits for it, then clears it", (
			early.is_rejected()
			and second.is_rejected() and feast_again.is_rejected()
			and not left.is_rejected()
			and not session.run.seat_run(0).pending_offers.has(Camp.OFFER_KEY)
	), "%s / %s" % [early.rejected_reason, left.rejected_reason])
	var outside: CampaignSession = Fixture.session(RUN_SEED)
	_check("choice: Feast and Train are refused outside a Camp", (
			outside.submit(FeastCommand.new(0)).is_rejected()
	))


func _test_regear() -> void:
	var session: CampaignSession = _at_camp()
	var seat_run: SeatRun = session.run.seat_run(0)
	var archer: UnitInstance = seat_run.army[ARCHER]
	var hakkapel: UnitInstance = seat_run.army[HAKKAPEL]
	var old_bow: String = archer.weapon_id
	var bow: String = Fixture.add_to_convoy(seat_run, SIMPLE_BOW, session.ids)
	var swap: CampaignBatch = session.submit(
			RegearCommand.new(0, bow, archer.instance_id, Loadout.Slot.WEAPON)
	)
	_check("regear: a convoy weapon onto a filled slot swaps the old one into the convoy", (
			not swap.is_rejected()
			and archer.weapon_id == bow
			and seat_run.convoy.has(old_bow)
			and Fixture.kinds(swap) == [
				CampaignFact.Kind.ITEM_EQUIPPED, CampaignFact.Kind.ITEM_EQUIPPED,
			]
			and swap.facts[0].target_id == archer.instance_id
			and swap.facts[1].target_id.is_empty()
	), swap.rejected_reason)
	var wrong_type: CampaignBatch = session.submit(
			RegearCommand.new(0, old_bow, hakkapel.instance_id, Loadout.Slot.WEAPON)
	)
	var shield: String = Fixture.add_to_convoy(seat_run, IRON_SHIELD, session.ids)
	var shield_in_pouch: CampaignBatch = session.submit(
			RegearCommand.new(0, shield, archer.instance_id, Loadout.Slot.POUCH)
	)
	_check("regear: a weapon the unit can't wield and equipment in the Pouch are refused", (
			wrong_type.is_rejected() and shield_in_pouch.is_rejected()
	), "%s / %s" % [wrong_type.rejected_reason, shield_in_pouch.rejected_reason])
	var old_pouch: String = archer.pouch_id
	var stow: CampaignBatch = session.submit(
			RegearCommand.new(0, old_bow, archer.instance_id, Loadout.Slot.POUCH)
	)
	_check("regear: a wieldable weapon stows in the Pouch, the trinket there to the convoy", (
			not stow.is_rejected()
			and archer.pouch_id == old_bow
			and seat_run.convoy.has(old_pouch)
			and Fixture.is_whole(seat_run)
	), stow.rejected_reason)
	var trade: CampaignBatch = session.submit(
			RegearCommand.new(0, archer.pouch_id, archer.instance_id, Loadout.Slot.WEAPON)
	)
	_check("regear: one unit's Pouch and Weapon swap", (
			not trade.is_rejected() and archer.weapon_id == old_bow and archer.pouch_id == bow
	), trade.rejected_reason)
	var unarmed: CampaignBatch = session.submit(RegearCommand.new(0, hakkapel.weapon_id, ""))
	_check("regear: a unit may be left unarmed (its weapon to the convoy)", (
			not unarmed.is_rejected() and hakkapel.weapon_id.is_empty()
	), unarmed.rejected_reason)
	var full_run: SeatRun = seat_run
	while not ItemPlacement.is_convoy_full(full_run, _catalog):
		Fixture.add_to_convoy(full_run, LUCKY_COIN, session.ids)
	var into_full: CampaignBatch = session.submit(RegearCommand.new(0, archer.pouch_id, ""))
	_check("regear: a full convoy refuses an item", (
			into_full.is_rejected()
	), into_full.rejected_reason)
	var fallen_session: CampaignSession = _at_camp()
	var fallen_run: SeatRun = fallen_session.run.seat_run(0)
	var fallen: UnitInstance = fallen_run.army[ARCHER]
	fallen_run.army.erase(fallen)
	fallen_run.fallen.append(fallen)
	var into_filled: CampaignBatch = fallen_session.submit(RegearCommand.new(
			0, fallen.weapon_id, fallen_run.army[COMMANDER].instance_id, Loadout.Slot.WEAPON
	))
	var fallen_bow: String = fallen.weapon_id
	var taken: CampaignBatch = fallen_session.submit(RegearCommand.new(0, fallen_bow, ""))
	var onto_fallen: CampaignBatch = fallen_session.submit(
			RegearCommand.new(0, fallen_bow, fallen.instance_id, Loadout.Slot.WEAPON)
	)
	_check("regear: a fallen unit's item can be taken, never swapped back or given to it", (
			into_filled.is_rejected()
			and not taken.is_rejected()
			and fallen.weapon_id.is_empty()
			and fallen_run.convoy.has(fallen_bow)
			and onto_fallen.is_rejected()
	), "%s / %s / %s" % [
		into_filled.rejected_reason, taken.rejected_reason, onto_fallen.rejected_reason,
	])
	var on_map: CampaignSession = Fixture.session(RUN_SEED)
	var map_run: SeatRun = on_map.run.seat_run(0)
	var map_move: CampaignBatch = on_map.submit(
			RegearCommand.new(0, map_run.army[ARCHER].weapon_id, "")
	)
	_check("regear: gear can't change outside a Camp", (
			map_move.is_rejected()
	), map_move.rejected_reason)


func _test_scrapping() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var seat_run: SeatRun = session.run.seat_run(0)
	var coin: String = Fixture.add_to_convoy(seat_run, LUCKY_COIN, session.ids)
	var coin_definition: ItemDefinition = _catalog.item(LUCKY_COIN)
	var base: int = Prices.scrap_value(
			coin_definition.kind, coin_definition.rarity, Prices.default_scrap_percent()
	)
	var gold_before: int = seat_run.gold
	var slot_item: CampaignBatch = session.submit(
			ScrapItemCommand.new(0, seat_run.army[ARCHER].weapon_id)
	)
	var scrapped: CampaignBatch = session.submit(ScrapItemCommand.new(0, coin))
	_check("scrap: on the map, a convoy item scraps for 20% (not a slot's item)", (
			slot_item.is_rejected()
			and not scrapped.is_rejected()
			and Fixture.kinds(scrapped) == [CampaignFact.Kind.ITEM_SCRAPPED]
			and scrapped.facts[0].amount == base
			and seat_run.gold == gold_before + base
			and not seat_run.items.has(coin)
	), scrapped.rejected_reason)
	seat_run.add_heirloom(SCRAPPERS_TONGS)
	var tongs_rate: float = RunOperations.scrap_percent(seat_run, _catalog)
	var with_tongs: int = Prices.scrap_value(coin_definition.kind, coin_definition.rarity, 40.0)
	var second: String = Fixture.add_to_convoy(seat_run, LUCKY_COIN, session.ids)
	var tongs: CampaignBatch = session.submit(ScrapItemCommand.new(0, second))
	_check("scrap: Scrapper's Tongs raises the rate to 40% on the campaign layer", (
			is_equal_approx(tongs_rate, 40.0)
			and not tongs.is_rejected()
			and tongs.facts[0].amount == with_tongs
			and ItemPlacement.scrap_value(coin_definition, seat_run, _catalog) == with_tongs
			and ItemPlacement.scrap_value(coin_definition) == base
	), "%.1f%%; %s" % [tongs_rate, tongs.rejected_reason])
	var pickup: ItemPlacement = ItemPlacement.new(ItemPlacement.Destination.SCRAP)
	var picked: ItemInstance = ItemInstance.new(session.ids.next_item_id("coin"), LUCKY_COIN)
	var first: int = session.run.fact_log.size()
	pickup.apply(session.run, 0, picked, _catalog)
	var at_pickup: CampaignFact = session.run.fact_log[first]
	_check("scrap: at pickup it pays the seat's rate too", (
			at_pickup.kind == CampaignFact.Kind.ITEM_SCRAPPED and at_pickup.amount == with_tongs
	), str(at_pickup.amount))


func _test_resume() -> void:
	var session: CampaignSession = _at_camp()
	var before: CampaignRunState = Fixture.through_json(session.run)
	_check("resume: a quit and Continue before the choice is still at the Camp, unchosen", (
			before != null and Camp.is_at_camp(before)
			and Camp.choice_of(before.seat_run(0)) == Camp.Choice.NONE
	))
	session.submit(TrainCommand.new(0, session.run.seat_run(0).army[ARCHER].instance_id))
	var after: CampaignRunState = Fixture.through_json(session.run)
	if after == null:
		_check("resume: the run after Train reloads", false)
		return
	var chosen: Camp.Choice = Camp.choice_of(after.seat_run(0))
	session.run = after
	var again: CampaignBatch = session.submit(FeastCommand.new(0))
	var regear: CampaignBatch = session.submit(
			RegearCommand.new(0, after.seat_run(0).army[ARCHER].weapon_id, "")
	)
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("resume: after Train it Continues with the choice made and the unit upgraded", (
			chosen == Camp.Choice.TRAIN
			and after.seat_run(0).army[ARCHER].is_upgraded
			and again.is_rejected()
			and not regear.is_rejected()
			and not left.is_rejected()
	), "choice %d; %s / %s" % [chosen, regear.rejected_reason, left.rejected_reason])


func _test_coop() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(session.run, CampaignGraph.NodeType.CAMP)
	var mine: SeatRun = session.run.seat_run(0)
	var theirs: SeatRun = session.run.seat_run(1)
	var their_archer: UnitInstance = theirs.army[ARCHER]
	their_archer.hp = 1
	var beet: String = Fixture.add_to_convoy(mine, HEARTBEET, session.ids)
	var heal: int = Camp.heal_amount(theirs, their_archer, _catalog)
	session.submit(FeastCommand.new(0, beet))
	var waiting: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("co-op: seat 0's Feast heals seat 1's units; the ingredient feeds only the cook", (
			their_archer.hp == 1 + heal
			and theirs.army[ARCHER].pending_gains.is_empty()
			and mine.army[ARCHER].pending_gains.size() == 1
			and waiting.is_rejected()
	), "%d (+%d); %s" % [their_archer.hp, heal, waiting.rejected_reason])
	var second_heal: int = Camp.heal_amount(theirs, their_archer, _catalog)
	var fed: CampaignBatch = session.submit(FeastCommand.new(1))
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(1))
	_check("co-op: each seat chooses for itself; a second Feast's heal stacks", (
			not fed.is_rejected()
			and second_heal > 0
			and (
					their_archer.hp == 1 + heal + second_heal
					or their_archer.hp == UnitInstance.FULL_HP
			)
			and not left.is_rejected()
	), "%s / %s" % [fed.rejected_reason, left.rejected_reason])
	var split: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(split.run, CampaignGraph.NodeType.CAMP)
	split.submit(FeastCommand.new(0))
	var trained: CampaignBatch = split.submit(
			TrainCommand.new(1, split.run.seat_run(1).army[ARCHER].instance_id)
	)
	_check("co-op: one seat feasts while the other trains", (
			not trained.is_rejected()
			and Camp.choice_of(split.run.seat_run(0)) == Camp.Choice.FEAST
			and Camp.choice_of(split.run.seat_run(1)) == Camp.Choice.TRAIN
			and not split.run.seat_run(0).army[ARCHER].is_upgraded
	), trained.rejected_reason)


func _test_gifting() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED, 2)
	var giver: SeatRun = session.run.seat_run(0)
	var receiver: SeatRun = session.run.seat_run(1)
	var gift: String = Fixture.add_to_convoy(giver, SIMPLE_SWORD, session.ids)
	var on_map: CampaignBatch = session.submit(GiftItemCommand.new(0, gift, 1))
	Fixture.enter(session.run, CampaignGraph.NodeType.CAMP)
	var to_self: CampaignBatch = session.submit(GiftItemCommand.new(0, gift, 0))
	var given: CampaignBatch = session.submit(GiftItemCommand.new(0, gift, 1))
	_check("gift: refused on the map and to oneself; at a Camp it moves convoy to convoy", (
			on_map.is_rejected() and to_self.is_rejected()
			and not given.is_rejected()
			and Fixture.kinds(given) == [CampaignFact.Kind.ITEM_GIFTED]
			and given.facts[0].amount == 1
			and not giver.items.has(gift) and receiver.convoy.has(gift)
			and Fixture.is_whole(giver) and Fixture.is_whole(receiver)
	), "%s / %s / %s" % [on_map.rejected_reason, to_self.rejected_reason, given.rejected_reason])
	while not ItemPlacement.is_convoy_full(receiver, _catalog):
		Fixture.add_to_convoy(receiver, LUCKY_COIN, session.ids)
	var another: String = Fixture.add_to_convoy(giver, SIMPLE_SWORD, session.ids)
	var full: CampaignBatch = session.submit(GiftItemCommand.new(0, another, 1))
	_check("gift: refused when the receiving convoy is full", (
			full.is_rejected()
	), full.rejected_reason)


# A new solo run inside a Camp.
func _at_camp() -> CampaignSession:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	if not Fixture.enter(session.run, CampaignGraph.NodeType.CAMP):
		_check("camp: the map has a Camp route", false)
	return session


func _max_hp(unit: UnitInstance) -> int:
	return unit.stats(_catalog).get_int(CombatValue.Key.HP)


func _hp_facts(batch: CampaignBatch) -> int:
	return _kind_count(batch, CampaignFact.Kind.HP_CHANGED)


func _hp_fact_for(batch: CampaignBatch, unit_id: String) -> int:
	var count: int = 0
	for fact: CampaignFact in batch.facts:
		if fact.kind == CampaignFact.Kind.HP_CHANGED and fact.actor_id == unit_id:
			count += 1
	return count


func _kind_count(batch: CampaignBatch, kind: CampaignFact.Kind) -> int:
	var count: int = 0
	for fact: CampaignFact in batch.facts:
		if fact.kind == kind:
			count += 1
	return count


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
