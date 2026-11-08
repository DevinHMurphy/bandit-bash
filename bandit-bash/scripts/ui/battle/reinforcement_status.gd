# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reinforcement_status.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name ReinforcementStatus
extends ObjectiveDetail
## The map's reinforcement points on the HUD, under any objective: how many are still open and the
## soonest turn one sends on. The open points are drawn on the board. Shown only on a map that has
## points.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The count line: [code]%d[/code] the points open, then every point on the map.
@export var open_format: String = "Reinforcement points open: %d of %d"

## The arrival line: [code]%d[/code] the turn whose enemy phase the soonest wave arrives after.
@export var next_format: String = "Next arrival: end of turn %d"

## The line once every point is closed.
@export var closed_text: String = "No more reinforcements"

@onready var _open: Label = %Open
@onready var _next: Label = %Next


func is_shown_for(view: HudViewModel.ObjectiveView) -> bool:
	return not view.points.is_empty()


func show_objective(view: HudViewModel.ObjectiveView) -> void:
	var open: int = view.open_point_tiles().size()
	_open.text = closed_text if open == 0 else open_format % [open, view.points.size()]
	var turn: int = view.next_arrival_turn()
	_next.text = next_format % [turn] if turn >= 0 else ""
	_next.visible = turn >= 0
