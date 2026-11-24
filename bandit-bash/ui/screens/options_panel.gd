# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     options_panel.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name OptionsPanel
extends VBoxContainer
## The open save file's settings: one [VolumeRow] per [enum SettingsData.Channel], the opening
## swap toggle, Apply and Back. The Options screen shows it, and the co-op pause menu shows it in
## its buttons' place, so both edit settings alike.[br]
## Edits a copy of [code]SaveService.settings[/code] ([method reload]). A volume is heard as its
## slider moves; Apply writes only the save file's settings file
## ([code]SaveService.save_settings()[/code]), which replaces the settings object, so a co-op
## client's [code]NetRelay[/code] sends the host the new ones. Back emits [signal back_pressed];
## [method discard], or leaving the tree, puts the settings in effect back, so an unapplied change
## goes. Every control takes focus, so arrows and a pad's d-pad move between them.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick   (move between the rows and buttons)
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick   (step the focused volume slider)
#   "ui_accept"            -> Enter, Space; pad A [Cross] (press Apply or Back, flip the toggle)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (Back's shortcut: presses it
#                             while the panel shows)
#   Mouse: drag or click a slider, click the toggle and buttons.
# ============================================================

## The player pressed Back (or ui_cancel, its shortcut). The panel changes nothing itself.
signal back_pressed()

const _CHANNEL_NAMES: Dictionary[SettingsData.Channel, String] = {
	SettingsData.Channel.MASTER: "Master",
	SettingsData.Channel.MUSIC: "Music",
	SettingsData.Channel.SFX: "Sound Effects",
}

const _ROW_SCENE: PackedScene = preload("res://ui/screens/volume_row.tscn")

# Shown while there are no unapplied changes.
const _IDLE_TEXT: String = "Volume changes are heard at once; Apply keeps them."

# Shown once a change is made and until it is applied.
const _UNAPPLIED_TEXT: String = "Unapplied changes. Press Apply to keep them."

## The heading above the settings, in the theme's title style.[br]
## [b]Empty:[/b] no heading (the Options screen shows its own).
@export var title_text: String = "":
	set(value):
		title_text = value
		if not is_node_ready():
			return
		_apply_title()

# The settings being edited: heard at once, saved only by the Apply button.
var _edited: SettingsData = null
var _rows_by_channel: Dictionary[SettingsData.Channel, VolumeRow] = {}
var _first_slider: HSlider = null

@onready var _title_label: Label = %Title
@onready var _status_label: Label = %Status
@onready var _rows: VBoxContainer = %Rows
@onready var _opening_swap: SettingToggle = %OpeningSwapToggle
@onready var _apply_button: Button = %ApplyButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_apply_title()
	_apply_button.pressed.connect(_on_apply_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)
	_opening_swap.toggled_on.connect(_on_opening_swap_toggled_on)
	for channel: SettingsData.Channel in _CHANNEL_NAMES:
		_add_row(channel)
	reload()


# The volumes heard here were the edited copy's; the settings in effect take over again.
func _exit_tree() -> void:
	discard()


## Starts editing a fresh copy of the settings in effect, the controls showing it and nothing
## unapplied. With no save file open Apply is disabled and the status says why.
func reload() -> void:
	_edited = SaveService.settings.copy()
	for channel: SettingsData.Channel in _rows_by_channel:
		_rows_by_channel[channel].set_volume(_edited.get_volume(channel))
	_opening_swap.set_on(_edited.is_opening_swap_on)
	_status_label.text = _IDLE_TEXT
	# Every route to a run passes Save Select, so this only guards against one that doesn't.
	_apply_button.disabled = not SaveService.has_open_save_file()
	if _apply_button.disabled:
		_status_label.text = "Open a save file to change settings."


## Puts the settings in effect back on the buses, so a volume heard but not applied goes.
func discard() -> void:
	if SaveService.settings != null:
		SaveService.settings.apply()


## Gives the first volume slider focus.
func focus_first() -> void:
	if _first_slider != null and _first_slider.is_visible_in_tree():
		_first_slider.grab_focus()


## The volume row of [param channel], for tests; null for a channel with none.
func get_volume_row(channel: SettingsData.Channel) -> VolumeRow:
	return _rows_by_channel.get(channel, null)


## The Back button, for tests and the hosts' focus links.
func get_back_button() -> Button:
	return _back_button


func _apply_title() -> void:
	_title_label.text = title_text
	_title_label.visible = not title_text.is_empty()


func _add_row(channel: SettingsData.Channel) -> void:
	var row: VolumeRow = _ROW_SCENE.instantiate()
	row.label_text = _CHANNEL_NAMES[channel]
	_rows.add_child(row)
	row.volume_changed.connect(_on_volume_row_volume_changed.bind(channel))
	_rows_by_channel[channel] = row
	if _first_slider == null:
		_first_slider = row.get_slider()


func _on_volume_row_volume_changed(volume: int, channel: SettingsData.Channel) -> void:
	_edited.set_volume(channel, volume)
	_edited.apply()
	_rows_by_channel[channel].set_volume(_edited.get_volume(channel))
	_status_label.text = _UNAPPLIED_TEXT


func _on_opening_swap_toggled_on(is_on: bool) -> void:
	_edited.is_opening_swap_on = is_on
	_status_label.text = _UNAPPLIED_TEXT


func _on_apply_button_pressed() -> void:
	var err: Error = SaveService.save_settings(_edited)
	if err != OK:
		_status_label.text = "Couldn't save settings (%s)." % [error_string(err)]
		return
	_status_label.text = "Applied. " + _IDLE_TEXT


func _on_back_button_pressed() -> void:
	back_pressed.emit()
