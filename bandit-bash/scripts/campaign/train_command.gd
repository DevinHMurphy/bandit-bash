# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     train_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name TrainCommand
extends CampaignCommand
## A seat's Camp choice of Train: its unit [member unit_id] is upgraded ([method Camp.train],
## through [method RunOperations.upgrade]). Valid inside a Camp before the seat has chosen, for a
## living, non-commander unit not upgraded yet.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

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


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
