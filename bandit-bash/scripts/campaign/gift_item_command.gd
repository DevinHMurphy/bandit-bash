# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     gift_item_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name GiftItemCommand
extends CampaignCommand
## Co-op gifting (unit-roster.md, Recruiting and item transfer: "convoy-to-convoy at any Camp or
## shop, where the whole team is together"): a seat gives one of its convoy items to another
## seat's convoy, keeping its instance id and state. Valid inside a Camp, an Armory or a
## Guildhall; refused when the receiving convoy is full ([method ItemPlacement.is_convoy_full]).
## Records [constant CampaignFact.Kind.ITEM_GIFTED].
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Instance id of the giver's convoy item.
var item_id: String = ""

## The seat receiving it.
var to_seat: int = -1

## Content the seats' heirlooms come from (convoy sizes); null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, item: String = "", receiver: int = -1) -> void:
	seat = sender
	item_id = item
	to_seat = receiver


func get_label() -> String:
	return "gift %s to seat %d" % [item_id, to_seat]


func validate(run: CampaignRunState) -> String:
	if (
			not Camp.is_at_camp(run) and not Armory.is_at_armory(run)
			and not Guildhall.is_at_guildhall(run)
	):
		return "items are given only at a Camp, an Armory or a Guildhall"
	var giver: SeatRun = run.seat_run(seat)
	var receiver: SeatRun = run.seat_run(to_seat)
	if receiver == null or to_seat == seat:
		return "seat %d can't receive a gift from seat %d" % [to_seat, seat]
	if not giver.convoy.has(item_id):
		return "seat %d's convoy holds no %s" % [seat, item_id]
	if receiver.items.has(item_id):
		return "seat %d already holds %s" % [to_seat, item_id]
	var contents: EffectCatalog.Index = _contents()
	if ItemPlacement.is_convoy_full(receiver, contents):
		return "seat %d's convoy is full (%d of %d)" % [
			to_seat, receiver.convoy.size(), ItemPlacement.convoy_capacity(receiver, contents),
		]
	return ""


func resolve(run: CampaignRunState) -> void:
	var giver: SeatRun = run.seat_run(seat)
	var receiver: SeatRun = run.seat_run(to_seat)
	var item: ItemInstance = giver.items[item_id]
	giver.convoy.remove_at(giver.convoy.find(item_id))
	giver.items.erase(item_id)
	receiver.items[item_id] = item
	receiver.convoy.append(item_id)
	var gifted: CampaignFact = CampaignFact.new(CampaignFact.Kind.ITEM_GIFTED, seat, item_id)
	gifted.definition_id = item.definition_id
	gifted.amount = to_seat
	run.record(gifted)


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
