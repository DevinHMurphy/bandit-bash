# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_loot_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## Loot found on a battle map ([member MapState.found]) reaching the run at the battle's end
## (BUG-039), for tests/campaign/run_all.gd, on real solo and 2-seat runs and maps, each against a
## twin battle with nothing found: a won solo map's gold, consumable and rune go to the seat, each
## item and rune with GAINED; a full convoy loses an item; in co-op what a teammate's unit took on
## a map goes to that map's owner, and a failed map's loot to nobody.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 0x0B39
const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const HOUSE_GOLD: int = 17
const TEAMMATE_GOLD: int = 11
const CONSUMABLE: String = "adept_anchovy"
const RUNE: String = "aegis"

var _pools: CombatMapPools = null
var _catalog: EffectCatalog.Index = null
var _rules: CombatRewardRules = null
var _report: Callable


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_pools = CombatMapPools.load_default()
	_catalog = EffectCatalog.index()
	_rules = CombatRewardRules.load_default()
	_test_solo()
	_test_full_convoy()
	_test_coop()


# A won solo map's loot: the gold added, the consumable in the convoy and the rune in a slot, each
# with GAINED; the twin battle with nothing found differs by exactly that.
func _test_solo() -> void:
	var twin: CampaignRunState = _won_battle(1, {})
	var loot: Array = [
		{"kind": "gold", "amount": HOUSE_GOLD},
		{"kind": "consumable", MapObjects.CONTENTS_ID_KEY: CONSUMABLE},
		{"kind": "rune", MapObjects.CONTENTS_ID_KEY: RUNE},
	]
	var found: Dictionary[int, Dictionary] = {0: {0: loot}}
	var looted: CampaignRunState = _won_battle(1, found)
	var seat_run: SeatRun = null if looted == null else looted.seat_run(0)
	var base: SeatRun = null if twin == null else twin.seat_run(0)
	var gained: PackedStringArray = _gained(looted)
	var newest: String = (
			"" if seat_run == null or seat_run.convoy.is_empty()
			else seat_run.convoy[seat_run.convoy.size() - 1]
	)
	_check("BUG-039 solo: a won map's loot reaches the run", (
			seat_run != null and base != null
			and seat_run.gold == base.gold + HOUSE_GOLD
			and seat_run.convoy.size() == base.convoy.size() + 1
			and seat_run.items[newest].definition_id == CONSUMABLE
			and _runes(seat_run).has(RUNE) and not _runes(base).has(RUNE)
			and gained == PackedStringArray([CONSUMABLE, RUNE])
			and Fixture.is_whole(seat_run)
	), "gained %s" % [gained])


# A full convoy can't take a looted item: it is lost, and the gold still comes.
func _test_full_convoy() -> void:
	var loot: Array = [
		{"kind": "gold", "amount": HOUSE_GOLD},
		{"kind": "consumable", MapObjects.CONTENTS_ID_KEY: CONSUMABLE},
	]
	var twin: CampaignRunState = _won_battle(1, {}, true)
	var looted: CampaignRunState = _won_battle(1, {0: {0: loot}}, true)
	var seat_run: SeatRun = null if looted == null else looted.seat_run(0)
	var base: SeatRun = null if twin == null else twin.seat_run(0)
	_check("BUG-039 solo: a full convoy loses a looted item, not the gold", (
			seat_run != null and base != null
			and seat_run.gold == base.gold + HOUSE_GOLD
			and seat_run.convoy == base.convoy
			and _gained(looted).is_empty()
	))


# Two seats: seat 1's unit took gold on seat 0's map, which goes to seat 0; seat 1's own map
# failed, so what was found there goes to nobody.
func _test_coop() -> void:
	var on_won: Array = [{"kind": "gold", "amount": TEAMMATE_GOLD}]
	var on_failed: Array = [{"kind": "gold", "amount": HOUSE_GOLD}]
	var twin: CampaignRunState = _won_battle(2, {})
	var looted: CampaignRunState = _won_battle(2, {0: {1: on_won}, 1: {1: on_failed}})
	_check("BUG-039 co-op: loot goes to the map's owner, a failed map's to nobody", (
			looted != null and twin != null
			and looted.seat_run(0).gold == twin.seat_run(0).gold + TEAMMATE_GOLD
			and looted.seat_run(1).gold == twin.seat_run(1).gold
	))


# A new run of seat_count seats on RUN_SEED whose first Standard battle ends with seat 0's map won
# (and every other map failed), with found (by seat whose map, then by looting seat: the loot)
# put on its maps first; with is_convoy_full, seat 0's convoy is filled first. Returns the run with
# the result applied; null when the battle couldn't begin.
func _won_battle(
		seat_count: int, found: Dictionary, is_convoy_full: bool = false
) -> CampaignRunState:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	for seat: int in made.run.seat_numbers():
		made.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	if is_convoy_full:
		var seat_run: SeatRun = made.run.seat_run(0)
		while not ItemPlacement.is_convoy_full(seat_run, _catalog):
			Fixture.add_to_convoy(seat_run, CONSUMABLE, made.ids)
	var battle: CombatEncounter = _begin(made)
	if battle == null:
		made.close()
		return null
	for seat: int in found:
		var map: CombatSession = battle.session_of_seat(seat)
		var by_looter: Dictionary = found[seat]
		for looter: int in by_looter:
			var taken: Array = by_looter[looter]
			map.state.map.found[looter] = taken.duplicate(true)
	for seat: int in made.run.seat_numbers():
		_end(battle.session_of_seat(seat), PLAYER if seat == 0 else ENEMY)
	var result: CampaignSession.BattleResult = made.collect_battle()
	var next: CampaignRunState = made.run.apply_battle(
			result, made.ids, made.reward_rolls(result), _rules, _catalog
	)
	made.end_battle()
	made.close()
	return next


# Moves made's run into its first floor-1 Standard combat node and begins its battle, every
# seat's opening swap off; null when it can't.
func _begin(made: CampaignSession) -> CombatEncounter:
	var run: CampaignRunState = made.run
	for node: int in run.next_nodes():
		if run.graph.type_of(node) != CampaignGraph.NodeType.STANDARD:
			continue
		Fixture.choose(made, node)
		var request: CampaignSession.BattleRequest = run.battle_request(_pools, _catalog)
		if request == null:
			return null
		for seat: int in run.seat_numbers():
			request.opening_swap[seat] = false
		return made.begin_battle(request)
	return null


# The content ids of the GAINED facts run recorded for loot (no source effect), in order.
func _gained(run: CampaignRunState) -> PackedStringArray:
	var ids: PackedStringArray = []
	if run == null:
		return ids
	for fact: CampaignFact in run.fact_log:
		if fact.kind == CampaignFact.Kind.GAINED and fact.source_effect_id.is_empty():
			if fact.definition_id == CONSUMABLE or fact.definition_id == RUNE:
				ids.append(fact.definition_id)
	return ids


# The rune content ids in seat_run's slots.
func _runes(seat_run: SeatRun) -> PackedStringArray:
	var ids: PackedStringArray = []
	for slot: SeatRun.RuneSlot in seat_run.rune_slots:
		if not slot.is_empty():
			ids.append(slot.definition_id)
	return ids


# Ends map's combat with winner as the winning side.
func _end(map: CombatSession, winner: CombatFact.CombatSide) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	map.engine.record(ended)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
