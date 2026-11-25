# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ready_toggle.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

class_name ReadyToggle
extends Button
## The Continue or Leave a co-op hand-off waits on: a Ready toggle in co-op, a plain button solo.
##
## [b]Solo[/b] ([member is_coop] off): reads [member solo_text]; each press emits [signal pressed]
## as any button does, then [signal ready_changed] with true. [b]Co-op:[/b] a toggle reading
## [member ready_text], then [member unready_text] with the pressed look once Ready, so a second
## press takes it back; each press emits [signal ready_changed]. [signal pressed] still comes with
## every press: a screen's handler skips the one that took Ready back ([method is_taking_back]).
## [member detail] follows the label in brackets. With key or pad focus it shows the glyph of
## [member press_action] in [member hint_bar]'s device family. Never disables itself.
##
## @tutorial(Co-op ready checks): docs/plans/2026-11-24-coop-ready-checks.md

# ============================================================
# INPUT MAP SETUP: none read here. "ui_accept" (Enter, Space; pad A [Cross]) presses the focused
# toggle through the GUI; a click presses it too.
# ============================================================

## The player made this seat Ready ([param is_ready] true) or took it back. Solo: true on every
## press.
signal ready_changed(is_ready: bool)

## The label in solo: what the screen's button has always read ("Continue", "Leave").
@export var solo_text: String = "Continue":
	set(value):
		solo_text = value
		if not is_node_ready():
			return
		_show_label()

## The label in co-op while the seat isn't Ready: pressing it makes the seat Ready.
@export var ready_text: String = "Ready":
	set(value):
		ready_text = value
		if not is_node_ready():
			return
		_show_label()

## The label in co-op once the seat is Ready: pressing it takes Ready back.
@export var unready_text: String = "Not ready":
	set(value):
		unready_text = value
		if not is_node_ready():
			return
		_show_label()

## Why the button can't be pressed yet, after the label in brackets ("Leave (choose Feast or Train
## first)"). [b]Empty:[/b] the label alone.
@export var detail: String = "":
	set(value):
		detail = value
		if not is_node_ready():
			return
		_show_label()

## Whether the run has teammates, which makes this a Ready toggle. [b]Off:[/b] a plain button.
## Turning it off drops Ready.
@export var is_coop: bool = false:
	set(value):
		is_coop = value
		if not is_node_ready():
			return
		_apply_mode()

## The screen's hint bar, whose glyphs, device family and glyph size the toggle's glyph follows
## ([method ControlHintBar.glyph_of]). [b]Unset:[/b] no glyph shows.
@export var hint_bar: ControlHintBar = null:
	set(value):
		_disconnect_device()
		hint_bar = value
		if not is_node_ready():
			return
		_connect_device()
		_show_glyph()

## The input action whose glyph shows while the toggle has focus: the one that presses it.
@export var press_action: StringName = &"ui_accept":
	set(value):
		press_action = value
		if not is_node_ready():
			return
		_show_glyph()

# Whether the press being handled took Ready back; cleared at the end of the frame.
var _is_taking_back: bool = false


func _ready() -> void:
	focus_entered.connect(_show_glyph)
	focus_exited.connect(_show_glyph)
	_connect_device()
	_apply_mode()


func _exit_tree() -> void:
	_disconnect_device()


# Called by the GUI before the toggled signal, and before the pressed signal and _pressed().
func _toggled(toggled_on: bool) -> void:
	if not is_coop:
		return
	_is_taking_back = not toggled_on
	if _is_taking_back:
		_end_press.call_deferred()
	_show_label()
	ready_changed.emit(toggled_on)


func _pressed() -> void:
	if not toggle_mode:
		ready_changed.emit(true)


## Whether the seat is Ready: co-op only, and only once pressed.
func is_ready() -> bool:
	return is_coop and button_pressed


## Makes the seat Ready or not without emitting anything: a screen putting it back after a
## refused Leave, or showing a gate's state. Solo: always not Ready.
func set_ready(value: bool) -> void:
	set_pressed_no_signal(value and is_coop)
	if not is_node_ready():
		return
	_show_label()


## Whether the press being handled took Ready back, for a [signal pressed] handler to skip it.
## True from such a press until the end of its frame.
func is_taking_back() -> bool:
	return _is_taking_back


# Solo a plain button, co-op a toggle; the label for the mode.
func _apply_mode() -> void:
	toggle_mode = is_coop
	if not is_coop:
		set_pressed_no_signal(false)
	_show_label()
	_show_glyph()


func _show_label() -> void:
	var label: String = solo_text
	if is_coop:
		label = unready_text if button_pressed else ready_text
	text = label if detail.is_empty() else "%s (%s)" % [label, detail]


# The press action's glyph while the toggle has focus, at the hint bar's glyph size; else none.
func _show_glyph() -> void:
	var glyph: Texture2D = null
	if has_focus() and is_instance_valid(hint_bar):
		glyph = hint_bar.glyph_of(press_action)
		add_theme_constant_override(&"icon_max_width", hint_bar.glyph_height)
	icon = glyph


func _end_press() -> void:
	_is_taking_back = false


func _connect_device() -> void:
	if not is_instance_valid(hint_bar) or not is_instance_valid(hint_bar.device):
		return
	if not hint_bar.device.family_changed.is_connected(_on_device_family_changed):
		hint_bar.device.family_changed.connect(_on_device_family_changed)


func _disconnect_device() -> void:
	if not is_instance_valid(hint_bar) or not is_instance_valid(hint_bar.device):
		return
	if hint_bar.device.family_changed.is_connected(_on_device_family_changed):
		hint_bar.device.family_changed.disconnect(_on_device_family_changed)


func _on_device_family_changed(_family: InputDeviceAdapter.Family) -> void:
	_show_glyph()
