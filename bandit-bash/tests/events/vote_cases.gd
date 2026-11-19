# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     vote_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Team choice through the commands EventNode builds: solo and individual events take no vote; a
## vote records EVENT_VOTED, shows in the view's tally and can change until the draw; an option a
## seat can't meet can't be voted for; the last vote draws from TEAM_CHOICE and records
## TEAM_OPTION_DRAWN, after which only the drawn option applies, to every seat; 2 votes against 1
## draw 2 in 3 over many seeds; a quit and Continue mid-vote and after the draw keeps the votes
## and the draw; and a combat option is always a team choice. Touches no save files.

const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

const NO_OPTION: int = EventRunState.NO_OPTION
const PAY: int = 0
const FIGHT: int = 1
const INTIMIDATE: int = 2
const OPTION_COUNT: int = 3
const TEAM_SIZE: int = 3
const POOR_GOLD: int = 10
# The odds check: seeds drawn, and how far the drawn share may stray from the votes' share
# (about three standard deviations at 2000 draws of a 2-in-3 chance; reward_cases.gd's TOLERANCE).
const ODDS_SEEDS: int = 2000
const ODDS_TOLERANCE: float = 0.025

var _report: Callable
var _fx: Fixture = null
var _toll: EventPool = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("vote: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_toll = _fx.pool([_fx.toll()])
	_test_solo_bypasses_the_vote()
	_test_individual_event_takes_no_vote()
	_test_changing_a_vote()
	_test_every_seat_requirements()
	_test_draw_and_apply()
	_test_vote_odds()
	_test_continue_mid_vote()
	_test_combat_is_a_team_choice()


func _test_solo_bypasses_the_vote() -> void:
	var solo: CampaignSession = _fx.unknown_session()
	_fx.open(solo, _toll)
	var view: EventView = EventNode.view(solo, 0, _toll, _fx.catalog)
	var voted: CampaignBatch = _fx.vote(solo, _toll, 0, INTIMIDATE)
	_check("solo: a team choice with one seat takes no vote", (
			not view.is_team_vote and not view.is_vote_needed()
			and voted.is_rejected() and voted.rejected_reason.contains("needs no vote")
	), voted.rejected_reason)
	var chosen: CampaignBatch = _fx.choose(solo, _toll, 0, INTIMIDATE)
	_check("solo: the option is chosen directly and applies", (
			not chosen.is_rejected() and solo.run.events.is_finished()
			and solo.run.events.votes.is_empty()
			and solo.run.seat_run(0).gold == Fixture.START_GOLD + Fixture.LOOT_GOLD
			and not _fx.kinds(chosen.facts).has(CampaignFact.Kind.TEAM_OPTION_DRAWN)
	), chosen.rejected_reason)


func _test_individual_event_takes_no_vote() -> void:
	var pair: CampaignSession = _fx.unknown_session(2)
	var goblet: EventPool = _fx.pool([_fx.goblet()])
	_fx.open(pair, goblet)
	var voted: CampaignBatch = _fx.vote(pair, goblet, 0, 2)
	var view: EventView = EventNode.view(pair, 0, goblet, _fx.catalog)
	_check("individual: an individual event takes no vote", (
			voted.is_rejected() and voted.rejected_reason.contains("isn't a team choice")
			and not view.is_team_vote
	), voted.rejected_reason)


func _test_changing_a_vote() -> void:
	var team: CampaignSession = _fx.unknown_session(TEAM_SIZE)
	_fx.open(team, _toll)
	var early: CampaignBatch = _fx.choose(team, _toll, 0, FIGHT)
	_check("vote: a team choice can't be chosen before the draw", (
			early.is_rejected() and early.rejected_reason.contains("hasn't drawn")
	), early.rejected_reason)
	var outside: CampaignBatch = _fx.vote(team, _toll, 0, OPTION_COUNT)
	_check("vote: an option the event lacks can't be voted for", (
			outside.is_rejected() and outside.rejected_reason.contains("no option")
	), outside.rejected_reason)
	var first: CampaignBatch = _fx.vote(team, _toll, 0, FIGHT)
	var view: EventView = EventNode.view(team, 1, _toll, _fx.catalog)
	_check("vote: a vote records EVENT_VOTED and shows in every seat's tally", (
			not first.is_rejected() and first.facts.size() == 1
			and first.facts[0].kind == CampaignFact.Kind.EVENT_VOTED
			and first.facts[0].seat == 0 and first.facts[0].amount == FIGHT
			and first.facts[0].definition_id == Fixture.TOLL
			and view.is_vote_needed() and _vote_of(view, 0) == FIGHT
			and _counts(view) == [0, 1, 0] and view.drawn == NO_OPTION
	), first.rejected_reason)
	var changed: CampaignBatch = _fx.vote(team, _toll, 0, INTIMIDATE)
	view = EventNode.view(team, 0, _toll, _fx.catalog)
	_check("vote: a seat changes its vote before the draw; the old one no longer counts", (
			not changed.is_rejected() and team.run.events.votes.size() == 1
			and team.run.events.votes[0] == INTIMIDATE and _counts(view) == [0, 0, 1]
			and team.run.events.drawn_option() == NO_OPTION
	), changed.rejected_reason)


func _test_every_seat_requirements() -> void:
	var team: CampaignSession = _fx.unknown_session(TEAM_SIZE)
	_fx.open(team, _toll)
	team.run.seat_run(2).gold = POOR_GOLD
	var view: EventView = EventNode.view(team, 0, _toll, _fx.catalog)
	var teammate: EventView = EventNode.view(team, 1, _toll, _fx.catalog)
	_check("requirements: an option one seat can't meet is greyed out for all, naming it", (
			view.options[PAY].unmet_reason.begins_with("seat 2")
			and teammate.options[PAY].unmet_reason.begins_with("seat 2")
			and view.options[FIGHT].is_available()
	), view.options[PAY].unmet_reason)
	var paid: CampaignBatch = _fx.vote(team, _toll, 0, PAY)
	var own: CampaignBatch = _fx.vote(team, _toll, 2, PAY)
	_check("requirements: no seat can vote for it, the seat short of gold included", (
			paid.is_rejected() and paid.rejected_reason.begins_with("seat 2")
			and own.is_rejected() and own.rejected_reason.begins_with("seat 2")
			and team.run.events.votes.is_empty()
	), "%s / %s" % [paid.rejected_reason, own.rejected_reason])


func _test_draw_and_apply() -> void:
	var team: CampaignSession = _fx.unknown_session(TEAM_SIZE)
	_fx.open(team, _toll)
	_fx.vote(team, _toll, 0, INTIMIDATE)
	_fx.vote(team, _toll, 1, INTIMIDATE)
	var last: CampaignBatch = _fx.vote(team, _toll, 2, INTIMIDATE)
	var view: EventView = EventNode.view(team, 0, _toll, _fx.catalog)
	_check("draw: the last vote draws, recording TEAM_OPTION_DRAWN after its EVENT_VOTED", (
			not last.is_rejected()
			and _fx.kinds(last.facts) == [
				CampaignFact.Kind.EVENT_VOTED, CampaignFact.Kind.TEAM_OPTION_DRAWN,
			]
			and last.facts[1].seat == CampaignFact.NO_SEAT and last.facts[1].amount == INTIMIDATE
			and team.run.events.drawn_option() == INTIMIDATE
			and view.drawn == INTIMIDATE and not view.is_vote_needed()
			and view.choosing == NO_OPTION and not team.run.events.is_finished()
	), last.rejected_reason)
	var late: CampaignBatch = _fx.vote(team, _toll, 0, FIGHT)
	var other: CampaignBatch = _fx.choose(team, _toll, 1, FIGHT)
	_check("draw: votes are fixed after the draw, and only the drawn option applies", (
			late.is_rejected() and late.rejected_reason.contains("already drew")
			and other.is_rejected() and other.rejected_reason.contains("drew option 2")
			and team.run.events.votes[0] == INTIMIDATE
	), "%s / %s" % [late.rejected_reason, other.rejected_reason])
	var applied: CampaignBatch = _fx.choose(team, _toll, 1, INTIMIDATE)
	var every: bool = not applied.is_rejected() and team.run.events.is_finished()
	for seat: int in TEAM_SIZE:
		var seat_run: SeatRun = team.run.seat_run(seat)
		var curse: String = team.run.events.seat_event(seat).rolls_of(INTIMIDATE).curse_id
		every = (
				every and seat_run.heirloom_ids().has(curse)
				and seat_run.gold == Fixture.START_GOLD + Fixture.LOOT_GOLD
				and team.run.events.seat_event(seat).chosen == INTIMIDATE
		)
	view = EventNode.view(team, 2, _toll, _fx.catalog)
	_check("draw: the drawn option applies to every seat; the tally and draw still show", (
			every and view.drawn == INTIMIDATE and view.chosen == INTIMIDATE
			and _counts(view) == [0, 0, TEAM_SIZE] and view.is_finished
	), applied.rejected_reason)


func _test_vote_odds() -> void:
	var team: CampaignSession = _fx.unknown_session(TEAM_SIZE)
	_fx.open(team, _toll)
	_fx.vote(team, _toll, 0, FIGHT)
	_fx.vote(team, _toll, 1, FIGHT)
	var tallied: EventRunState = team.run.events.copy()
	tallied.votes[2] = INTIMIDATE
	var counts: PackedInt32Array = []
	counts.resize(OPTION_COUNT)
	for seed_index: int in ODDS_SEEDS:
		var drawn: int = EventVoteCommand.draw(tallied, OPTION_COUNT, _team_stream(
				seed_index, team.run
		))
		if drawn >= 0 and drawn < OPTION_COUNT:
			counts[drawn] += 1
	var fight_share: float = float(counts[FIGHT]) / float(ODDS_SEEDS)
	_check("odds: 2 votes against 1 draw the 2-vote option 2 times in 3 over many seeds", (
			absf(fight_share - 2.0 / 3.0) <= ODDS_TOLERANCE
			and counts[PAY] == 0 and counts[FIGHT] + counts[INTIMIDATE] == ODDS_SEEDS
	), "%s" % [counts])
	var expected: int = EventVoteCommand.draw(tallied, OPTION_COUNT, RngStream.new(
			RngKey.derive_seed(
					Fixture.RUN_SEED, RngKey.RngPurpose.TEAM_CHOICE,
					team.run.floor_number, team.run.node, -1, -1
			)
	))
	_fx.vote(team, _toll, 2, INTIMIDATE)
	_check("odds: the command draws from the node's shared TEAM_CHOICE stream", (
			team.run.events.drawn_option() == expected and expected != NO_OPTION
	), "%d vs %d" % [team.run.events.drawn_option(), expected])


func _test_continue_mid_vote() -> void:
	var team: CampaignSession = _fx.unknown_session(TEAM_SIZE)
	_fx.open(team, _toll)
	_fx.vote(team, _toll, 0, FIGHT)
	_fx.vote(team, _toll, 1, INTIMIDATE)
	var resumed: CampaignSession = _fx.resume(team)
	_check("continue mid-vote: the save loads", resumed != null, error_string(_fx.resume_error))
	if resumed == null:
		return
	var view: EventView = EventNode.view(resumed, 2, _toll, _fx.catalog)
	_check("continue mid-vote: every vote is kept and the vote is still open", (
			view.is_vote_needed() and view.votes.size() == 2
			and _vote_of(view, 0) == FIGHT
			and _vote_of(view, 1) == INTIMIDATE and _counts(view) == [0, 1, 1]
	))
	var changed: CampaignBatch = _fx.vote(resumed, _toll, 1, FIGHT)
	_fx.vote(team, _toll, 1, FIGHT)
	_fx.vote(team, _toll, 2, INTIMIDATE)
	var last: CampaignBatch = _fx.vote(resumed, _toll, 2, INTIMIDATE)
	_check("continue mid-vote: a vote still changes, and the draw matches the unbroken run", (
			not changed.is_rejected() and not last.is_rejected()
			and resumed.run.events.drawn_option() != NO_OPTION
			and resumed.run.events.drawn_option() == team.run.events.drawn_option()
	), "%s / %s" % [changed.rejected_reason, last.rejected_reason])
	var drawn: int = team.run.events.drawn_option()
	var again: CampaignSession = _fx.resume(resumed)
	if again == null:
		_check("continue after the draw: the save loads", false, error_string(_fx.resume_error))
		return
	var applied: CampaignBatch = _fx.choose(again, _toll, 0, drawn)
	_check("continue after the draw: the drawn option is kept and applies to every seat", (
			EventNode.view(again, 0, _toll, _fx.catalog).drawn == drawn
			and not applied.is_rejected() and again.run.events.is_finished()
	), applied.rejected_reason)


func _test_combat_is_a_team_choice() -> void:
	var lone: EventDefinition = _fx.toll()
	lone.is_team_choice = false
	var found: PackedStringArray = lone.problems()
	_check("combat: an event with a combat option that isn't a team choice is unsound", (
			_fx.toll().problems().is_empty() and found.size() == 1
			and found[0].contains("team choice")
	), str(found))
	var team: CampaignSession = _fx.unknown_session(TEAM_SIZE)
	_fx.open(team, _toll)
	var alone: CampaignBatch = _fx.choose(team, _toll, 0, FIGHT)
	for seat: int in TEAM_SIZE:
		_fx.vote(team, _toll, seat, FIGHT)
	var fought: CampaignBatch = _fx.choose(team, _toll, 0, FIGHT)
	_check("combat: one seat can't start the fight alone; the team's draw starts it for all", (
			alone.is_rejected() and team.run.events.drawn_option() == NO_OPTION
			and not fought.is_rejected() and team.run.events.is_combat_pending
			and team.run.events.is_finished()
	), "%s / %s" % [alone.rejected_reason, fought.rejected_reason])


# The view's vote count per option, in option order.
func _counts(view: EventView) -> Array[int]:
	var found: Array[int] = []
	for shown: EventView.OptionView in view.options:
		found.append(shown.vote_count)
	return found


# The view's vote of seat; NO_OPTION when it hasn't voted.
func _vote_of(view: EventView, seat: int) -> int:
	return view.votes.get(seat, NO_OPTION)


# The TEAM_CHOICE stream at run's node for a run seeded seed_index.
func _team_stream(seed_index: int, run: CampaignRunState) -> RngStream:
	return RngStream.new(RngKey.derive_seed(
			seed_index, RngKey.RngPurpose.TEAM_CHOICE, run.floor_number, run.node, -1, -1
	))


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
