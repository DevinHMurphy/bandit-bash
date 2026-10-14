# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     profile_data.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name ProfileData
extends RefCounted
## The profile block of a save file: who plays it and their progress across runs.
##
## Stored as [constant FILE_NAME] in the save file's folder. [code]SaveService[/code] decides when
## to read and write it; this class only converts between its fields and a [SaveFile] envelope.
## [br]
## Not player-editable: the name shown is always the Steam persona name, cached in
## [member last_steam_name] so a save file still shows a name while Steam is unavailable.
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md
##
## @todo: TOD-001 - Replace raw [member sections] with registered SaveSections (plan milestone M5).

## File name inside the save file's folder.
const FILE_NAME: String = "profile.json"

## Current schema version of this block. Raising it needs a step in [method _migration_steps].
const SCHEMA_VERSION: int = 1

const _KEY_LAST_STEAM_NAME: String = "last_steam_name"
const _KEY_PLAY_TIME_SECONDS: String = "play_time_seconds"
const _KEY_CREATED_AT: String = "created_at"

## Steam persona name seen when this save file was last opened. Empty if Steam never was available.
var last_steam_name: String = ""

## Total play time across every run of this save file.[br]
## [b]Units:[/b] seconds.
var play_time_seconds: int = 0

## When this save file was created.[br]
## [b]Units:[/b] Unix seconds, UTC.
var created_at: int = 0

# TODO(TOD-001): Replace with registered SaveSections (plan milestone M5).
## Section key to [code]{"version": int, "data": Dictionary}[/code]: unlocks, achievements,
## statistics, Hall of Heroes. Carried through unchanged so nothing written there is lost.
var sections: Dictionary = {}


## Returns this profile as a [SaveFile] envelope, ready for [method SaveFile.write].
func to_envelope() -> Dictionary:
	var core: Dictionary = {
		_KEY_LAST_STEAM_NAME: last_steam_name,
		_KEY_PLAY_TIME_SECONDS: play_time_seconds,
		_KEY_CREATED_AT: created_at,
	}
	return SaveFile.make_envelope(SCHEMA_VERSION, core, sections.duplicate(true))


## Fills this profile from [param envelope], migrating it to [constant SCHEMA_VERSION] first.
##
## Edits [param envelope] while migrating. Missing fields keep their defaults. On error the
## profile is left unchanged.
## Returns [constant OK] or the [method SaveMigrations.run] error;
## [constant ERR_FILE_UNRECOGNIZED] means a newer schema than this build knows.
func load_envelope(envelope: Dictionary) -> Error:
	var err: Error = SaveMigrations.run(envelope, SCHEMA_VERSION, _migration_steps())
	if err != OK:
		return err

	var core: Dictionary = envelope[SaveFile.KEY_CORE]
	last_steam_name = str(core.get(_KEY_LAST_STEAM_NAME, ""))
	play_time_seconds = maxi(int(core.get(_KEY_PLAY_TIME_SECONDS, 0)), 0)
	created_at = int(core.get(_KEY_CREATED_AT, 0))
	sections = envelope[SaveFile.KEY_SECTIONS]
	return OK


## Returns a profile for a brand-new save file, with [member created_at] set to now.
static func create_new() -> ProfileData:
	var profile: ProfileData = ProfileData.new()
	profile.created_at = int(Time.get_unix_time_from_system())
	return profile


# One step per schema version after 1, oldest first; see SaveMigrations.
static func _migration_steps() -> Array[Callable]:
	return []
