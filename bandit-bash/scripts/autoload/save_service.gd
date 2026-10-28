# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_service.gd
# Author:
# Created:  October 14, 2026
# Modified: October 28, 2026
# ==============================================================================

extends Node
## Owns which save file is open, and every read and write of save data.
##
## Registered as autoload [code]SaveService[/code], after [code]SteamNetwork[/code] (its
## [code]_ready()[/code] connects to it) and before [code]SceneRouter[/code]. Screens ask it for
## data and never touch disk; every file goes through [SaveFile]. [b]Why an autoload:[/b] the open
## save file outlives every screen change, and its multiplayer RPCs need the same path on every
## peer from boot.[br]
## A save file is [code]user://saves/save_N/[/code]; Save Select always opens one before the Main
## Menu, and [constant LAST_SELECTED_PATH] remembers it across launches.[br]
## [b]Play time[/b] counts while a campaign is active and is added to the campaign and profile at
## each [method save_checkpoint].[br]
## [b]Sections:[/b] systems keep their own data by registering with [method register_section].[br]
## [b]Battles:[/b] the combat file is written before the campaign with the same checkpoint
## number; [member resume_point] says whether a continued run resumes or restarts its battle.[br]
## [b]Ended runs[/b] are archived before their slot empties; see [member last_archive_error].[br]
## [b]Multiplayer:[/b] only the host saves the campaign. Clients keep [member multiplayer_replica]
## and write only their own profile and archive (kit P16).
##
## @tutorial(Save system design): docs/design/save-system.md

## A save file was opened and [member profile] is loaded.
## [param save_number]: 1 to [constant SAVE_FILE_COUNT].
signal save_file_opened(save_number: int)

## The open save file was closed; [member profile] is null again.
signal save_file_closed()

## A run became active on this machine as [member campaign]: a new one after its first save, a
## continued solo run, or a resumed multiplayer one. [code]CampaignService[/code] builds its session
## on it. Not emitted on a multiplayer client, which has no [member campaign].
## [param mode]: which slot. [param resumed]: false for a new run, true for a saved one.
signal campaign_activated(mode: CampaignData.Mode, resumed: bool)

## A run ended and its campaign slot was emptied.
## [param mode]: which slot. [param won]: true for a win, false for a loss or abandon.
signal run_ended(mode: CampaignData.Mode, won: bool)

## A checkpoint finished: [method save_checkpoint], [method begin_battle] or [method end_battle].
## [param error]: [constant OK], or why it failed; on failure the previous save is still on disk.
signal checkpoint_saved(error: Error)

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

# One --name=value token: a separate value token could be read by Godot as a scene path.
## Debug builds only: a user argument (after [code]--[/code]) that gives every new run this
## seed, in [method RunSeed.parse]'s form, e.g. [code]-- --run-seed=3F9A-12C0-77E1-A[/code].
## Lets a headless test start a known run.
const _RUN_SEED_ARG: String = "--run-seed="

# Section keys reserved for systems that don't exist yet (plan, Blocks). Each is held by a
# RawSaveSection until its system registers the real section under the same key.
const _RESERVED_PROFILE_SECTIONS: Array[String] = [
	"unlocks",
	"achievements",
	"statistics",
	"hall_of_heroes",
]
const _RESERVED_CAMPAIGN_SECTIONS: Array[String] = ["rng"]
const _RESERVED_COMBAT_SECTIONS: Array[String] = ["enemy_units", "entities", "rng"]

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

## The battle in progress, or null. Set by [method begin_battle] and by [method continue_solo_run]
## when it resumes a battle.
var combat: CombatData = null

## How the last [method continue_solo_run] picked up: on the campaign, inside the saved battle, or
## restarting a battle whose combat file was unusable. Gameplay reads it to know where to start.
var resume_point: CombatData.ResumePoint = CombatData.ResumePoint.CAMPAIGN

## Result of writing the archive record of the run that ended last: [constant OK], or why it
## couldn't be written (the run ended anyway). [constant ERR_UNCONFIGURED] before any run ends.
var last_archive_error: Error = ERR_UNCONFIGURED

## Multiplayer clients only: the host's campaign as of its last checkpoint. Never saved; null on
## the host, in solo, and outside a multiplayer run.
var multiplayer_replica: CampaignData = null

# Multiplayer clients only: true while taking part in a host's run, so play time is counted and
# flushed to this machine's profile.
var _is_client_in_run: bool = false

# The run that ended last, until the Results screen takes it with take_ended_run().
var _ended_run: ArchiveRecord = null

# Time.get_ticks_msec() at each file's last successful play-time flush. Separate per file so a
# write that fails for one file can't make the other count the same time twice.
var _campaign_flush_msec: int = 0
var _profile_flush_msec: int = 0

var _sections: SaveSectionRegistry = SaveSectionRegistry.new()


func _ready() -> void:
	for key: String in _RESERVED_PROFILE_SECTIONS:
		_sections.register(SaveSection.Block.PROFILE, RawSaveSection.new(key))
	for key: String in _RESERVED_CAMPAIGN_SECTIONS:
		_sections.register(SaveSection.Block.CAMPAIGN, RawSaveSection.new(key))
	for key: String in _RESERVED_COMBAT_SECTIONS:
		_sections.register(SaveSection.Block.COMBAT, RawSaveSection.new(key))
	SteamNetwork.lobby_left.connect(_on_steam_network_lobby_left)


## Registers [param section] to keep its data in [param block] of every save file.
##
## Call it before a save file opens (an autoload's [code]_ready()[/code] is early enough): a
## section registered later misses that file's load and starts from [method SaveSection.reset].
## Replaces any section with the same key, which is how a system takes over a reserved key.
func register_section(block: SaveSection.Block, section: SaveSection) -> void:
	if has_open_save_file():
		push_warning("SaveService: '%s' registered with a save file open." % [section.get_key()])
	_sections.register(block, section)


## Registers [param section] to keep data for every player of a campaign. Same timing rule as
## [method register_section].
func register_player_section(section: PlayerSaveSection) -> void:
	if has_open_save_file():
		push_warning("SaveService: '%s' registered with a save file open." % [section.get_key()])
	_sections.register_player(section)


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

	var multi: CampaignData = CampaignData.new()
	var multi_path: String = _get_campaign_path(save_number, CampaignData.Mode.MULTIPLAYER)
	var multi_err: Error = _load_campaign_into(multi_path, multi)
	if multi_err == ERR_FILE_NOT_FOUND:
		summary.multi_state = SaveFileSummary.State.EMPTY
	elif multi_err != OK:
		summary.multi_state = _get_failure_state(multi_err)
	else:
		summary.multi_state = SaveFileSummary.State.READY
		summary.multi_player_count = multi.players.size()
		summary.multi_last_opened = multi.last_opened
	return summary


## The save file an accepted invite should use (plan, row 27): the last selected one; else the
## first readable one; else the first empty one, which opening creates.
## Returns [constant NO_SAVE_FILE] only when every save file is unreadable or too new.
func get_invite_save_number() -> int:
	var last_selected: int = get_last_selected()
	var first_empty: int = NO_SAVE_FILE
	var first_ready: int = NO_SAVE_FILE
	for save_number: int in range(1, SAVE_FILE_COUNT + 1):
		var state: SaveFileSummary.State = get_summary(save_number).state
		if state == SaveFileSummary.State.READY:
			if save_number == last_selected:
				return save_number
			if first_ready == NO_SAVE_FILE:
				first_ready = save_number
		elif state == SaveFileSummary.State.EMPTY and first_empty == NO_SAVE_FILE:
			first_empty = save_number
	return first_ready if first_ready != NO_SAVE_FILE else first_empty


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
		_sections.reset(SaveSection.Block.PROFILE)
		needs_write = true
	elif result.error != OK:
		return result.error
	else:
		loaded = ProfileData.new()
		var load_err: Error = loaded.load_envelope(result.envelope)
		if load_err == OK:
			load_err = _sections.restore(SaveSection.Block.PROFILE, loaded.sections)
		if load_err != OK:
			_sections.reset(SaveSection.Block.PROFILE)
			return load_err

	var steam_name: String = _get_steam_name()
	if not steam_name.is_empty() and steam_name != loaded.last_steam_name:
		loaded.last_steam_name = steam_name
		needs_write = true

	if needs_write:
		loaded.sections = _sections.capture(SaveSection.Block.PROFILE, loaded.sections)
		var write_err: Error = SaveFile.write(path, loaded.to_envelope())
		if write_err != OK:
			_sections.reset(SaveSection.Block.PROFILE)
			return write_err

	current_save_number = save_number
	profile = loaded
	settings = _read_settings(save_number)
	settings.apply()
	_write_last_selected(save_number)
	save_file_opened.emit(save_number)
	return OK


## Closes the open save file, if any, and drops the active campaign. Writes nothing; every save
## happens at its own trigger, except that a multiplayer client's play time is flushed to its
## profile first.
func close_save_file() -> void:
	if not has_open_save_file():
		return
	_end_client_run()
	current_save_number = NO_SAVE_FILE
	profile = null
	_end_campaign()
	_sections.reset(SaveSection.Block.PROFILE)
	save_file_closed.emit()


## True when the open save file has a solo run in progress, readable or not.
func has_solo_campaign() -> bool:
	return has_campaign(CampaignData.Mode.SOLO)


## True when the open save file has a multiplayer campaign it hosts, readable or not.
func has_multiplayer_campaign() -> bool:
	return has_campaign(CampaignData.Mode.MULTIPLAYER)


## True when the open save file's [param slot_mode] slot holds a run, readable or not.
func has_campaign(slot_mode: CampaignData.Mode) -> bool:
	if not has_open_save_file():
		return false
	return SaveFile.exists(_get_campaign_path(current_save_number, slot_mode))


## Drops the active campaign without saving, e.g. before the Main Menu opens a lobby for a new
## multiplayer campaign. The files are untouched.
func clear_campaign() -> void:
	_end_campaign()


## Starts a new solo run in the open save file, writes its first save, then emits
## [signal campaign_activated].
##
## The run becomes [member campaign] and play time starts counting. Its seed is
## [param typed_seed] when given, else the debug command line's ([constant _RUN_SEED_ARG]), else
## a new [method RunSeed.generate].
## [param typed_seed]: a seed typed into a debug entry, or [constant RunSeed.NO_SEED].
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open,
## [constant ERR_ALREADY_EXISTS] when a solo run is already in progress,
## [constant ERR_INVALID_PARAMETER] for a [param typed_seed] outside 0 to
## [constant RunSeed.MAX_SEED], or the write error; on error no campaign is active.
func start_new_solo_run(typed_seed: int = RunSeed.NO_SEED) -> Error:
	if not has_open_save_file():
		push_error("SaveService: can't start a run with no save file open.")
		return ERR_UNCONFIGURED
	if has_solo_campaign():
		push_error("SaveService: save %d already has a solo run." % [current_save_number])
		return ERR_ALREADY_EXISTS
	if typed_seed != RunSeed.NO_SEED and (typed_seed < 0 or typed_seed > RunSeed.MAX_SEED):
		push_error("SaveService: not a run seed - %d" % [typed_seed])
		return ERR_INVALID_PARAMETER

	_ended_run = null
	campaign = CampaignData.create_solo(_choose_run_seed(typed_seed))
	_sections.reset(SaveSection.Block.CAMPAIGN)
	_sections.reset_players(campaign.players)
	_start_play_clock()
	var err: Error = save_checkpoint()
	if err != OK:
		_end_campaign()
		return err
	campaign_activated.emit(campaign.mode, false)
	return OK


## Loads the open save file's solo run as [member campaign], starts counting play time and emits
## [signal campaign_activated].
##
## Sets [member resume_point], loading [member combat] when the battle can resume. A combat file
## left by a crash outside a battle is deleted; an unusable one during a battle is deleted and the
## battle restarts from Begin (plan, "Combat crash protection", load table).
## Writes nothing else; the next checkpoint saves.
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open, or the campaign's
## read or load error; on error no campaign is active. A bad combat file is never an error.
func continue_solo_run() -> Error:
	var err: Error = _activate_campaign(CampaignData.Mode.SOLO)
	if err == OK:
		_start_play_clock()
		campaign_activated.emit(CampaignData.Mode.SOLO, true)
	return err


## Starts a new multiplayer campaign as the host, one seat per admitted lobby member, and writes
## its first save. Then tells every client the run started and emits [signal campaign_activated].
##
## Its seed is the debug command line's ([constant _RUN_SEED_ARG]), else a new
## [method RunSeed.generate].
## [param steam_ids]: the members' Steam ids in seat order, the host first. The player count is
## fixed from here on (plan, row 21).
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open,
## [constant ERR_ALREADY_EXISTS] when the multiplayer slot already holds a campaign,
## [constant ERR_INVALID_PARAMETER] for an empty or repeated id, or the write error.
func start_new_multiplayer_run(steam_ids: PackedInt64Array) -> Error:
	if not has_open_save_file():
		push_error("SaveService: can't start a run with no save file open.")
		return ERR_UNCONFIGURED
	if has_multiplayer_campaign():
		push_error("SaveService: save %d already hosts a campaign." % [current_save_number])
		return ERR_ALREADY_EXISTS

	var id_strings: PackedStringArray = []
	for steam_id: int in steam_ids:
		if steam_id <= 0 or id_strings.has(str(steam_id)):
			push_error("SaveService: invalid player list for a multiplayer run.")
			return ERR_INVALID_PARAMETER
		id_strings.append(str(steam_id))
	if id_strings.is_empty():
		return ERR_INVALID_PARAMETER

	_ended_run = null
	campaign = CampaignData.create_multiplayer(_choose_run_seed(RunSeed.NO_SEED), id_strings)
	_sections.reset(SaveSection.Block.CAMPAIGN)
	_sections.reset_players(campaign.players)
	_start_play_clock()
	var err: Error = save_checkpoint()
	if err != OK:
		_end_campaign()
		return err
	_announce_run_started()
	campaign_activated.emit(CampaignData.Mode.MULTIPLAYER, false)
	return OK


## Loads the open save file's multiplayer campaign as [member campaign], ready for the lobby to
## gather its players. Play time doesn't count until [method resume_multiplayer_run].
##
## Applies the same battle load table as [method continue_solo_run].
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open, or the read or load
## error; on error no campaign is active.
func load_multiplayer_campaign() -> Error:
	return _activate_campaign(CampaignData.Mode.MULTIPLAYER)


## Resumes the loaded multiplayer campaign once every player is in the lobby and Ready: starts
## play time, tells every client the run started and emits [signal campaign_activated].
##
## Returns [constant OK], or [constant ERR_UNCONFIGURED] when no multiplayer campaign is loaded.
func resume_multiplayer_run() -> Error:
	if campaign == null or campaign.mode != CampaignData.Mode.MULTIPLAYER:
		push_error("SaveService: no multiplayer campaign loaded to resume.")
		return ERR_UNCONFIGURED
	_start_play_clock()
	_announce_run_started()
	campaign_activated.emit(CampaignData.Mode.MULTIPLAYER, true)
	return OK


## Saves [member campaign] at a checkpoint (plan, row 13), then the profile. During a battle it
## writes [member combat] first, with the checkpoint number the campaign is about to take; this is
## the end-of-player-phase and Save & Quit save.
##
## Adds play time since each file's last successful write, raises
## [member CampaignData.checkpoint_seq] by one and sets [member CampaignData.last_opened] to now.
## A failed write leaves that file's in-memory values and play-time flush point unchanged, so the
## time is added once by the next successful save.
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no active campaign, or the first write
## error; nothing after a failed write is written.
func save_checkpoint() -> Error:
	if campaign == null or not has_open_save_file():
		push_error("SaveService: no active campaign to save.")
		return ERR_UNCONFIGURED

	var err: Error = _write_checkpoint()
	if err == OK:
		_announce_checkpoint()
	checkpoint_saved.emit(err)
	return err


## Starts and saves a battle when the player presses Begin after battle prep (plan, "Combat crash
## protection", step 1).
##
## Captures the campaign's sections first, then sets [member CampaignData.combat_in_progress]:
## until [method end_battle], campaign writes keep the sections as they are now, so a battle can
## always restart from this point. Also used to restart a battle after
## [constant CombatData.ResumePoint.BATTLE_RETRY].
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no active campaign,
## [constant ERR_ALREADY_IN_USE] during a battle, or the write error; on error no battle is
## active.
func begin_battle() -> Error:
	if campaign == null or not has_open_save_file():
		push_error("SaveService: can't begin a battle with no active campaign.")
		return ERR_UNCONFIGURED
	if combat != null:
		push_error("SaveService: a battle is already in progress.")
		return ERR_ALREADY_IN_USE

	_capture_campaign_sections()
	var was_in_progress: bool = campaign.combat_in_progress
	campaign.combat_in_progress = true
	combat = CombatData.new()
	_sections.reset(SaveSection.Block.COMBAT)

	var err: Error = save_checkpoint()
	if err != OK:
		combat = null
		campaign.combat_in_progress = was_in_progress
		_sections.reset(SaveSection.Block.COMBAT)
	return err


## Ends the battle in progress (plan, "Combat crash protection", step 3): writes the campaign with
## the battle's results, then deletes the combat file.
##
## Systems apply the battle's results to their campaign sections before calling this; they are
## captured here. If the campaign write fails, the battle stays in progress and nothing changes.
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no battle in progress, or the first
## write or delete error.
func end_battle() -> Error:
	if campaign == null or combat == null or not has_open_save_file():
		push_error("SaveService: no battle in progress to end.")
		return ERR_UNCONFIGURED

	var begin_sections: Dictionary = campaign.sections
	var begin_player_sections: Array[Dictionary] = []
	for player: CampaignData.PlayerRun in campaign.players:
		begin_player_sections.append(player.sections)

	campaign.combat_in_progress = false
	var now_msec: int = Time.get_ticks_msec()
	var campaign_err: Error = _write_campaign(now_msec)
	if campaign_err != OK:
		campaign.combat_in_progress = true
		campaign.sections = begin_sections
		for index: int in campaign.players.size():
			campaign.players[index].sections = begin_player_sections[index]
		checkpoint_saved.emit(campaign_err)
		return campaign_err

	var profile_err: Error = _write_profile(now_msec)
	var delete_err: Error = SaveFile.delete(_get_combat_path(current_save_number, campaign.mode))
	_end_battle_state()
	_announce_checkpoint()
	var err: Error = delete_err if delete_err != OK else profile_err
	checkpoint_saved.emit(err)
	return err


## Ends the active run, solo or multiplayer, as a win or loss: flushes play time to the profile,
## archives the run, empties its slot and emits [signal run_ended].
##
## The record includes play time up to now and the roster as it is now, even mid-battle. It is
## kept for [method take_ended_run]; the archive write's result is in [member last_archive_error].
## A multiplayer host also sends the record to every client, which archives it too (rows 11, 23).
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no active campaign, or the profile
## write or delete error. The run ends even when a write fails.
func end_run(won: bool) -> Error:
	if campaign == null or not has_open_save_file():
		push_error("SaveService: no active run to end.")
		return ERR_UNCONFIGURED

	var slot_mode: CampaignData.Mode = campaign.mode
	var now_msec: int = Time.get_ticks_msec()
	_capture_campaign_sections()
	campaign.play_time_seconds += _get_whole_seconds_since(_campaign_flush_msec, now_msec)
	var record: ArchiveRecord = ArchiveRecord.from_campaign(
			campaign, won, _get_player_names(campaign)
	)
	var profile_err: Error = _write_profile(now_msec)
	last_archive_error = _write_archive(record)
	_ended_run = record
	if _is_multiplayer_host():
		var record_envelope: Dictionary = record.to_envelope()
		for peer_id: int in _get_client_peer_ids():
			_client_run_ended.rpc_id(peer_id, record_envelope)

	var delete_err: Error = _delete_campaign_slot(slot_mode)
	_end_campaign()
	run_ended.emit(slot_mode, won)
	return delete_err if delete_err != OK else profile_err


## Abandons the open save file's [param slot_mode] run from the Main Menu: archives it as lost,
## empties the slot and emits [signal run_ended]. Play time was already counted at the run's last
## checkpoint.
##
## Abandoning a multiplayer campaign is a host-only, local act: the other players aren't there,
## and only the host's archive gets the record.
## A run whose file can't be read is still abandoned, unarchived; [member last_archive_error]
## says so.
## Returns [constant OK], [constant ERR_UNCONFIGURED] with no save file open, or the delete error.
func abandon_run(slot_mode: CampaignData.Mode) -> Error:
	if not has_open_save_file():
		push_error("SaveService: can't abandon a run with no save file open.")
		return ERR_UNCONFIGURED

	var source: CampaignData = campaign
	if source != null and source.mode == slot_mode:
		_capture_campaign_sections()
	else:
		source = CampaignData.new()
		var path: String = _get_campaign_path(current_save_number, slot_mode)
		last_archive_error = _load_campaign_into(path, source)
		if last_archive_error != OK:
			push_warning("SaveService: abandoned run in %s couldn't be archived." % [path])
			source = null

	if source != null:
		last_archive_error = _write_archive(
				ArchiveRecord.from_campaign(source, false, _get_player_names(source))
		)
	if campaign != null and campaign.mode == slot_mode:
		_end_campaign()

	var err: Error = _delete_campaign_slot(slot_mode)
	if err == OK:
		run_ended.emit(slot_mode, false)
	return err


## Returns the record of the run that ended last and forgets it, so the Results screen shows a run
## only once. Null when no run ended since the last call.
func take_ended_run() -> ArchiveRecord:
	var record: ArchiveRecord = _ended_run
	_ended_run = null
	return record


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


func _get_combat_path(save_number: int, slot_mode: CampaignData.Mode) -> String:
	return get_save_file_dir(save_number) + CombatData.get_file_name(slot_mode)


# Loads the open save file's slot_mode campaign as the active campaign, with its sections and the
# battle load table. Doesn't start play time.
func _activate_campaign(slot_mode: CampaignData.Mode) -> Error:
	_end_campaign()
	_ended_run = null
	if not has_open_save_file():
		push_error("SaveService: can't load a run with no save file open.")
		return ERR_UNCONFIGURED

	var loaded: CampaignData = CampaignData.new()
	var path: String = _get_campaign_path(current_save_number, slot_mode)
	var err: Error = _load_campaign_into(path, loaded)
	if err != OK:
		return err
	if loaded.mode != slot_mode:
		push_error("SaveService: %s holds the wrong kind of campaign." % [path])
		return ERR_INVALID_DATA

	var sections_err: Error = _sections.restore(SaveSection.Block.CAMPAIGN, loaded.sections)
	if sections_err == OK:
		sections_err = _sections.restore_players(loaded.players)
	if sections_err != OK:
		_end_campaign()
		return sections_err

	campaign = loaded
	resume_point = _load_battle()
	return OK


# A new run's seed: typed_seed unless it is RunSeed.NO_SEED, else the debug command line's, else
# a generated one. A command-line seed that doesn't parse is ignored with a warning, so a typo
# can't stop a run from starting.
func _choose_run_seed(typed_seed: int) -> int:
	if typed_seed != RunSeed.NO_SEED:
		return typed_seed
	if not OS.is_debug_build():
		return RunSeed.generate()
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(_RUN_SEED_ARG):
			continue
		var seed_text: String = arg.trim_prefix(_RUN_SEED_ARG)
		var parsed: int = RunSeed.parse(seed_text)
		if parsed != RunSeed.NO_SEED:
			return parsed
		push_warning("SaveService: ignoring %s'%s', not a run seed." % [_RUN_SEED_ARG, seed_text])
	return RunSeed.generate()


# Reads and loads one campaign file into target. Returns ERR_FILE_NOT_FOUND for an empty slot.
func _load_campaign_into(path: String, target: CampaignData) -> Error:
	var result: SaveFile.ReadResult = SaveFile.read(path)
	if result.error != OK:
		return result.error
	return target.load_envelope(result.envelope)


# Applies the load table for the just-loaded campaign; see continue_solo_run(). The combat file
# is trusted only when its checkpoint_seq equals the campaign's, or is one ahead (a crash between
# the combat write and the campaign write).
func _load_battle() -> CombatData.ResumePoint:
	var path: String = _get_combat_path(current_save_number, campaign.mode)
	if not campaign.combat_in_progress:
		if SaveFile.exists(path):
			push_warning("SaveService: deleting a combat file left outside a battle: %s" % [path])
			SaveFile.delete(path)
		return CombatData.ResumePoint.CAMPAIGN

	var loaded: CombatData = CombatData.new()
	var result: SaveFile.ReadResult = SaveFile.read(path)
	var err: Error = result.error
	if err == OK:
		err = loaded.load_envelope(result.envelope)
	var seq_gap: int = loaded.checkpoint_seq - campaign.checkpoint_seq
	if err == OK and seq_gap != 0 and seq_gap != 1:
		err = ERR_INVALID_DATA
	if err == OK:
		err = _sections.restore(SaveSection.Block.COMBAT, loaded.sections)
	if err == OK:
		combat = loaded
		return CombatData.ResumePoint.BATTLE

	push_warning(
			"SaveService: the battle in %s can't be resumed (%s); it restarts from Begin."
			% [path, error_string(err)]
	)
	SaveFile.delete(path)
	_sections.reset(SaveSection.Block.COMBAT)
	return CombatData.ResumePoint.BATTLE_RETRY


# Writes record to the open save file's archive folder, adding a suffix if a record with the same
# name exists (two runs ending in the same second).
func _write_archive(record: ArchiveRecord) -> Error:
	var folder: String = get_save_file_dir(current_save_number) + ArchiveRecord.FOLDER_NAME + "/"
	var base_name: String = record.get_file_name().get_basename()
	var path: String = folder + record.get_file_name()
	var suffix: int = 2
	while SaveFile.exists(path):
		path = folder + "%s_%d.json" % [base_name, suffix]
		suffix += 1

	var err: Error = SaveFile.write(path, record.to_envelope())
	if err != OK:
		push_error("SaveService: archiving the run failed - %s" % [error_string(err)])
	return err


# Display name per seat for archive records. Solo is the save file's cached Steam name.
# Display name per seat for archive records: this machine's cached Steam name for its own seat (and
# for solo), Steam's name for the others when Steam is available.
func _get_player_names(source: CampaignData) -> Dictionary[int, String]:
	var names: Dictionary[int, String] = {}
	var own_steam_id: String = str(Steam.getSteamID()) if SteamManager.is_available else ""
	for player: CampaignData.PlayerRun in source.players:
		var is_own: bool = player.steam_id.is_empty() or player.steam_id == own_steam_id
		if is_own and profile != null:
			names[player.seat] = profile.last_steam_name
		elif SteamManager.is_available:
			names[player.seat] = SteamNetwork.get_member_name(player.steam_id.to_int())
	return names


func _is_multiplayer_host() -> bool:
	return (
			campaign != null
			and campaign.mode == CampaignData.Mode.MULTIPLAYER
			and SteamNetwork.has_active_session()
			and multiplayer.is_server()
	)


# Host: after a campaign save, clients write their own profiles and refresh their replica.
func _announce_checkpoint() -> void:
	if not _is_multiplayer_host():
		return
	var envelope: Dictionary = campaign.to_envelope()
	for peer_id: int in _get_client_peer_ids():
		_client_checkpoint.rpc_id(peer_id, envelope)


func _announce_run_started() -> void:
	if not _is_multiplayer_host():
		return
	var envelope: Dictionary = campaign.to_envelope()
	for peer_id: int in _get_client_peer_ids():
		_client_run_started.rpc_id(peer_id, envelope)


# Admitted members other than the host. Campaign data goes only to them, never to a connection
# the host refused but hasn't cut off yet.
func _get_client_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
		if member.peer_id != multiplayer.get_unique_id():
			peer_ids.append(member.peer_id)
	return peer_ids


# Client: flushes play time to this machine's profile and stops counting.
func _end_client_run() -> void:
	if not _is_client_in_run:
		return
	if has_open_save_file():
		_write_profile(Time.get_ticks_msec())
	_is_client_in_run = false
	multiplayer_replica = null


# Client: replaces the replica with the host's campaign, ignoring anything that doesn't load.
func _update_replica(envelope: Dictionary) -> void:
	var replica: CampaignData = CampaignData.new()
	if replica.load_envelope(envelope.duplicate(true)) != OK:
		push_warning("SaveService: ignoring an unreadable campaign from the host.")
		return
	multiplayer_replica = replica


@rpc("authority", "reliable", "call_remote")
func _client_run_started(envelope: Dictionary) -> void:
	_update_replica(envelope)
	_ended_run = null
	_is_client_in_run = has_open_save_file()
	_profile_flush_msec = Time.get_ticks_msec()


@rpc("authority", "reliable", "call_remote")
func _client_checkpoint(envelope: Dictionary) -> void:
	_update_replica(envelope)
	if _is_client_in_run:
		_write_profile(Time.get_ticks_msec())


# Client: archives the host's record of the ended run in this machine's own archive (rows 11, 23).
@rpc("authority", "reliable", "call_remote")
func _client_run_ended(record_envelope: Dictionary) -> void:
	_end_client_run()
	var record: ArchiveRecord = ArchiveRecord.new()
	if record.load_envelope(record_envelope.duplicate(true)) != OK:
		push_warning("SaveService: ignoring an unreadable archive record from the host.")
		return
	if not has_open_save_file():
		return
	last_archive_error = _write_archive(record)
	_ended_run = record


func _on_steam_network_lobby_left() -> void:
	_end_client_run()


# Deletes a campaign slot's campaign and combat files. Returns the first delete error.
func _delete_campaign_slot(slot_mode: CampaignData.Mode) -> Error:
	var combat_err: Error = SaveFile.delete(_get_combat_path(current_save_number, slot_mode))
	var campaign_err: Error = SaveFile.delete(_get_campaign_path(current_save_number, slot_mode))
	return combat_err if combat_err != OK else campaign_err


# Drops the active campaign and its battle and empties their sections, so nothing from them
# leaks into the next run.
func _end_campaign() -> void:
	campaign = null
	_end_battle_state()
	resume_point = CombatData.ResumePoint.CAMPAIGN
	_sections.reset(SaveSection.Block.CAMPAIGN)
	_sections.clear_players()


func _end_battle_state() -> void:
	combat = null
	_sections.reset(SaveSection.Block.COMBAT)


func _capture_campaign_sections() -> void:
	campaign.sections = _sections.capture(SaveSection.Block.CAMPAIGN, campaign.sections)
	_sections.capture_players(campaign.players)


# The body of save_checkpoint(): combat file (during a battle), campaign, then profile, stopping
# at the first failure.
func _write_checkpoint() -> Error:
	if combat != null:
		var combat_err: Error = _write_combat()
		if combat_err != OK:
			return combat_err

	var now_msec: int = Time.get_ticks_msec()
	var campaign_err: Error = _write_campaign(now_msec)
	if campaign_err != OK:
		return campaign_err
	return _write_profile(now_msec)


# Writes the combat file with the checkpoint number the campaign write that follows will take.
func _write_combat() -> Error:
	var previous_seq: int = combat.checkpoint_seq
	combat.checkpoint_seq = campaign.checkpoint_seq + 1
	combat.sections = _sections.capture(SaveSection.Block.COMBAT, combat.sections)
	var path: String = _get_combat_path(current_save_number, campaign.mode)
	var err: Error = SaveFile.write(path, combat.to_envelope())
	if err != OK:
		combat.checkpoint_seq = previous_seq
	return err


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
	# During a battle the campaign keeps its sections as they were at Begin; see begin_battle().
	if not campaign.combat_in_progress:
		_capture_campaign_sections()
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
	profile.sections = _sections.capture(SaveSection.Block.PROFILE, profile.sections)
	var err: Error = SaveFile.write(_get_profile_path(current_save_number), profile.to_envelope())
	if err != OK:
		profile.play_time_seconds -= seconds
		return err

	_profile_flush_msec += seconds * 1000
	return OK


# Whole seconds only; the leftover milliseconds stay behind the flush point for the next save.
func _get_whole_seconds_since(since_msec: int, now_msec: int) -> int:
	# Truncation is the point (above). On the statement: 4.7 ignores it on the func for the body.
	@warning_ignore("integer_division")
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
	var save_number: int = core.get(_KEY_SAVE_NUMBER, NO_SAVE_FILE) as int
	return save_number if is_valid_save_number(save_number) else NO_SAVE_FILE


# A failure only costs Save Select its focus hint, so it's a warning, not an error for the caller.
func _write_last_selected(save_number: int) -> void:
	var envelope: Dictionary = SaveFile.make_envelope(
			_LAST_SELECTED_SCHEMA_VERSION, {_KEY_SAVE_NUMBER: save_number}
	)
	var err: Error = SaveFile.write(LAST_SELECTED_PATH, envelope)
	if err != OK:
		push_warning("SaveService: couldn't remember save %d as last selected." % [save_number])
