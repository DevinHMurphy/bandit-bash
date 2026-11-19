# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_run_state.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventRunState
extends RefCounted
## A run's events: the ones seen since the pool last refilled, and the event open at a node with
## each seat's rolled options, chooser stage and choice, the team's votes and a pending surprise
## combat.
##
## Held by [member CampaignRunState.events] and changed only by the event commands
## ([OpenEventCommand], [EventChooserCommand], [EventVoteCommand], [EventOptionCommand]). Plain
## data with ids only, saved as the [code]events[/code] section ([EventSaveSection]) through
## [method capture] and [method restore]; a restore checks everything first and changes nothing
## on error. The open event stays after every seat has chosen, until the next one opens, so a
## continued run shows the same outcome.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md
## @tutorial(Save system design): docs/design/save-system.md

## [member SeatEvent.choosing], [member SeatEvent.chosen] and a vote when there is none.
const NO_OPTION: int = -1

# capture()'s keys and saved names. Never change them: saved runs are read by these names.
const _KEY_SEEN: String = "seen"
const _KEY_CURRENT: String = "current"
const _KEY_EVENT: String = "event"
const _KEY_FLOOR: String = "floor"
const _KEY_NODE: String = "node"
const _KEY_SEATS: String = "seats"
const _KEY_ROLLS: String = "rolls"
const _KEY_CHOOSING: String = "choosing"
const _KEY_CHOSEN: String = "chosen"
const _KEY_VOTES: String = "votes"
const _KEY_COMBAT: String = "combat_pending"

## Ids of the events drawn since the pool last refilled, in draw order: none of them is drawn
## again until no unseen event is eligible.
var seen: PackedStringArray = []

## Content id of the open event. [b]Empty:[/b] none has opened this run.
var event_id: String = ""

## The floor of the node the open event is at; 0 with none.
var floor_number: int = 0

## The [CampaignGraph] node the open event is at; [constant CampaignGraph.NO_NODE] with none.
var node: int = CampaignGraph.NO_NODE

## Each seat's part of the open event, by seat.
var seats: Dictionary[int, SeatEvent] = {}

## Each seat's vote in a team choice of more than one seat, by seat: an option index, set by
## [EventVoteCommand] and kept after the draw until the next event opens, so the tally still
## shows. [b]Empty:[/b] no votes.
var votes: Dictionary[int, int] = {}

## Whether the open event chose a surprise combat its node hasn't fought yet, which
## [method CampaignRunState.battle_request] begins on the Standard pool.
var is_combat_pending: bool = false


## Whether an event is open at floor [param at_floor], node [param at_node].
func is_open_at(at_floor: int, at_node: int) -> bool:
	return not event_id.is_empty() and floor_number == at_floor and node == at_node


## Whether the event at floor [param at_floor], node [param at_node] chose a surprise combat.
func is_combat_pending_at(at_floor: int, at_node: int) -> bool:
	return is_combat_pending and is_open_at(at_floor, at_node)


## [param seat]'s part of the open event; null for a seat not in it.
func seat_event(seat: int) -> SeatEvent:
	return seats.get(seat, null)


## Whether every seat of the open event has chosen; false with no event open.
func is_finished() -> bool:
	if event_id.is_empty() or seats.is_empty():
		return false
	for seat: int in seats:
		if seats[seat].chosen == NO_OPTION:
			return false
	return true


## Whether every seat of the open event has voted; false with no event open.
func has_every_vote() -> bool:
	if seats.is_empty():
		return false
	for seat: int in seats:
		if not votes.has(seat):
			return false
	return true


## The votes for each of [param option_count] options, by option index. A vote outside them
## counts for none.
func tally(option_count: int) -> PackedInt32Array:
	var counts: PackedInt32Array = []
	counts.resize(maxi(option_count, 0))
	for seat: int in votes:
		var option: int = votes[seat]
		if option >= 0 and option < counts.size():
			counts[option] += 1
	return counts


## The option a team choice's votes drew, waiting for the team's [EventOptionCommand]: every
## seat's [member SeatEvent.choosing], which a team choice uses for nothing else.
## [constant NO_OPTION] before the draw, once it applies, or when the seats disagree.
func drawn_option() -> int:
	var drawn: int = NO_OPTION
	for seat: int in seats:
		var choosing: int = seats[seat].choosing
		if choosing == NO_OPTION or (drawn != NO_OPTION and choosing != drawn):
			return NO_OPTION
		drawn = choosing
	return drawn


## Opens event [param id] at floor [param at_floor], node [param at_node] for [param seat_numbers],
## each with its [param rolls] (one [EventRolls] per option, by seat), replacing the event open
## before. Marks it seen.
func open(
		id: String,
		at_floor: int,
		at_node: int,
		seat_numbers: PackedInt32Array,
		rolls: Dictionary[int, Array]
) -> void:
	event_id = id
	floor_number = at_floor
	node = at_node
	seats = {}
	votes = {}
	is_combat_pending = false
	for seat: int in seat_numbers:
		var part: SeatEvent = SeatEvent.new()
		var seat_rolls: Array = rolls.get(seat, [])
		part.rolls.assign(seat_rolls)
		seats[seat] = part
	seen.append(id)


## This state as plain JSON, for the [code]events[/code] section. [code]current[/code] is
## [code]{}[/code] with no event open; seats and votes are keyed by seat as decimal strings.
func capture() -> Dictionary:
	var current: Dictionary = {}
	if not event_id.is_empty():
		var seat_data: Dictionary = {}
		for seat: int in seats:
			seat_data[str(seat)] = seats[seat].capture()
		var vote_data: Dictionary = {}
		for seat: int in votes:
			vote_data[str(seat)] = votes[seat]
		current = {
			_KEY_EVENT: event_id,
			_KEY_FLOOR: floor_number,
			_KEY_NODE: node,
			_KEY_SEATS: seat_data,
			_KEY_VOTES: vote_data,
			_KEY_COMBAT: is_combat_pending,
		}
	return {_KEY_SEEN: Array(seen), _KEY_CURRENT: current}


## Takes [param data], as [method capture] wrote it, numbers as whole floats too. Returns
## [constant ERR_INVALID_DATA], changing nothing, for a missing field, an empty id, a seat key or
## number that isn't whole, a choice or vote outside the seat's options, or a seat both choosing
## and chosen.
func restore(data: Dictionary) -> Error:
	var seen_data: Variant = data.get(_KEY_SEEN)
	var current: Variant = data.get(_KEY_CURRENT)
	if not seen_data is Array or not current is Dictionary:
		return _refuse(data)
	var read_seen: PackedStringArray = []
	for id: Variant in seen_data as Array:
		if not id is String or (id as String).is_empty():
			return _refuse(data)
		read_seen.append(id as String)
	var read: EventRunState = (
			EventRunState.new() if (current as Dictionary).is_empty()
			else _read_current(current as Dictionary)
	)
	if read == null:
		return _refuse(data)

	seen = read_seen
	event_id = read.event_id
	floor_number = read.floor_number
	node = read.node
	seats = read.seats
	votes = read.votes
	is_combat_pending = read.is_combat_pending
	return OK


## A copy that shares nothing with this state, through [method capture] and [method restore].
func copy() -> EventRunState:
	var copied: EventRunState = EventRunState.new()
	copied.restore(capture())
	return copied


func _refuse(data: Dictionary) -> Error:
	push_error("EventRunState: the events data is unusable - %s" % [data])
	return ERR_INVALID_DATA


# A state holding the open event current describes; null for anything unusable (see restore()).
static func _read_current(current: Dictionary) -> EventRunState:
	var id: Variant = current.get(_KEY_EVENT)
	var at_floor: Variant = CampaignRunState.whole_number(current.get(_KEY_FLOOR))
	var at_node: Variant = CampaignRunState.whole_number(current.get(_KEY_NODE))
	var seat_data: Variant = current.get(_KEY_SEATS)
	var vote_data: Variant = current.get(_KEY_VOTES)
	var pending: Variant = current.get(_KEY_COMBAT)
	if (
			not id is String or (id as String).is_empty()
			or at_floor == null or at_node == null
			or not seat_data is Dictionary or not vote_data is Dictionary
			or not pending is bool
	):
		return null
	var read: EventRunState = EventRunState.new()
	for key: Variant in seat_data as Dictionary:
		var seat: Variant = _seat_of(key)
		var entry: Variant = (seat_data as Dictionary)[key]
		var part: SeatEvent = (
				SeatEvent.restore(entry as Dictionary) if entry is Dictionary else null
		)
		if seat == null or part == null:
			return null
		read.seats[seat as int] = part
	for key: Variant in vote_data as Dictionary:
		var seat: Variant = _seat_of(key)
		var option: Variant = CampaignRunState.whole_number((vote_data as Dictionary)[key])
		if seat == null or option == null or not read.seats.has(seat as int):
			return null
		if (option as int) < 0 or (option as int) >= read.seats[seat as int].rolls.size():
			return null
		read.votes[seat as int] = option as int
	read.event_id = id as String
	read.floor_number = at_floor as int
	read.node = at_node as int
	read.is_combat_pending = pending as bool
	return read


# A seat number from its saved key, a decimal string from 0; null otherwise.
static func _seat_of(key: Variant) -> Variant:
	if not key is String or not (key as String).is_valid_int():
		return null
	var seat: int = (key as String).to_int()
	return seat if seat >= 0 else null


## One seat's part of the open event: its rolled options, the option whose chooser it has open,
## and the option it chose.
class SeatEvent:
	extends RefCounted

	## One [EventRolls] per option of the event, in option order.
	var rolls: Array[EventRolls] = []
	## The option whose unit or weapon chooser is open; in a team choice, the option the votes
	## drew ([method EventRunState.drawn_option]). [constant NO_OPTION] for none.
	var choosing: int = NO_OPTION
	## The option the seat chose and resolved; [constant NO_OPTION] before it chooses.
	var chosen: int = NO_OPTION

	## The rolls of option [param index]; empty rolls for an index it has none for.
	func rolls_of(index: int) -> EventRolls:
		if index < 0 or index >= rolls.size():
			return EventRolls.new()
		return rolls[index]

	## This part as plain JSON.
	func capture() -> Dictionary:
		var roll_data: Array = []
		for each: EventRolls in rolls:
			roll_data.append(each.capture())
		return {_KEY_ROLLS: roll_data, _KEY_CHOOSING: choosing, _KEY_CHOSEN: chosen}

	## The part [param data] describes; null for unusable data (see [method EventRunState.restore]).
	static func restore(data: Dictionary) -> SeatEvent:
		var roll_data: Variant = data.get(_KEY_ROLLS)
		var read_choosing: Variant = CampaignRunState.whole_number(data.get(_KEY_CHOOSING))
		var read_chosen: Variant = CampaignRunState.whole_number(data.get(_KEY_CHOSEN))
		if not roll_data is Array or read_choosing == null or read_chosen == null:
			return null
		var part: SeatEvent = SeatEvent.new()
		for entry: Variant in roll_data as Array:
			var each: EventRolls = (
					EventRolls.restore(entry as Dictionary) if entry is Dictionary else null
			)
			if each == null:
				return null
			part.rolls.append(each)
		var option_count: int = part.rolls.size()
		for option: int in [read_choosing as int, read_chosen as int]:
			if option < NO_OPTION or option >= option_count:
				return null
		if (read_choosing as int) != NO_OPTION and (read_chosen as int) != NO_OPTION:
			return null
		part.choosing = read_choosing as int
		part.chosen = read_chosen as int
		return part
