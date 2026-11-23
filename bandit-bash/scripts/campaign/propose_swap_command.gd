# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     propose_swap_command.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name ProposeSwapCommand
extends CampaignCommand
## In co-op, the seat proposes a [UnitSwap] to [member partner]: its [member unit_id] to the
## partner's map and the partner's [member partner_unit_id] to its own, for the next combat the
## team fights. Records [constant CampaignFact.Kind.SWAP_PROPOSED]; the proposal waits in
## [member CampaignRunState.swap_proposals], unsaved, for [AnswerSwapCommand].
##
## Valid on the campaign map only, for two living non-commander units of the two seats, neither in
## an accepted swap, when no proposal or swap joins the pair yet. A unit may be in several open
## proposals; accepting one ends the others naming its units.
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the sender's unit, the partner
## seat, the partner's unit.
const WIRE_TYPE: String = "swap_propose"

## The sender's unit, which would go to the partner's map.
var unit_id: String = ""

## The partner seat.
var partner: int = -1

## The partner's unit, which would come to the sender's map.
var partner_unit_id: String = ""


func _init(
		sender: int = -1, own_unit: String = "", partner_seat: int = -1,
		partner_unit: String = ""
) -> void:
	seat = sender
	unit_id = own_unit
	partner = partner_seat
	partner_unit_id = partner_unit


func get_label() -> String:
	return "propose swap %s for seat %d's %s" % [unit_id, partner, partner_unit_id]


func validate(run: CampaignRunState) -> String:
	var problem: String = UnitSwap.agreement_problem(run)
	if not problem.is_empty():
		return problem
	if partner == seat:
		return "a swap is with a teammate"
	if run.seat_run(partner) == null:
		return "seat %d isn't in the run" % [partner]
	if UnitSwap.between(run, seat, partner) != null:
		return "seat %d and seat %d already have a swap or a proposal" % [seat, partner]
	problem = UnitSwap.unit_problem(run, seat, unit_id)
	if not problem.is_empty():
		return problem
	return UnitSwap.unit_problem(run, partner, partner_unit_id)


func resolve(run: CampaignRunState) -> void:
	var proposal: UnitSwap = UnitSwap.new(seat, unit_id, partner, partner_unit_id)
	run.swap_proposals.append(proposal)
	run.record(proposal.fact(CampaignFact.Kind.SWAP_PROPOSED))


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [unit_id, partner, partner_unit_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 3 or not values[0] is String or not values[2] is String:
		return false
	var partner_seat: Variant = _wire_at_least(values[1], _NO_INDEX)
	if partner_seat == null:
		return false
	unit_id = values[0]
	partner = partner_seat
	partner_unit_id = values[2]
	return true
