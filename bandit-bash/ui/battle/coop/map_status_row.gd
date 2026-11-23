# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_status_row.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name MapStatusRow
extends VBoxContainer
## One map of a co-op battle as a seat sees it ([CoopViewModel.MapStatus]): a button naming it
## with its turn and the units and enemies left; under it a warning chip while it is frozen or
## calls for aid, and a note of the rest (viewed, picked, the seat's units there, units on their
## way, why it can't be picked). The [MapsPanel] views a map when its button is pressed; the
## [SendPanel] picks it as the target. Only asks: the panels act. Reads no input action itself;
## the GUI moves focus between rows.

## The button was pressed: [param session_id] is the map shown.
signal pressed(session_id: int)

# ASSUMPTION: the row's wordings; no design doc words them.
const _AID: String = "Calls for aid"
const _FROZEN: String = "Frozen"
const _CAN_ACT: String = "Your units can act"
const _HAS_UNITS: String = "Your units are here"
const _VIEWING: String = "Viewing"
const _PICKED: String = "Picked"

## The button's least size, so rows line up in a panel.[br]
## [b]Units:[/b] base units. [b](0, 0):[/b] as large as its text.
@export var button_size: Vector2 = Vector2(440.0, 36.0):
	set(value):
		button_size = value
		if not is_node_ready():
			return
		_button.custom_minimum_size = button_size

## Whether the button stays down once pressed, as the send panel's picked target does.[br]
## [b]Off:[/b] a plain button, as the maps panel's.
@export var is_pickable: bool = false:
	set(value):
		is_pickable = value
		if not is_node_ready():
			return
		_button.toggle_mode = is_pickable

## The map shown; -1 before [method show_status].
var session_id: int = -1

@onready var _button: Button = %MapButton
@onready var _warning: Label = %Warning
@onready var _note: Label = %Note


func _ready() -> void:
	_button.custom_minimum_size = button_size
	_button.toggle_mode = is_pickable
	_button.pressed.connect(_on_map_button_pressed)


## Shows [param shown]. [param is_viewed]: the screen shows this map now. [param refusal]: why it
## can't be picked, with the button disabled (empty leaves it enabled); in the note unless
## [param shows_refusal] is false, as when a banner already states it. [param is_picked]: the
## picked target, for a pickable row.
func show_status(
		shown: CoopViewModel.MapStatus,
		is_viewed: bool,
		refusal: String = "",
		is_picked: bool = false,
		shows_refusal: bool = true
) -> void:
	session_id = shown.session_id
	_button.text = summary(shown)
	_button.disabled = not refusal.is_empty()
	_button.set_pressed_no_signal(is_picked and is_pickable)
	var warnings: PackedStringArray = []
	if shown.is_frozen:
		warnings.append(_FROZEN)
	if shown.is_aid_called and not shown.is_finished:
		warnings.append(_AID)
	var tags: PackedStringArray = []
	if is_viewed:
		tags.append(_VIEWING)
	if is_picked and is_pickable:
		tags.append(_PICKED)
	if shown.can_act and not shown.is_own:
		tags.append(_CAN_ACT)
	elif shown.has_units and not shown.is_own:
		tags.append(_HAS_UNITS)
	if shown.arriving > 0:
		tags.append("%d on the way" % [shown.arriving])
	if not refusal.is_empty() and shows_refusal:
		tags.append("Can't send: %s" % [refusal])
	_warning.text = " · ".join(warnings)
	_warning.visible = not warnings.is_empty()
	_note.text = " · ".join(tags)
	_note.visible = not tags.is_empty()


## Whether the row is picked.
func is_picked() -> bool:
	return is_pickable and _button.button_pressed


## The button, which takes focus, for the panel's links and for tests.
func get_button() -> Button:
	return _button


## The warning chip's and the note's text, for tests.
func get_note() -> String:
	return " · ".join([_warning.text, _note.text])


## A map's line: its name, then its turn and what is left on it, or how it ended.
static func summary(shown: CoopViewModel.MapStatus) -> String:
	if shown.is_finished:
		return "%s · %s on turn %d" % [shown.title, "Won" if shown.is_won else "Lost", shown.turn]
	return "%s · Turn %d · %d %s · %d %s" % [
		shown.title,
		shown.turn,
		shown.units_left,
		"unit" if shown.units_left == 1 else "units",
		shown.enemies_left,
		"enemy" if shown.enemies_left == 1 else "enemies",
	]


func _on_map_button_pressed() -> void:
	pressed.emit(session_id)
