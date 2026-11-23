# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_bar.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name CoopBar
extends PanelContainer
## A co-op battle's strip in the HUD's bottom row, beside the turn bar: Maps, naming the map
## viewed and marked while a teammate calls for aid, and the seat's own [AidButton] while its map
## is fought. The mouse's way in: keys and pads open the [MapsPanel] with cycle_weapon, and reach
## the call for aid there. Only asks: [CoopBattle] acts. Its buttons never take focus, so they
## never take ui_accept from the board.

## Maps was pressed.
signal maps_pressed()

## The call for aid was pressed: [param is_raised] the flag asked for.
signal aid_requested(is_raised: bool)

# ASSUMPTION: the strip's wordings; no design doc words them.
## Maps' text: [code]%s[/code] whose map is viewed, short so it fits ("Yours", "Player 2").
@export var maps_text: String = "Maps · %s"

## Added to Maps' text while a teammate's call for aid is up.
@export var aid_mark_text: String = " · Aid called"

@onready var _maps_button: Button = %MapsButton
@onready var _aid_button: AidButton = %AidButton


func _ready() -> void:
	_maps_button.pressed.connect(_on_maps_button_pressed)
	_aid_button.aid_requested.connect(_on_aid_button_aid_requested)


## Shows [param viewed_title], whose map is viewed; [param is_teammate_calling]: a teammate's call
## for aid is up; the seat's own call as [param is_aid_raised] while [param is_own_open], disabled
## while [param is_aid_waiting].
func show_bar(
		viewed_title: String,
		is_teammate_calling: bool,
		is_aid_raised: bool,
		is_own_open: bool,
		is_aid_waiting: bool
) -> void:
	_maps_button.text = maps_text % [viewed_title]
	if is_teammate_calling:
		_maps_button.text += aid_mark_text
	_aid_button.show_flag(is_aid_raised, is_own_open, is_aid_waiting)


## Maps, for tests.
func get_maps_button() -> Button:
	return _maps_button


## The call for aid, for tests.
func get_aid_button() -> AidButton:
	return _aid_button


func _on_maps_button_pressed() -> void:
	maps_pressed.emit()


func _on_aid_button_aid_requested(is_raised: bool) -> void:
	aid_requested.emit(is_raised)
