# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seize_objective.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name SeizeObjective
extends ObjectiveDetail
## Seize's HUD: the seize tiles, drawn on the board, and how one is taken (combat map plan,
## Objectives: a player unit ends its turn on it).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The tiles line: [code]%d[/code] the seize tiles on the map.
@export var tiles_format: String = "Seize tiles: %d, marked on the map"

## How a tile is taken.[br]
## [b]Empty:[/b] no line.
@export var rule_text: String = "End a unit's turn on one to win"

@onready var _tiles: Label = %Tiles
@onready var _rule: Label = %Rule


func is_shown_for(view: HudViewModel.ObjectiveView) -> bool:
	return view.objective == CombatMapDefinition.Objective.SEIZE


func show_objective(view: HudViewModel.ObjectiveView) -> void:
	_tiles.text = tiles_format % [view.seize_tiles.size()]
	_rule.text = rule_text
	_rule.visible = not rule_text.is_empty()
