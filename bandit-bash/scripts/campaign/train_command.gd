# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     train_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name TrainCommand
extends CampaignCommand
## A seat's Camp choice of Train: its unit [member unit_id] is upgraded ([method Camp.train],
## through [method RunOperations.upgrade]). Valid inside a Camp before the seat has chosen, for a
## living, non-commander unit not upgraded yet.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the unit travels.
const WIRE_TYPE: String = "train"

## Instance id of the unit upgraded.
var unit_id: String = ""

## Content the run's units come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, unit: String = "") -> void:
	seat = sender
	unit_id = unit


func get_label() -> String:
	return "train %s" % [unit_id]


func validate(run: CampaignRunState) -> String:
	return Camp.train_problem(run, seat, unit_id, _contents())


func resolve(run: CampaignRunState) -> void:
	Camp.train(run, seat, unit_id, _contents())


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [unit_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1 or not values[0] is String:
		return false
	unit_id = values[0]
	return true


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
