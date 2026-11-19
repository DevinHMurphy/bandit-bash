# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     bus_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The buses and the volume settings: the layout has Music, SFX and UI under Master;
## [method SettingsData.apply] sets each bus to its channel's dB, the UI bus following SFX; a
## volume of 0 mutes its buses and any other level unmutes them. Puts the settings in effect back
## at the end.

# Tolerance for comparing bus volumes. Units: dB.
const DB_EPSILON: float = 0.001

var _check: Callable
var _root: Window


func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	_check_layout()
	_check_levels()
	_check_mute()
	var service: Node = _root.get_node_or_null(^"SaveService")
	var in_effect: SettingsData = null
	if service != null:
		in_effect = service.get(&"settings")
	if in_effect != null:
		in_effect.apply()
	else:
		SettingsData.new().apply()


func _check_layout() -> void:
	var under_master: bool = true
	for bus_name: StringName in [
		AudioCue.MUSIC_BUS_NAME, AudioCue.SFX_BUS_NAME, AudioCue.UI_BUS_NAME,
	]:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index < 0 or AudioServer.get_bus_send(index) != AudioCue.MASTER_BUS_NAME:
			under_master = false
	_check.call(
			"buses: Music, SFX and UI exist and send to Master",
			under_master and AudioServer.get_bus_index(AudioCue.MASTER_BUS_NAME) == 0,
	)


func _check_levels() -> void:
	var settings: SettingsData = SettingsData.new()
	settings.set_volume(SettingsData.Channel.MASTER, 7)
	settings.set_volume(SettingsData.Channel.MUSIC, 3)
	settings.set_volume(SettingsData.Channel.SFX, 9)
	settings.apply()
	var pairs: Dictionary[StringName, SettingsData.Channel] = {
		AudioCue.MASTER_BUS_NAME: SettingsData.Channel.MASTER,
		AudioCue.MUSIC_BUS_NAME: SettingsData.Channel.MUSIC,
		AudioCue.SFX_BUS_NAME: SettingsData.Channel.SFX,
		AudioCue.UI_BUS_NAME: SettingsData.Channel.SFX,
	}
	var wrong: PackedStringArray = []
	for bus_name: StringName in pairs:
		var index: int = AudioServer.get_bus_index(bus_name)
		var want: float = settings.get_volume_db(pairs[bus_name])
		var got: float = AudioServer.get_bus_volume_db(index)
		if absf(got - want) > DB_EPSILON or AudioServer.is_bus_mute(index):
			wrong.append("%s %.1f dB, want %.1f" % [bus_name, got, want])
	_check.call(
			"buses: apply() sets each bus to its channel's dB, UI from SFX",
			wrong.is_empty(),
			", ".join(wrong),
	)
	# Godot_FE's mapping: master level - 5, music and sfx level - 20.
	var master_db: float = AudioServer.get_bus_volume_db(0)
	var music_db: float = AudioServer.get_bus_volume_db(
			AudioServer.get_bus_index(AudioCue.MUSIC_BUS_NAME)
	)
	_check.call(
			"buses: Master 7 is +2 dB and Music 3 is -17 dB (Godot_FE's mapping)",
			absf(master_db - 2.0) < DB_EPSILON and absf(music_db + 17.0) < DB_EPSILON,
			"Master %.1f, Music %.1f" % [master_db, music_db],
	)


func _check_mute() -> void:
	var settings: SettingsData = SettingsData.new()
	settings.set_volume(SettingsData.Channel.SFX, 0)
	settings.apply()
	var sfx: int = AudioServer.get_bus_index(AudioCue.SFX_BUS_NAME)
	var ui: int = AudioServer.get_bus_index(AudioCue.UI_BUS_NAME)
	var music: int = AudioServer.get_bus_index(AudioCue.MUSIC_BUS_NAME)
	_check.call(
			"buses: SFX 0 mutes the SFX and UI buses at -80 dB, and leaves Music on",
			AudioServer.is_bus_mute(sfx)
			and AudioServer.is_bus_mute(ui)
			and absf(AudioServer.get_bus_volume_db(sfx) - SettingsData.MUTED_DB) < DB_EPSILON
			and not AudioServer.is_bus_mute(music),
	)
	settings.set_volume(SettingsData.Channel.MASTER, 0)
	settings.apply()
	_check.call("buses: Master 0 mutes Master", AudioServer.is_bus_mute(0))
	settings.set_volume(SettingsData.Channel.SFX, 1)
	settings.set_volume(SettingsData.Channel.MASTER, 1)
	settings.apply()
	_check.call(
			"buses: raising a muted channel above 0 unmutes it",
			not AudioServer.is_bus_mute(sfx) and not AudioServer.is_bus_mute(0),
	)
