# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     scrap_item_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name ScrapItemCommand
extends CampaignCommand
## Scraps a seat's convoy item for gold at its scrap rate ([method RunOperations.scrap]; items.md,
## Scrapping: "army management can scrap any convoy item in one step"). Valid at any stage of a
## run outside battle (the session refuses commands mid-battle), on the map as at a node: the
## army view's one change allowed everywhere (game-vision.md, Inventory).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the item travels.
const WIRE_TYPE: String = "scrap_item"

## Instance id of the convoy item scrapped.
var item_id: String = ""

## Content the item and the seat's heirlooms come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, item: String = "") -> void:
	seat = sender
	item_id = item


func get_label() -> String:
	return "scrap %s" % [item_id]


func validate(run: CampaignRunState) -> String:
	return RunOperations.scrap_problem(run, seat, item_id)


func resolve(run: CampaignRunState) -> void:
	RunOperations.scrap(run, seat, item_id, _contents())


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [item_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1 or not values[0] is String:
		return false
	item_id = values[0]
	return true


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
