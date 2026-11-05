# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     turn_bar.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name TurnBar
extends PanelContainer
## The strip along the bottom of the battle screen: a status line and End Turn.
##
## It only reports the press; [BattleController] turns it into an [EndTurnCommand], asking first
## while units can still act, and says when it can be pressed ([method set_can_end_turn]).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## End Turn was pressed.
signal end_turn_pressed()

@onready var _status_label: Label = %Status
@onready var _end_turn_button: Button = %EndTurnButton


func _ready() -> void:
	_end_turn_button.pressed.connect(_on_end_turn_button_pressed)


## Shows [param text] as the status line.
func show_status(text: String) -> void:
	_status_label.text = text


## The status line shown.
func get_status() -> String:
	return _status_label.text


## Whether End Turn can be pressed.
func set_can_end_turn(can_end_turn: bool) -> void:
	_end_turn_button.disabled = not can_end_turn


## The End Turn button, for tests that press it.
func get_end_turn_button() -> Button:
	return _end_turn_button


func _on_end_turn_button_pressed() -> void:
	end_turn_pressed.emit()
