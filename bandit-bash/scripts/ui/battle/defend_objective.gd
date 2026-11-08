# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     defend_objective.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name DefendObjective
extends ObjectiveDetail
## Defend's HUD: the turns left, the defend tiles (drawn on the board) and a warning while an
## enemy stands on one, since its ending its turn there loses the map (combat map plan,
## Objectives).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The turns line: [code]%d[/code] the turns left, then the turns to hold.
@export var turns_format: String = "Turns left: %d of %d"

## The tiles line: [code]%d[/code] the defend tiles on the map.
@export var tiles_format: String = "Defend tiles: %d, marked on the map"

## The warning while an enemy stands on a defend tile.[br]
## [b]Empty:[/b] never warns.
@export var taken_text: String = "An enemy stands on a defend tile!"

@onready var _turns: Label = %Turns
@onready var _tiles: Label = %Tiles
@onready var _taken: Label = %Taken


func is_shown_for(view: HudViewModel.ObjectiveView) -> bool:
	return view.objective == CombatMapDefinition.Objective.DEFEND


func show_objective(view: HudViewModel.ObjectiveView) -> void:
	_turns.text = turns_format % [view.turns_left, view.survive_turns]
	_tiles.text = tiles_format % [view.defend_tiles.size()]
	_taken.text = taken_text
	_taken.visible = view.is_defend_tile_taken and not taken_text.is_empty()
