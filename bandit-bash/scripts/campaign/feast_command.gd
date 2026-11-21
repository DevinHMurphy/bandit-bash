# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     feast_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name FeastCommand
extends CampaignCommand
## A seat's Camp choice of the Feast, cooking [member ingredient_id] or nothing
## ([method Camp.feast]). Valid inside a Camp before the seat has chosen.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the ingredient travels.
const WIRE_TYPE: String = "feast"

## Instance id of the ingredient cooked, from the seat's convoy or a living unit's Pouch.
## [b]Empty:[/b] none is cooked; the Feast still heals.
var ingredient_id: String = ""

## Content the run's units and items come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, ingredient: String = "") -> void:
	seat = sender
	ingredient_id = ingredient


func get_label() -> String:
	return "feast" if ingredient_id.is_empty() else "feast, cooking %s" % [ingredient_id]


func validate(run: CampaignRunState) -> String:
	return Camp.feast_problem(run, seat, ingredient_id, _contents())


func resolve(run: CampaignRunState) -> void:
	Camp.feast(run, seat, ingredient_id, _contents())


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [ingredient_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1 or not values[0] is String:
		return false
	ingredient_id = values[0]
	return true


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
