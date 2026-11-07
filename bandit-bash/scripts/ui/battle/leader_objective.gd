# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leader_objective.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name LeaderObjective
extends ObjectiveDetail
## Defeat the Leader's and Defeat the Boss's HUD: how many of the marked enemies are left, and
## their names; the board outlines them ([LeaderMark]).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The count line: [code]%d[/code] the marked enemies left, then every one marked.
@export var left_format: String = "Marked left: %d of %d"

## The line while no enemy is marked (no enemy has appeared on a leader slot).
@export var none_text: String = "No marked enemy on the map yet"

## The note under the names, saying where the marks are.[br]
## [b]Empty:[/b] no note.
@export var board_note: String = "Outlined on the map"

@onready var _left: Label = %Left
@onready var _names: Label = %Names
@onready var _note: Label = %Note


func is_shown_for(view: HudViewModel.ObjectiveView) -> bool:
	return view.objective in [
		CombatMapDefinition.Objective.DEFEAT_LEADER, CombatMapDefinition.Objective.DEFEAT_BOSS,
	]


func show_objective(view: HudViewModel.ObjectiveView) -> void:
	if view.marked_ids.is_empty():
		_left.text = none_text
	else:
		_left.text = left_format % [view.marked_left_ids.size(), view.marked_ids.size()]
	_names.text = ", ".join(view.marked_left_names)
	_names.visible = not view.marked_left_names.is_empty()
	_note.text = board_note
	_note.visible = not board_note.is_empty() and not view.marked_left_ids.is_empty()
