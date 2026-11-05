# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_change_mark.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name IntentChangeMark
extends Node2D
## The move preview's mark over an enemy whose intent would change if the selected unit moved to the
## hovered tile ([member MovePreview.changed_enemies]). Greybox: a label authored in the scene,
## styled by the theme's [code]IntentChangeLabel[/code]. UI4 draws the intent itself.
##
## [MovePreviewMarks] places and reuses these, one per changed enemy.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: a greybox "!" until UI4's intent glyphs; no basis in the vision or Godot_FE.
## The text shown over the enemy.
@export var mark_text: String = "!"

## The enemy marked; empty while unused.
var enemy_id: String = ""

@onready var _label: Label = %MarkLabel


func _ready() -> void:
	_label.text = mark_text


## Shows the mark for [param marked_id] at [param board_position], a point in the board's space.
func show_for(marked_id: String, board_position: Vector2) -> void:
	enemy_id = marked_id
	position = board_position
	visible = true
