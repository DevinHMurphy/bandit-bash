# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_vote_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventVoteCommand
extends EventCommand
## The seat votes for an option of the open team-choice event, replacing its own earlier vote,
## recording [constant CampaignFact.Kind.EVENT_VOTED]. The vote that completes the set draws the
## team's option ([method draw]) and records [constant CampaignFact.Kind.TEAM_OPTION_DRAWN];
## the team's [EventOptionCommand] then applies it to every seat, with each seat's picks.
##
## Only a team choice of more than one seat is voted on: with one seat, [EventOptionCommand]
## chooses directly. An option is voted for only if every seat can take it. Votes change until
## the draw and are fixed after it. Saved like every command, so a quit mid-vote keeps them.
## Built by [method EventNode.vote].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The option voted for, its index in [member EventDefinition.options].
var option_index: int = EventRunState.NO_OPTION

## The node's shared [code]TEAM_CHOICE[/code] stream, drawn from once by the vote that completes
## the set.
var draw_stream: RngStream = null


func _init(sender: int = -1, option: int = EventRunState.NO_OPTION) -> void:
	seat = sender
	option_index = option


func get_label() -> String:
	return "vote for event option %d" % [option_index]


func validate(run: CampaignRunState) -> String:
	var problem: String = open_problem(run)
	if problem.is_empty():
		problem = EventCommand.seat_problem(run, seat)
	if not problem.is_empty():
		return problem
	var event: EventDefinition = open_event(run)
	var events: EventRunState = run.events
	if not event.is_team_choice:
		return "\"%s\" isn't a team choice" % [event.title]
	if events.seats.size() < 2:
		return "a team choice with one seat needs no vote"
	if events.drawn_option() != EventRunState.NO_OPTION:
		return "the team already drew option %d" % [events.drawn_option()]
	if option_index < 0 or option_index >= event.options.size():
		return "the event has no option %d" % [option_index]
	if draw_stream == null:
		return "no team choice stream to draw from"
	var every: PackedInt32Array = PackedInt32Array(events.seats.keys())
	every.sort()
	for seat_number: int in every:
		var unmet: String = EventResolver.unmet_reason(
				EventContext.of(run, seat_number, event, option_index, catalog)
		)
		if not unmet.is_empty():
			return "seat %d: %s" % [seat_number, unmet]
	return ""


func resolve(run: CampaignRunState) -> void:
	var events: EventRunState = run.events
	events.votes[seat] = option_index
	EventCommand.record_event(run, CampaignFact.Kind.EVENT_VOTED, seat, option_index)
	if not events.has_every_vote():
		return
	var drawn: int = EventVoteCommand.draw(events, open_event(run).options.size(), draw_stream)
	for seat_number: int in events.seats:
		events.seats[seat_number].choosing = drawn
	EventCommand.record_event(
			run, CampaignFact.Kind.TEAM_OPTION_DRAWN, CampaignFact.NO_SEAT, drawn
	)


## The option [param events]' votes draw among [param option_count] options, from
## [param stream] with one weighted roll: each option's chance is its share of the votes, so 2
## votes against 1 is a 2-in-3 chance. -1, reported and without drawing, with no vote among them.
static func draw(events: EventRunState, option_count: int, stream: RngStream) -> int:
	return stream.pick_weighted(events.tally(option_count))
