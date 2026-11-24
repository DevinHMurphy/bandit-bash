# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     menu_confirm.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name MenuConfirm
extends VBoxContainer
## A question a menu asks in its buttons' place before a step that can't be undone: the question,
## then a cancel and a confirm button. It only asks: confirm emits [signal confirmed], cancel (or
## [method cancel], which the host menu calls on ui_cancel) emits [signal cancelled]. Cancel has
## focus when it opens ([method focus_first]), so a stray accept changes nothing.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick   (between the two buttons)
#   "ui_up" / "ui_down"    -> deliberately inert: focus stays on the two buttons
#   "ui_accept"            -> Enter, Space; pad A [Cross] (press the focused button)
#   "ui_cancel"            -> not read here: the host menu calls cancel() for it
#   Mouse: clicks on the buttons.
# ============================================================

## The player confirmed the step.
signal confirmed()

## The player chose not to take the step.
signal cancelled()

## The question asked, one or two sentences saying what the step does.
@export_multiline var question_text: String = "Are you sure?":
	set(value):
		question_text = value
		if not is_node_ready():
			return
		_question_label.text = question_text

## The confirm button's text, naming the step ("Forfeit").
@export var confirm_text: String = "Confirm":
	set(value):
		confirm_text = value
		if not is_node_ready():
			return
		_confirm_button.text = confirm_text

## The cancel button's text.
@export var cancel_text: String = "Stay":
	set(value):
		cancel_text = value
		if not is_node_ready():
			return
		_cancel_button.text = cancel_text

@onready var _question_label: Label = %Question
@onready var _cancel_button: Button = %CancelButton
@onready var _confirm_button: Button = %ConfirmButton


func _ready() -> void:
	_question_label.text = question_text
	_confirm_button.text = confirm_text
	_cancel_button.text = cancel_text
	_cancel_button.pressed.connect(cancel)
	_confirm_button.pressed.connect(_on_confirm_button_pressed)
	var buttons: Array[Button] = [_cancel_button, _confirm_button]
	for i: int in buttons.size():
		var button: Button = buttons[i]
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = self_path
		button.focus_neighbor_bottom = self_path
		button.focus_neighbor_left = button.get_path_to(buttons[maxi(i - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(buttons[mini(i + 1, buttons.size() - 1)])
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right


## Gives the cancel button focus.
func focus_first() -> void:
	_cancel_button.grab_focus()


## Declines the step: emits [signal cancelled].
func cancel() -> void:
	cancelled.emit()


## The cancel button, for tests.
func get_cancel_button() -> Button:
	return _cancel_button


## The confirm button, for tests.
func get_confirm_button() -> Button:
	return _confirm_button


func _on_confirm_button_pressed() -> void:
	confirmed.emit()
