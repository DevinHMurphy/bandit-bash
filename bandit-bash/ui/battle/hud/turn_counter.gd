# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     turn_counter.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name TurnCounter
extends PanelContainer
## The turn against the map's par, coloured once past par (combat UI plan, question 11;
## game-vision.md, Combat maps: each map has an authored turn par, and the darkness comes at par).
##
## Draws a [HudViewModel.TurnView]. Godot_FE coloured the count in four bands (green to 80% of
## par, yellow to par, red to 120%, dark red beyond); this colours it only past par, as the plan
## decides.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The text: [code]%d[/code] the turn, then the par.
@export var turn_format: String = "Turn %d of par %d"

## The text on a map with no par set: [code]%d[/code] the turn.
@export var no_par_format: String = "Turn %d"

## The text before turn 1 (the opening swap window): [code]%d[/code] the par.
@export var before_first_turn_format: String = "Before turn 1 · par %d"

# ASSUMPTION: greybox colour, the intent attack glyph's red; no basis in the vision.
## The text's colour once the turn is past par; within par it keeps the theme's.
@export var past_par_color: Color = Color(1.0, 0.4, 0.35, 1.0)

var _view: HudViewModel.TurnView = null

@onready var _text: Label = %Text


## Shows [param view].
func show_turn(view: HudViewModel.TurnView) -> void:
	_view = view
	if view == null:
		return
	if view.turn < 1:
		_text.text = before_first_turn_format % [view.par]
	elif view.par <= 0:
		_text.text = no_par_format % [view.turn]
	else:
		_text.text = turn_format % [view.turn, view.par]
	if view.is_past_par():
		_text.add_theme_color_override(&"font_color", past_par_color)
	else:
		_text.remove_theme_color_override(&"font_color")


## The text shown.
func get_text() -> String:
	return _text.text


## Whether the past-par colour shows.
func is_past_par_shown() -> bool:
	return _text.has_theme_color_override(&"font_color")


## The text's colour now: [member past_par_color] past par, else the theme's.
func get_text_color() -> Color:
	return _text.get_theme_color(&"font_color")
