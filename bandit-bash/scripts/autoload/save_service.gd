# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_service.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Node
## Owns which save file is open, and every read and write of save data.
##
## Registered as autoload [code]SaveService[/code], after [code]NetLog[/code]. Screens ask it for
## data and never touch disk; every file goes through [SaveFile].[br]
## A save file is the folder [code]user://saves/save_N/[/code], N from 1 to
## [constant SAVE_FILE_COUNT]. The game always opens one on Save Select before the Main Menu, and
## [constant LAST_SELECTED_PATH] remembers the last one across launches (Save Select focus,
## accepted invites).[br]
## [b]Why an autoload:[/b] the open save file outlives every screen change.
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md

## A save file was opened and [member profile] is loaded.
## [param save_number]: 1 to [constant SAVE_FILE_COUNT].
signal save_file_opened(save_number: int)

## The open save file was closed; [member profile] is null again.
signal save_file_closed()

## Number of save files. Carried over from [code]Godot_FE/Game Start Screen/start_screen.gd[/code]
## (three slots).
const SAVE_FILE_COUNT: int = 3

## [member current_save_number] when no save file is open.
const NO_SAVE_FILE: int = 0

## Folder holding every save file.
const SAVES_DIR: String = "user://saves/"

## Remembers the last opened save file.
const LAST_SELECTED_PATH: String = SAVES_DIR + "last_selected.json"

const _LAST_SELECTED_SCHEMA_VERSION: int = 1
const _KEY_SAVE_NUMBER: String = "save_number"

## The open save file, 1 to [constant SAVE_FILE_COUNT], or [constant NO_SAVE_FILE].
var current_save_number: int = NO_SAVE_FILE

## Profile of the open save file. Null when [member current_save_number] is
## [constant NO_SAVE_FILE].
var profile: ProfileData = null

## Settings in effect: the open save file's, or, before one is opened, the last selected one's
## (see [method load_startup_settings]). Never null; defaults when there is nothing to load.
## Closing a save file keeps its settings in effect. Change it through [method save_settings].
var settings: SettingsData = SettingsData.new()


## True while a save file is open.
func has_open_save_file() -> bool:
	return current_save_number != NO_SAVE_FILE


## True for 1 to [constant SAVE_FILE_COUNT].
func is_valid_save_number(save_number: int) -> bool:
	return save_number >= 1 and save_number <= SAVE_FILE_COUNT


## Folder of save file [param save_number], with a trailing slash.
func get_save_file_dir(save_number: int) -> String:
	return SAVES_DIR + "save_%d/" % [save_number]


## Reads what Save Select shows for [param save_number] without opening it.
##
## Like any [method SaveFile.read], this repairs a file from its backup when it has to; the
## summary reports that once in [member SaveFileSummary.was_recovered].
func get_summary(save_number: int) -> SaveFileSummary:
	var summary: SaveFileSummary = SaveFileSummary.new()
	summary.save_number = save_number

	var result: SaveFile.ReadResult = SaveFile.read(_get_profile_path(save_number))
	if result.error == ERR_FILE_NOT_FOUND:
		summary.state = SaveFileSummary.State.EMPTY
		return summary
	if result.error != OK:
		summary.state = _get_failure_state(result.error)
		return summary

	var loaded: ProfileData = ProfileData.new()
	var load_err: Error = loaded.load_envelope(result.envelope)
	if load_err != OK:
		summary.state = _get_failure_state(load_err)
		return summary

	summary.state = SaveFileSummary.State.READY
	summary.was_recovered = result.was_recovered()
	summary.player_name = loaded.last_steam_name
	summary.play_time_seconds = loaded.play_time_seconds
	return summary


## Opens save file [param save_number], creating it if it's empty, and remembers it as last
## selected.
##
## Closes any open save file first. Refreshes [member ProfileData.last_steam_name] when Steam is
## available. On any error nothing is left open.
## Returns [constant OK], [constant ERR_PARAMETER_RANGE_ERROR], or the read, migration or write
## error; [constant ERR_FILE_UNRECOGNIZED] means a newer game wrote it.
func open_save_file(save_number: int) -> Error:
	if not is_valid_save_number(save_number):
		push_error("SaveService: no save file %d." % [save_number])
		return ERR_PARAMETER_RANGE_ERROR
	close_save_file()

	var path: String = _get_profile_path(save_number)
	var result: SaveFile.ReadResult = SaveFile.read(path)
	var loaded: ProfileData = null
	var needs_write: bool = false

	if result.error == ERR_FILE_NOT_FOUND:
		loaded = ProfileData.create_new()
		needs_write = true
	elif result.error != OK:
		return result.error
	else:
		loaded = ProfileData.new()
		var load_err: Error = loaded.load_envelope(result.envelope)
		if load_err != OK:
			return load_err

	var steam_name: String = _get_steam_name()
	if not steam_name.is_empty() and steam_name != loaded.last_steam_name:
		loaded.last_steam_name = steam_name
		needs_write = true

	if needs_write:
		var write_err: Error = SaveFile.write(path, loaded.to_envelope())
		if write_err != OK:
			return write_err

	current_save_number = save_number
	profile = loaded
	settings = _read_settings(save_number)
	settings.apply()
	_write_last_selected(save_number)
	save_file_opened.emit(save_number)
	return OK


## Closes the open save file, if any. Writes nothing; every save happens at its own trigger.
func close_save_file() -> void:
	if not has_open_save_file():
		return
	current_save_number = NO_SAVE_FILE
	profile = null
	save_file_closed.emit()


## Deletes save file [param save_number] and everything in it, archive included. Cannot be undone.
##
## Closes it first if it's open, and forgets it as last selected.
## Returns [constant OK], [constant ERR_PARAMETER_RANGE_ERROR], or the deletion error.
func delete_save_file(save_number: int) -> Error:
	if not is_valid_save_number(save_number):
		push_error("SaveService: no save file %d." % [save_number])
		return ERR_PARAMETER_RANGE_ERROR
	if current_save_number == save_number:
		close_save_file()

	var err: Error = SaveFile.delete_folder(get_save_file_dir(save_number))
	if err != OK:
		return err
	if _read_last_selected() == save_number:
		SaveFile.delete(LAST_SELECTED_PATH)
	return OK


## Loads and applies the last selected save file's settings, or defaults when there is none.
##
## [code]boot.gd[/code] calls this once before the first screen, so Start and Save Select already
## use the player's settings. Nothing is written.
func load_startup_settings() -> void:
	var save_number: int = get_last_selected()
	if save_number == NO_SAVE_FILE:
		settings = SettingsData.new()
	else:
		settings = _read_settings(save_number)
	settings.apply()


## Writes [param new_settings] to the open save file's settings file, and nothing else, then
## makes a copy of them the settings in effect and applies them.
##
## Returns [constant OK], [constant ERR_UNCONFIGURED] when no save file is open, or the write
## error; on any error [member settings] is unchanged.
func save_settings(new_settings: SettingsData) -> Error:
	if not has_open_save_file():
		push_error("SaveService: can't save settings with no save file open.")
		return ERR_UNCONFIGURED

	var path: String = _get_settings_path(current_save_number)
	var err: Error = SaveFile.write(path, new_settings.to_envelope())
	if err != OK:
		return err
	settings = new_settings.copy()
	settings.apply()
	return OK


## The last opened save file if it still exists, else [constant NO_SAVE_FILE].
func get_last_selected() -> int:
	var save_number: int = _read_last_selected()
	if save_number == NO_SAVE_FILE:
		return NO_SAVE_FILE
	if not SaveFile.exists(_get_profile_path(save_number)):
		return NO_SAVE_FILE
	return save_number


func _get_profile_path(save_number: int) -> String:
	return get_save_file_dir(save_number) + ProfileData.FILE_NAME


func _get_settings_path(save_number: int) -> String:
	return get_save_file_dir(save_number) + SettingsData.FILE_NAME


# Missing settings are normal (nothing applied yet) and give defaults. An unreadable or too-new
# file also gives defaults, with a warning, rather than blocking the save file from opening.
func _read_settings(save_number: int) -> SettingsData:
	var loaded: SettingsData = SettingsData.new()
	var result: SaveFile.ReadResult = SaveFile.read(_get_settings_path(save_number))
	if result.error == ERR_FILE_NOT_FOUND:
		return loaded
	if result.error != OK or loaded.load_envelope(result.envelope) != OK:
		push_warning("SaveService: settings of save %d unreadable; using defaults." % [save_number])
		return SettingsData.new()
	return loaded


func _get_failure_state(err: Error) -> SaveFileSummary.State:
	if err == ERR_FILE_UNRECOGNIZED:
		return SaveFileSummary.State.TOO_NEW
	return SaveFileSummary.State.UNREADABLE


func _get_steam_name() -> String:
	if not SteamManager.is_available:
		return ""
	return Steam.getPersonaName()


# Returns the stored save number, or NO_SAVE_FILE when the pointer is missing or invalid. Doesn't
# check that the save file still exists; get_last_selected() does.
func _read_last_selected() -> int:
	var result: SaveFile.ReadResult = SaveFile.read(LAST_SELECTED_PATH)
	if result.error != OK:
		return NO_SAVE_FILE

	var steps: Array[Callable] = []
	if SaveMigrations.run(result.envelope, _LAST_SELECTED_SCHEMA_VERSION, steps) != OK:
		return NO_SAVE_FILE

	var core: Dictionary = result.envelope[SaveFile.KEY_CORE]
	var save_number: int = int(core.get(_KEY_SAVE_NUMBER, NO_SAVE_FILE))
	return save_number if is_valid_save_number(save_number) else NO_SAVE_FILE


# A failure only costs Save Select its focus hint, so it's a warning, not an error for the caller.
func _write_last_selected(save_number: int) -> void:
	var envelope: Dictionary = SaveFile.make_envelope(
			_LAST_SELECTED_SCHEMA_VERSION, {_KEY_SAVE_NUMBER: save_number}
	)
	var err: Error = SaveFile.write(LAST_SELECTED_PATH, envelope)
	if err != OK:
		push_warning("SaveService: couldn't remember save %d as last selected." % [save_number])
