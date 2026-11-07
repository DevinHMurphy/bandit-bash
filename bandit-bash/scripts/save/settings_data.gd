# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     settings_data.gd
# Author:
# Created:  October 14, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name SettingsData
extends RefCounted
## The settings block of a save file, the one block players may edit, in Options or by hand.
##
## Stored as [constant FILE_NAME] in the save file's folder. Because players can edit the file,
## [method load_envelope] repairs bad values instead of rejecting the file: out-of-range volumes
## are clamped, and a value of the wrong type falls back to its default.[br]
## Volumes keep the old build's 0-10 scale and dB mapping
## ([code]Godot_FE/options/options_config.gd[/code]), except that SFX now reads
## [member sfx_volume]; the old build read the music volume for SFX.[br]
## [member is_opening_swap_on] is the opening-swap setting (combat core plan, question 17): a solo
## battle reads it when it begins.
##
## @tutorial(Save system design): docs/design/save-system.md
##
## @todo: TOD-001 - Apply volumes to audio buses in [method apply] once an audio system exists.

## A volume setting.
enum Channel {
	## Everything; [member master_volume].
	MASTER = 0,
	## Music; [member music_volume].
	MUSIC = 1,
	## Sound effects; [member sfx_volume].
	SFX = 2,
}

## File name inside the save file's folder.
const FILE_NAME: String = "settings.json"

## Current schema version of this block. Raising it needs a step in [method _migration_steps].
const SCHEMA_VERSION: int = 2

## Lowest volume. [b]0 mutes[/b] the channel.
const MIN_VOLUME: int = 0
## Highest volume.
const MAX_VOLUME: int = 10
## Volume for a new save file, or for a missing or invalid value.
## From [code]options_config.gd:13-15[/code].
const DEFAULT_VOLUME: int = 5

## Volume used for a muted channel. [b]Units:[/b] dB. From [code]options_config.gd:27,31[/code].
## [br][b]Note:[/b] the old build muted master with a bus mute flag instead; -80 dB is inaudible.
const MUTED_DB: float = -80.0

## [member is_opening_swap_on] for a new save file, or for a missing or invalid value: on, for
## casual players (combat core plan, question 17; the orchestrator's P07 design item).
const DEFAULT_OPENING_SWAP: bool = true

## The opening-swap setting's key in the file's [code]core[/code]. Never rename it without a
## migration: the saved value would silently become the default.
const OPENING_SWAP_KEY: String = "opening_swap"

# dB added to the 0-10 level, per channel (options_config.gd:25,29,33). Master at 10 is +5 dB,
# above unity; carried over unchanged.
const _OFFSET_DB: Dictionary[Channel, float] = {
	Channel.MASTER: -5.0,
	Channel.MUSIC: -20.0,
	Channel.SFX: -20.0,
}

const _KEYS: Dictionary[Channel, String] = {
	Channel.MASTER: "master_volume",
	Channel.MUSIC: "music_volume",
	Channel.SFX: "sfx_volume",
}

## Master volume. [b]Range:[/b] [constant MIN_VOLUME] (muted) to [constant MAX_VOLUME].
var master_volume: int = DEFAULT_VOLUME
## Music volume. [b]Range:[/b] [constant MIN_VOLUME] (muted) to [constant MAX_VOLUME].
var music_volume: int = DEFAULT_VOLUME
## Sound effects volume. [b]Range:[/b] [constant MIN_VOLUME] (muted) to [constant MAX_VOLUME].
var sfx_volume: int = DEFAULT_VOLUME
## Whether a solo battle opens in the swap window before turn 1, closed by Start (on), or starts
## turn 1 at once (off): [member CampaignSession.BattleRequest.opening_swap] for the run's seat.
var is_opening_swap_on: bool = DEFAULT_OPENING_SWAP


## Returns the 0-10 volume of [param channel].
func get_volume(channel: Channel) -> int:
	match channel:
		Channel.MUSIC:
			return music_volume
		Channel.SFX:
			return sfx_volume
	return master_volume


## Sets [param channel] to [param value], clamped to [constant MIN_VOLUME]-[constant MAX_VOLUME].
func set_volume(channel: Channel, value: int) -> void:
	var clamped: int = clampi(value, MIN_VOLUME, MAX_VOLUME)
	match channel:
		Channel.MASTER:
			master_volume = clamped
		Channel.MUSIC:
			music_volume = clamped
		Channel.SFX:
			sfx_volume = clamped


## Returns the bus volume for [param channel]: [constant MUTED_DB] at 0, otherwise the level plus
## the channel's offset. [b]Units:[/b] dB.
func get_volume_db(channel: Channel) -> float:
	var level: int = get_volume(channel)
	if level == MIN_VOLUME:
		return MUTED_DB
	return float(level) + _OFFSET_DB[channel]


## Applies these settings to the game. A stub: there is no audio system yet, and the opening swap
## is read when a battle begins.
func apply() -> void:
	# TODO(TOD-001): Set each audio bus to get_volume_db() once the audio system adds the buses.
	pass


## Returns an independent copy, for screens that edit settings before applying them.
func copy() -> SettingsData:
	var duplicate_settings: SettingsData = SettingsData.new()
	for channel: Channel in _KEYS:
		duplicate_settings.set_volume(channel, get_volume(channel))
	duplicate_settings.is_opening_swap_on = is_opening_swap_on
	return duplicate_settings


## Returns these settings as a [SaveFile] envelope, ready for [method SaveFile.write].
func to_envelope() -> Dictionary:
	var core: Dictionary = {}
	for channel: Channel in _KEYS:
		core[_KEYS[channel]] = get_volume(channel)
	core[OPENING_SWAP_KEY] = is_opening_swap_on
	return SaveFile.make_envelope(SCHEMA_VERSION, core)


## Fills these settings from [param envelope], migrating it to [constant SCHEMA_VERSION] first.
##
## Edits [param envelope] while migrating. Each volume is clamped to range; a missing value or one
## that isn't a number becomes [constant DEFAULT_VOLUME]. A missing opening swap, or one that isn't
## a JSON bool, becomes [constant DEFAULT_OPENING_SWAP]. On error the settings are unchanged.
## Returns [constant OK] or the [method SaveMigrations.run] error.
func load_envelope(envelope: Dictionary) -> Error:
	var err: Error = SaveMigrations.run(envelope, SCHEMA_VERSION, _migration_steps())
	if err != OK:
		return err

	var core: Dictionary = envelope[SaveFile.KEY_CORE]
	for channel: Channel in _KEYS:
		set_volume(channel, _read_volume(core.get(_KEYS[channel])))
	is_opening_swap_on = _read_bool(core.get(OPENING_SWAP_KEY), DEFAULT_OPENING_SWAP)
	return OK


# Fractional values round to the nearest step; anything that isn't a number is the default.
func _read_volume(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			var whole: int = value
			return whole
		TYPE_FLOAT:
			var fractional: float = value
			return roundi(fractional)
	return DEFAULT_VOLUME


# Only a JSON bool counts; 0, 1, "true" or null give the default, as a mistyped volume does.
func _read_bool(value: Variant, fallback: bool) -> bool:
	if typeof(value) != TYPE_BOOL:
		return fallback
	var flag: bool = value
	return flag


# One step per schema version after 1, oldest first; see SaveMigrations.
static func _migration_steps() -> Array[Callable]:
	return [_add_opening_swap]


# 1 -> 2: adds the opening-swap setting at its default. A value already there (a hand edit) is
# kept for load_envelope to read or repair.
static func _add_opening_swap(envelope: Dictionary) -> Error:
	var core: Variant = envelope.get(SaveFile.KEY_CORE)
	if not core is Dictionary:
		return ERR_INVALID_DATA
	var fields: Dictionary = core
	if not fields.has(OPENING_SWAP_KEY):
		fields[OPENING_SWAP_KEY] = DEFAULT_OPENING_SWAP
	return OK
