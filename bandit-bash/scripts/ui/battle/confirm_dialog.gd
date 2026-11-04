# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     confirm_dialog.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name ConfirmDialog
extends BattlePanel
## A question with Confirm and Back: the last step before a targeted action is sent, and End Turn
## while units can still act.
##
## Opened by [BattleController] through [PanelHost] with the question's text. Confirm emits
## [signal BattlePanel.confirmed] with [code]true[/code]; Back emits
## [signal BattlePanel.cancelled], as cancel does. Both buttons are authored in the scene.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

@onready var _message: Label = %Message
@onready var _confirm_button: Button = %ConfirmButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)


## [param payload]: the question, a [String].
func open_with(payload: Variant) -> void:
	_message.text = str(payload)


func focus_first() -> void:
	_confirm_button.grab_focus()


## The question shown.
func get_message() -> String:
	return _message.text


## The Confirm button, for tests that press it.
func get_confirm_button() -> Button:
	return _confirm_button


func _on_confirm_button_pressed() -> void:
	confirmed.emit(true)


func _on_back_button_pressed() -> void:
	cancelled.emit()
