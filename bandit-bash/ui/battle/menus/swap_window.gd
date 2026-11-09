# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_window.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name SwapWindow
extends PanelContainer
## The opening swap window's panel, before turn 1: how to trade two units' deployment tiles, and
## Start (combat UI plan, question 12; always on in M1).
##
## [BattleController] shows it while the seat may still swap, sets its hint as the player picks
## units, and turns its Start press into a [StartCommand]. Picking the units happens on the board.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Start was pressed.
signal start_pressed()

@onready var _hint: Label = %Hint
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_button_pressed)


## Shows [param text] as the hint.
func show_hint(text: String) -> void:
	_hint.text = text


## The hint shown.
func get_hint() -> String:
	return _hint.text


## The Start button, for tests that press it.
func get_start_button() -> Button:
	return _start_button


func _on_start_button_pressed() -> void:
	start_pressed.emit()
