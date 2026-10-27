# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     options_screen.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Control
## Options: the open save file's settings. Reached from the Main Menu only.
##
## Edits a copy of [code]SaveService.settings[/code]. Apply writes only the open save file's
## settings file ([code]SaveService.save_settings()[/code]); Back discards anything not applied.
## [br]
## One slider row per [enum SettingsData.Channel] is built in code. Volumes are saved but not yet
## heard: [method SettingsData.apply] is a stub until an audio system exists.

const _CHANNEL_NAMES: Dictionary[SettingsData.Channel, String] = {
	SettingsData.Channel.MASTER: "Master",
	SettingsData.Channel.MUSIC: "Music",
	SettingsData.Channel.SFX: "Sound Effects",
}

# Shown while there are no unapplied changes.
const _IDLE_TEXT: String = "Volumes are saved, but there is no audio yet."

# Width of the channel name column, so the sliders line up. Units: pixels.
const _NAME_COLUMN_WIDTH: float = 120.0
# Slider width. Units: pixels.
const _SLIDER_WIDTH: float = 200.0

# The settings being edited; applied only by the Apply button.
var _edited: SettingsData = null
var _value_labels: Dictionary[SettingsData.Channel, Label] = {}
var _first_slider: HSlider = null

@onready var _status_label: Label = %Status
@onready var _rows: VBoxContainer = %Rows
@onready var _apply_button: Button = %ApplyButton


func _ready() -> void:
	_apply_button.pressed.connect(_on_apply_button_pressed)
	_edited = SaveService.settings.copy()

	for channel: SettingsData.Channel in _CHANNEL_NAMES:
		_rows.add_child(_build_row(channel))

	_status_label.text = _IDLE_TEXT
	# Every route here passes Save Select, so this only guards against a future route that doesn't.
	if not SaveService.has_open_save_file():
		_apply_button.disabled = true
		_status_label.text = "Open a save file to change settings."
	if _first_slider != null:
		_first_slider.grab_focus.call_deferred()


func _build_row(channel: SettingsData.Channel) -> Control:
	var row: HBoxContainer = HBoxContainer.new()

	var name_label: Label = Label.new()
	name_label.text = _CHANNEL_NAMES[channel]
	name_label.custom_minimum_size.x = _NAME_COLUMN_WIDTH
	row.add_child(name_label)

	var slider: HSlider = HSlider.new()
	slider.min_value = SettingsData.MIN_VOLUME
	slider.max_value = SettingsData.MAX_VOLUME
	slider.step = 1.0
	slider.value = _edited.get_volume(channel)
	slider.custom_minimum_size.x = _SLIDER_WIDTH
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_slider_value_changed.bind(channel))
	row.add_child(slider)
	if _first_slider == null:
		_first_slider = slider

	var value_label: Label = Label.new()
	value_label.text = str(_edited.get_volume(channel))
	row.add_child(value_label)
	_value_labels[channel] = value_label

	return row


func _on_slider_value_changed(value: float, channel: SettingsData.Channel) -> void:
	_edited.set_volume(channel, roundi(value))
	_value_labels[channel].text = str(_edited.get_volume(channel))
	_status_label.text = "Unapplied changes. Press Apply to keep them."


func _on_apply_button_pressed() -> void:
	var err: Error = SaveService.save_settings(_edited)
	if err != OK:
		_status_label.text = "Couldn't save settings (%s)." % [error_string(err)]
		return
	_status_label.text = "Applied. " + _IDLE_TEXT
