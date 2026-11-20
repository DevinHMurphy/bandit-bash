# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     key_heirloom_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name KeyHeirloomCommand
extends CampaignCommand
## Takes a seat's heirloom from a won Key combat ([KeyHeirloom]), or gives it up
## ([member is_taking] false). Taking grants it ([method RunOperations.grant_heirloom]:
## [constant CampaignFact.Kind.GAINED]); giving it up records nothing, as a skipped item pick
## does. Valid at the combat's results while the seat's offer is open.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Whether the seat takes the heirloom; false gives it up.
var is_taking: bool = true

## Content the heirloom comes from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, taking: bool = true) -> void:
	seat = sender
	is_taking = taking


func get_label() -> String:
	return "take key heirloom" if is_taking else "give up key heirloom"


func validate(run: CampaignRunState) -> String:
	if run.flow.stage != RunFlow.Stage.RESULTS:
		return "the run isn't at a combat's results"
	var offer: KeyHeirloom = KeyHeirloom.pending(run.seat_run(seat))
	if offer == null:
		return "seat %d has no key combat heirloom" % [seat]
	if offer.is_resolved:
		return "seat %d already took or gave up its heirloom" % [seat]
	if not is_taking:
		return ""
	return RunOperations.heirloom_problem(run, seat, offer.heirloom_id, _contents())


func resolve(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var offer: KeyHeirloom = KeyHeirloom.pending(seat_run)
	offer.is_resolved = true
	offer.is_taken = is_taking
	offer.store(seat_run)
	if is_taking:
		RunOperations.grant_heirloom(run, seat, offer.heirloom_id, _contents())


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
