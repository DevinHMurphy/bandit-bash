# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_message.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name BattleMessage
extends PanelContainer
## A small message that shows for a while and hides itself: why the session rejected a command.
##
## [BattleController] shows each [signal CombatSession.command_rejected] reason here
## ([method show_message]); a new message replaces the one showing. It counts real time, not
## playback time, and holds no rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## How long a message stays up.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it stays until the next message.
# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass.
@export_range(0.0, 10.0, 0.1) var hold_time: float = 3.0

var _time_left: float = 0.0

@onready var _text: Label = %Text


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible or hold_time <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		visible = false


## Shows [param text] for [member hold_time] seconds.
func show_message(text: String) -> void:
	_text.text = text
	_time_left = hold_time
	visible = true


## Whether a message is showing.
func is_showing() -> bool:
	return visible


## The message last shown.
func get_text() -> String:
	return _text.text
