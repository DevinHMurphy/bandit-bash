# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     objective_panel.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name ObjectivePanel
extends PanelContainer
## The map's objective as text, such as "Rout: defeat every enemy" (combat UI plan, question 11;
## game-vision.md, Combat maps: Objectives).
##
## Shows [method HudViewModel.objective_text]; each objective's own HUD (seize tiles, a survive
## countdown) is UI6's.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The line shown before the objective; empty shows the objective alone.
@export var heading: String = "Objective"

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text


func _ready() -> void:
	_heading.text = heading
	_heading.visible = not heading.is_empty()


## Shows [param text] as the objective.
func show_objective(text: String) -> void:
	_text.text = text


## The objective shown.
func get_text() -> String:
	return _text.text
