# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     volume_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name VolumeRow
extends HBoxContainer
## One volume on the Options screen: the channel's name, a slider over
## [constant SettingsData.MIN_VOLUME] to [constant SettingsData.MAX_VOLUME] in whole steps, and
## the value. While the slider has focus the row draws the theme's [code]HSlider[/code]
## [code]focus[/code] style around it, the 2-unit [code]accent[/code] outline (ui-style.md, Focus
## and hover): Godot's [HSlider] draws no focus style of its own, only a brighter grabber. The
## outline reaches past the slider's ends (the style's expand margins), so an OutlineGap of the
## same width keeps it off the value.[br]
## The slider steps on left and right from keys and, through the row, from a pad's d-pad and
## stick, which Godot's slider ignores; the mouse drags or clicks it.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions):
#   "ui_left" / "ui_right" -> arrows (the slider's own); d-pad, left stick (read here from the
#                             slider's gui_input: one step each, so focus doesn't move instead)
#   Mouse: drag or click the slider.
# ============================================================

## The player moved the slider to [param volume], a whole step.
signal volume_changed(volume: int)

## The channel's name, shown on the left.
@export var label_text: String = "Volume":
	set(value):
		label_text = value
		if not is_node_ready():
			return
		_name_label.text = label_text

## The width of the name column, so the rows' sliders line up.[br]
## [b]Units:[/b] base units. [b]0:[/b] the name's own width.
@export_range(0.0, 400.0, 4.0) var name_width: float = 120.0:
	set(value):
		name_width = value
		if not is_node_ready():
			return
		_name_label.custom_minimum_size.x = name_width

@onready var _name_label: Label = %Name
@onready var _slider: HSlider = %Slider
@onready var _value_label: Label = %Value


func _ready() -> void:
	_name_label.text = label_text
	_name_label.custom_minimum_size.x = name_width
	_slider.min_value = SettingsData.MIN_VOLUME
	_slider.max_value = SettingsData.MAX_VOLUME
	_slider.step = 1.0
	_slider.value_changed.connect(_on_slider_value_changed)
	_slider.gui_input.connect(_on_slider_gui_input)
	_slider.focus_entered.connect(queue_redraw)
	_slider.focus_exited.connect(queue_redraw)


func _draw() -> void:
	if not _slider.has_focus():
		return
	# ASSUMPTION: the row draws the theme's HSlider focus style, as Godot 4.7.1's slider draws none
	# (a focused slider rendered with a red focus style shows no red).
	draw_style_box(get_theme_stylebox(&"focus", &"HSlider"), _slider.get_rect())


## Shows [param volume] without emitting [signal volume_changed].
func set_volume(volume: int) -> void:
	_slider.set_value_no_signal(volume)
	_value_label.text = str(volume)


## The volume shown.
func get_volume() -> int:
	return roundi(_slider.value)


## The slider, for focus and tests.
func get_slider() -> HSlider:
	return _slider


## Whether the row draws its focus outline now: its slider has focus.
func is_showing_focus() -> bool:
	return _slider.has_focus()


# A pad's left or right steps the slider once, as an arrow key does; taken, so focus stays.
func _on_slider_gui_input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	var direction: float = 0.0
	if event.is_action_pressed(&"ui_left", true):
		direction = -1.0
	elif event.is_action_pressed(&"ui_right", true):
		direction = 1.0
	if direction == 0.0:
		return
	_slider.value += direction * _slider.step
	_slider.accept_event()


func _on_slider_value_changed(value: float) -> void:
	_value_label.text = str(roundi(value))
	volume_changed.emit(roundi(value))
