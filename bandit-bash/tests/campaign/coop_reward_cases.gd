# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_reward_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## A co-op battle's end and rewards for tests/campaign/run_all.gd, on real 2- and 3-seat runs, real
## maps and the real catalog: with a failed map, a sent unit, a swap's visitors and a fallen
## commander, each seat's COMBAT_ENDED records its own map, the run reaches its results, a failed
## seat gets no gold, XP, pick or Standout (its results show the loss) and its visitor on a won map
## earns nothing, a won seat's visitor on a failed map earns personal XP and the Standout but no
## shared XP, a sent unit's shared XP comes once, from its won map, a seat's grades count its units
## lost anywhere and a received map's speed bonus goes, while a visitor isn't received; the swaps
## lapse. Every map failed still reaches the results; a Boss won on one map is beaten and one no map
## beat isn't; solo wins and losses are unchanged.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 0x0C08
const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
# The seat whose map fails in the mixed battles.
const FAILED_SEAT: int = 1
# Tallied hits: the visitor's beat the sent unit's, so seat 0's Standout is its visitor; seat 1's
# visitor has the most of all, and still earns nothing.
const VISITOR_HITS: int = 2
const SENT_HITS: int = 1
const FAILED_VISITOR_HITS: int = 5

var _report: Callable
var _pools: CombatMapPools = null
var _catalog: EffectCatalog.Index = null
var _rules: CombatRewardRules = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_pools = CombatMapPools.load_default()
	_catalog = EffectCatalog.index()
	_rules = CombatRewardRules.load_default()
	_test_mixed_battle(2)
	_test_mixed_battle(3)
	_test_sent_unit_lost_on_partner_map()
	_test_every_map_failed()
	_test_visitor_isnt_received()
	_test_boss(true)
	_test_boss(false)
	_test_solo_unchanged(true)
	_test_solo_unchanged(false)


# Seat 0 and seat 1 swap a unit; seat 0 wins and sends a unit to the last seat's map, whose
# commander falls; seat 1's map fails. With two seats the sent unit lands on the failed map; with
# three, on seat 2's won map.
func _test_mixed_battle(seat_count: int) -> void:
	var label: String = "mixed %d seats" % [seat_count]
	var made: CampaignSession = _swapped(seat_count)
	var run: CampaignRunState = made.run
	var swap: UnitSwap = run.flow.swaps[0]
	var away: String = swap.unit_a
	var failed_visitor: String = swap.unit_b
	var battle: CombatEncounter = _begin(made)
	if battle == null:
		_check("%s: the battle begins" % [label], false)
		made.close()
		return
	var target_seat: int = seat_count - 1
	var home: CombatSession = battle.session_of_seat(0)
	var target: CombatSession = battle.session_of_seat(target_seat)
	var commander: String = target.commander_ids.get(target_seat, "")
	_end(home, PLAYER)
	var sent: String = _own_unit_on(home, 0)
	var reason: String = battle.send_unit(
			sent, home.session_id, target.session_id, target.state.tile_of(commander)
	)
	var landed: PackedStringArray = battle.deliver_arrivals(target.session_id)
	target.state.defeat(target.engine, commander, "")
	_end(battle.session_of_seat(FAILED_SEAT), ENEMY)
	for seat: int in range(FAILED_SEAT + 1, seat_count):
		_end(battle.session_of_seat(seat), PLAYER)
	var result: CampaignSession.BattleResult = made.collect_battle()
	_record(result.tally, away, BattleTally.Action.HIT, VISITOR_HITS)
	_record(result.tally, sent, BattleTally.Action.HIT, SENT_HITS)
	_record(result.tally, failed_visitor, BattleTally.Action.HIT, FAILED_VISITOR_HITS)
	var gold_before: Dictionary[int, int] = _gold_of(run)
	var next: CampaignRunState = _apply(made, result)
	made.end_battle()
	if next == null:
		_check("%s: the result applies" % [label], false)
		made.close()
		return
	var first: int = run.fact_log.size()
	made.run = next

	var ended: Dictionary[int, int] = _ended_amounts(next, first)
	var expected_ended: Dictionary[int, int] = {}
	for seat: int in seat_count:
		expected_ended[seat] = 0 if seat == FAILED_SEAT else 1
	_check("%s: each seat's COMBAT_ENDED records its own map" % [label], (
			ended == expected_ended
	), str(ended))
	_check("%s: the run reaches its results once every map has ended" % [label], (
			reason.is_empty() and landed == PackedStringArray([sent])
			and result.is_finished and not result.is_won
			and next.flow.stage == RunFlow.Stage.RESULTS
	), "%s, landed %s" % [reason, landed])

	var failed_run: SeatRun = next.seat_run(FAILED_SEAT)
	var model: CombatResultsModel = CombatResultsModel.build(made, FAILED_SEAT, _catalog, _rules)
	_check("%s: the failed seat gets no gold, XP, pick or Standout" % [label], (
			failed_run.gold == gold_before[FAILED_SEAT]
			and not failed_run.pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
			and ItemPick.pending(failed_run) == null
			and not KeyHeirloom.is_open(failed_run)
			and _leveled_seats(next, first).find(FAILED_SEAT) == -1
	), "gold %d, was %d" % [failed_run.gold, gold_before[FAILED_SEAT]])
	_check("%s: the failed seat's results show the loss" % [label], (
			model != null and model.is_lost
			and model.xp_lines.is_empty() and model.standout_name.is_empty()
			and model.pick == null and model.grades != null and model.grades.gold == 0
	))
	var winner_model: CombatResultsModel = CombatResultsModel.build(made, 0, _catalog, _rules)
	_check("%s: a won seat's results aren't lost" % [label], (
			winner_model != null and not winner_model.is_lost
			and not winner_model.xp_lines.is_empty()
	))

	var awards: Dictionary[String, XpAward] = _awards(next.seat_run(0))
	var own: XpAward = awards.get(next.seat_run(0).commander_id, null)
	var sent_award: XpAward = awards.get(sent, null)
	var away_award: XpAward = awards.get(away, null)
	var shared: int = 0 if own == null else own.shared
	_check("%s: a sent unit's shared XP comes once, from its won map" % [label], (
			shared > 0 and sent_award != null and sent_award.shared == shared
			and sent_award.personal == SENT_HITS * _rules.personal_xp_for(BattleTally.Action.HIT)
	), "own %d, sent %s" % [shared, sent_award.capture() if sent_award != null else {}])
	_check("%s: a visitor on a failed map earns personal XP and the Standout, no shared XP" % [
		label,
	], (
			away_award != null and away_award.shared == 0
			and away_award.personal == VISITOR_HITS * _rules.personal_xp_for(BattleTally.Action.HIT)
			and away_award.is_standout
	), str(away_award.capture() if away_award != null else {}))
	_check("%s: the failed seat's visitor on a won map earns nothing" % [label], (
			_award_count(next, failed_visitor) == 0
	))
	var once: bool = true
	for seat: int in seat_count:
		for unit: UnitInstance in next.seat_run(seat).army:
			once = once and _award_count(next, unit.instance_id) <= 1
	_check("%s: no unit earns XP twice" % [label], once)
	var home_report: CampaignRunState.CombatReport = CampaignRunState.read_combat_report(
			next.seat_run(0), _rules
	)
	_check("%s: the sender lost no unit, so its no-losses grade stands" % [label], (
			home_report != null and home_report.grades.is_without_losses
	))

	var target_run: SeatRun = next.seat_run(target_seat)
	var back: UnitInstance = target_run.unit(commander)
	_check("%s: the fallen commander is back at critical health" % [label], (
			back != null and target_run.army.has(back) and back.hp >= 1
			and back.hp != UnitInstance.FULL_HP and not target_run.fallen.has(back)
	))
	if target_seat != FAILED_SEAT:
		var target_report: CampaignRunState.CombatReport = CampaignRunState.read_combat_report(
				target_run, _rules
		)
		var target_awards: Dictionary[String, XpAward] = _awards(target_run)
		_check("%s: the received map's seat loses both grades, and pays no XP to others" % [
			label,
		], (
				target_report != null
				and not target_report.grades.is_under_par
				and not target_report.grades.is_without_losses
				and not target_awards.has(sent) and not target_awards.has(commander)
				and target_run.gold > gold_before[target_seat]
		))
	_check("%s: the swaps lapse" % [label], (
			next.flow.swaps.is_empty() and next.swap_proposals.is_empty()
			and next.seat_run(0).unit(away) != null
			and next.seat_run(FAILED_SEAT).unit(failed_visitor) != null
	))
	made.close()


# Seat 0 wins and sends a unit to seat 1's map, where it falls; seat 1 then wins. Seat 0's grades
# lose no-losses for a unit lost on a partner's map; seat 1's keep it.
func _test_sent_unit_lost_on_partner_map() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var battle: CombatEncounter = _begin(made)
	if battle == null:
		_check("sent and lost: the battle begins", false)
		made.close()
		return
	var home: CombatSession = battle.session_of_seat(0)
	var target: CombatSession = battle.session_of_seat(1)
	_end(home, PLAYER)
	var sent: String = _own_unit_on(home, 0)
	var commander: String = target.commander_ids.get(1, "")
	var aim: Vector2i = target.state.tile_of(commander)
	battle.send_unit(sent, home.session_id, target.session_id, aim)
	var landed: PackedStringArray = battle.deliver_arrivals(target.session_id)
	target.state.defeat(target.engine, sent, "")
	_end(target, PLAYER)
	var result: CampaignSession.BattleResult = made.collect_battle()
	var next: CampaignRunState = _apply(made, result)
	made.end_battle()
	var home_report: CampaignRunState.CombatReport = (
			null if next == null else CampaignRunState.read_combat_report(next.seat_run(0), _rules)
	)
	var target_report: CampaignRunState.CombatReport = (
			null if next == null else CampaignRunState.read_combat_report(next.seat_run(1), _rules)
	)
	_check("sent and lost: the owner's grades count its unit lost on a partner's map", (
			landed == PackedStringArray([sent])
			and home_report != null and target_report != null
			and not home_report.grades.is_without_losses
			and target_report.grades.is_without_losses
			and not target_report.grades.is_under_par
			and result.seats[0].units_lost == 1 and result.seats[1].units_lost == 0
	), "landed %s" % [landed])
	_check("sent and lost: it falls from its owner's army, in its owner's report", (
			next != null
			and next.seat_run(0).fallen.has(next.seat_run(0).unit(sent))
			and home_report != null and home_report.stats.has(sent)
			and target_report != null and not target_report.stats.has(sent)
	))
	made.close()


# Both maps fail: the run still reaches its results, with nothing for either seat.
func _test_every_map_failed() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var battle: CombatEncounter = _begin(made)
	if battle == null:
		_check("every map failed: the battle begins", false)
		made.close()
		return
	for session: CombatSession in battle.get_sessions():
		_end(session, ENEMY)
	var result: CampaignSession.BattleResult = made.collect_battle()
	var gold_before: Dictionary[int, int] = _gold_of(made.run)
	var first: int = made.run.fact_log.size()
	var next: CampaignRunState = _apply(made, result)
	made.end_battle()
	if next == null:
		_check("every map failed: the result applies", false)
		made.close()
		return
	made.run = next
	var empty: bool = true
	for seat: int in next.seat_numbers():
		var model: CombatResultsModel = CombatResultsModel.build(made, seat, _catalog, _rules)
		empty = (
				empty and model != null and model.is_lost
				and next.seat_run(seat).gold == gold_before[seat]
				and ItemPick.pending(next.seat_run(seat)) == null
		)
	_check("every map failed: the run reaches its results, every seat's empty", (
			next.flow.stage == RunFlow.Stage.RESULTS
			and _ended_amounts(next, first) == _by_seat([0, 0])
			and empty
	), str(_ended_amounts(next, first)))
	made.close()


# Both maps won with a swap in place: neither map counts its visitor as received.
func _test_visitor_isnt_received() -> void:
	var made: CampaignSession = _swapped(2)
	var battle: CombatEncounter = _begin(made)
	if battle == null:
		_check("visitor: the battle begins", false)
		made.close()
		return
	for session: CombatSession in battle.get_sessions():
		_end(session, PLAYER)
	var result: CampaignSession.BattleResult = made.collect_battle()
	_check("visitor: a swap's visitor isn't a received unit, so no speed bonus is lost", (
			not result.seats[0].has_received_units and not result.seats[1].has_received_units
	))
	made.close()


# A two-seat run at its Boss node ends with seat 0's map won and seat 1's failed (one_won), or
# both failed: the Boss is beaten when one map won it, and the run stays in the node (it is lost)
# when none did.
func _test_boss(one_won: bool) -> void:
	var label: String = "boss %s" % ["one map won" if one_won else "every map failed"]
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var run: CampaignRunState = made.run
	if not Fixture.enter(run, CampaignGraph.NodeType.BOSS):
		_check("%s: the map has a Boss node" % [label], false)
		return
	var result: CampaignSession.BattleResult = CampaignSession.BattleResult.new()
	result.floor_number = run.floor_number
	result.node = run.node
	result.is_finished = true
	for seat: int in run.seat_numbers():
		var outcome: CampaignSession.SeatOutcome = CampaignSession.SeatOutcome.new()
		outcome.seat = seat
		outcome.is_won = one_won and seat == 0
		outcome.combat_type = CombatMapDefinition.CombatType.BOSS
		result.seats[seat] = outcome
	var next: CampaignRunState = _apply(made, result)
	if one_won:
		_check("%s: the Boss is beaten, the failed seat paid nothing" % [label], (
				next != null and next.is_boss_beaten()
				and next.seat_run(0).pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
				and not next.seat_run(1).pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
		))
	else:
		_check("%s: no results, so the run is lost" % [label], (
				next != null and not next.is_boss_beaten()
				and next.flow.stage == RunFlow.Stage.NODE
		))
	made.close()


# A solo battle won reaches its results with COMBAT_ENDED 1 and a report; lost, it stays in the
# node (the run ends) with COMBAT_ENDED 0 and no report.
func _test_solo_unchanged(won: bool) -> void:
	var label: String = "solo %s" % ["won" if won else "lost"]
	var made: CampaignSession = Fixture.session(RUN_SEED)
	var battle: CombatEncounter = _begin(made)
	if battle == null:
		_check("%s: the battle begins" % [label], false)
		made.close()
		return
	_end(battle.session_of_seat(0), PLAYER if won else ENEMY)
	var first: int = made.run.fact_log.size()
	var next: CampaignRunState = _apply(made, made.collect_battle())
	made.end_battle()
	var has_report: bool = (
			next != null
			and next.seat_run(0).pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
	)
	_check("%s: unchanged" % [label], (
			next != null
			and _ended_amounts(next, first) == _by_seat([1 if won else 0])
			and has_report == won
			and (next.flow.stage == RunFlow.Stage.RESULTS) == won
	))
	made.close()


# A new run of seat_count seats on the map with seat 0's first unit swapped for seat 1's.
func _swapped(seat_count: int) -> CampaignSession:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var mine: String = _unit_of(made.run, 0)
	var theirs: String = _unit_of(made.run, 1)
	made.submit(ProposeSwapCommand.new(0, mine, 1, theirs))
	made.submit(AnswerSwapCommand.new(1, 0, true, mine, theirs))
	return made


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


func _apply(made: CampaignSession, result: CampaignSession.BattleResult) -> CampaignRunState:
	return made.run.apply_battle(result, made.ids, made.reward_rolls(result), _rules, _catalog)


# Each seat's COMBAT_ENDED amount among run's facts from index first on, by seat.
func _ended_amounts(run: CampaignRunState, first: int) -> Dictionary[int, int]:
	var amounts: Dictionary[int, int] = {}
	for fact: CampaignFact in run.fact_log.slice(first):
		if fact.kind == CampaignFact.Kind.COMBAT_ENDED:
			amounts[fact.seat] = fact.amount
	return amounts


# values by seat: the first seat 0's, and so on.
func _by_seat(values: Array[int]) -> Dictionary[int, int]:
	var by_seat: Dictionary[int, int] = {}
	for seat: int in values.size():
		by_seat[seat] = values[seat]
	return by_seat


# The seats of run's LEVELED_UP facts from index first on.
func _leveled_seats(run: CampaignRunState, first: int) -> PackedInt32Array:
	var seats: PackedInt32Array = []
	for fact: CampaignFact in run.fact_log.slice(first):
		if fact.kind == CampaignFact.Kind.LEVELED_UP:
			seats.append(fact.seat)
	return seats


func _gold_of(run: CampaignRunState) -> Dictionary[int, int]:
	var gold: Dictionary[int, int] = {}
	for seat: int in run.seat_numbers():
		gold[seat] = run.seat_run(seat).gold
	return gold


# seat_run's report's awards by unit id; empty with no report.
func _awards(seat_run: SeatRun) -> Dictionary[String, XpAward]:
	var found: Dictionary[String, XpAward] = {}
	var report: CampaignRunState.CombatReport = CampaignRunState.read_combat_report(
			seat_run, _rules
	)
	if report == null:
		return found
	for award: XpAward in report.xp:
		found[award.unit_id] = award
	return found


# How many seats' reports award unit_id.
func _award_count(run: CampaignRunState, unit_id: String) -> int:
	var count: int = 0
	for seat: int in run.seat_numbers():
		if _awards(run.seat_run(seat)).has(unit_id):
			count += 1
	return count


# Adds times of action to unit_id in tally.
func _record(tally: BattleTally, unit_id: String, action: BattleTally.Action, times: int) -> void:
	var counts: Dictionary = tally.capture().get("units", {})
	var entry: Dictionary = counts.get(unit_id, {})
	for each: BattleTally.Action in BattleTally.ACTION_IDS:
		var name: String = BattleTally.ACTION_IDS[each]
		entry[name] = (entry.get(name, 0) as int) + (times if each == action else 0)
	counts[unit_id] = entry
	tally.restore({"units": counts})


# The index-th living unit of seat's army that isn't its commander; empty when there is none.
func _unit_of(run: CampaignRunState, seat: int, index: int = 0) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	var found: int = 0
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == seat_run.commander_id:
			continue
		if found == index:
			return unit.instance_id
		found += 1
	return ""


# A player unit of seat on map that isn't its commander.
func _own_unit_on(map: CombatSession, seat: int) -> String:
	for unit_id: String in map.state.units_of(PLAYER):
		if map.state.seat_of(unit_id) == seat and map.commander_ids.get(seat, "") != unit_id:
			return unit_id
	return ""


# Ends map's combat with winner as the winning side.
func _end(map: CombatSession, winner: CombatFact.CombatSide) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	map.engine.record(ended)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
