# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     turn_counter.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name TurnCounter
extends PanelContainer
## The turn against the map's par, on a danger chip once past par (combat UI plan, question 11;
## game-vision.md, Combat maps: each map has an authored turn par, and the darkness comes at par).
##
## Draws a [HudViewModel.TurnView]. Godot_FE coloured the count in four bands (green to 80% of
## par, yellow to par, red to 120%, dark red beyond); this marks it only past par, as the plan
## decides, with [code]text[/code] on the [code]danger_fill[/code] chip (5.42:1), since
## [code]danger[/code] text on [code]panel[/code] fails contrast (2.79:1).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The text: [code]%d[/code] the turn, then the par.
@export var turn_format: String = "Turn %d of par %d"

## The text on a map with no par set: [code]%d[/code] the turn.
@export var no_par_format: String = "Turn %d"

## The text before turn 1 (the opening swap window): [code]%d[/code] the par.
@export var before_first_turn_format: String = "Before turn 1 · par %d"

## The text's theme type once the turn is past par; within par it keeps the scene's. Defaults to
## [code]HudWarningHeading[/code], the heading on a danger chip.
@export var past_par_type: StringName = &"HudWarningHeading"

var _view: HudViewModel.TurnView = null

# The text's theme type within par, as the scene sets it.
var _in_par_type: StringName = &""

@onready var _text: Label = %Text


func _ready() -> void:
	_in_par_type = _text.theme_type_variation


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
	_text.theme_type_variation = past_par_type if view.is_past_par() else _in_par_type


## The text shown.
func get_text() -> String:
	return _text.text


## Whether the past-par chip shows.
func is_past_par_shown() -> bool:
	return _text.theme_type_variation == past_par_type and past_par_type != _in_par_type


## The text's theme type now: [member past_par_type] past par, else the scene's.
func get_text_type() -> StringName:
	return _text.theme_type_variation


## The text's colour now, from its theme type.
func get_text_color() -> Color:
	return _text.get_theme_color(&"font_color")
