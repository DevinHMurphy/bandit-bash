# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name SaveCard
extends PanelContainer
## One save file on Save Select: its number as a heading, what it holds, and its buttons. Open
## (New on an empty file) is the screen's main action, so it is the primary button; Delete shows
## only on a file that isn't empty. Both take focus, so keys, d-pad and A reach them as clicks do.
## Holds no save data: the screen fills it ([method show_save]) and acts on its signals.

## The player pressed Open or New on save [param save_number].
signal open_requested(save_number: int)

## The player pressed Delete on save [param save_number].
signal delete_requested(save_number: int)

var _save_number: int = 0

@onready var _title_label: Label = %Title
@onready var _detail_label: Label = %Detail
@onready var _open_button: Button = %OpenButton
@onready var _delete_button: Button = %DeleteButton


func _ready() -> void:
	_open_button.pressed.connect(_on_open_button_pressed)
	_delete_button.pressed.connect(_on_delete_button_pressed)


## Shows save [param save_number] described by [param detail]. [param is_empty]: no file yet, so
## the button reads New and Delete hides. [param can_open]: whether Open or New is enabled.
func show_save(save_number: int, detail: String, is_empty: bool, can_open: bool) -> void:
	_save_number = save_number
	_title_label.text = "Save %d" % [save_number]
	_detail_label.text = detail
	_open_button.text = "New" if is_empty else "Open"
	_open_button.disabled = not can_open
	_delete_button.visible = not is_empty


## The Open or New button.
func get_open_button() -> Button:
	return _open_button


## The Delete button, for tests.
func get_delete_button() -> Button:
	return _delete_button


func _on_open_button_pressed() -> void:
	open_requested.emit(_save_number)


func _on_delete_button_pressed() -> void:
	delete_requested.emit(_save_number)
