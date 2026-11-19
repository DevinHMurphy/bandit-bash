# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_pick_command.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ItemPickCommand
extends CampaignCommand
## The seat takes one offer of its [ItemPick] and places it, or skips the pick ([constant SKIP]),
## at a combat's results.
##
## Valid only while the run is at [constant RunFlow.Stage.RESULTS] and the seat's pick is still
## open, once per pick. Taking an offer makes a new item, with the instance id the offer was rolled
## with, and places it by [member placement] ([method ItemPlacement.apply]), which records its
## facts; a placement [method ItemPlacement.validate] refuses rejects the whole take. Skipping
## gives nothing. Either way the pick is resolved, so [LeaveNodeCommand] can leave the node.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## [member index] for skipping the pick.
const SKIP: int = -1

## The offer taken, its index in [member ItemPick.offers]; [constant SKIP] to take none.
var index: int = SKIP

## Where a taken item goes. [b]Null:[/b] to the convoy, which a full convoy rejects. Must be null
## for a skip.
var placement: ItemPlacement = null

## The content the offers and the seat's items come from. [b]Null:[/b] the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(
		sender: int = -1, offer_index: int = SKIP, item_placement: ItemPlacement = null
) -> void:
	seat = sender
	index = offer_index
	placement = item_placement


func get_label() -> String:
	if index == SKIP:
		return "skip item pick"
	return "take item pick %d (%s)" % [index, _placement().describe()]


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
		return "" if placement == null else "a skip places nothing"
	if index < 0 or index >= pick.offers.size():
		return "the item pick has no offer %d" % [index]
	var offer: ItemPick.Offer = pick.offers[index]
	if seat_run.items.has(offer.instance_id):
		return "the seat already holds %s" % [offer.instance_id]
	var contents: EffectCatalog.Index = _contents()
	return _placement().validate(seat_run, contents.item(offer.definition_id), contents)


func resolve(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var pick: ItemPick = ItemPick.pending(seat_run)
	pick.is_resolved = true
	pick.taken = ItemPick.NOT_TAKEN if index == SKIP else index
	pick.store(seat_run)
	if index == SKIP:
		# A skip records no fact: nothing is gained, and CampaignFact has no kind for a pick
		# resolved without a gain.
		return
	var offer: ItemPick.Offer = pick.offers[index]
	_placement().apply(
			run, seat, ItemInstance.new(offer.instance_id, offer.definition_id), _contents()
	)


func _placement() -> ItemPlacement:
	return placement if placement != null else ItemPlacement.new()


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
