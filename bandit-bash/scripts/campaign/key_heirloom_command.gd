# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     key_heirloom_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name KeyHeirloomCommand
extends CampaignCommand
## Takes a seat's heirloom from a won Key combat ([KeyHeirloom]), or gives it up
## ([member is_taking] false). Taking grants it ([method RunOperations.grant_heirloom]:
## [constant CampaignFact.Kind.GAINED]); giving it up records nothing, as a skipped item pick
## does. Valid at the combat's results while the seat's offer is open. A take is refused when the
## offer no longer holds [member expected_heirloom_id] (a teammate took that unique heirloom
## first) or holds a unique heirloom a teammate owns ([method UniqueClaims.take_problem]).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): whether it takes and the
## expected heirloom travel.
const WIRE_TYPE: String = "key_heirloom"

## Whether the seat takes the heirloom; false gives it up.
var is_taking: bool = true

## Content id of the heirloom the seat saw offered; a take is refused once the offer holds
## another. [b]Empty:[/b] no check.
var expected_heirloom_id: String = ""

## Content the heirloom comes from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, taking: bool = true, expected_heirloom: String = "") -> void:
	seat = sender
	is_taking = taking
	expected_heirloom_id = expected_heirloom


func get_label() -> String:
	if not is_taking:
		return "give up key heirloom"
	if expected_heirloom_id.is_empty():
		return "take key heirloom"
	return "take key heirloom, expecting %s" % [expected_heirloom_id]


func validate(run: CampaignRunState) -> String:
	if run.flow.stage != RunFlow.Stage.RESULTS:
		return "the run isn't at a combat's results"
	var offer: KeyHeirloom = KeyHeirloom.pending(run.seat_run(seat))
	if offer == null:
		return "seat %d has no key combat heirloom" % [seat]
	var contents: EffectCatalog.Index = _contents()
	# Before the resolved check: an offer settled because nothing could replace a teammate's
	# claim still names that teammate.
	if is_taking:
		var claimed: String = UniqueClaims.take_problem(
				run, seat, offer.heirloom_id, expected_heirloom_id, contents
		)
		if not claimed.is_empty():
			return claimed
	if offer.is_resolved:
		return "seat %d already took or gave up its heirloom" % [seat]
	if not is_taking:
		return ""
	return RunOperations.heirloom_problem(run, seat, offer.heirloom_id, contents)


func resolve(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var offer: KeyHeirloom = KeyHeirloom.pending(seat_run)
	offer.is_resolved = true
	offer.is_taken = is_taking
	offer.store(seat_run)
	if is_taking:
		RunOperations.grant_heirloom(run, seat, offer.heirloom_id, _contents())


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [is_taking, expected_heirloom_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 2 or not values[0] is bool or not values[1] is String:
		return false
	is_taking = values[0]
	expected_heirloom_id = values[1]
	return true


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
