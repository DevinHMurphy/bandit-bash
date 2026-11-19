# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     friend_lobby_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name FriendLobbyRow
extends HBoxContainer
## One friend's lobby in the Lobby screen's list: the friend's name (with the lobby's game version
## when it differs from this one) and Join, disabled for a lobby on another version. Holds no
## lobby itself: the screen fills it ([method show_lobby]) and joins on [signal join_requested].

## The player pressed Join on lobby [param lobby_id].
signal join_requested(lobby_id: int)

var _lobby_id: int = 0

@onready var _name_label: Label = %Name
@onready var _join_button: Button = %JoinButton


func _ready() -> void:
	_join_button.pressed.connect(_on_join_button_pressed)


## Shows lobby [param lobby_id] as [param text]; [param can_join]: whether Join is enabled.
func show_lobby(lobby_id: int, text: String, can_join: bool) -> void:
	_lobby_id = lobby_id
	_name_label.text = text
	_join_button.disabled = not can_join


## The Join button, for focus and tests.
func get_join_button() -> Button:
	return _join_button


func _on_join_button_pressed() -> void:
	join_requested.emit(_lobby_id)
