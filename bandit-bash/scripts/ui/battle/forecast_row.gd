# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_row.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name ForecastRow
extends HBoxContainer
## One row of the forecast panel: the acting unit's cell, the row's label, the target's cell
## ([ForecastViewModel.Row]).
##
## [ForecastPanel] places one per row and reuses them when the forecast changes. The three labels
## are authored in the scene; their widths and alignment are set there.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

@onready var _actor_cell: Label = %ActorCell
@onready var _label: Label = %RowLabel
@onready var _target_cell: Label = %TargetCell


## Shows [param row].
func show_row(row: ForecastViewModel.Row) -> void:
	_actor_cell.text = row.actor
	_label.text = row.label
	_target_cell.text = row.target


## The cells shown, for tests: label, actor's cell, target's cell.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_label.text, _actor_cell.text, _target_cell.text])
