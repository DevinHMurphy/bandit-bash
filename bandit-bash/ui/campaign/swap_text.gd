# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_text.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SwapText
extends RefCounted
## The words the co-op map shows about [UnitSwap]s, as one seat (the viewer) reads them: units
## named by their owner and type ("your Knight", "Player 2's Archer"), each swap's state, and the
## rules' refusals with the teammate named ([method refusal]). Reading only; static, never
## instantiated. Seats are named by [method CampaignLink.seat_name].
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

## What a pair of seats has between them, as [method status_of] reads it.
enum PairStatus {
	## No proposal and no swap.
	NONE = 0,
	## The viewer proposed; the teammate hasn't answered.
	PROPOSED_BY_VIEWER = 1,
	## The teammate proposed to the viewer, who hasn't answered.
	PROPOSED_TO_VIEWER = 2,
	## Both agreed: it applies to the next combat.
	ACCEPTED = 3,
}

# An instance id as the rules' reasons write one: a kind, a colon and a number.
const _ID_PATTERN: String = "[A-Za-z_]+:\\d+"

# The word before an id the rules write after "living unit": the id then reads as a type only.
const _UNIT_WORD: String = "unit "


## What lies between [param viewer] and [param partner] on [param run].
static func status_of(run: CampaignRunState, viewer: int, partner: int) -> PairStatus:
	var swap: UnitSwap = UnitSwap.between(run, viewer, partner)
	if swap == null:
		return PairStatus.NONE
	if run.flow.swaps.has(swap):
		return PairStatus.ACCEPTED
	return PairStatus.PROPOSED_BY_VIEWER if swap.seat_a == viewer else PairStatus.PROPOSED_TO_VIEWER


## Unit [param unit_id] of seat [param owner]'s type as the army shows it ("Knight"); "a unit
## that left" when the seat no longer holds it.
static func unit_title(
		run: CampaignRunState, owner: int, unit_id: String, catalog: EffectCatalog.Index
) -> String:
	var seat_run: SeatRun = run.seat_run(owner)
	var unit: UnitInstance = null if seat_run == null else seat_run.unit(unit_id)
	if unit == null:
		return "a unit that left"
	return RecruitOfferCard.title_of(unit, catalog)


## Unit [param unit_id] of seat [param owner] as [param viewer] reads it: "your Knight", or
## "Player 2's Archer".
static func unit_label(
		run: CampaignRunState,
		owner: int,
		unit_id: String,
		viewer: int,
		catalog: EffectCatalog.Index
) -> String:
	var title: String = unit_title(run, owner, unit_id, catalog)
	if owner == viewer:
		return "your %s" % [title]
	return "%s's %s" % [CampaignLink.seat_name(owner), title]


## The line of [param viewer]'s [SwapRow] for [param partner]: what the pair has and what waits.
static func row_summary(
		run: CampaignRunState, viewer: int, partner: int, catalog: EffectCatalog.Index
) -> String:
	var name: String = CampaignLink.seat_name(partner)
	var swap: UnitSwap = UnitSwap.between(run, viewer, partner)
	match status_of(run, viewer, partner):
		PairStatus.PROPOSED_BY_VIEWER:
			return "You proposed %s to %s's map and their %s to yours. Waiting for %s." % [
				unit_label(run, viewer, swap.unit_a, viewer, catalog), name,
				unit_title(run, partner, swap.unit_b, catalog), name,
			]
		PairStatus.PROPOSED_TO_VIEWER:
			return "%s proposes their %s to your map and %s to theirs." % [
				name, unit_title(run, partner, swap.unit_a, catalog),
				unit_label(run, viewer, swap.unit_b, viewer, catalog),
			]
		PairStatus.ACCEPTED:
			return "Swapped for the next combat: %s to %s's map, their %s to yours." % [
				unit_label(run, viewer, _unit_of(swap, viewer), viewer, catalog), name,
				unit_title(run, partner, _unit_of(swap, partner), catalog),
			]
	return "No swap with %s." % [name]


## The map's side-panel line for [param viewer] and [param partner]; empty when the pair has
## nothing open or agreed.
static func status_line(run: CampaignRunState, viewer: int, partner: int) -> String:
	var name: String = CampaignLink.seat_name(partner)
	match status_of(run, viewer, partner):
		PairStatus.PROPOSED_BY_VIEWER:
			return "Your swap proposal waits for %s." % [name]
		PairStatus.PROPOSED_TO_VIEWER:
			return "%s proposes a swap: open Army, then Swaps, to answer." % [name]
		PairStatus.ACCEPTED:
			return "Swap with %s for the next combat." % [name]
	return ""


## The army view's lines for [param viewer]'s accepted swaps, one each in partner order:
## "Next combat: your Knight goes to Player 2's map; their Archer comes to yours."
static func army_lines(
		run: CampaignRunState, viewer: int, catalog: EffectCatalog.Index
) -> PackedStringArray:
	var lines: PackedStringArray = []
	for partner: int in run.seat_numbers():
		if partner == viewer or status_of(run, viewer, partner) != PairStatus.ACCEPTED:
			continue
		var swap: UnitSwap = UnitSwap.between(run, viewer, partner)
		lines.append("Next combat: %s goes to %s's map; their %s comes to yours." % [
			unit_label(run, viewer, _unit_of(swap, viewer), viewer, catalog),
			CampaignLink.seat_name(partner),
			unit_title(run, partner, _unit_of(swap, partner), catalog),
		])
	return lines


## The note on [param viewer]'s unit [param unit_id] in the army view while an accepted swap names
## it ("Swap: to Player 2's map"); empty when none does.
static func unit_note(run: CampaignRunState, viewer: int, unit_id: String) -> String:
	for swap: UnitSwap in run.flow.swaps:
		if swap.seat_a == viewer and swap.unit_a == unit_id:
			return "Swap: to %s's map" % [CampaignLink.seat_name(swap.seat_b)]
		if swap.seat_b == viewer and swap.unit_b == unit_id:
			return "Swap: to %s's map" % [CampaignLink.seat_name(swap.seat_a)]
	return ""


## The [TeamPanel] note on [param teammate]'s swaps as [param viewer] reads them, one sentence
## per open proposal or accepted swap naming the teammate; empty when there is none.
static func team_note(
		run: CampaignRunState, teammate: int, viewer: int, catalog: EffectCatalog.Index
) -> String:
	var sentences: PackedStringArray = []
	for swap: UnitSwap in run.swap_proposals + run.flow.swaps:
		if swap.seat_a != teammate and swap.seat_b != teammate:
			continue
		var other: int = swap.seat_b if swap.seat_a == teammate else swap.seat_a
		var theirs: String = unit_title(run, teammate, _unit_of(swap, teammate), catalog)
		var others: String = unit_label(run, other, _unit_of(swap, other), viewer, catalog)
		if run.flow.swaps.has(swap):
			sentences.append("Swapping their %s for %s next combat." % [theirs, others])
		elif swap.seat_a == teammate:
			sentences.append("Proposed their %s for %s." % [theirs, others])
		else:
			var proposer: String = "You" if other == viewer else CampaignLink.seat_name(other)
			sentences.append("%s proposed %s for their %s." % [proposer, others, theirs])
	return " ".join(sentences)


## A refusal of [param viewer]'s swap command with [param partner] as the screen shows it:
## "Can't swap with Player 2: …", [param reason] (seats already named by [CampaignLink]) with
## each unit id as its owner and type, or its type alone after "unit ".
static func refusal(
		reason: String,
		run: CampaignRunState,
		viewer: int,
		partner: int,
		catalog: EffectCatalog.Index
) -> String:
	var pattern: RegEx = RegEx.create_from_string(_ID_PATTERN)
	var shown: String = reason
	var hits: Array[RegExMatch] = pattern.search_all(reason)
	hits.reverse()
	for hit: RegExMatch in hits:
		var owner: int = _owner_of(run, hit.get_string())
		if owner < 0:
			continue
		var start: int = hit.get_start()
		var is_after_unit: bool = (
				start >= _UNIT_WORD.length()
				and reason.substr(start - _UNIT_WORD.length(), _UNIT_WORD.length()) == _UNIT_WORD
		)
		var named: String = (
				unit_title(run, owner, hit.get_string(), catalog) if is_after_unit
				else unit_label(run, owner, hit.get_string(), viewer, catalog)
		)
		shown = shown.left(start) + named + shown.substr(hit.get_end())
	return "Can't swap with %s: %s." % [CampaignLink.seat_name(partner), shown]


# The unit seat sends in swap.
static func _unit_of(swap: UnitSwap, seat: int) -> String:
	return swap.unit_a if swap.seat_a == seat else swap.unit_b


# The seat of run holding unit_id, living or fallen; -1 for none.
static func _owner_of(run: CampaignRunState, unit_id: String) -> int:
	for seat: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat)
		if seat_run != null and seat_run.unit(unit_id) != null:
			return seat
	return -1
