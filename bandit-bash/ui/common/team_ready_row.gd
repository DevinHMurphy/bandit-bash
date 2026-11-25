# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     team_ready_row.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

class_name TeamReadyRow
extends HBoxContainer
## One seat's line in a [TeamReadyStatus]: the player's name, its machine's load as a bar where
## the status shows bars ([member shows_bar]), and its state. A Ready seat's state reads in body
## text, a waiting one muted, as the other team status rows read. Reading only; takes no input.
##
## @tutorial(Co-op ready checks): docs/plans/2026-11-24-coop-ready-checks.md

## Whether the load bar shows between the name and the state. [b]Off:[/b] the name and state only.
@export var shows_bar: bool = false:
	set(value):
		shows_bar = value
		if not is_node_ready():
			return
		_bar.visible = shows_bar

var _state: TeamReadyStatus.State = TeamReadyStatus.State.LOADING

@onready var _name_label: Label = %Name
@onready var _bar: ProgressBar = %Bar
@onready var _state_label: Label = %State


func _ready() -> void:
	_bar.visible = shows_bar


## Shows [param seat_name] in [param state], its bar at [param progress] (0.0 to 1.0).
func show_seat(seat_name: String, state: TeamReadyStatus.State, progress: float) -> void:
	_state = state
	_name_label.text = seat_name
	_state_label.text = TeamReadyStatus.STATE_NAMES[state]
	_state_label.theme_type_variation = (
			&"BodyLabel" if state == TeamReadyStatus.State.READY else &"MutedLabel"
	)
	_bar.value = clampf(progress, 0.0, 1.0) * _bar.max_value


## The state shown.
func get_state() -> TeamReadyStatus.State:
	return _state


## The name shown, for tests.
func get_name_text() -> String:
	return _name_label.text


## The state as shown ("Ready"), for tests.
func get_state_text() -> String:
	return _state_label.text


## The load the bar shows, 0.0 to 1.0, for tests.
func get_progress() -> float:
	return _bar.value / _bar.max_value


## Whether the bar shows, for tests.
func is_bar_shown() -> bool:
	return _bar.visible


## The row as one line, "Player 2 · Ready", for tests.
func get_line() -> String:
	return "%s · %s" % [_name_label.text, _state_label.text]
