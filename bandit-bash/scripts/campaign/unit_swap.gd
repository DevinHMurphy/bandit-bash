# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_swap.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name UnitSwap
extends RefCounted
## A co-op unit swap between two seats: each one's unit starts the next combat the team fights on
## the other's map, still owned and controlled by its seat. Seat A proposed it.
##
## Open proposals live in [member CampaignRunState.swap_proposals] (never saved); accepted swaps in
## [member RunFlow.swaps] (the [code]run_flow[/code] section). [ProposeSwapCommand],
## [AnswerSwapCommand] and [WithdrawSwapCommand] make and end them; [method end_broken] ends one
## whose unit left its army, and [method end_all] ends every one when the combat ends. Each end
## records [constant CampaignFact.Kind.SWAP_ENDED] with its reason in
## [member CampaignFact.definition_id]. At most one proposal or swap joins a pair of seats.
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

## [constant CampaignFact.Kind.SWAP_ENDED]'s reason: the partner declined the proposal.
const END_DECLINED: String = "declined"

## [constant CampaignFact.Kind.SWAP_ENDED]'s reason: one of the two seats withdrew it.
const END_WITHDRAWN: String = "withdrawn"

## [constant CampaignFact.Kind.SWAP_ENDED]'s reason: a named unit left its army or fell, or joined
## another accepted swap.
const END_UNIT_LEFT: String = "unit_left"

## [constant CampaignFact.Kind.SWAP_ENDED]'s reason: the combat it was for ended.
const END_COMBAT_ENDED: String = "combat_ended"

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_SEAT_A: String = "seat_a"
const _KEY_UNIT_A: String = "unit_a"
const _KEY_SEAT_B: String = "seat_b"
const _KEY_UNIT_B: String = "unit_b"

## The seat that proposed it.
var seat_a: int = -1

## Seat A's unit, which goes to seat B's map.
var unit_a: String = ""

## The partner seat.
var seat_b: int = -1

## Seat B's unit, which goes to seat A's map.
var unit_b: String = ""


func _init(
		first_seat: int = -1, first_unit: String = "", second_seat: int = -1,
		second_unit: String = ""
) -> void:
	seat_a = first_seat
	unit_a = first_unit
	seat_b = second_seat
	unit_b = second_unit


## Whether it joins [param one] and [param other], either way round.
func joins(one: int, other: int) -> bool:
	return (seat_a == one and seat_b == other) or (seat_a == other and seat_b == one)


## Whether it names [param unit_id].
func names_unit(unit_id: String) -> bool:
	return unit_a == unit_id or unit_b == unit_id


## A fact of [param kind] about it, in its proposer's view: seat A, its unit as the actor, seat
## B's unit as the target, seat B as the amount, and [param reason] as the definition.
func fact(kind: CampaignFact.Kind, reason: String = "") -> CampaignFact:
	var made: CampaignFact = CampaignFact.new(kind, seat_a, unit_a)
	made.target_id = unit_b
	made.amount = seat_b
	made.definition_id = reason
	return made


## It as plain JSON, for the [code]run_flow[/code] section.
func capture() -> Dictionary:
	return {_KEY_SEAT_A: seat_a, _KEY_UNIT_A: unit_a, _KEY_SEAT_B: seat_b, _KEY_UNIT_B: unit_b}


## Why no swap can be proposed, answered or withdrawn on [param run] now: one seat, or the run
## isn't on the campaign map. Empty when one can.
static func agreement_problem(run: CampaignRunState) -> String:
	if run.seats.size() < 2:
		return "a swap needs a teammate"
	if not run.is_on_map():
		return "swaps are agreed on the campaign map"
	return ""


## Why seat [param seat]'s unit [param unit_id] can't be named in a swap on [param run] now:
## not a living unit of its army, its commander, or already in an accepted swap. Empty when it
## can.
static func unit_problem(run: CampaignRunState, seat: int, unit_id: String) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if not _is_in_army(seat_run, unit_id):
		return "seat %d has no living unit %s in its army" % [seat, unit_id]
	if unit_id == seat_run.commander_id:
		return "a commander stays on its own map"
	for swap: UnitSwap in run.flow.swaps:
		if swap.names_unit(unit_id):
			return "%s is already in a swap" % [unit_id]
	return ""


## The open proposal or accepted swap joining [param one] and [param other] on [param run]; null
## when none does.
static func between(run: CampaignRunState, one: int, other: int) -> UnitSwap:
	for swap: UnitSwap in run.swap_proposals + run.flow.swaps:
		if swap.joins(one, other):
			return swap
	return null


## Ends every open proposal and accepted swap on [param run] that names a unit no longer living in
## its seat's army, recording [constant CampaignFact.Kind.SWAP_ENDED] ([constant END_UNIT_LEFT])
## for each, proposals first.
static func end_broken(run: CampaignRunState) -> void:
	for swap: UnitSwap in run.swap_proposals.duplicate():
		if not _is_whole(run, swap):
			run.swap_proposals.erase(swap)
			run.record(swap.fact(CampaignFact.Kind.SWAP_ENDED, END_UNIT_LEFT))
	for swap: UnitSwap in run.flow.swaps.duplicate():
		if not _is_whole(run, swap):
			run.flow.swaps.erase(swap)
			run.record(swap.fact(CampaignFact.Kind.SWAP_ENDED, END_UNIT_LEFT))


## Ends every accepted swap, then every open proposal, on [param run], recording
## [constant CampaignFact.Kind.SWAP_ENDED] with [param reason] for each.
static func end_all(run: CampaignRunState, reason: String) -> void:
	for swap: UnitSwap in run.flow.swaps + run.swap_proposals:
		run.record(swap.fact(CampaignFact.Kind.SWAP_ENDED, reason))
	run.flow.swaps.clear()
	run.swap_proposals.clear()


## The swap [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null for a missing or wrong field, a seat below 0, an empty unit, two equal seats or units.
static func restore(data: Variant) -> UnitSwap:
	if not data is Dictionary:
		return null
	var fields: Dictionary = data
	var first_seat: Variant = CampaignRunState.whole_number(fields.get(_KEY_SEAT_A))
	var second_seat: Variant = CampaignRunState.whole_number(fields.get(_KEY_SEAT_B))
	var first_unit: Variant = fields.get(_KEY_UNIT_A)
	var second_unit: Variant = fields.get(_KEY_UNIT_B)
	if (
			first_seat == null or second_seat == null
			or not first_unit is String or not second_unit is String
			or (first_seat as int) < 0 or (second_seat as int) < 0
			or first_seat == second_seat
			or (first_unit as String).is_empty() or (second_unit as String).is_empty()
			or first_unit == second_unit
	):
		return null
	return UnitSwap.new(
			first_seat as int, first_unit as String, second_seat as int, second_unit as String
	)


# Whether both of swap's units are still living units of their seats' armies.
static func _is_whole(run: CampaignRunState, swap: UnitSwap) -> bool:
	var first: SeatRun = run.seat_run(swap.seat_a)
	var second: SeatRun = run.seat_run(swap.seat_b)
	return (
			first != null and second != null
			and _is_in_army(first, swap.unit_a) and _is_in_army(second, swap.unit_b)
	)


# Whether unit_id is in seat_run's army: a living unit (fallen ones leave it).
static func _is_in_army(seat_run: SeatRun, unit_id: String) -> bool:
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == unit_id:
			return true
	return false
