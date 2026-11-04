# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_debug_bar.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name BattleDebugBar
extends PanelContainer
## A debug strip for driving the player seat before turn input exists: a status line, End Turn,
## and the opening swap window's Start.
##
## It only reports presses; [BattleScreen] turns them into commands. Turn input (UI2) replaces it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## End Turn was pressed.
signal end_turn_pressed()

## Start was pressed (the opening swap window's).
signal start_pressed()

@onready var _status_label: Label = %Status
@onready var _start_button: Button = %StartButton
@onready var _end_turn_button: Button = %EndTurnButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_button_pressed)
	_end_turn_button.pressed.connect(_on_end_turn_button_pressed)


## Shows [param text] as the status line.
func show_status(text: String) -> void:
	_status_label.text = text


## Shows which buttons can be pressed: Start only in the opening swap window
## ([param can_start]), End Turn only when [param can_end_turn].
func show_buttons(can_start: bool, can_end_turn: bool) -> void:
	_start_button.visible = can_start
	_end_turn_button.disabled = not can_end_turn


## The End Turn button, for tests that press it.
func get_end_turn_button() -> Button:
	return _end_turn_button


## The Start button, for tests that press it.
func get_start_button() -> Button:
	return _start_button


func _on_start_button_pressed() -> void:
	start_pressed.emit()


func _on_end_turn_button_pressed() -> void:
	end_turn_pressed.emit()
