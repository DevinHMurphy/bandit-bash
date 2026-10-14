# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_data.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name CampaignData
extends RefCounted
## The campaign block: one run in progress, solo or multiplayer.
##
## A save file has one campaign slot per [enum Mode], stored as [method get_file_name] in its
## folder. [code]SaveService[/code] decides when to read and write it; this class converts between
## its fields and a [SaveFile] envelope.[br]
## Solo and multiplayer share one shape: [member players] holds one [CampaignData.PlayerRun] per
## seat, and solo is a single seat 0 with no Steam id.[br]
## Level and progress fields carry the old build's meaning
## ([code]Godot_FE/overworld_new/player_overworld_data.gd:16-18[/code]) until the campaign system is
## ported and defines them.
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md

## Which campaign slot of a save file this is.
enum Mode {
	## Single player; [code]campaign_solo.json[/code].
	SOLO = 0,
	## Multiplayer, host only; [code]campaign_multi.json[/code].
	MULTIPLAYER = 1,
}

## Current schema version of this block. Raising it needs a step in [method _migration_steps].
const SCHEMA_VERSION: int = 1

## Seat of the host, and of the only player in solo.
const HOST_SEAT: int = 0

const _FILE_NAMES: Dictionary[Mode, String] = {
	Mode.SOLO: "campaign_solo.json",
	Mode.MULTIPLAYER: "campaign_multi.json",
}

# Stored as strings, not enum ints, so reordering Mode can't silently change saved files.
const _MODE_IDS: Dictionary[Mode, String] = {
	Mode.SOLO: "solo",
	Mode.MULTIPLAYER: "multiplayer",
}

const _KEY_MODE: String = "mode"
const _KEY_SEED: String = "seed"
const _KEY_DIFFICULTY: String = "difficulty"
const _KEY_MODIFIERS: String = "modifiers"
const _KEY_PLAY_TIME_SECONDS: String = "play_time_seconds"
const _KEY_STARTED_AT: String = "started_at"
const _KEY_LAST_OPENED: String = "last_opened"
const _KEY_LEVEL_ID: String = "level_id"
const _KEY_FLOORS_CLIMBED: String = "floors_climbed"
const _KEY_COMBAT_MAPS_COMPLETED: String = "combat_maps_completed"
const _KEY_PLAYERS: String = "players"
const _KEY_COMBAT_IN_PROGRESS: String = "combat_in_progress"

## Which slot this campaign lives in.
var mode: Mode = Mode.SOLO

## Seed the run was generated from. Generated results are saved too, so a later change to a
## generator can't alter a run in progress. Named [code]run_seed[/code] to avoid shadowing
## [method @GlobalScope.seed].
var run_seed: int = 0

## Difficulty id. Empty until run setup exists.
var difficulty: String = ""

## Run modifier ids. Empty until run setup exists.
var modifiers: PackedStringArray = []

## Time played in this run.[br]
## [b]Units:[/b] seconds.
var play_time_seconds: int = 0

## When the run started.[br]
## [b]Units:[/b] Unix seconds, UTC.
var started_at: int = 0

## When the run was last saved; shown as "last played".[br]
## [b]Units:[/b] Unix seconds, UTC.
var last_opened: int = 0

## True from the moment a battle's Begin is saved until the battle ends. While true, everything
## the battle changes lives only in the combat file and this campaign keeps its sections as they
## were at Begin, which is what lets a lost combat file restart the battle ([CombatData]).
var combat_in_progress: bool = false

## Counts every write of this campaign. A combat file is only valid beside the campaign write it
## was paired with (plan, "Combat crash protection").
var checkpoint_seq: int = 0

## Id of the current level. Empty until the campaign system defines levels.
var level_id: String = ""

## Floors climbed this run.
var floors_climbed: int = 0

## Key combat maps completed this run.
var combat_maps_completed: int = 0

## One entry per seat, ordered by seat. Never empty in a loaded or created campaign.
var players: Array[PlayerRun] = []

## Section key to [code]{"version": int, "data": Dictionary}[/code], as stored on disk.
## [code]SaveService[/code] moves it to and from the registered [SaveSection]s
## ([SaveSectionRegistry]); this class only stores it.
var sections: Dictionary = {}


## Returns this campaign as a [SaveFile] envelope, ready for [method SaveFile.write].
func to_envelope() -> Dictionary:
	var player_entries: Array[Dictionary] = []
	for player: PlayerRun in players:
		player_entries.append(player.to_dict())

	var core: Dictionary = {
		_KEY_MODE: _MODE_IDS[mode],
		_KEY_SEED: run_seed,
		_KEY_DIFFICULTY: difficulty,
		_KEY_MODIFIERS: Array(modifiers),
		_KEY_PLAY_TIME_SECONDS: play_time_seconds,
		_KEY_STARTED_AT: started_at,
		_KEY_LAST_OPENED: last_opened,
		_KEY_LEVEL_ID: level_id,
		_KEY_FLOORS_CLIMBED: floors_climbed,
		_KEY_COMBAT_MAPS_COMPLETED: combat_maps_completed,
		_KEY_PLAYERS: player_entries,
		_KEY_COMBAT_IN_PROGRESS: combat_in_progress,
	}
	return SaveFile.make_envelope(SCHEMA_VERSION, core, sections.duplicate(true), checkpoint_seq)


## Fills this campaign from [param envelope], migrating it to [constant SCHEMA_VERSION] first.
##
## Edits [param envelope] while migrating. Missing simple fields keep their defaults. On error the
## campaign is left unchanged.
## Returns [constant OK]; [constant ERR_INVALID_DATA] for an unknown mode or a missing or malformed
## player list; or the [method SaveMigrations.run] error.
func load_envelope(envelope: Dictionary) -> Error:
	var err: Error = SaveMigrations.run(envelope, SCHEMA_VERSION, _migration_steps())
	if err != OK:
		return err

	var core: Dictionary = envelope[SaveFile.KEY_CORE]
	var mode_key: Variant = _MODE_IDS.find_key(str(core.get(_KEY_MODE, "")))
	if mode_key == null:
		return ERR_INVALID_DATA
	var loaded_players: Array[PlayerRun] = _read_players(core.get(_KEY_PLAYERS))
	if loaded_players.is_empty():
		return ERR_INVALID_DATA

	mode = mode_key
	run_seed = int(core.get(_KEY_SEED, 0))
	difficulty = str(core.get(_KEY_DIFFICULTY, ""))
	modifiers = _read_strings(core.get(_KEY_MODIFIERS))
	play_time_seconds = maxi(int(core.get(_KEY_PLAY_TIME_SECONDS, 0)), 0)
	started_at = int(core.get(_KEY_STARTED_AT, 0))
	last_opened = int(core.get(_KEY_LAST_OPENED, 0))
	checkpoint_seq = int(envelope[SaveFile.KEY_CHECKPOINT_SEQ])
	level_id = str(core.get(_KEY_LEVEL_ID, ""))
	floors_climbed = maxi(int(core.get(_KEY_FLOORS_CLIMBED, 0)), 0)
	combat_maps_completed = maxi(int(core.get(_KEY_COMBAT_MAPS_COMPLETED, 0)), 0)
	combat_in_progress = core.get(_KEY_COMBAT_IN_PROGRESS, false) == true
	players = loaded_players
	sections = envelope[SaveFile.KEY_SECTIONS]
	return OK


## Returns a new solo campaign: seat 0 only, started now.
## [param new_seed]: the run seed.
static func create_solo(new_seed: int) -> CampaignData:
	var campaign: CampaignData = CampaignData.new()
	var now: int = int(Time.get_unix_time_from_system())
	campaign.mode = Mode.SOLO
	campaign.run_seed = new_seed
	campaign.started_at = now
	campaign.last_opened = now

	var host: PlayerRun = PlayerRun.new()
	host.seat = HOST_SEAT
	campaign.players.append(host)
	return campaign


## File name of the campaign slot for [param slot_mode], inside a save file's folder.
static func get_file_name(slot_mode: Mode) -> String:
	return _FILE_NAMES[slot_mode]


# Returns an empty array when the list is missing or any entry is malformed; the caller treats
# that as invalid data rather than loading a campaign with players silently dropped.
static func _read_players(value: Variant) -> Array[PlayerRun]:
	var loaded: Array[PlayerRun] = []
	if typeof(value) != TYPE_ARRAY:
		return loaded

	var entries: Array = value
	for entry: Variant in entries:
		var player: PlayerRun = PlayerRun.from_dict(entry)
		if player == null:
			loaded.clear()
			return loaded
		loaded.append(player)
	return loaded


static func _read_strings(value: Variant) -> PackedStringArray:
	var strings: PackedStringArray = []
	if typeof(value) != TYPE_ARRAY:
		return strings
	var entries: Array = value
	for entry: Variant in entries:
		strings.append(str(entry))
	return strings


# One step per schema version after 1, oldest first; see SaveMigrations.
static func _migration_steps() -> Array[Callable]:
	return []


## One player's part of a campaign: the seat and the data owned per player.
class PlayerRun:
	extends RefCounted

	const _KEY_SEAT: String = "seat"
	const _KEY_STEAM_ID: String = "steam_id"
	const _KEY_SECTIONS: String = "sections"

	## Stable id for the life of the campaign; [constant CampaignData.HOST_SEAT] is the host.
	var seat: int = 0
	## Steam id as a decimal string (too large for a JSON number). Empty in solo.
	var steam_id: String = ""
	## Per-player section key (roster, inventory, convoy, economy) to
	## [code]{"version": int, "data": Dictionary}[/code], as stored on disk. Moved to and from the
	## registered [PlayerSaveSection]s by [SaveSectionRegistry].
	var sections: Dictionary = {}

	## Returns this player as plain data for the envelope.
	func to_dict() -> Dictionary:
		return {
			_KEY_SEAT: seat,
			_KEY_STEAM_ID: steam_id,
			_KEY_SECTIONS: sections.duplicate(true),
		}

	## Returns a player read from [param value], or null when it isn't a well-formed entry.
	static func from_dict(value: Variant) -> PlayerRun:
		if typeof(value) != TYPE_DICTIONARY:
			return null
		var entry: Dictionary = value
		var seat_type: int = typeof(entry.get(_KEY_SEAT))
		if seat_type != TYPE_INT and seat_type != TYPE_FLOAT:
			return null
		if typeof(entry.get(_KEY_SECTIONS, {})) != TYPE_DICTIONARY:
			return null

		var player: PlayerRun = PlayerRun.new()
		player.seat = int(entry[_KEY_SEAT])
		player.steam_id = str(entry.get(_KEY_STEAM_ID, ""))
		player.sections = entry.get(_KEY_SECTIONS, {})
		return player
