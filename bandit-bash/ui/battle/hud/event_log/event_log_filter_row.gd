# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_log_filter_row.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name EventLogFilterRow
extends HBoxContainer
## The [EventLog]'s filters: one toggle per group (Combat, Movement, Events, Effects), all on at
## the start of each battle ([method reset]). A group that is on shows filled and lit, one that is
## off shows as an outline in [code]text_muted[/code], so the state reads without colour.[br]
## The mouse presses them at any time; they take focus only while [method set_navigable] is on,
## which [BattleController]'s EVENT_LOG stage sets, so a click never leaves Enter on a filter.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## A filter was turned on or off.
signal filters_changed()

## The Combat toggle's text.
@export var combat_text: String = "Combat":
	set(value):
		combat_text = value
		_apply_texts()

## The Movement toggle's text.
@export var movement_text: String = "Movement":
	set(value):
		movement_text = value
		_apply_texts()

## The Events toggle's text.
@export var events_text: String = "Events":
	set(value):
		events_text = value
		_apply_texts()

## The Effects toggle's text.
@export var effects_text: String = "Effects":
	set(value):
		effects_text = value
		_apply_texts()

var _buttons: Dictionary[EventLogWriter.Group, Button] = {}

@onready var _combat: Button = %Combat
@onready var _movement: Button = %Movement
@onready var _events: Button = %Events
@onready var _effects: Button = %Effects


func _ready() -> void:
	_buttons = {
		EventLogWriter.Group.COMBAT: _combat,
		EventLogWriter.Group.MOVEMENT: _movement,
		EventLogWriter.Group.EVENTS: _events,
		EventLogWriter.Group.EFFECTS: _effects,
	}
	for button: Button in _buttons.values():
		button.toggled.connect(_on_button_toggled)
	_apply_texts()


## Whether [param group]'s lines show; [constant EventLogWriter.Group.NONE] always does.
func is_group_shown(group: EventLogWriter.Group) -> bool:
	if not _buttons.has(group):
		return true
	return _buttons[group].button_pressed


## Turns [param group]'s filter on or off, as its toggle would.
func set_group_shown(group: EventLogWriter.Group, is_shown: bool) -> void:
	if _buttons.has(group):
		_buttons[group].button_pressed = is_shown


## Turns every filter on, without [signal filters_changed].
func reset() -> void:
	for button: Button in _buttons.values():
		button.set_pressed_no_signal(true)


## The groups shown as a bit set (1 shl group), for tests and snapshots.
func get_shown_mask() -> int:
	var mask: int = 0
	for group: EventLogWriter.Group in _buttons:
		if _buttons[group].button_pressed:
			mask |= 1 << group
	return mask


## The toggles, in the row's order.
func get_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for group: EventLogWriter.Group in EventLogWriter.GROUPS:
		buttons.append(_buttons[group])
	return buttons


## Lets the toggles take focus while [param is_navigable]; off, they give it up.
func set_navigable(is_navigable: bool) -> void:
	for button: Button in _buttons.values():
		button.focus_mode = Control.FOCUS_ALL if is_navigable else Control.FOCUS_NONE


func _apply_texts() -> void:
	if not is_node_ready():
		return
	_combat.text = combat_text
	_movement.text = movement_text
	_events.text = events_text
	_effects.text = effects_text


func _on_button_toggled(_is_pressed: bool) -> void:
	filters_changed.emit()
