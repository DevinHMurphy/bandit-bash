# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forfeit_command.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name ForfeitCommand
extends CampaignCommand
## In co-op, a non-host seat leaves the run for good: it forfeits, or the host removes it after a
## drop ([member is_removed]). Records [constant CampaignFact.Kind.SEAT_FORFEITED], then
## [method drop_seat], then any draw its leaving completes: a route vote ([RouteVoteCommand]'s
## draw and [constant CampaignFact.Kind.NODE_CHOSEN]) or a team choice's vote
## ([constant CampaignFact.Kind.TEAM_OPTION_DRAWN]). Seats are never renumbered. A unique heirloom
## only it held can be offered again, since [method ArmoryStock.unique_owner] reads the run's
## seats; a shop's shared stock stays as rolled. The host abandons a run instead.[br]
## [b]In a battle[/b] [method CampaignSession.submit] records only the fact and marks the seat's map
## forfeited ([method CombatEncounter.forfeit]); the battle's end drops the seat
## ([method CampaignRunState.apply_battle]). Built by [method for_session].
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): nothing but the sender travels;
## a seat forfeits only for itself.
const WIRE_TYPE: String = "forfeit"

## Whether the host removed the seat after a drop, rather than the seat forfeiting itself. The
## host's own act, so never on the wire. Recorded as the fact's [member CampaignFact.amount].
var is_removed: bool = false

## The next floor's shared [code]ROUTE_DRAW[/code] stream, for a route vote the leaving seat
## completes. Null when the run isn't on the map.
var route_stream: RngStream = null

## The node's shared [code]TEAM_CHOICE[/code] stream, for a team vote the leaving seat completes.
## Null when no event is open at the run's node.
var team_stream: RngStream = null

## The events the open one is looked up in, for its options; null when none is open.
var pool: EventPool = null


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "remove seat %d" % [seat] if is_removed else "forfeit"


func validate(run: CampaignRunState) -> String:
	if run.seats.size() < 2:
		return "a solo run is abandoned, not forfeited"
	if seat == CampaignData.HOST_SEAT:
		return "the host abandons the run instead"
	return ""


func resolve(run: CampaignRunState) -> void:
	run.record(fact_for(seat, is_removed))
	ForfeitCommand.drop_seat(run, seat)
	_draw_route(run)
	_draw_team_choice(run)


func get_wire_type() -> String:
	return WIRE_TYPE


## The forfeit of seat [param sender] on [param session]'s run, with the streams and events its
## leaving may draw from: the route's only on the map, the team choice's only with an event open at
## the node, so no stream is made that nothing draws from. Null, reported, with no run.
static func for_session(session: CampaignSession, sender: int) -> ForfeitCommand:
	if session == null or session.run == null:
		push_error("ForfeitCommand: no run to forfeit")
		return null
	var run: CampaignRunState = session.run
	var command: ForfeitCommand = ForfeitCommand.new(sender)
	if run.is_on_map():
		command.route_stream = session.rng.stream(RngKey.new(
				RngKey.RngPurpose.ROUTE_DRAW, run.floor_number + 1
		))
	if run.events.is_open_at(run.floor_number, run.node):
		command.pool = EventPool.load_default()
		command.team_stream = session.rng.stream(RngKey.new(
				RngKey.RngPurpose.TEAM_CHOICE, run.floor_number, run.node
		))
	return command


## [constant CampaignFact.Kind.SEAT_FORFEITED] for [param leaving]; [param removed] marks a host's
## removal.
static func fact_for(leaving: int, removed: bool) -> CampaignFact:
	var left: CampaignFact = CampaignFact.new(CampaignFact.Kind.SEAT_FORFEITED, leaving)
	left.amount = 1 if removed else 0
	return left


## Takes [param leaving] out of [param run], drawing nothing: its [SeatRun], its route votes, its
## part of the open event and its vote there, then every swap and proposal naming it
## ([method UnitSwap.end_broken], [constant UnitSwap.END_UNIT_LEFT]). A seat not in the run
## changes nothing.
static func drop_seat(run: CampaignRunState, leaving: int) -> void:
	if not run.seats.has(leaving):
		return
	run.seats.erase(leaving)
	run.route_votes.erase(leaving)
	run.events.seats.erase(leaving)
	run.events.votes.erase(leaving)
	# ASSUMPTION: a forfeiter's swaps end as "unit_left" (its units left with it); no new reason.
	UnitSwap.end_broken(run)


# On the map, a route vote every seat left has now cast draws the team's node, as the last vote
# does.
func _draw_route(run: CampaignRunState) -> void:
	if not run.is_on_map():
		return
	var open: Dictionary[int, int] = run.open_route_votes()
	if open.is_empty():
		return
	for seat_number: int in run.seat_numbers():
		if not open.has(seat_number):
			return
	if route_stream == null:
		push_error("ForfeitCommand: the route vote is complete, but no stream to draw from")
		return
	var drawn: int = RouteVoteCommand.draw(run, route_stream)
	if drawn == CampaignGraph.NO_NODE:
		return
	run.enter_node(drawn)
	var chosen: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_CHOSEN)
	chosen.amount = drawn
	run.record(chosen)


# In an open team choice, a vote every seat left has now cast draws the team's option, as the last
# vote does; a drawn option every seat left has now applied marks its surprise combat pending, as
# the last seat's apply does.
func _draw_team_choice(run: CampaignRunState) -> void:
	var events: EventRunState = run.events
	if not events.is_open_at(run.floor_number, run.node) or events.seats.is_empty():
		return
	var event: EventDefinition = null if pool == null else pool.event(events.event_id)
	if event == null or not event.is_team_choice:
		return
	if events.drawn_option() == EventRunState.NO_OPTION:
		if events.votes.is_empty() or not events.has_every_vote():
			return
		if team_stream == null:
			push_error("ForfeitCommand: no stream to draw the team vote from")
			return
		var drawn: int = EventVoteCommand.draw(events, event.options.size(), team_stream)
		if drawn < 0:
			return
		for seat_number: int in events.seats:
			events.seats[seat_number].choosing = drawn
		EventCommand.record_event(
				run, CampaignFact.Kind.TEAM_OPTION_DRAWN, CampaignFact.NO_SEAT, drawn
		)
		return
	var option: int = events.drawn_option()
	if (
			events.is_finished() and option < event.options.size()
			and _starts_combat(event.options[option])
	):
		events.is_combat_pending = true


# Whether option starts a surprise combat once the team has applied it.
static func _starts_combat(option: EventOption) -> bool:
	for outcome: EventOutcome in option.outcomes:
		if outcome is SurpriseCombatOutcome:
			return true
	return false
