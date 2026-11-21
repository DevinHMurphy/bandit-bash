# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     treasure_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name TreasureCommand
extends CampaignCommand
## Takes a seat's whole Treasure chest, or gives it up ([member is_taking] false).
##
## Taking pays its gold at once, never a convoy slot (items.md, Scrapping: treasure turns into its
## full value on pickup; [constant CampaignFact.Kind.GOLD_CHANGED] by [constant SOURCE_ID]),
## grants its heirloom ([method RunOperations.grant_heirloom]) and places its Legendary item by
## [member placement] ([method ItemPlacement.apply]). Giving it up records nothing. Valid inside a
## Treasure node while the seat's chest is open; either way the chest is resolved and the run can
## leave once every seat's is.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## [member CampaignFact.definition_id] of the chest's gold.
const SOURCE_ID: String = "treasure"

## Its name on the wire ([method CampaignCommand.get_wire_type]): whether it takes and the
## placement travel; the catalog is the host's.
const WIRE_TYPE: String = "treasure"

## Whether the seat takes the chest; false gives it up.
var is_taking: bool = true

## Where the chest's Legendary item goes; needed exactly when it holds one and is taken.
var placement: ItemPlacement = null

## Content the chest's heirloom and item come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(
		sender: int = -1, taking: bool = true, item_placement: ItemPlacement = null
) -> void:
	seat = sender
	is_taking = taking
	placement = item_placement


func get_label() -> String:
	if not is_taking:
		return "give up treasure"
	return "take treasure%s" % ["" if placement == null else " (%s)" % [placement.describe()]]


func validate(run: CampaignRunState) -> String:
	if not OpenTreasureCommand.is_at_treasure(run):
		return "the run isn't inside a Treasure node"
	var seat_run: SeatRun = run.seat_run(seat)
	var chest: TreasureChest = TreasureChest.pending(seat_run)
	if chest == null:
		return "seat %d has no chest" % [seat]
	if chest.is_resolved:
		return "seat %d already took or gave up its chest" % [seat]
	if not is_taking:
		return "" if placement == null else "giving the chest up places nothing"
	var contents: EffectCatalog.Index = _contents()
	if not chest.heirloom_id.is_empty():
		var problem: String = RunOperations.heirloom_problem(
				run, seat, chest.heirloom_id, contents
		)
		if not problem.is_empty():
			return problem
	if chest.item == null:
		return "" if placement == null else "the chest holds no item to place"
	if seat_run.items.has(chest.item.instance_id):
		return "the seat already holds %s" % [chest.item.instance_id]
	return RunOperations.item_problem(
			run, seat, contents.item(chest.item.definition_id), placement, contents
	)


func resolve(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var chest: TreasureChest = TreasureChest.pending(seat_run)
	chest.is_resolved = true
	chest.is_taken = is_taking
	chest.store(seat_run)
	if not is_taking:
		return
	var contents: EffectCatalog.Index = _contents()
	if chest.gold > 0:
		RunOperations.grant_gold(run, seat, chest.gold, SOURCE_ID)
	if not chest.heirloom_id.is_empty():
		RunOperations.grant_heirloom(run, seat, chest.heirloom_id, contents)
	if chest.item != null:
		RunOperations.grant_item(
				run, seat,
				ItemInstance.new(chest.item.instance_id, chest.item.definition_id),
				placement, contents
		)


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [is_taking, _placement_to_wire(placement)]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 2 or not values[0] is bool or not _is_placement_wire(values[1]):
		return false
	is_taking = values[0]
	placement = _placement_of_wire(values[1] as Array)
	return true


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
