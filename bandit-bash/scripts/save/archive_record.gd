# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     archive_record.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name ArchiveRecord
extends RefCounted
## A record of one ended run, won or lost, kept in the save file's [code]archive/[/code] folder.
##
## Built from the campaign just before its slot is emptied ([method from_campaign]) and written
## once; nothing changes it afterwards. All plain data, so a multiplayer host can send it to every
## player to keep in their own archive (plan milestone M11). An archive viewer reads it later.
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md

## Current schema version of this block. Raising it needs a step in [method _migration_steps].
const SCHEMA_VERSION: int = 1

## Folder inside a save file's folder that holds the records.
const FOLDER_NAME: String = "archive"

## The per-player section copied into each record. Matches the per-player roster section key.
const ROSTER_SECTION_KEY: String = "roster"

const _KEY_MODE: String = "mode"
const _KEY_OUTCOME: String = "outcome"
const _KEY_STARTED_AT: String = "started_at"
const _KEY_ENDED_AT: String = "ended_at"
const _KEY_PLAY_TIME_SECONDS: String = "play_time_seconds"
const _KEY_SEED: String = "seed"
const _KEY_DIFFICULTY: String = "difficulty"
const _KEY_MODIFIERS: String = "modifiers"
const _KEY_FLOORS_CLIMBED: String = "floors_climbed"
const _KEY_COMBAT_MAPS_COMPLETED: String = "combat_maps_completed"
const _KEY_PLAYERS: String = "players"

const _OUTCOME_WON: String = "won"
const _OUTCOME_LOST: String = "lost"

## Which campaign slot the run was in.
var mode: CampaignData.Mode = CampaignData.Mode.SOLO
## True for a win; false for a loss or an abandoned run.
var won: bool = false
## When the run started. [b]Units:[/b] Unix seconds, UTC.
var started_at: int = 0
## When the run ended. [b]Units:[/b] Unix seconds, UTC.
var ended_at: int = 0
## Total time played in the run. [b]Units:[/b] seconds.
var play_time_seconds: int = 0
## The run's seed.
var run_seed: int = 0
## Difficulty id; empty until run setup exists.
var difficulty: String = ""
## Run modifier ids.
var modifiers: PackedStringArray = []
## Floors climbed.
var floors_climbed: int = 0
## Key combat maps completed.
var combat_maps_completed: int = 0
## One entry per seat, as the run ended.
var players: Array[ArchivedPlayer] = []


## Returns this record as a [SaveFile] envelope, ready for [method SaveFile.write].
func to_envelope() -> Dictionary:
	var player_entries: Array[Dictionary] = []
	for player: ArchivedPlayer in players:
		player_entries.append(player.to_dict())

	var core: Dictionary = {
		_KEY_MODE: CampaignData.get_mode_id(mode),
		_KEY_OUTCOME: _OUTCOME_WON if won else _OUTCOME_LOST,
		_KEY_STARTED_AT: started_at,
		_KEY_ENDED_AT: ended_at,
		_KEY_PLAY_TIME_SECONDS: play_time_seconds,
		_KEY_SEED: run_seed,
		_KEY_DIFFICULTY: difficulty,
		_KEY_MODIFIERS: Array(modifiers),
		_KEY_FLOORS_CLIMBED: floors_climbed,
		_KEY_COMBAT_MAPS_COMPLETED: combat_maps_completed,
		_KEY_PLAYERS: player_entries,
	}
	return SaveFile.make_envelope(SCHEMA_VERSION, core)


## Fills this record from [param envelope], migrating it to [constant SCHEMA_VERSION] first.
##
## Edits [param envelope] while migrating. On error the record is left unchanged.
## Returns [constant OK]; [constant ERR_INVALID_DATA] for an unknown mode or outcome or a
## malformed player list; or the [method SaveMigrations.run] error.
func load_envelope(envelope: Dictionary) -> Error:
	var err: Error = SaveMigrations.run(envelope, SCHEMA_VERSION, _migration_steps())
	if err != OK:
		return err

	var core: Dictionary = envelope[SaveFile.KEY_CORE]
	var loaded_mode: int = CampaignData.find_mode(str(core.get(_KEY_MODE, "")))
	var outcome: String = str(core.get(_KEY_OUTCOME, ""))
	if loaded_mode == -1 or (outcome != _OUTCOME_WON and outcome != _OUTCOME_LOST):
		return ERR_INVALID_DATA

	var loaded_players: Array[ArchivedPlayer] = []
	var entries: Variant = core.get(_KEY_PLAYERS)
	if typeof(entries) != TYPE_ARRAY:
		return ERR_INVALID_DATA
	var entry_list: Array = entries
	for entry: Variant in entry_list:
		var player: ArchivedPlayer = ArchivedPlayer.from_dict(entry)
		if player == null:
			return ERR_INVALID_DATA
		loaded_players.append(player)

	mode = loaded_mode as CampaignData.Mode
	won = outcome == _OUTCOME_WON
	started_at = int(core.get(_KEY_STARTED_AT, 0))
	ended_at = int(core.get(_KEY_ENDED_AT, 0))
	play_time_seconds = maxi(int(core.get(_KEY_PLAY_TIME_SECONDS, 0)), 0)
	run_seed = int(core.get(_KEY_SEED, 0))
	difficulty = str(core.get(_KEY_DIFFICULTY, ""))
	modifiers = _read_strings(core.get(_KEY_MODIFIERS))
	floors_climbed = maxi(int(core.get(_KEY_FLOORS_CLIMBED, 0)), 0)
	combat_maps_completed = maxi(int(core.get(_KEY_COMBAT_MAPS_COMPLETED, 0)), 0)
	players = loaded_players
	return OK


## File name for this record inside [constant FOLDER_NAME], e.g. [code]solo_1760000000.json[/code].
## [code]SaveService[/code] adds a suffix if two runs end in the same second.
func get_file_name() -> String:
	return "%s_%d.json" % [CampaignData.get_mode_id(mode), ended_at]


## Returns a record of [param campaign] ending now.
##
## [param won]: the outcome. [param player_names]: seat to display name; seats without one get an
## empty name. Copies each player's [constant ROSTER_SECTION_KEY] section as saved, so call it
## after the campaign's sections were last captured.
static func from_campaign(
		campaign: CampaignData,
		run_won: bool,
		player_names: Dictionary[int, String]
) -> ArchiveRecord:
	var record: ArchiveRecord = ArchiveRecord.new()
	record.mode = campaign.mode
	record.won = run_won
	record.started_at = campaign.started_at
	record.ended_at = int(Time.get_unix_time_from_system())
	record.play_time_seconds = campaign.play_time_seconds
	record.run_seed = campaign.run_seed
	record.difficulty = campaign.difficulty
	record.modifiers = campaign.modifiers.duplicate()
	record.floors_climbed = campaign.floors_climbed
	record.combat_maps_completed = campaign.combat_maps_completed

	for campaign_player: CampaignData.PlayerRun in campaign.players:
		var player: ArchivedPlayer = ArchivedPlayer.new()
		player.seat = campaign_player.seat
		player.steam_id = campaign_player.steam_id
		player.name = player_names.get(campaign_player.seat, "")
		var roster: Variant = campaign_player.sections.get(ROSTER_SECTION_KEY, {})
		if typeof(roster) == TYPE_DICTIONARY:
			player.roster = roster.duplicate(true)
		record.players.append(player)
	return record


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


## One player as the run ended.
class ArchivedPlayer:
	extends RefCounted

	const _KEY_SEAT: String = "seat"
	const _KEY_STEAM_ID: String = "steam_id"
	const _KEY_NAME: String = "name"
	const _KEY_ROSTER: String = "roster"

	## The player's seat in the run.
	var seat: int = 0
	## Steam id as a decimal string. Empty in solo.
	var steam_id: String = ""
	## Display name when the run ended.
	var name: String = ""
	## The player's roster section entry as saved:
	## [code]{"version": int, "data": Dictionary}[/code], or empty when the run had none.
	var roster: Dictionary = {}

	## Returns this player as plain data for the envelope.
	func to_dict() -> Dictionary:
		return {
			_KEY_SEAT: seat,
			_KEY_STEAM_ID: steam_id,
			_KEY_NAME: name,
			_KEY_ROSTER: roster.duplicate(true),
		}

	## Returns a player read from [param value], or null when it isn't a well-formed entry.
	static func from_dict(value: Variant) -> ArchivedPlayer:
		if typeof(value) != TYPE_DICTIONARY:
			return null
		var entry: Dictionary = value
		var seat_type: int = typeof(entry.get(_KEY_SEAT))
		if seat_type != TYPE_INT and seat_type != TYPE_FLOAT:
			return null
		if typeof(entry.get(_KEY_ROSTER, {})) != TYPE_DICTIONARY:
			return null

		var player: ArchivedPlayer = ArchivedPlayer.new()
		player.seat = int(entry[_KEY_SEAT])
		player.steam_id = str(entry.get(_KEY_STEAM_ID, ""))
		player.name = str(entry.get(_KEY_NAME, ""))
		player.roster = entry.get(_KEY_ROSTER, {})
		return player
