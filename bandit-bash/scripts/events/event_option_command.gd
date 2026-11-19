# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_option_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventOptionCommand
extends EventCommand
## The seat chooses an option of the open event, with its picks ([EventChoice]: the unit or
## weapon, item placements, a rune to discard), and it resolves through [EventResolver].
##
## An individual event resolves for the sending seat only. A team choice resolves once for every
## seat, each with its own rolls and picks ([member team_choices]), all or nothing: every seat
## must be able to take it. With more than one seat, only the option the votes drew
## ([EventVoteCommand]) can be chosen, and only after the draw. For each seat,
## [constant CampaignFact.Kind.EVENT_CHOSEN] comes before the option's own facts. A surprise
## combat marks [member EventRunState.is_combat_pending], so the node's battle begins on the
## Standard pool. Built by [method EventNode.choose].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The option chosen, its index in [member EventDefinition.options].
var option_index: int = EventRunState.NO_OPTION

## The sending seat's picks. [b]Null:[/b] nothing picked.
var choice: EventChoice = null

## The other seats' picks in a team choice, by seat. [b]Missing:[/b] nothing picked.
var team_choices: Dictionary[int, EventChoice] = {}

## Mints the instance ids of new items and runes.
var ids: InstanceIdAllocator = null

## Each seat's [code]EVENT_OUTCOME[/code] stream at the node, for draws made as the option
## applies (a prefix re-roll), by seat.
var streams: Dictionary[int, RngStream] = {}


func _init(
		sender: int = -1, option: int = EventRunState.NO_OPTION, picked: EventChoice = null
) -> void:
	seat = sender
	option_index = option
	choice = picked


func get_label() -> String:
	return "choose event option %d" % [option_index]


func validate(run: CampaignRunState) -> String:
	var problem: String = open_problem(run)
	if not problem.is_empty():
		return problem
	var event: EventDefinition = open_event(run)
	if option_index < 0 or option_index >= event.options.size():
		return "the event has no option %d" % [option_index]
	var acting: PackedInt32Array = _acting_seats(run, event)
	for seat_number: int in acting:
		problem = EventCommand.seat_problem(run, seat_number)
		if not problem.is_empty():
			return problem
	if event.is_team_choice and acting.size() > 1:
		var drawn: int = run.events.drawn_option()
		if drawn == EventRunState.NO_OPTION:
			return "the team hasn't drawn its option yet"
		if drawn != option_index:
			return "the team drew option %d, not %d" % [drawn, option_index]
	for seat_number: int in acting:
		problem = EventResolver.refusal(_context(run, event, seat_number))
		if not problem.is_empty():
			return problem if run.seats.size() < 2 else "seat %d: %s" % [seat_number, problem]
	return ""


func resolve(run: CampaignRunState) -> void:
	var event: EventDefinition = open_event(run)
	for seat_number: int in _acting_seats(run, event):
		var part: EventRunState.SeatEvent = run.events.seat_event(seat_number)
		part.choosing = EventRunState.NO_OPTION
		part.chosen = option_index
		EventCommand.record_event(run, CampaignFact.Kind.EVENT_CHOSEN, seat_number, option_index)
		var result: EventResult = EventResolver.resolve(_context(run, event, seat_number))
		if result.surprise_combat != null:
			run.events.is_combat_pending = true


# The seats the option applies to: every seat of a team choice, ascending, else the sender.
func _acting_seats(run: CampaignRunState, event: EventDefinition) -> PackedInt32Array:
	if not event.is_team_choice:
		return PackedInt32Array([seat])
	var every: PackedInt32Array = PackedInt32Array(run.events.seats.keys())
	every.sort()
	return every


func _context(run: CampaignRunState, event: EventDefinition, of_seat: int) -> EventContext:
	var picked: EventChoice = choice if of_seat == seat else team_choices.get(of_seat, null)
	var stream: RngStream = streams.get(of_seat, null)
	return EventContext.of(run, of_seat, event, option_index, catalog, ids, stream, picked)
