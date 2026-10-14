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
## [b]Play time[/b] counts only while a campaign is active ([member campaign]). Each
## [method save_checkpoint] adds the time since that file's last successful write to the campaign
## and to the profile; time since the last checkpoint is lost if the game quits without one.[br]
## [b]Why an autoload:[/b] the open save file outlives every screen change.
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md
##
## @todo: TOD-001 - Archive the run in [method end_solo_run] and [method abandon_solo_run]
## (plan milestone M7).

## A save file was opened and [member profile] is loaded.
## [param save_number]: 1 to [constant SAVE_FILE_COUNT].
signal save_file_opened(save_number: int)

## The open save file was closed; [member profile] is null again.
signal save_file_closed()

## A run ended and its campaign slot was emptied.
## [param mode]: which slot. [param won]: true for a win, false for a loss or abandon.
signal run_ended(mode: CampaignData.Mode, won: bool)

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

## The campaign being played, or null outside a run. Set by [method start_new_solo_run] and
## [method continue_solo_run]; saved only by [method save_checkpoint].
var campaign: CampaignData = null

# Time.get_ticks_msec() at each file's last successful play-time flush. Separate per file so a
# write that fails for one file can't make the other count the same time twice.
var _campaign_flush_msec: int = 0
var _profile_flush_msec: int = 0


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

	var solo: CampaignData = CampaignData.new()
	var solo_path: String = _get_campaign_path(save_number, CampaignData.Mode.SOLO)
	var solo_err: Error = _load_campaign_into(solo_path, solo)
	if solo_err == ERR_FILE_NOT_FOUND:
		summary.solo_state = SaveFileSummary.State.EMPTY
	elif solo_err != OK:
		summary.solo_state = _get_failure_state(solo_err)
	else:
		summary.solo_state = SaveFileSummary.State.READY
		summary.solo_floors_climbed = solo.floors_climbed
		summary.solo_last_opened = solo.last_opened
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


## Closes the open save file, if any, and drops the active campaign. Writes nothing; every save
## happens at its own trigger.
func close_save_file() -> void:
	if not has_open_save_file():
		return
	current_save_number = NO_SAVE_FILE
	profile = null
	campaign = null
	save_file_closed.emit()


## True when the open save file has a solo run in progress, readable or not.
func has_solo_campaign() -> bool:
	if not has_open_save_file():
		return false
	return SaveFile.exists(_get_campaign_path(current_save_number, CampaignData.Mode.SOLO))


## Starts a new solo run in the open save file and writes its first save.
##
## The run becomes [member campaign] and play time starts counting.
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open,
## [constant ERR_ALREADY_EXISTS] when a solo run is already in progress, or the write error; on
## error no campaign is active.
func start_new_solo_run() -> Error:
	if not has_open_save_file():
		push_error("SaveService: can't start a run with no save file open.")
		return ERR_UNCONFIGURED
	if has_solo_campaign():
		push_error("SaveService: save %d already has a solo run." % [current_save_number])
		return ERR_ALREADY_EXISTS

	# ASSUMPTION: a random seed until run setup chooses one; run setup belongs to the campaign
	# system (plan, Scope).
	campaign = CampaignData.create_solo(randi())
	_start_play_clock()
	var err: Error = save_checkpoint()
	if err != OK:
		campaign = null
	return err


## Loads the open save file's solo run as [member campaign] and starts counting play time.
##
## Writes nothing; the next checkpoint saves.
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open, or the read or load
## error; on error no campaign is active.
func continue_solo_run() -> Error:
	campaign = null
	if not has_open_save_file():
		push_error("SaveService: can't continue a run with no save file open.")
		return ERR_UNCONFIGURED

	var loaded: CampaignData = CampaignData.new()
	var path: String = _get_campaign_path(current_save_number, CampaignData.Mode.SOLO)
	var err: Error = _load_campaign_into(path, loaded)
	if err != OK:
		return err
	if loaded.mode != CampaignData.Mode.SOLO:
		push_error("SaveService: %s is not a solo campaign." % [path])
		return ERR_INVALID_DATA

	campaign = loaded
	_start_play_clock()
	return OK


## Saves [member campaign] at a checkpoint (plan, row 13), then the profile.
##
## Adds play time since each file's last successful write, raises
## [member CampaignData.checkpoint_seq] by one and sets [member CampaignData.last_opened] to now.
## A failed write leaves that file's in-memory values and play-time flush point unchanged, so the
## time is added once by the next successful save.
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no active campaign, or the first write
## error; the profile isn't written when the campaign write fails.
func save_checkpoint() -> Error:
	if campaign == null or not has_open_save_file():
		push_error("SaveService: no active campaign to save.")
		return ERR_UNCONFIGURED

	var now_msec: int = Time.get_ticks_msec()
	var campaign_err: Error = _write_campaign(now_msec)
	if campaign_err != OK:
		return campaign_err
	return _write_profile(now_msec)


## Ends the active solo run as a win or loss: flushes play time to the profile, empties the solo
## slot and emits [signal run_ended].
##
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no active solo campaign, or the first
## write or delete error. The run ends even when the profile write fails.
func end_solo_run(won: bool) -> Error:
	if campaign == null or campaign.mode != CampaignData.Mode.SOLO or not has_open_save_file():
		push_error("SaveService: no active solo run to end.")
		return ERR_UNCONFIGURED

	var profile_err: Error = _write_profile(Time.get_ticks_msec())
	# TODO(TOD-001): Write the archive record with the outcome before deleting (plan M7).
	var path: String = _get_campaign_path(current_save_number, CampaignData.Mode.SOLO)
	var delete_err: Error = SaveFile.delete(path)
	campaign = null
	run_ended.emit(CampaignData.Mode.SOLO, won)
	return delete_err if delete_err != OK else profile_err


## Abandons the open save file's solo run from the Main Menu: empties the slot as a loss and emits
## [signal run_ended]. Play time was already counted at the run's last checkpoint.
##
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open, or the delete error.
func abandon_solo_run() -> Error:
	if not has_open_save_file():
		push_error("SaveService: can't abandon a run with no save file open.")
		return ERR_UNCONFIGURED
	if campaign != null and campaign.mode == CampaignData.Mode.SOLO:
		campaign = null

	# TODO(TOD-001): Archive the run as lost before deleting (plan M7).
	var path: String = _get_campaign_path(current_save_number, CampaignData.Mode.SOLO)
	var err: Error = SaveFile.delete(path)
	if err == OK:
		run_ended.emit(CampaignData.Mode.SOLO, false)
	return err


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


func _get_campaign_path(save_number: int, slot_mode: CampaignData.Mode) -> String:
	return get_save_file_dir(save_number) + CampaignData.get_file_name(slot_mode)


# Reads and loads one campaign file into target. Returns ERR_FILE_NOT_FOUND for an empty slot.
func _load_campaign_into(path: String, target: CampaignData) -> Error:
	var result: SaveFile.ReadResult = SaveFile.read(path)
	if result.error != OK:
		return result.error
	return target.load_envelope(result.envelope)


func _start_play_clock() -> void:
	var now_msec: int = Time.get_ticks_msec()
	_campaign_flush_msec = now_msec
	_profile_flush_msec = now_msec


func _write_campaign(now_msec: int) -> Error:
	var seconds: int = _get_whole_seconds_since(_campaign_flush_msec, now_msec)
	var previous_play_time: int = campaign.play_time_seconds
	var previous_seq: int = campaign.checkpoint_seq
	var previous_opened: int = campaign.last_opened

	campaign.play_time_seconds += seconds
	campaign.checkpoint_seq += 1
	campaign.last_opened = int(Time.get_unix_time_from_system())
	var path: String = _get_campaign_path(current_save_number, campaign.mode)
	var err: Error = SaveFile.write(path, campaign.to_envelope())
	if err != OK:
		campaign.play_time_seconds = previous_play_time
		campaign.checkpoint_seq = previous_seq
		campaign.last_opened = previous_opened
		return err

	_campaign_flush_msec += seconds * 1000
	return OK


func _write_profile(now_msec: int) -> Error:
	var seconds: int = _get_whole_seconds_since(_profile_flush_msec, now_msec)
	profile.play_time_seconds += seconds
	var err: Error = SaveFile.write(_get_profile_path(current_save_number), profile.to_envelope())
	if err != OK:
		profile.play_time_seconds -= seconds
		return err

	_profile_flush_msec += seconds * 1000
	return OK


# Whole seconds only; the leftover milliseconds stay behind the flush point for the next save.
@warning_ignore("integer_division")
func _get_whole_seconds_since(since_msec: int, now_msec: int) -> int:
	return maxi(now_msec - since_msec, 0) / 1000


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
