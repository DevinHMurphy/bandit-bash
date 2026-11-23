# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     aid_button.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name AidButton
extends Button
## The seat's call for aid on its own map ([CallForAidCommand]): "Call for aid" while the flag is
## down, "Lower the call" while it is up, so each press asks for the other value, never a toggle
## that two crossing presses could flip the wrong way. Hidden once the map's combat has ended (the
## flag stays as it was). Only asks: [CoopBattle] sends the command. Reads no input action itself;
## the [CoopBar]'s copy is the mouse's, the [MapsPanel]'s is reached by focus.

## Pressed: [param is_raised] is the flag asked for, true to raise it.
signal aid_requested(is_raised: bool)

# ASSUMPTION: the button's wordings; no design doc words them.
## The text while the flag is down.
@export var raise_text: String = "Call for aid"

## The text while the flag is up.
@export var lower_text: String = "Lower the call"

# The flag as last shown.
var _is_raised: bool = false


func _ready() -> void:
	text = raise_text
	pressed.connect(_on_pressed)


## Shows the flag as [param is_raised]; [param is_open]: the map is still being fought, else the
## button hides. [param is_waiting]: a call was sent and hasn't settled, so it is disabled.
func show_flag(is_raised: bool, is_open: bool, is_waiting: bool = false) -> void:
	_is_raised = is_raised
	text = lower_text if is_raised else raise_text
	visible = is_open
	disabled = is_waiting


## The flag as last shown.
func is_raised() -> bool:
	return _is_raised


func _on_pressed() -> void:
	aid_requested.emit(not _is_raised)
