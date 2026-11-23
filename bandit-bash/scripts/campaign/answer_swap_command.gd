# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     answer_swap_command.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name AnswerSwapCommand
extends CampaignCommand
## In co-op, the seat answers [member proposer]'s open [UnitSwap] proposal to it. Accepting moves
## it to [member RunFlow.swaps], saved, recording [constant CampaignFact.Kind.SWAP_ACCEPTED] for
## the answering seat, then ends every other open proposal naming either unit
## ([constant UnitSwap.END_UNIT_LEFT]). Declining ends it ([constant UnitSwap.END_DECLINED]).
##
## Valid on the campaign map only, from the partner the proposal names. The answer names the two
## units its sender saw, and is refused when the proposal now names others, so it never accepts a
## swap its sender didn't see.
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the proposer, the answer, and the
## proposer's and the sender's units as seen.
const WIRE_TYPE: String = "swap_answer"

## The seat whose proposal this answers.
var proposer: int = -1

## Whether the swap is accepted; false declines it.
var is_accepting: bool = false

## The proposer's unit the sender saw in the proposal.
var proposer_unit_id: String = ""

## The sender's own unit the sender saw in the proposal.
var unit_id: String = ""


func _init(
		sender: int = -1, proposing_seat: int = -1, accepts: bool = false,
		proposer_unit: String = "", own_unit: String = ""
) -> void:
	seat = sender
	proposer = proposing_seat
	is_accepting = accepts
	proposer_unit_id = proposer_unit
	unit_id = own_unit


func get_label() -> String:
	return "%s seat %d's swap" % ["accept" if is_accepting else "decline", proposer]


func validate(run: CampaignRunState) -> String:
	var problem: String = UnitSwap.agreement_problem(run)
	if not problem.is_empty():
		return problem
	var proposal: UnitSwap = _proposal(run)
	if proposal == null:
		return "seat %d has no open proposal to seat %d" % [proposer, seat]
	if proposal.unit_a != proposer_unit_id or proposal.unit_b != unit_id:
		return "seat %d's proposal names other units now" % [proposer]
	if not is_accepting:
		return ""
	problem = UnitSwap.unit_problem(run, proposer, proposer_unit_id)
	if not problem.is_empty():
		return problem
	return UnitSwap.unit_problem(run, seat, unit_id)


func resolve(run: CampaignRunState) -> void:
	var proposal: UnitSwap = _proposal(run)
	run.swap_proposals.erase(proposal)
	if not is_accepting:
		run.record(proposal.fact(CampaignFact.Kind.SWAP_ENDED, UnitSwap.END_DECLINED))
		return
	run.flow.swaps.append(proposal)
	var accepted: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.SWAP_ACCEPTED, seat, proposal.unit_b
	)
	accepted.target_id = proposal.unit_a
	accepted.amount = proposer
	run.record(accepted)
	for other: UnitSwap in run.swap_proposals.duplicate():
		if other.names_unit(proposal.unit_a) or other.names_unit(proposal.unit_b):
			run.swap_proposals.erase(other)
			run.record(other.fact(CampaignFact.Kind.SWAP_ENDED, UnitSwap.END_UNIT_LEFT))


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [proposer, is_accepting, proposer_unit_id, unit_id]


func _read_wire_fields(values: Array) -> bool:
	if (
			values.size() != 4 or not values[1] is bool
			or not values[2] is String or not values[3] is String
	):
		return false
	var proposing_seat: Variant = _wire_at_least(values[0], _NO_INDEX)
	if proposing_seat == null:
		return false
	proposer = proposing_seat
	is_accepting = values[1]
	proposer_unit_id = values[2]
	unit_id = values[3]
	return true


# The open proposal from proposer to the sender; null when there is none.
func _proposal(run: CampaignRunState) -> UnitSwap:
	for proposal: UnitSwap in run.swap_proposals:
		if proposal.seat_a == proposer and proposal.seat_b == seat:
			return proposal
	return null
