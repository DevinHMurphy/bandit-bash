# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     setting_toggle.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name SettingToggle
extends VBoxContainer
## One on/off setting on the Options screen: a check button with its name, and a line under it
## saying what on means.
##
## Holds no setting itself: the screen sets it ([method set_on], which emits nothing) and reads
## [signal toggled_on]. The button takes focus, so the keyboard's arrows and a pad's d-pad reach it
## and accept (Enter, Space, A [Cross]) flips it, as a click does.

## The player flipped the button. [param is_on]: its new state.
signal toggled_on(is_on: bool)

## The setting's name, beside the button.
@export var label_text: String = "Setting":
	set(value):
		label_text = value
		if is_node_ready():
			_button.text = label_text

## What on means, in the line under the button.[br]
## [b]Empty:[/b] no line shows.
@export_multiline var hint_text: String = "":
	set(value):
		hint_text = value
		if is_node_ready():
			_show_hint()

@onready var _button: CheckButton = %Button
@onready var _hint: Label = %Hint


func _ready() -> void:
	_button.text = label_text
	_show_hint()
	_button.toggled.connect(_on_button_toggled)


## Shows [param is_on] without emitting [signal toggled_on].
func set_on(is_on: bool) -> void:
	_button.set_pressed_no_signal(is_on)


## Whether the button shows on.
func is_on() -> bool:
	return _button.button_pressed


## The button, for focus neighbours and tests.
func get_button() -> CheckButton:
	return _button


func _show_hint() -> void:
	_hint.text = hint_text
	_hint.visible = not hint_text.is_empty()


func _on_button_toggled(is_pressed: bool) -> void:
	toggled_on.emit(is_pressed)
