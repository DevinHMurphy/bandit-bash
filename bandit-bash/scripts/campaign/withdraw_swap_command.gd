# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     withdraw_swap_command.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name WithdrawSwapCommand
extends CampaignCommand
## In co-op, the seat withdraws the open proposal or the accepted [UnitSwap] joining it and
## [member partner], whichever seat proposed it, recording [constant CampaignFact.Kind.SWAP_ENDED]
## ([constant UnitSwap.END_WITHDRAWN]). Valid on the campaign map only: once the team is inside a
## node, the swap stands for the combat.
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the partner seat.
const WIRE_TYPE: String = "swap_withdraw"

## The other seat of the proposal or swap.
var partner: int = -1


func _init(sender: int = -1, partner_seat: int = -1) -> void:
	seat = sender
	partner = partner_seat


func get_label() -> String:
	return "withdraw the swap with seat %d" % [partner]


func validate(run: CampaignRunState) -> String:
	var problem: String = UnitSwap.agreement_problem(run)
	if not problem.is_empty():
		return problem
	if partner == seat or UnitSwap.between(run, seat, partner) == null:
		return "seat %d has no swap or proposal with seat %d" % [seat, partner]
	return ""


func resolve(run: CampaignRunState) -> void:
	var swap: UnitSwap = UnitSwap.between(run, seat, partner)
	run.swap_proposals.erase(swap)
	run.flow.swaps.erase(swap)
	run.record(swap.fact(CampaignFact.Kind.SWAP_ENDED, UnitSwap.END_WITHDRAWN))


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [partner]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1:
		return false
	var partner_seat: Variant = _wire_at_least(values[0], _NO_INDEX)
	if partner_seat == null:
		return false
	partner = partner_seat
	return true
