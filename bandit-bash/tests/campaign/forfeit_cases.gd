# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forfeit_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## Co-op forfeits on the campaign layer for tests/campaign/run_all.gd ([ForfeitCommand]), on real
## 2- and 3-seat runs from the real map rules and catalog: at the map the seat leaves the run and
## the session, SEAT_FORFEITED first, seats keep their numbers and every section still validates;
## a route vote it completes draws; in a shop the shared stock stays as rolled; in a team choice a
## vote it completes draws, and a drawn combat everyone left applied becomes pending; its swaps and
## proposals end; a unique heirloom only it held can be offered again; a host's removal is marked;
## solo, the host and an outsider are refused; the wire form round-trips and the host fills it.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 0x0C14
const BROTHERS: String = "brothers_in_arms"
const BANDIT_TOLL: String = "bandit_toll"
# Bandit Toll's options: Pay the Toll, Fight (a surprise combat), Intimidate.
const TOLL_OPTIONS: int = 3
const TOLL_FIGHT: int = 1

var _report: Callable
var _catalog: EffectCatalog.Index = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_test_refusals()
	_test_at_the_map(2)
	_test_at_the_map(3)
	_test_route_vote_draws(2)
	_test_route_vote_draws(3)
	_test_in_a_shop()
	_test_event_vote_draws()
	_test_drawn_combat_pending()
	_test_swaps_end()
	_test_unique_heirloom_freed()
	_test_removal_marked()
	_test_wire()


# Solo, the host and a seat outside the run are refused, changing nothing.
func _test_refusals() -> void:
	var solo: CampaignSession = Fixture.session(RUN_SEED)
	var solo_batch: CampaignBatch = solo.forfeit_seat(0)
	var team: CampaignSession = Fixture.session(RUN_SEED, 2)
	var host_batch: CampaignBatch = team.forfeit_seat(CampaignData.HOST_SEAT)
	var outside_batch: CampaignBatch = team.forfeit_seat(5)
	_check("forfeit: solo, the host and an outsider are refused", (
			solo_batch.rejected_reason == "a solo run is abandoned, not forfeited"
			and host_batch.rejected_reason == "the host abandons the run instead"
			and outside_batch.rejected_reason == "seat 5 isn't in the run"
			and solo.run.seats.size() == 1
			and team.run.seats.size() == 2
			and team.seats == PackedInt32Array([0, 1])
	))
	solo.close()
	team.close()


# The last seat forfeits on the map: it leaves the run and the session, SEAT_FORFEITED first, the
# other seats keep their numbers, and every section round-trips through JSON.
func _test_at_the_map(seat_count: int) -> void:
	var label: String = "forfeit at the map, %d seats" % [seat_count]
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var leaving: int = 1
	var batch: CampaignBatch = made.forfeit_seat(leaving)
	var kept: PackedInt32Array = []
	for seat: int in seat_count:
		if seat != leaving:
			kept.append(seat)
	var events: EventRunState = EventRunState.new()
	var copied: CampaignRunState = Fixture.through_json(made.run)
	_check("%s: the seat leaves; seats keep their numbers" % [label], (
			not batch.is_rejected()
			and Fixture.kinds(batch) == [CampaignFact.Kind.SEAT_FORFEITED]
			and batch.facts[0].seat == leaving
			and batch.facts[0].amount == 0
			and made.run.seat_numbers() == kept
			and made.seats == kept
	), batch.rejected_reason)
	_check("%s: every section still validates" % [label], (
			copied != null
			and copied.seat_numbers() == kept
			and events.restore(Fixture.json(made.run.events.capture())) == OK
	))
	made.close()


# Every seat but the leaving one has voted: its forfeit completes the vote, which draws a node
# among the votes, NODE_CHOSEN for no seat, and its own vote goes.
func _test_route_vote_draws(seat_count: int) -> void:
	var label: String = "forfeit completes a route vote, %d seats" % [seat_count]
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var next: PackedInt32Array = made.run.next_nodes()
	var leaving: int = seat_count - 1
	var voted: PackedInt32Array = []
	for seat: int in seat_count:
		var node: int = next[seat % next.size()]
		made.submit(RouteVoteCommand.for_session(made, seat, node))
		if seat != leaving:
			voted.append(node)
		if seat == seat_count - 2:
			break
	var before: int = made.run.node
	var batch: CampaignBatch = made.forfeit_seat(leaving)
	_check("%s: the remaining votes draw the node" % [label], (
			before == CampaignGraph.NO_NODE
			and Fixture.kinds(batch) == [
				CampaignFact.Kind.SEAT_FORFEITED, CampaignFact.Kind.NODE_CHOSEN,
			]
			and batch.facts[1].seat == CampaignFact.NO_SEAT
			and voted.has(made.run.node)
			and made.run.flow.stage == RunFlow.Stage.NODE
			and not made.run.route_votes.has(leaving)
	), "node %d, votes %s" % [made.run.node, voted])
	made.close()


# Inside an Armory with its stock rolled, a forfeit leaves the shared stock as it was.
func _test_in_a_shop() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 3)
	var is_inside: bool = Fixture.enter(made.run, CampaignGraph.NodeType.ARMORY)
	var opened: CampaignBatch = made.submit(OpenArmoryCommand.for_session(made, _catalog))
	var stock: Dictionary = made.run.flow.capture().get("shop_stock", {})
	var stock_text: String = JSON.stringify(stock, "", true)
	var batch: CampaignBatch = made.forfeit_seat(2)
	var after: Dictionary = made.run.flow.capture().get("shop_stock", {})
	_check("forfeit in a shop: the shared stock stays as rolled", (
			is_inside
			and opened != null and not opened.is_rejected()
			and not stock.is_empty()
			and not batch.is_rejected()
			and JSON.stringify(after, "", true) == stock_text
			and made.run.seat_numbers() == PackedInt32Array([0, 1])
	))
	made.close()


# Bandit Toll open for three seats; seats 0 and 2 voted: seat 1's forfeit completes the vote,
# which draws one of their options for the two seats left, and its part of the event goes.
func _test_event_vote_draws() -> void:
	var made: CampaignSession = _toll_session(3)
	var events: EventRunState = made.run.events
	made.submit(EventNode.vote(made, 0, 0))
	made.submit(EventNode.vote(made, 2, 2))
	var undrawn: int = events.drawn_option()
	var batch: CampaignBatch = made.forfeit_seat(1)
	var drawn: int = events.drawn_option()
	var copied: EventRunState = EventRunState.new()
	_check("forfeit completes an event vote: it draws for the seats left", (
			undrawn == EventRunState.NO_OPTION
			and Fixture.kinds(batch) == [
				CampaignFact.Kind.SEAT_FORFEITED, CampaignFact.Kind.TEAM_OPTION_DRAWN,
			]
			and (drawn == 0 or drawn == 2)
			and not events.seats.has(1)
			and not events.votes.has(1)
			and copied.restore(Fixture.json(events.capture())) == OK
	), "drawn %d" % [drawn])
	made.close()


# Bandit Toll drew Fight and seat 0 applied it: seat 1's forfeit leaves everyone applied, so the
# surprise combat is pending, as the last seat's apply makes it.
func _test_drawn_combat_pending() -> void:
	var made: CampaignSession = _toll_session(2)
	var events: EventRunState = made.run.events
	for seat: int in events.seats:
		events.seats[seat].choosing = TOLL_FIGHT
	events.seats[0].choosing = EventRunState.NO_OPTION
	events.seats[0].chosen = TOLL_FIGHT
	var batch: CampaignBatch = made.forfeit_seat(1)
	_check("forfeit after a drawn Fight: the surprise combat is pending", (
			not batch.is_rejected()
			and events.is_finished()
			and events.is_combat_pending_at(made.run.floor_number, made.run.node)
	))
	made.close()


# Seat 1 has an accepted swap with seat 0 and a proposal to seat 2; seats 0 and 2 a proposal of
# their own: the forfeit ends seat 1's two ("unit_left") and keeps the other.
func _test_swaps_end() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 3)
	var run: CampaignRunState = made.run
	made.submit(ProposeSwapCommand.new(0, _unit_of(run, 0), 1, _unit_of(run, 1)))
	made.submit(AnswerSwapCommand.new(1, 0, true, _unit_of(run, 0), _unit_of(run, 1)))
	made.submit(ProposeSwapCommand.new(1, _unit_of(run, 1, 1), 2, _unit_of(run, 2)))
	made.submit(ProposeSwapCommand.new(0, _unit_of(run, 0, 1), 2, _unit_of(run, 2, 1)))
	var swaps_before: int = run.flow.swaps.size() + run.swap_proposals.size()
	var batch: CampaignBatch = made.forfeit_seat(1)
	var reasons: PackedStringArray = []
	for fact: CampaignFact in batch.facts:
		if fact.kind == CampaignFact.Kind.SWAP_ENDED:
			reasons.append(fact.definition_id)
	_check("forfeit ends the seat's swaps and proposals, and keeps the others", (
			swaps_before == 3
			and reasons == PackedStringArray([UnitSwap.END_UNIT_LEFT, UnitSwap.END_UNIT_LEFT])
			and run.flow.swaps.is_empty()
			and run.swap_proposals.size() == 1
			and run.swap_proposals[0].joins(0, 2)
	), "%d before, reasons %s" % [swaps_before, reasons])
	made.close()


# Seat 1 owns the unique Brothers in Arms: after its forfeit nobody does, so it can be offered to
# seat 0 again.
func _test_unique_heirloom_freed() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	made.run.seat_run(1).add_heirloom(BROTHERS)
	var owner_before: int = ArmoryStock.unique_owner(made.run, _catalog, BROTHERS)
	var barred: bool = UniqueClaims.owned_by_teammates(made.run, 0, _catalog).has(BROTHERS)
	made.forfeit_seat(1)
	_check("forfeit frees a unique heirloom only the seat held", (
			owner_before == 1
			and barred
			and ArmoryStock.unique_owner(made.run, _catalog, BROTHERS) == CampaignFact.NO_SEAT
			and not UniqueClaims.owned_by_teammates(made.run, 0, _catalog).has(BROTHERS)
	))
	made.close()


# The host's removal after a drop is the same leaving, its fact marked.
func _test_removal_marked() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var batch: CampaignBatch = made.forfeit_seat(1, true)
	_check("a host's removal leaves the run, its fact marked", (
			not batch.is_rejected()
			and batch.label == "remove seat 1"
			and batch.facts[0].kind == CampaignFact.Kind.SEAT_FORFEITED
			and batch.facts[0].amount == 1
			and made.run.seat_numbers() == PackedInt32Array([0])
	))
	made.close()


# The wire form carries only its sender, through JSON; the host's fill builds it with the streams
# it may draw from, and a removal never travels.
func _test_wire() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var sent: ForfeitCommand = ForfeitCommand.new(1)
	sent.is_removed = true
	var wire: Array = sent.to_wire()
	var parsed: Variant = JSON.parse_string(JSON.stringify(wire))
	var back: CampaignCommand = (
			CampaignCommand.from_wire(parsed as Array) if parsed is Array else null
	)
	var filled: CampaignCommand = HostFill.complete(back, made)
	var forfeit: ForfeitCommand = filled as ForfeitCommand
	var batch: CampaignBatch = null if filled == null else made.submit(filled)
	_check("forfeit wire: it round-trips through JSON and the host fills it", (
			wire == [ForfeitCommand.WIRE_TYPE, 1, 0]
			and back is ForfeitCommand
			and back.seat == 1
			and not (back as ForfeitCommand).is_removed
			and forfeit != null
			and forfeit.route_stream != null
			and HostFill.FILLED.has(ForfeitCommand.WIRE_TYPE)
			and batch != null and not batch.is_rejected()
			and made.run.seat_numbers() == PackedInt32Array([0])
	), str(wire))
	made.close()


# A run of seat_count seats inside a floor-1 node with Bandit Toll open for every seat, each with
# empty rolls.
func _toll_session(seat_count: int) -> CampaignSession:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var run: CampaignRunState = made.run
	Fixture.enter(run, CampaignGraph.NodeType.UNKNOWN)
	var rolls: Dictionary[int, Array] = {}
	for seat: int in run.seat_numbers():
		var seat_rolls: Array = []
		for option: int in TOLL_OPTIONS:
			seat_rolls.append(EventRolls.new())
		rolls[seat] = seat_rolls
		run.seat_run(seat).gold = 100
	run.flow.unknown = UnknownResolution.EVENT
	run.events.open(BANDIT_TOLL, run.floor_number, run.node, run.seat_numbers(), rolls)
	return made


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


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
