# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     team_apply_cases.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

extends RefCounted
## A team choice's drawn option applied by each seat to its own army, through its own
## EventOptionCommand, in 2, 3 and 4 seats: Bandit Toll (data/events/) and a test team event with
## picks (the goblet made a team choice). Each apply changes only the sender's army and records
## only its facts; the view lists who still chooses; picks naming a teammate's unit or item are
## refused, changing nothing; Bandit Toll's surprise combat waits for the last seat; a quit and
## Continue between two seats' applies keeps both; solo plays as before; and an Unknown that
## rolled a shop, Treasure or combat opens no event. Touches no save files.

const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

const NO_OPTION: int = EventRunState.NO_OPTION
const TOLL_ID: String = "bandit_toll"
const TEAM_GOBLET: String = "test_team_goblet"
const FIGHT: int = 1
const INTIMIDATE: int = 2
const DRINK: int = 0
const ICE: int = 1
const SEAT_COUNTS: Array[int] = [2, 3, 4]

var _report: Callable
var _fx: Fixture = null
var _toll: EventPool = null
var _drill: EventPool = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	var toll: EventDefinition = EventPool.load_default().event(TOLL_ID)
	_check("team apply: the catalog, rules and Bandit Toll load", _fx.is_ready() and toll != null)
	if not _fx.is_ready() or toll == null:
		return
	_toll = _fx.pool([toll])
	var goblet: EventDefinition = _fx.goblet()
	goblet.id = TEAM_GOBLET
	goblet.is_team_choice = true
	_drill = _fx.pool([goblet])
	for count: int in SEAT_COUNTS:
		_test_toll_fight(count)
		_test_toll_loot(count)
		_test_picks(count)
	_test_teammate_placement()
	_test_quit_between_applies()
	_test_quit_before_the_fight()
	_test_solo_unchanged()
	_test_unknown_outcomes()


func _test_toll_fight(count: int) -> void:
	var team: CampaignSession = _team(count, _toll, FIGHT)
	var order: PackedInt32Array = _seats(count)
	order.reverse()
	var problem: String = _apply_in_turn(team, _toll, FIGHT, order, false)
	var view: EventView = EventNode.view(team, 0, _toll, _fx.catalog)
	_check("%d seats: Bandit Toll's Fight, applied by each seat, waits for the last" % [count], (
			problem.is_empty() and team.run.events.is_finished()
			and team.run.events.is_combat_pending_at(team.run.floor_number, team.run.node)
			and view.is_combat_pending and view.seats_still_choosing().is_empty()
	), problem)


func _test_toll_loot(count: int) -> void:
	var team: CampaignSession = _team(count, _toll, INTIMIDATE)
	var gold: Array[int] = []
	for seat: int in count:
		gold.append(team.run.seat_run(seat).gold)
	var problem: String = _apply_in_turn(team, _toll, INTIMIDATE, _seats(count), true)
	var every: bool = problem.is_empty() and team.run.events.is_finished()
	for seat: int in count:
		var seat_run: SeatRun = team.run.seat_run(seat)
		var curse: String = team.run.events.seat_event(seat).rolls_of(INTIMIDATE).curse_id
		every = (
				every and seat_run.gold > gold[seat] and seat_run.heirloom_ids().has(curse)
				and _fx.curses_of(Fixture.MINOR).has(curse)
		)
	_check("%d seats: Bandit Toll's Intimidate gives each seat its own loot and curse" % [count], (
			every and not team.run.events.is_combat_pending
	), problem)


func _test_picks(count: int) -> void:
	var team: CampaignSession = _team(count, _drill, DRINK)
	var refused: bool = true
	var problem: String = ""
	for seat: int in count:
		var teammate: int = (seat + 1) % count
		var theirs: UnitInstance = _fx.soldier(team.run.seat_run(teammate))
		var before: Dictionary[int, String] = _states(team.run)
		var logged: int = team.run.fact_log.size()
		var wrong: CampaignBatch = _fx.choose(
				team, _drill, seat, DRINK, EventChoice.new(theirs.instance_id)
		)
		refused = (
				refused and wrong.is_rejected()
				and wrong.rejected_reason.contains("belongs to seat %d's army" % [teammate])
				and _states(team.run) == before and team.run.fact_log.size() == logged
				and team.run.events.seat_event(seat).chosen == NO_OPTION
		)
		if not wrong.is_rejected():
			problem = "seat %d picked seat %d's unit" % [seat, teammate]
			break
		var own: UnitInstance = _fx.soldier(team.run.seat_run(seat))
		problem = _apply(team, _drill, seat, DRINK, EventChoice.new(own.instance_id), before, true)
		if not problem.is_empty():
			break
	_check("%d seats: a seat's pick of a teammate's unit is refused, naming the owner" % [count], (
			refused and problem.is_empty()
	), problem)
	_check("%d seats: each seat's pick changes only its own army" % [count], (
			problem.is_empty() and team.run.events.is_finished()
			and not team.run.events.is_combat_pending
	), problem)


func _test_teammate_placement() -> void:
	var team: CampaignSession = _team(2, _drill, ICE)
	var theirs: UnitInstance = _fx.soldier(team.run.seat_run(1))
	var picked: EventChoice = EventChoice.new()
	picked.placements[0] = ItemPlacement.new(ItemPlacement.Destination.EQUIP, theirs.instance_id)
	var before: Dictionary[int, String] = _states(team.run)
	var wrong: CampaignBatch = _fx.choose(team, _drill, 0, ICE, picked)
	var own: CampaignBatch = _fx.choose(team, _drill, 0, ICE)
	_check("teammate picks: equipping a new item on a teammate's unit is refused", (
			wrong.is_rejected() and wrong.rejected_reason.contains("belongs to seat 1's army")
			and not own.is_rejected() and _states(team.run)[1] == before[1]
	), "%s / %s" % [wrong.rejected_reason, own.rejected_reason])


func _test_quit_between_applies() -> void:
	var team: CampaignSession = _team(2, _drill, DRINK)
	var first: UnitInstance = _fx.soldier(team.run.seat_run(0))
	var applied: CampaignBatch = _fx.choose(
			team, _drill, 0, DRINK, EventChoice.new(first.instance_id)
	)
	var saved: Dictionary[int, String] = _states(team.run)
	var resumed: CampaignSession = _fx.resume(team)
	_check("quit between applies: the save loads", (
			not applied.is_rejected() and resumed != null
	), "%s / %s" % [applied.rejected_reason, error_string(_fx.resume_error)])
	if resumed == null:
		return
	var view: EventView = EventNode.view(resumed, 1, _drill, _fx.catalog)
	var again: CampaignBatch = _fx.choose(
			resumed, _drill, 0, DRINK, EventChoice.new(first.instance_id)
	)
	_check("quit between applies: seat 0's apply is kept and seat 1 still chooses the draw", (
			_states(resumed.run) == saved and view.drawn == DRINK
			and view.choices.size() == 2 and view.choices[0] == DRINK
			and view.choices[1] == NO_OPTION
			and view.seats_still_choosing() == PackedInt32Array([1]) and not view.is_finished
			and again.is_rejected() and again.rejected_reason.contains("already chose")
	), again.rejected_reason)

	var second: UnitInstance = _fx.soldier(team.run.seat_run(1))
	_fx.choose(team, _drill, 1, DRINK, EventChoice.new(second.instance_id))
	var after: CampaignBatch = _fx.choose(
			resumed, _drill, 1, DRINK, EventChoice.new(second.instance_id)
	)
	var states: Dictionary[int, String] = _states(resumed.run)
	var final: CampaignSession = _fx.resume(resumed)
	_check("quit between applies: both applies hold on Continue, as in the unbroken run", (
			not after.is_rejected() and resumed.run.events.is_finished()
			and states == _states(team.run) and states[0] == saved[0]
			and final != null and _states(final.run) == states and final.run.events.is_finished()
	), after.rejected_reason)


func _test_quit_before_the_fight() -> void:
	var team: CampaignSession = _team(2, _toll, FIGHT)
	_fx.choose(team, _toll, 1, FIGHT)
	var resumed: CampaignSession = _fx.resume(team)
	if resumed == null:
		_check("quit before the fight: the save loads", false, error_string(_fx.resume_error))
		return
	var waiting: bool = (
			not resumed.run.events.is_combat_pending
			and resumed.run.events.seat_event(1).chosen == FIGHT
	)
	var last: CampaignBatch = _fx.choose(resumed, _toll, 0, FIGHT)
	_check("quit before the fight: no combat on Continue until the last seat applies", (
			waiting and not last.is_rejected()
			and resumed.run.events.is_combat_pending_at(
					resumed.run.floor_number, resumed.run.node
			)
	), last.rejected_reason)


func _test_solo_unchanged() -> void:
	var solo: CampaignSession = _fx.unknown_session()
	_fx.open(solo, _toll)
	var fought: CampaignBatch = _fx.choose(solo, _toll, 0, FIGHT)
	_check("solo: Bandit Toll's Fight applies at once and the combat is pending", (
			not fought.is_rejected()
			and _fx.kinds(fought.facts) == [CampaignFact.Kind.EVENT_CHOSEN]
			and solo.run.events.is_finished() and solo.run.events.is_combat_pending
			and EventNode.view(solo, 0, _toll, _fx.catalog).seats_still_choosing().is_empty()
	), fought.rejected_reason)
	var alone: CampaignSession = _fx.unknown_session()
	_fx.open(alone, _drill)
	var unit: UnitInstance = _fx.soldier(alone.run.seat_run(0))
	var drank: CampaignBatch = _fx.choose(
			alone, _drill, 0, DRINK, EventChoice.new(unit.instance_id)
	)
	_check("solo: a team choice with picks is chosen directly, with no vote", (
			not drank.is_rejected() and alone.run.events.is_finished()
			and alone.run.events.votes.is_empty() and not drank.facts.is_empty()
			and drank.facts[0].kind == CampaignFact.Kind.EVENT_CHOSEN
	), drank.rejected_reason)


func _test_unknown_outcomes() -> void:
	for outcome: String in [
		UnknownResolution.COMBAT, UnknownResolution.ARMORY,
		UnknownResolution.GUILDHALL, UnknownResolution.TREASURE,
	]:
		var made: CampaignSession = _fx.unknown_session()
		made.run.flow.unknown = outcome
		var opened: CampaignBatch = _fx.open(made, _fx.pool())
		_check("BUG-025: an Unknown that became %s opens no event" % [outcome], (
				opened.is_rejected() and opened.rejected_reason.contains("became %s" % [outcome])
				and not made.run.events.is_open_at(made.run.floor_number, made.run.node)
		), opened.rejected_reason)
	var event: CampaignSession = _fx.unknown_session()
	event.run.flow.unknown = UnknownResolution.EVENT
	var drawn: CampaignBatch = _fx.open(event, _fx.pool())
	_check("BUG-025: an Unknown that became an event still opens one", (
			not drawn.is_rejected()
	), drawn.rejected_reason)


# A run of count seats in an Unknown node with events' only event open, every seat having voted
# for option, so the team drew it.
func _team(count: int, events: EventPool, option: int) -> CampaignSession:
	var team: CampaignSession = _fx.unknown_session(count)
	_fx.open(team, events)
	for seat: int in count:
		_fx.vote(team, events, seat, option)
	return team


# Each seat of order applies option with no picks; checks every apply as _apply does, and before
# the last that the team still waits with no combat pending. The first problem; empty for none.
func _apply_in_turn(
		team: CampaignSession,
		events: EventPool,
		option: int,
		order: PackedInt32Array,
		is_changing: bool
) -> String:
	if team.run.events.drawn_option() != option:
		return "the team drew %d, not %d" % [team.run.events.drawn_option(), option]
	for step: int in order.size():
		var seat: int = order[step]
		var problem: String = _apply(
				team, events, seat, option, null, _states(team.run), is_changing
		)
		if not problem.is_empty():
			return problem
		if step == order.size() - 1:
			break
		var view: EventView = EventNode.view(team, seat, events, _fx.catalog)
		var waiting: PackedInt32Array = order.slice(step + 1)
		waiting.sort()
		if view.seats_still_choosing() != waiting or view.is_finished:
			return "after seat %d: still choosing %s" % [seat, view.seats_still_choosing()]
		if team.run.events.is_combat_pending or view.is_combat_pending:
			return "after seat %d: the combat is pending early" % [seat]
	return ""


# Seat applies option with picked; the problem if it was refused, recorded a fact of another seat,
# changed another seat's part of the run from before, or (is_changing) left its own unchanged.
func _apply(
		team: CampaignSession,
		events: EventPool,
		seat: int,
		option: int,
		picked: EventChoice,
		before: Dictionary[int, String],
		is_changing: bool
) -> String:
	var batch: CampaignBatch = _fx.choose(team, events, seat, option, picked)
	if batch.is_rejected():
		return "seat %d: %s" % [seat, batch.rejected_reason]
	if batch.facts.is_empty() or batch.facts[0].kind != CampaignFact.Kind.EVENT_CHOSEN:
		return "seat %d: EVENT_CHOSEN isn't first" % [seat]
	for fact: CampaignFact in batch.facts:
		if fact.seat != seat:
			return "seat %d's apply recorded a fact of seat %d" % [seat, fact.seat]
	var after: Dictionary[int, String] = _states(team.run)
	for other: int in after:
		if other != seat and after[other] != before[other]:
			return "seat %d's apply changed seat %d" % [seat, other]
	if is_changing and after[seat] == before[seat]:
		return "seat %d's apply changed nothing of its own" % [seat]
	return ""


# Every seat's part of run (roster, heirlooms, runes, economy) as sorted JSON, by seat.
func _states(run: CampaignRunState) -> Dictionary[int, String]:
	var found: Dictionary[int, String] = {}
	for seat: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat)
		found[seat] = JSON.stringify({
			"roster": seat_run.capture_roster(),
			"heirlooms": seat_run.capture_heirlooms(),
			"runes": seat_run.capture_runes(),
			"economy": seat_run.capture_economy(),
		})
	return found


# Seats 0 to count - 1, ascending.
func _seats(count: int) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for seat: int in count:
		found.append(seat)
	return found


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
