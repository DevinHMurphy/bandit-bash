# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_view.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name EventView
extends RefCounted
## What the event screen shows one seat of the event open at the run's node: the event, each
## option with its rolled parts, named curse and votes, why an option is greyed out, the seat's
## chooser stage and choice, the team's vote and draw, which seats have chosen, and a pending
## surprise combat.
##
## A read-only snapshot built by [method EventNode.view] from the saved state, so a continued run
## shows exactly what was shown before the quit. It holds definitions and ids only; changing it
## changes nothing. A team choice's option is greyed out unless every seat can take it; with more
## than one seat it is voted on ([method is_vote_needed], [method EventNode.vote]), and each seat
## then applies the draw to its own army ([method seats_still_choosing]).
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The seat it shows.
var seat: int = 0

## The open event. [b]Null:[/b] none is open at the run's node, or [member problem] says why.
var event: EventDefinition = null

## Why an open event can't be shown, such as a saved id the pool lacks. [b]Empty:[/b] none.
var problem: String = ""

## Each option, in the event's order.
var options: Array[OptionView] = []

## The option whose chooser the seat has open; [constant EventRunState.NO_OPTION] for none, and
## always in a team choice, which has no chooser stage.
var choosing: int = EventRunState.NO_OPTION

## The option the seat chose; [constant EventRunState.NO_OPTION] before it chooses.
var chosen: int = EventRunState.NO_OPTION

## Whether every seat has chosen, so the node can be left (or its combat begun).
var is_finished: bool = false

## Whether the event chose a surprise combat its node hasn't fought.
var is_combat_pending: bool = false

## Whether the event is decided by the team's votes: a team choice of more than one seat.
var is_team_vote: bool = false

## Each seat's vote, by seat: an option index. [b]Empty:[/b] no votes, or no team vote.
var votes: Dictionary[int, int] = {}

## The option the team's votes drew, which each seat applies with its own [EventOptionCommand].
## [constant EventRunState.NO_OPTION] before the draw and outside a team vote.
var drawn: int = EventRunState.NO_OPTION

## Each seat's choice, by seat: the option it chose (in a team vote, applied to its own army), or
## [constant EventRunState.NO_OPTION] while it still chooses. Every seat of the event is a key.
var choices: Dictionary[int, int] = {}


## Whether an event is open to show.
func is_open() -> bool:
	return event != null


## The seats that haven't chosen yet, ascending: in a team vote, the ones the team's choice
## still waits on. Empty once [member is_finished].
func seats_still_choosing() -> PackedInt32Array:
	var waiting: PackedInt32Array = []
	for seat_number: int in choices:
		if choices[seat_number] == EventRunState.NO_OPTION:
			waiting.append(seat_number)
	waiting.sort()
	return waiting


## Whether the team still votes: a team vote whose option isn't drawn yet. Each seat may vote,
## or change its vote, until then.
func is_vote_needed() -> bool:
	return is_team_vote and drawn == EventRunState.NO_OPTION


## The view of [param of_seat] in [param run]'s open event, its definition from [param pool] and
## its reasons read with [param catalog]. Closed (no [member event]) outside a node or with no
## event open at it.
static func build(
		run: CampaignRunState, of_seat: int, pool: EventPool, catalog: EffectCatalog.Index
) -> EventView:
	var view: EventView = EventView.new()
	view.seat = of_seat
	if run == null or run.flow.stage == RunFlow.Stage.MAP:
		return view
	var state: EventRunState = run.events
	if not state.is_open_at(run.floor_number, run.node):
		return view
	var found: EventDefinition = null if pool == null else pool.event(state.event_id)
	var part: EventRunState.SeatEvent = state.seat_event(of_seat)
	if found == null or part == null or catalog == null:
		view.problem = "event \"%s\" can't be shown for seat %d" % [state.event_id, of_seat]
		return view
	view.event = found
	view.choosing = EventRunState.NO_OPTION if found.is_team_choice else part.choosing
	view.chosen = part.chosen
	view.is_finished = state.is_finished()
	view.is_combat_pending = state.is_combat_pending
	view.is_team_vote = found.is_team_choice and state.seats.size() > 1
	for seat_number: int in state.seats:
		view.choices[seat_number] = state.seats[seat_number].chosen
	var tally: PackedInt32Array = state.tally(found.options.size())
	if view.is_team_vote:
		view.votes = state.votes.duplicate()
		view.drawn = state.drawn_option()
	for index: int in found.options.size():
		var shown: OptionView = OptionView.new()
		shown.index = index
		shown.option = found.options[index]
		shown.rolls = part.rolls_of(index)
		shown.curse_id = (
				shown.option.curse_id if not shown.option.curse_id.is_empty()
				else shown.rolls.curse_id
		)
		shown.unmet_reason = _unmet(run, found, index, of_seat, catalog)
		shown.vote_count = tally[index] if view.is_team_vote else 0
		view.options.append(shown)
	return view


# Why option index is greyed out for of_seat: its own reason, or in a team choice the first
# seat's, in seat order, that can't take it.
static func _unmet(
		run: CampaignRunState,
		event: EventDefinition,
		index: int,
		of_seat: int,
		catalog: EffectCatalog.Index
) -> String:
	var checked: PackedInt32Array = PackedInt32Array([of_seat])
	if event.is_team_choice:
		checked = PackedInt32Array(run.events.seats.keys())
		checked.sort()
	for seat_number: int in checked:
		var reason: String = EventResolver.unmet_reason(
				EventContext.of(run, seat_number, event, index, catalog)
		)
		if not reason.is_empty():
			return reason if seat_number == of_seat else "seat %d %s" % [seat_number, reason]
	return ""


## One option as the screen shows it.
class OptionView:
	extends RefCounted

	## Its index in the event's options.
	var index: int = 0
	## Its definition: title, text, requirements, blocks.
	var option: EventOption = null
	## The seat's rolled parts: each block's drawn item, rune or heirloom by block index.
	var rolls: EventRolls = EventRolls.new()
	## Content id of the curse it gives, named or drawn; empty for none.
	var curse_id: String = ""
	## Why it is greyed out; empty when it can be chosen.
	var unmet_reason: String = ""
	## The seats that voted for it in a team vote; 0 outside one.
	var vote_count: int = 0

	## Whether it can be chosen.
	func is_available() -> bool:
		return unmet_reason.is_empty()

	## What the player picks after choosing it.
	func chooser() -> EventOutcome.Chooser:
		return option.chooser()
