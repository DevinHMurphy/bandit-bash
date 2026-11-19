# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     options_screen.gd
# Author:
# Created:  October 14, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Control
## Options: the open save file's settings. Reached from the Main Menu only.
##
## Edits a copy of [code]SaveService.settings[/code]. Apply writes only the open save file's
## settings file ([code]SaveService.save_settings()[/code]); Back discards anything not applied.
## [br]
## One [VolumeRow] per [enum SettingsData.Channel] is added in code. A volume is heard as its
## slider moves ([method SettingsData.apply] on the copy); leaving the screen any way applies the
## settings in effect again, so an unapplied change goes with Back. The opening-swap
## toggle ([code]%OpeningSwapToggle[/code], a [SettingToggle] scene) edits
## [member SettingsData.is_opening_swap_on], which the next battle to begin reads.[br]
## Every control takes focus, so the arrows and a pad's d-pad move between them and accept or A
## presses or flips the focused one.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick   (move between the rows and buttons)
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick   (step the focused volume slider)
#   "ui_accept"            -> Enter, Space; pad A [Cross] (press Apply or Back, flip the toggle)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (Back's shortcut: presses it)
#   Mouse: drag or click a slider, click the toggle and buttons.
# Hint context: MENU.
# ============================================================

const _CHANNEL_NAMES: Dictionary[SettingsData.Channel, String] = {
	SettingsData.Channel.MASTER: "Master",
	SettingsData.Channel.MUSIC: "Music",
	SettingsData.Channel.SFX: "Sound Effects",
}

const _ROW_SCENE: PackedScene = preload("res://ui/screens/volume_row.tscn")

# Shown while there are no unapplied changes.
const _IDLE_TEXT: String = "Volume changes are heard at once; Apply keeps them."

# The settings being edited: heard at once, saved only by the Apply button.
var _edited: SettingsData = null
var _rows_by_channel: Dictionary[SettingsData.Channel, VolumeRow] = {}
var _first_slider: HSlider = null

@onready var _status_label: Label = %Status
@onready var _rows: VBoxContainer = %Rows
@onready var _apply_button: Button = %ApplyButton
@onready var _opening_swap: SettingToggle = %OpeningSwapToggle


func _ready() -> void:
	_apply_button.pressed.connect(_on_apply_button_pressed)
	_edited = SaveService.settings.copy()

	for channel: SettingsData.Channel in _CHANNEL_NAMES:
		_add_row(channel)
	_opening_swap.set_on(_edited.is_opening_swap_on)
	_opening_swap.toggled_on.connect(_on_opening_swap_toggled_on)

	_status_label.text = _IDLE_TEXT
	# Every route here passes Save Select, so this only guards against a future route that doesn't.
	if not SaveService.has_open_save_file():
		_apply_button.disabled = true
		_status_label.text = "Open a save file to change settings."
	if _first_slider != null:
		_first_slider.grab_focus.call_deferred()


# The volumes heard here were the edited copy's; the settings in effect take over again.
func _exit_tree() -> void:
	SaveService.settings.apply()


## The volume row of [param channel], for tests; null for a channel with none.
func get_volume_row(channel: SettingsData.Channel) -> VolumeRow:
	return _rows_by_channel.get(channel, null)


func _add_row(channel: SettingsData.Channel) -> void:
	var row: VolumeRow = _ROW_SCENE.instantiate()
	row.label_text = _CHANNEL_NAMES[channel]
	_rows.add_child(row)
	row.set_volume(_edited.get_volume(channel))
	row.volume_changed.connect(_on_volume_row_volume_changed.bind(channel))
	_rows_by_channel[channel] = row
	if _first_slider == null:
		_first_slider = row.get_slider()


func _on_volume_row_volume_changed(volume: int, channel: SettingsData.Channel) -> void:
	_edited.set_volume(channel, volume)
	_edited.apply()
	_rows_by_channel[channel].set_volume(_edited.get_volume(channel))
	_status_label.text = "Unapplied changes. Press Apply to keep them."


func _on_opening_swap_toggled_on(is_on: bool) -> void:
	_edited.is_opening_swap_on = is_on
	_status_label.text = "Unapplied changes. Press Apply to keep them."


func _on_apply_button_pressed() -> void:
	var err: Error = SaveService.save_settings(_edited)
	if err != OK:
		_status_label.text = "Couldn't save settings (%s)." % [error_string(err)]
		return
	_status_label.text = "Applied. " + _IDLE_TEXT
