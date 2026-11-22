# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     route_vote_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## Co-op route votes for tests/campaign/run_all.gd ([RouteVoteCommand]), on real runs from the real
## map rules: 2-, 3- and 4-seat votes draw the pinned node from the floor's seeded ROUTE_DRAW
## stream; over many streams each node is drawn at its share of the votes; a vote records
## ROUTE_VOTED and a re-vote replaces it; the last vote enters the drawn node (NODE_CHOSEN for no
## seat); the votes stay after the draw until the next floor's first vote; every refusal changes
## nothing; a quit mid-vote and Continue keep the votes and draw the same node; solo choosing is
## unchanged.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 0x0C06
# Any seed for the starting offer left open in the refusal case.
const OFFER_SEED: int = 12

# The golden draws, by seat count: each seat's vote as an index into the run's first next nodes
# (wrapped to their count), and the index of the node the last vote draws.
const GOLDEN_VOTES: Dictionary[int, Array] = {2: [0, 1], 3: [0, 0, 1], 4: [0, 1, 1, 2]}
const GOLDEN_DRAWN: Dictionary[int, int] = {2: 1, 3: 0, 4: 1}

# Streams drawn from for the shares, and how far a share may stray from its votes' share. Units:
# draws; share (0 to 1).
const SHARE_DRAWS: int = 3000
const SHARE_TOLERANCE: float = 0.03

var _report: Callable


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_test_golden_draws()
	_test_shares()
	_test_revote_replaces()
	_test_votes_kept_until_next_floor()
	_test_refusals()
	_test_quit_mid_vote()
	_test_solo_unchanged()


# Every seat votes as GOLDEN_VOTES says: only the last vote draws, from floor 1's ROUTE_DRAW
# stream, and it draws GOLDEN_DRAWN's node.
func _test_golden_draws() -> void:
	for seat_count: int in GOLDEN_VOTES:
		var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
		var run: CampaignRunState = made.run
		var next: PackedInt32Array = run.next_nodes()
		var votes: Array = GOLDEN_VOTES[seat_count]
		var early_draws: int = 0
		var last: CampaignBatch = null
		for seat: int in seat_count:
			var node: int = next[(votes[seat] as int) % next.size()]
			last = made.submit(RouteVoteCommand.for_session(made, seat, node))
			if run.node != CampaignGraph.NO_NODE and seat < seat_count - 1:
				early_draws += 1
		var drawn: int = next.find(run.node)
		_check("golden: %d seats' votes draw the pinned node from the floor's stream" % [
			seat_count,
		], (
				early_draws == 0
				and last != null
				and Fixture.kinds(last) == [
					CampaignFact.Kind.ROUTE_VOTED, CampaignFact.Kind.NODE_CHOSEN,
				]
				and last.facts[1].seat == CampaignFact.NO_SEAT
				and last.facts[1].amount == run.node
				and drawn == GOLDEN_DRAWN[seat_count]
				and run.floor_number == 1
				and run.flow.stage == RunFlow.Stage.NODE
		), "drew index %d, %s" % [drawn, last.rejected_reason if last != null else "no batch"])


# Over many streams, 2 votes against 1 draws the first node about 2 times in 3, and 1, 2 and 1
# votes draw a quarter, a half and a quarter; a node nobody voted for is never drawn.
func _test_shares() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 4)
	var run: CampaignRunState = made.run
	var next: PackedInt32Array = run.next_nodes()
	if next.size() < 3:
		_check("shares: floor 1 has three nodes to vote for", false, str(next))
		return
	run.route_votes = {0: next[0], 1: next[0], 2: next[1]}
	var two_to_one: PackedInt32Array = _draw_counts(run, next)
	_check("shares: 2 votes against 1 draw the first node about 2 times in 3", (
			absf(two_to_one[0] / float(SHARE_DRAWS) - 2.0 / 3.0) <= SHARE_TOLERANCE
			and two_to_one[0] + two_to_one[1] == SHARE_DRAWS
	), str(two_to_one))
	run.route_votes = {0: next[0], 1: next[1], 2: next[1], 3: next[2]}
	var quarters: PackedInt32Array = _draw_counts(run, next)
	_check("shares: 1, 2 and 1 votes draw a quarter, a half and a quarter", (
			absf(quarters[0] / float(SHARE_DRAWS) - 0.25) <= SHARE_TOLERANCE
			and absf(quarters[1] / float(SHARE_DRAWS) - 0.5) <= SHARE_TOLERANCE
			and absf(quarters[2] / float(SHARE_DRAWS) - 0.25) <= SHARE_TOLERANCE
	), str(quarters))


# A seat's second vote replaces its first: one vote stands, the tally moves, nothing is drawn.
func _test_revote_replaces() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 3)
	var run: CampaignRunState = made.run
	var next: PackedInt32Array = run.next_nodes()
	var first: CampaignBatch = made.submit(RouteVoteCommand.for_session(made, 0, next[0]))
	var again: CampaignBatch = made.submit(
			RouteVoteCommand.for_session(made, 0, next[next.size() - 1])
	)
	var tally: PackedInt32Array = RouteVoteCommand.tally(run)
	_check("re-vote: a vote records ROUTE_VOTED; voting again replaces it", (
			Fixture.kinds(first) == [CampaignFact.Kind.ROUTE_VOTED]
			and first.facts[0].seat == 0
			and first.facts[0].amount == next[0]
			and Fixture.kinds(again) == [CampaignFact.Kind.ROUTE_VOTED]
			and again.facts[0].amount == next[next.size() - 1]
			and _votes_are(run.open_route_votes(), {0: next[next.size() - 1]})
			and tally[tally.size() - 1] == 1
			and _sum(tally) == 1
			and run.is_on_map()
	), "%s, tally %s" % [run.route_votes, tally])


# After the draw the votes stay, on the floor entered, though none is open; the next floor's first
# vote clears them.
func _test_votes_kept_until_next_floor() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var run: CampaignRunState = made.run
	var node: int = run.next_nodes()[0]
	Fixture.choose(made, node)
	var kept: Dictionary[int, int] = run.route_votes.duplicate()
	var open_inside: Dictionary[int, int] = run.open_route_votes()
	made.submit(LeaveNodeCommand.new(0))
	var open_on_map: Dictionary[int, int] = run.open_route_votes()
	var child: int = run.next_nodes()[0]
	made.submit(RouteVoteCommand.for_session(made, 1, child))
	_check("kept: the votes stay after their draw until the next floor's first vote", (
			_votes_are(kept, {0: node, 1: node})
			and open_inside.is_empty()
			and open_on_map.is_empty()
			and _votes_are(run.route_votes, {1: child})
			and RouteVoteCommand.tally(run)[0] == 1
	), "%s, then %s" % [kept, run.route_votes])


# Each refused vote changes nothing and records nothing.
func _test_refusals() -> void:
	var solo: CampaignSession = Fixture.session(RUN_SEED)
	var alone: CampaignBatch = solo.submit(
			RouteVoteCommand.for_session(solo, 0, solo.run.next_nodes()[0])
	)
	_check("refused: a solo run has no vote", (
			alone.is_rejected()
			and alone.rejected_reason == "a route with one seat needs no vote"
			and solo.run.route_votes.is_empty()
	), alone.rejected_reason)

	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var run: CampaignRunState = made.run
	var next: PackedInt32Array = run.next_nodes()
	var before: String = _map_text(run)
	var facts: int = run.fact_log.size()
	var unstreamed: CampaignBatch = made.submit(RouteVoteCommand.new(0, next[0]))
	var too_far: CampaignBatch = made.submit(
			RouteVoteCommand.for_session(made, 0, run.graph.nodes_on_floor(2)[0])
	)
	var no_node: CampaignBatch = made.submit(
			RouteVoteCommand.for_session(made, 0, CampaignGraph.NO_NODE)
	)
	var stranger: CampaignBatch = made.submit(RouteVoteCommand.for_session(made, 5, next[0]))
	var waiting: SeatRun = run.seat_run(1)
	StartingOffer.roll(
			RngStream.new(OFFER_SEED), waiting, EffectCatalog.index(), made.ids, false
	).store(waiting)
	var offer_open: CampaignBatch = made.submit(RouteVoteCommand.for_session(made, 0, next[0]))
	waiting.pending_offers.erase(StartingOffer.OFFER_KEY)
	_check("refused: no stream, an unreachable node, no node, a stranger, an open offer", (
			unstreamed.rejected_reason == "no route draw stream to draw from"
			and too_far.is_rejected()
			and no_node.is_rejected()
			and stranger.is_rejected()
			and offer_open.rejected_reason == "seat 1 hasn't taken its starting heirloom"
			and _map_text(run) == before
			and run.fact_log.size() == facts
	), "%s / %s / %s / %s / %s" % [
		unstreamed.rejected_reason, too_far.rejected_reason, no_node.rejected_reason,
		stranger.rejected_reason, offer_open.rejected_reason,
	])

	Fixture.choose(made, next[0])
	var inside: CampaignBatch = made.submit(RouteVoteCommand.for_session(made, 0, next[0]))
	_check("refused: no vote inside a node", (
			inside.is_rejected() and inside.rejected_reason.begins_with("the run is inside node")
	), inside.rejected_reason)


# Two of three seats vote, the run goes through JSON as a quit and Continue gives it back, and the
# third seat's vote on each draws the same node from the same stream.
func _test_quit_mid_vote() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 3)
	var next: PackedInt32Array = made.run.next_nodes()
	made.submit(RouteVoteCommand.for_session(made, 0, next[0]))
	made.submit(RouteVoteCommand.for_session(made, 1, next[next.size() - 1]))
	var copied: CampaignRunState = Fixture.through_json(made.run)
	var resumed: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, made.run.seat_numbers()
	)
	resumed.run = copied
	var kept: bool = copied != null and copied.route_votes == made.run.route_votes
	var never_quit: CampaignBatch = made.submit(RouteVoteCommand.for_session(made, 2, next[0]))
	var after_quit: CampaignBatch = (
			resumed.submit(RouteVoteCommand.for_session(resumed, 2, next[0])) if kept else null
	)
	_check("quit mid-vote: Continue keeps the votes, and the last vote draws the same node", (
			kept
			and after_quit != null
			and not never_quit.is_rejected()
			and not after_quit.is_rejected()
			and copied.node == made.run.node
			and copied.route_votes == made.run.route_votes
	), "%s / %s" % [made.run.route_votes, copied.route_votes if copied != null else null])


# A solo run still chooses directly, for its own seat, with no votes.
func _test_solo_unchanged() -> void:
	var solo: CampaignSession = Fixture.session(RUN_SEED)
	var node: int = solo.run.next_nodes()[0]
	var chosen: CampaignBatch = solo.submit(ChooseNodeCommand.new(0, node))
	_check("solo: a node is chosen directly, recording NODE_CHOSEN for the seat", (
			Fixture.kinds(chosen) == [CampaignFact.Kind.NODE_CHOSEN]
			and chosen.facts[0].seat == 0
			and chosen.facts[0].amount == node
			and solo.run.node == node
			and solo.run.route_votes.is_empty()
	), chosen.rejected_reason)


# How often each of next is drawn from run's open votes over SHARE_DRAWS streams.
func _draw_counts(run: CampaignRunState, next: PackedInt32Array) -> PackedInt32Array:
	var counts: PackedInt32Array = []
	counts.resize(next.size())
	for draw_seed: int in SHARE_DRAWS:
		var index: int = next.find(RouteVoteCommand.draw(run, RngStream.new(draw_seed)))
		if index >= 0:
			counts[index] += 1
	return counts


# Whether votes holds exactly expected's seats and nodes.
func _votes_are(votes: Dictionary[int, int], expected: Dictionary) -> bool:
	if votes.size() != expected.size():
		return false
	for seat: Variant in expected:
		if not votes.has(seat as int) or votes[seat as int] != (expected[seat] as int):
			return false
	return true


func _sum(values: PackedInt32Array) -> int:
	var total: int = 0
	for value: int in values:
		total += value
	return total


func _map_text(run: CampaignRunState) -> String:
	return JSON.stringify([run.capture_map(), run.flow.capture()])


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
