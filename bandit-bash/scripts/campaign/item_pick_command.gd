# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_pick_command.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name ItemPickCommand
extends CampaignCommand
## The seat takes one offer of its [ItemPick], or skips it ([constant SKIP]), at a combat's
## results.
##
## Valid only while the run is at [constant RunFlow.Stage.RESULTS] and the seat's pick is still
## open, once per pick. Taking an offer puts a new item, with the instance id the offer was rolled
## with, at the end of the convoy and records [constant CampaignFact.Kind.GAINED]; skipping gives
## nothing. Either way the pick is resolved, so [LeaveNodeCommand] can leave the node.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-001 - Put the taken item where the player chooses: a unit's slot or the convoy, and
## a full convoy's choice (RN5). It goes to the convoy, uncapped, until then.

## [member index] for skipping the pick.
const SKIP: int = -1

## The offer taken, its index in [member ItemPick.offers]; [constant SKIP] to take none.
var index: int = SKIP


func _init(sender: int = -1, offer_index: int = SKIP) -> void:
	seat = sender
	index = offer_index


func get_label() -> String:
	return "skip item pick" if index == SKIP else "take item pick %d" % [index]


func validate(run: CampaignRunState) -> String:
	if run.flow.stage != RunFlow.Stage.RESULTS:
		return "the run isn't at a combat's results"
	var seat_run: SeatRun = run.seat_run(seat)
	var pick: ItemPick = ItemPick.pending(seat_run)
	if pick == null:
		return "seat %d has no item pick" % [seat]
	if pick.is_resolved:
		return "seat %d already took or skipped its item pick" % [seat]
	if index == SKIP:
		return ""
	if index < 0 or index >= pick.offers.size():
		return "the item pick has no offer %d" % [index]
	if seat_run.items.has(pick.offers[index].instance_id):
		return "the seat already holds %s" % [pick.offers[index].instance_id]
	return ""


func resolve(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var pick: ItemPick = ItemPick.pending(seat_run)
	pick.is_resolved = true
	pick.taken = ItemPick.NOT_TAKEN if index == SKIP else index
	pick.store(seat_run)
	if index == SKIP:
		# ASSUMPTION: a skip records no fact; nothing is gained, and CampaignFact has no kind for a
		# pick resolved without a gain.
		return
	var offer: ItemPick.Offer = pick.offers[index]
	# TODO(TOD-001): RN5's new-item placement replaces the convoy, and checks its size.
	seat_run.items[offer.instance_id] = ItemInstance.new(offer.instance_id, offer.definition_id)
	seat_run.convoy.append(offer.instance_id)
	var gained: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.GAINED, seat, offer.instance_id
	)
	gained.definition_id = offer.definition_id
	run.record(gained)
