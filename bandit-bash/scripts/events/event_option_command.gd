# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_option_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventOptionCommand
extends EventCommand
## The seat chooses an option of the open event with its own picks ([EventChoice]: the unit or
## weapon, item placements, a rune to discard, the unit that leaves a full army and its
## hand-over), resolved for that seat alone through
## [EventResolver]: [constant CampaignFact.Kind.EVENT_CHOSEN] comes before the option's facts.
##
## A team choice of more than one seat takes only the option the votes drew ([EventVoteCommand]),
## after the draw. Each seat applies it to its own army with its own command, and the team's
## choice is done once every seat has ([method EventRunState.is_finished]). Picks naming a
## teammate's unit or item are refused. A surprise combat is marked pending
## ([member EventRunState.is_combat_pending]) only as the last seat applies, so the battle never
## begins while a teammate still chooses. Built by [method EventNode.choose].
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the option and the sender's own
## picks travel; the pool, catalog, allocator and streams are the host's.
const WIRE_TYPE: String = "event_option"

## The option chosen, its index in [member EventDefinition.options].
var option_index: int = EventRunState.NO_OPTION

## The sending seat's picks. [b]Null:[/b] nothing picked.
var choice: EventChoice = null

## Mints the instance ids of new items and runes.
var ids: InstanceIdAllocator = null

## Each seat's [code]EVENT_OUTCOME[/code] stream at the node, for draws made as the option
## applies (a prefix re-roll), by seat. Only the sender's is drawn from.
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
	problem = EventCommand.seat_problem(run, seat)
	if not problem.is_empty():
		return problem
	if event.is_team_choice and run.events.seats.size() > 1:
		var drawn: int = run.events.drawn_option()
		if drawn == EventRunState.NO_OPTION:
			return "the team hasn't drawn its option yet"
		if drawn != option_index:
			return "the team drew option %d, not %d" % [drawn, option_index]
	problem = _teammate_pick_problem(run)
	if not problem.is_empty():
		return problem
	problem = EventResolver.refusal(_context(run, event))
	if problem.is_empty() or run.seats.size() < 2:
		return problem
	return "seat %d: %s" % [seat, problem]


func resolve(run: CampaignRunState) -> void:
	var event: EventDefinition = open_event(run)
	var part: EventRunState.SeatEvent = run.events.seat_event(seat)
	part.choosing = EventRunState.NO_OPTION
	part.chosen = option_index
	EventCommand.record_event(run, CampaignFact.Kind.EVENT_CHOSEN, seat, option_index)
	var result: EventResult = EventResolver.resolve(_context(run, event))
	if result.surprise_combat != null and run.events.is_finished():
		run.events.is_combat_pending = true


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [option_index, _choice_to_wire(choice)]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 2 or not _is_choice_wire(values[1]):
		return false
	var option: Variant = _wire_at_least(values[0], EventRunState.NO_OPTION)
	if option == null:
		return false
	option_index = option
	choice = _choice_of_wire(values[1] as Array)
	return true


# The sender's context for the option, with its own picks and stream.
func _context(run: CampaignRunState, event: EventDefinition) -> EventContext:
	var stream: RngStream = streams.get(seat, null)
	return EventContext.of(run, seat, event, option_index, catalog, ids, stream, choice)


# Why the sender's picks name a teammate's army: the first unit or item id among them that
# another seat owns and the sender doesn't. Empty when none does. Instance ids are unique across
# seats, so an id both own can't happen.
func _teammate_pick_problem(run: CampaignRunState) -> String:
	if choice == null:
		return ""
	var own: SeatRun = run.seat_run(seat)
	for id: String in _picked_ids():
		if id.is_empty() or _is_owned_by(own, id):
			continue
		for other: int in run.seat_numbers():
			if other != seat and _is_owned_by(run.seat_run(other), id):
				return "%s belongs to seat %d's army, not seat %d's" % [id, other, seat]
	return ""


# Every unit and item id the sender's picks name: the chosen unit and weapon, the unit to dismiss
# and each item it hands over, and each placement's unit and convoy scrap.
func _picked_ids() -> PackedStringArray:
	var found: PackedStringArray = [choice.unit_id, choice.weapon_id, choice.replaced_id]
	found.append_array(PackedStringArray(choice.hand_over.keys()))
	for index: int in choice.placements:
		var placement: ItemPlacement = choice.placements[index]
		if placement != null:
			found.append(placement.unit_id)
			found.append(placement.convoy_scrap_id)
	return found


# Whether seat_run holds the unit (living or fallen) or the item id.
static func _is_owned_by(seat_run: SeatRun, id: String) -> bool:
	return seat_run != null and (seat_run.unit(id) != null or seat_run.items.has(id))
