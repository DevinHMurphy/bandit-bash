# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leave_confirm_dialog.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name LeaveConfirmDialog
extends Control
## Asks before the victory's Leave gives up the rewards still open, naming them. It only asks:
## Leave emits [signal confirmed], Stay or ui_cancel emits [signal cancelled]; the
## [VictoryOverlay] sends the commands. Stay has focus when it opens, so a stray accept keeps the
## rewards.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, except where noted):
#   "ui_left" / "ui_right" -> Left / Right arrows; d-pad, left stick   (between Stay and Leave)
#   "ui_up" / "ui_down"    -> deliberately inert: focus stays on the two buttons
#   "ui_accept"            -> Enter, Space; pad A [Cross]              (press the focused button)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options]      (read in _input while
#                             shown: as Stay; taken first, so the pause menu doesn't open)
#   Mouse: clicks on the buttons; the backdrop takes clicks outside the panel.
# ============================================================

## The player chose to leave without the open rewards.
signal confirmed()

## The player chose to stay.
signal cancelled()

## How dark the backdrop over the Rewards stage is.[br]
## [b]0.0:[/b] no dimming; [b]1.0:[/b] the stage hidden. 0.6 matches the [PlacementPanel]'s.
@export_range(0.0, 1.0, 0.05) var backdrop_alpha: float = 0.6

@onready var _backdrop: ColorRect = %Backdrop
@onready var _question_label: Label = %Question
@onready var _stay_button: Button = %StayButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	visible = false
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, backdrop_alpha)
	_stay_button.pressed.connect(_on_stay_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	for button: Button in [_stay_button, _leave_button]:
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = self_path
		button.focus_neighbor_bottom = self_path
	_stay_button.focus_neighbor_left = _stay_button.get_path_to(_stay_button)
	_stay_button.focus_neighbor_right = _stay_button.get_path_to(_leave_button)
	_leave_button.focus_neighbor_left = _leave_button.get_path_to(_stay_button)
	_leave_button.focus_neighbor_right = _leave_button.get_path_to(_leave_button)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_stay_button_pressed()


## Opens, asking about the rewards titled [param titles], with Stay focused.
func open(titles: PackedStringArray) -> void:
	_question_label.text = "Leave without taking: %s?" % [", ".join(titles)]
	visible = true
	_stay_button.grab_focus()


## The question as shown, for tests.
func get_question() -> String:
	return _question_label.text


## The Stay button, for tests.
func get_stay_button() -> Button:
	return _stay_button


## The Leave button, for tests.
func get_leave_button() -> Button:
	return _leave_button


func _on_stay_button_pressed() -> void:
	visible = false
	cancelled.emit()


func _on_leave_button_pressed() -> void:
	visible = false
	confirmed.emit()
