# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loading_gate.gd
# Author:
# Created:  November 14, 2026
# Modified: November 24, 2026
# ==============================================================================

extends Control
## Loading: the gate every run passes on its way in, with a bar per player ([TeamReadyStatus]):
## the player's name and Ready, Loading or Done, filled from that machine's load.
##
## [method set_state] shows the ready gate's state as the host announces it. Until a state comes,
## the screen shows what this machine knows: its own bar, full on arrival (Done), and Ready once
## its co-op Ready is pressed. Continue ([ReadyToggle], Ready in co-op) sends everyone to the
## screen the run belongs on ([method RunScreen.go]); with no run held, the battle screen. Only the
## host routes: a client's press asks the host for the run and waits for its route. Continue has
## focus from the start, so a pad can press it.
##
## @tutorial(Co-op ready checks): docs/plans/2026-11-24-coop-ready-checks.md

# ============================================================
# INPUT MAP SETUP: none read here. "ui_accept" (Enter, Space; pad A [Cross]) presses the focused
# Continue through the GUI; a click presses it too.
# ============================================================

## The hint context solo, where Continue moves on.
const HINT_SOLO: StringName = &"LOADING"

## The hint context in co-op, where Continue is the seat's Ready.
const HINT_COOP: StringName = &"LOADING_COOP"

## The name this machine's own bar shows.
const LOCAL_NAME: String = "You"

var _seat: int = CampaignData.HOST_SEAT

@onready var _status: TeamReadyStatus = %TeamReadyStatus
@onready var _continue_button: ReadyToggle = %ContinueButton
@onready var _hints: ScreenHints = %ScreenHints
@onready var _hint_bar: ControlHintBar = %ControlHintBar


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	var is_coop: bool = session != null and session.seats.size() > 1
	_seat = CampaignService.local_seat()
	_continue_button.is_coop = is_coop
	_continue_button.hint_bar = _hint_bar
	_continue_button.pressed.connect(_on_continue_button_pressed)
	_hints.context = HINT_COOP if is_coop else HINT_SOLO
	_show_local(false)
	_continue_button.grab_focus.call_deferred()


## Shows the gate's state, as [method TeamReadyStatus.set_state] takes it: a bar per seat of
## [param seat_names], each at its machine's load in [param progress_by_seat] (0.0 to 1.0).
func set_state(
		ready_seats: PackedInt32Array,
		loaded_seats: PackedInt32Array,
		progress_by_seat: Dictionary[int, float],
		seat_names: Dictionary[int, String],
) -> void:
	_status.set_state(ready_seats, loaded_seats, progress_by_seat, seat_names)


## The bars, for tests and captures.
func get_status() -> TeamReadyStatus:
	return _status


## Continue, or Ready in co-op, for tests and captures.
func get_continue_button() -> ReadyToggle:
	return _continue_button


# This machine's bar alone: loaded on arrival, as nothing here loads in steps; Ready once pressed.
func _show_local(is_ready: bool) -> void:
	var ready_seats: PackedInt32Array = []
	if is_ready:
		ready_seats.append(_seat)
	var names: Dictionary[int, String] = {_seat: LOCAL_NAME}
	set_state(ready_seats, PackedInt32Array([_seat]), {}, names)


func _on_continue_button_pressed() -> void:
	if _continue_button.is_taking_back():
		_show_local(false)
		return
	_show_local(_continue_button.is_ready())
	RunScreen.go()
