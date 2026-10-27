# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 14, 2026
# Modified: October 27, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the save layer ([SaveFile], [SaveMigrations], [ProfileData],
## [SettingsData], [CampaignData], [CombatData], [ArchiveRecord], [SaveSectionRegistry]) and the
## lobby admission rules ([LobbyAdmission]).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/save/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in broken
## files make [SaveFile] log errors and warnings on purpose; only FAIL lines mean a problem.[br]
## Works in [constant TEST_DIR] and deletes it afterwards. Autoloads don't exist in
## [code]--script[/code] mode, so nothing here may use [code]SaveService[/code].

## Scratch folder for test files. Emptied before and after the run.
const TEST_DIR: String = "user://test_saves/"

## A file path inside [constant TEST_DIR] used by most cases.
const TEST_PATH: String = TEST_DIR + "test.json"

# Text that can't parse as JSON, standing in for a write cut off by a crash.
const TRUNCATED_JSON: String = "{\"schema_version\": 1, \"core\": {"

# A real Steam id. Above 2^53, so it can't survive as a JSON number.
const STEAM_ID: String = "76561198000000001"

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Save layer tests. Errors and warnings from SaveFile below are expected. ---")
	_clear_test_dir()

	_test_round_trip()
	_test_write_rotates_backup()
	_test_steam_id_and_float_precision()
	_test_crash_while_writing_temp()
	_test_crash_before_backup_rotation()
	_test_crash_before_final_rename()
	_test_corrupt_live_uses_backup()
	_test_all_copies_corrupt()
	_test_missing_file()
	_test_newer_game_version_refused()
	_test_malformed_envelope_not_written()
	_test_version_comparison()
	_test_migrations_run_in_order()
	_test_migrations_reject_bad_versions()
	_test_exists_and_delete()
	_test_delete_folder()
	_test_profile_round_trip()
	_test_profile_defaults_and_newer_schema()
	_test_settings_round_trip_and_copy()
	_test_settings_repairs_hand_edits()
	_test_settings_volume_db()
	_test_campaign_solo_round_trip()
	_test_campaign_run_seed_exact_in_json()
	_test_campaign_multiplayer_shape()
	_test_campaign_rejects_bad_data()
	_test_sections_capture_keeps_unregistered()
	_test_sections_restore_and_reset()
	_test_sections_migrate_and_refuse()
	_test_sections_raw_and_replace()
	_test_player_sections_per_seat()
	_test_combat_round_trip()
	_test_combat_rejects_bad_data()
	_test_archive_from_campaign()
	_test_archive_round_trip_and_bad_data()
	_test_multiplayer_campaign()
	_test_multiplayer_campaign_rejects_bad_ids()
	_test_lobby_admission()

	SaveFile.delete_folder(TEST_DIR)
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _test_round_trip() -> void:
	_clear_test_dir()
	var sections: Dictionary = {"unlocks": {"version": 1, "data": {"knight": true}}}
	var envelope: Dictionary = SaveFile.make_envelope(1, {"name": "Ada", "count": 3}, sections)
	var write_err: Error = SaveFile.write(TEST_PATH, envelope)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("round trip: write OK", write_err == OK, error_string(write_err))
	_check("round trip: read OK", result.error == OK, error_string(result.error))
	_check("round trip: from live file", result.source == SaveFile.Source.LIVE)
	_check("round trip: string field", (_core(result).get("name") == "Ada") as bool)
	_check("round trip: int field", (_core(result).get("count", 0) as int) == 3)
	var data: Dictionary = result.envelope[SaveFile.KEY_SECTIONS]["unlocks"]["data"]
	_check("round trip: section data", (data.get("knight") == true) as bool)
	_check(
			"round trip: game version stamped",
			(result.envelope[SaveFile.KEY_GAME_VERSION] == SaveFile.get_running_version()) as bool
	)
	_check("round trip: saved_at stamped", (result.envelope[SaveFile.KEY_SAVED_AT] as int) > 0)
	_check("round trip: no .tmp left", not FileAccess.file_exists(_temp()))
	_check("round trip: first write makes no .bak", not FileAccess.file_exists(_backup()))


func _test_write_rotates_backup() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	SaveFile.write(TEST_PATH, _envelope_with_seq(2))

	_check("rotation: live holds newest", _seq_on_disk(TEST_PATH) == 2)
	_check("rotation: .bak holds previous", _seq_on_disk(_backup()) == 1)
	_check("rotation: no .tmp left", not FileAccess.file_exists(_temp()))


func _test_steam_id_and_float_precision() -> void:
	_clear_test_dir()
	var ratio: float = 0.1 + 0.2
	SaveFile.write(TEST_PATH, SaveFile.make_envelope(1, {"steam_id": STEAM_ID, "ratio": ratio}))
	var core: Dictionary = _core(SaveFile.read(TEST_PATH))

	var steam_id_back: int = str(core.get("steam_id")).to_int()
	var ratio_back: float = core.get("ratio", 0.0) as float
	_check("precision: Steam id exact as string", (core.get("steam_id") == STEAM_ID) as bool)
	_check("precision: Steam id converts back exactly", steam_id_back == 76561198000000001)
	_check("precision: float exact", ratio_back == ratio, str(ratio_back))


# Crash during save step 1: the .tmp is incomplete, the live file is untouched.
func _test_crash_while_writing_temp() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	_write_raw(_temp(), TRUNCATED_JSON)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("crash in step 1: read OK", result.error == OK, error_string(result.error))
	_check("crash in step 1: uses live", result.source == SaveFile.Source.LIVE)
	_check("crash in step 1: live data", _seq(result) == 1)
	_check("crash in step 1: broken .tmp removed", not FileAccess.file_exists(_temp()))
	_check("crash in step 1: not reported as recovered", not result.was_recovered())


# Crash after step 1, before step 2: a complete newer .tmp beside a valid older live file.
func _test_crash_before_backup_rotation() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	_write_raw(_temp(), _envelope_text(2, SaveFile.get_running_version()))
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("crash before step 2: read OK", result.error == OK, error_string(result.error))
	_check("crash before step 2: uses .tmp", result.source == SaveFile.Source.TEMP)
	_check("crash before step 2: newest data", _seq(result) == 2)
	_check("crash before step 2: live repaired", _seq_on_disk(TEST_PATH) == 2)
	_check("crash before step 2: old live became .bak", _seq_on_disk(_backup()) == 1)
	_check("crash before step 2: .tmp gone", not FileAccess.file_exists(_temp()))
	_check("crash before step 2: reported as recovered", result.was_recovered())


# Crash between steps 2 and 3: no live file, .bak holds the previous save, .tmp the new one.
func _test_crash_before_final_rename() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	SaveFile.write(TEST_PATH, _envelope_with_seq(2))
	DirAccess.rename_absolute(TEST_PATH, _temp())
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("crash before step 3: read OK", result.error == OK, error_string(result.error))
	_check("crash before step 3: uses .tmp", result.source == SaveFile.Source.TEMP)
	_check("crash before step 3: newest data", _seq(result) == 2)
	_check("crash before step 3: live restored", _seq_on_disk(TEST_PATH) == 2)
	_check("crash before step 3: .bak kept", _seq_on_disk(_backup()) == 1)
	_check("crash before step 3: .tmp gone", not FileAccess.file_exists(_temp()))


func _test_corrupt_live_uses_backup() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	SaveFile.write(TEST_PATH, _envelope_with_seq(2))
	_write_raw(TEST_PATH, TRUNCATED_JSON)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("corrupt live: read OK", result.error == OK, error_string(result.error))
	_check("corrupt live: uses .bak", result.source == SaveFile.Source.BACKUP)
	_check("corrupt live: backup data", _seq(result) == 1)
	_check("corrupt live: live repaired from .bak", _seq_on_disk(TEST_PATH) == 1)
	_check("corrupt live: .bak kept", _seq_on_disk(_backup()) == 1)
	_check("corrupt live: reported as recovered", result.was_recovered())


func _test_all_copies_corrupt() -> void:
	_clear_test_dir()
	_write_raw(TEST_PATH, TRUNCATED_JSON)
	_write_raw(_temp(), TRUNCATED_JSON)
	_write_raw(_backup(), "not json at all")
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check(
			"all corrupt: ERR_FILE_CORRUPT",
			result.error == ERR_FILE_CORRUPT,
			error_string(result.error)
	)
	_check("all corrupt: empty envelope", result.envelope.is_empty())
	_check(
			"all corrupt: files left for inspection",
			FileAccess.file_exists(TEST_PATH)
			and FileAccess.file_exists(_temp())
			and FileAccess.file_exists(_backup())
	)


func _test_missing_file() -> void:
	_clear_test_dir()
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check(
			"missing: ERR_FILE_NOT_FOUND",
			result.error == ERR_FILE_NOT_FOUND,
			error_string(result.error)
	)
	_check("missing: not reported as recovered", not result.was_recovered())


func _test_newer_game_version_refused() -> void:
	_clear_test_dir()
	var text: String = _envelope_text(1, "999.0.0")
	_write_raw(TEST_PATH, text)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check(
			"newer version: ERR_FILE_UNRECOGNIZED",
			result.error == ERR_FILE_UNRECOGNIZED,
			error_string(result.error)
	)
	_check("newer version: empty envelope", result.envelope.is_empty())
	_check("newer version: file untouched", FileAccess.get_file_as_string(TEST_PATH) == text)


func _test_malformed_envelope_not_written() -> void:
	_clear_test_dir()
	var err: Error = SaveFile.write(TEST_PATH, {"core": {}})

	_check(
			"malformed write: ERR_INVALID_PARAMETER",
			err == ERR_INVALID_PARAMETER,
			error_string(err)
	)
	_check("malformed write: nothing on disk", not FileAccess.file_exists(TEST_PATH))


# Exercises version ordering through read(): a file is refused only when strictly newer.
func _test_version_comparison() -> void:
	var running: String = SaveFile.get_running_version()
	_check(
			"version: running version is set",
			not running.is_empty(),
			"set application/config/version"
	)

	var cases: Dictionary[String, bool] = {
		running: true,
		"0.0.1": true,
		running + ".0": true,
		running + ".1": false,
	}
	for version: String in cases:
		_clear_test_dir()
		_write_raw(TEST_PATH, _envelope_text(1, version))
		var accepted: bool = SaveFile.read(TEST_PATH).error == OK
		_check("version: %s accepted=%s" % [version, cases[version]], accepted == cases[version])


func _test_migrations_run_in_order() -> void:
	var steps: Array[Callable] = [_step_add_gold, _step_rename_gold]

	var from_one: Dictionary = SaveFile.make_envelope(1, {})
	var err_one: Error = SaveMigrations.run(from_one, 3, steps)
	var core_one: Dictionary = from_one[SaveFile.KEY_CORE]
	_check("migrate 1->3: OK", err_one == OK, error_string(err_one))
	_check(
			"migrate 1->3: both steps ran",
			(core_one.get("coins") == 100) as bool and not core_one.has("gold")
	)
	_check("migrate 1->3: version set", (from_one[SaveFile.KEY_SCHEMA_VERSION] as int) == 3)

	var from_two: Dictionary = SaveFile.make_envelope(2, {"gold": 7})
	SaveMigrations.run(from_two, 3, steps)
	var core_two: Dictionary = from_two[SaveFile.KEY_CORE]
	_check("migrate 2->3: only the last step ran", (core_two.get("coins") == 7) as bool)

	var current: Dictionary = SaveFile.make_envelope(3, {"coins": 5})
	var err_current: Error = SaveMigrations.run(current, 3, steps)
	var core_current: Dictionary = current[SaveFile.KEY_CORE]
	_check("migrate 3->3: no-op", err_current == OK and (core_current.get("coins") == 5) as bool)


func _test_migrations_reject_bad_versions() -> void:
	var steps: Array[Callable] = [_step_add_gold, _step_rename_gold]
	var too_new: Error = SaveMigrations.run(SaveFile.make_envelope(4, {}), 3, steps)
	var too_old: Error = SaveMigrations.run(SaveFile.make_envelope(0, {}), 3, steps)
	var wrong_steps: Error = SaveMigrations.run(SaveFile.make_envelope(1, {}), 3, [_step_add_gold])
	var failing: Error = SaveMigrations.run(SaveFile.make_envelope(1, {}), 2, [_step_fail])

	_check(
			"migrate: newer schema refused",
			too_new == ERR_FILE_UNRECOGNIZED,
			error_string(too_new)
	)
	_check("migrate: schema 0 refused", too_old == ERR_INVALID_DATA, error_string(too_old))
	_check("migrate: step count mismatch", wrong_steps == ERR_BUG, error_string(wrong_steps))
	_check("migrate: failing step reported", failing == ERR_INVALID_DATA, error_string(failing))


func _test_exists_and_delete() -> void:
	_clear_test_dir()
	_check("exists: false with no copies", not SaveFile.exists(TEST_PATH))
	_write_raw(_backup(), TRUNCATED_JSON)
	_check("exists: true with only a .bak", SaveFile.exists(TEST_PATH))

	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	_write_raw(_temp(), TRUNCATED_JSON)
	var err: Error = SaveFile.delete(TEST_PATH)
	_check("delete: OK", err == OK, error_string(err))
	_check("delete: every copy gone", not SaveFile.exists(TEST_PATH))
	_check("delete: missing file is OK", SaveFile.delete(TEST_PATH) == OK)


func _test_delete_folder() -> void:
	var folder: String = TEST_DIR + "save_9/"
	SaveFile.write(folder + "profile.json", _envelope_with_seq(1))
	SaveFile.write(folder + "archive/run_1.json", _envelope_with_seq(1))
	var err: Error = SaveFile.delete_folder(folder)

	_check("delete folder: OK", err == OK, error_string(err))
	_check("delete folder: gone with subfolders", not DirAccess.dir_exists_absolute(folder))
	_check("delete folder: missing folder is OK", SaveFile.delete_folder(folder) == OK)
	_check(
			"delete folder: refuses user:// root",
			SaveFile.delete_folder("user://") == ERR_INVALID_PARAMETER
	)
	_check(
			"delete folder: refuses res://",
			SaveFile.delete_folder("res://tests/") == ERR_INVALID_PARAMETER
	)


func _test_profile_round_trip() -> void:
	_clear_test_dir()
	var profile: ProfileData = ProfileData.create_new()
	profile.last_steam_name = "Ada"
	profile.play_time_seconds = 4321
	profile.sections = {"unlocks": {"version": 1, "data": {"knight": true}}}
	SaveFile.write(TEST_PATH, profile.to_envelope())

	var loaded: ProfileData = ProfileData.new()
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check("profile: load OK", err == OK, error_string(err))
	_check("profile: created_at set", profile.created_at > 0)
	_check("profile: created_at kept", loaded.created_at == profile.created_at)
	_check("profile: name kept", loaded.last_steam_name == "Ada")
	_check("profile: play time kept", loaded.play_time_seconds == 4321)
	_check("profile: sections carried through", loaded.sections.has("unlocks"))


func _test_profile_defaults_and_newer_schema() -> void:
	var sparse: ProfileData = ProfileData.new()
	var err: Error = sparse.load_envelope(SaveFile.make_envelope(1, {}))
	_check("profile defaults: load OK", err == OK, error_string(err))
	_check(
			"profile defaults: missing fields keep defaults",
			sparse.last_steam_name.is_empty() and sparse.play_time_seconds == 0
	)

	var newer: ProfileData = ProfileData.new()
	newer.last_steam_name = "unchanged"
	var newer_envelope: Dictionary = SaveFile.make_envelope(
			ProfileData.SCHEMA_VERSION + 1, {"last_steam_name": "from the future"}
	)
	var newer_err: Error = newer.load_envelope(newer_envelope)
	_check("profile newer schema: refused", newer_err == ERR_FILE_UNRECOGNIZED)
	_check("profile newer schema: left unchanged", newer.last_steam_name == "unchanged")


func _test_settings_round_trip_and_copy() -> void:
	_clear_test_dir()
	var defaults: SettingsData = SettingsData.new()
	_check(
			"settings: defaults are 5",
			defaults.master_volume == 5 and defaults.music_volume == 5 and defaults.sfx_volume == 5
	)

	var settings: SettingsData = SettingsData.new()
	settings.set_volume(SettingsData.Channel.MASTER, 8)
	settings.set_volume(SettingsData.Channel.MUSIC, 0)
	settings.set_volume(SettingsData.Channel.SFX, 3)
	SaveFile.write(TEST_PATH, settings.to_envelope())

	var loaded: SettingsData = SettingsData.new()
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check("settings: load OK", err == OK, error_string(err))
	_check(
			"settings: volumes kept",
			loaded.master_volume == 8 and loaded.music_volume == 0 and loaded.sfx_volume == 3
	)

	var copied: SettingsData = loaded.copy()
	copied.set_volume(SettingsData.Channel.MASTER, 1)
	_check("settings: copy is independent", loaded.master_volume == 8 and copied.master_volume == 1)


# settings.json is player-editable, so bad values are repaired rather than rejected.
func _test_settings_repairs_hand_edits() -> void:
	var core: Dictionary = {"master_volume": 99, "music_volume": "loud", "sfx_volume": 7.6}
	var settings: SettingsData = SettingsData.new()
	var err: Error = settings.load_envelope(SaveFile.make_envelope(1, core))

	_check("settings hand edits: still loads", err == OK, error_string(err))
	_check("settings hand edits: too high clamped", settings.master_volume == 10)
	_check("settings hand edits: wrong type is default", settings.music_volume == 5)
	_check("settings hand edits: fraction rounded", settings.sfx_volume == 8)

	var negative: SettingsData = SettingsData.new()
	negative.load_envelope(SaveFile.make_envelope(1, {"master_volume": -3}))
	_check("settings hand edits: negative clamped", negative.master_volume == 0)
	_check("settings hand edits: missing is default", negative.sfx_volume == 5)


func _test_settings_volume_db() -> void:
	var settings: SettingsData = SettingsData.new()
	settings.set_volume(SettingsData.Channel.MASTER, 10)
	settings.set_volume(SettingsData.Channel.MUSIC, 2)
	settings.set_volume(SettingsData.Channel.SFX, 9)

	var master_db: float = settings.get_volume_db(SettingsData.Channel.MASTER)
	var sfx_db: float = settings.get_volume_db(SettingsData.Channel.SFX)
	_check("volume dB: master is level - 5", master_db == 5.0, str(master_db))
	_check("volume dB: SFX reads sfx_volume, not music", sfx_db == -11.0, str(sfx_db))

	settings.set_volume(SettingsData.Channel.MUSIC, 0)
	_check(
			"volume dB: 0 mutes",
			settings.get_volume_db(SettingsData.Channel.MUSIC) == SettingsData.MUTED_DB
	)


func _test_campaign_solo_round_trip() -> void:
	_clear_test_dir()
	var campaign: CampaignData = CampaignData.create_solo(123456)
	campaign.difficulty = "hard"
	campaign.modifiers = PackedStringArray(["fog", "famine"])
	campaign.play_time_seconds = 90
	campaign.checkpoint_seq = 4
	campaign.level_id = "forest_2"
	campaign.floors_climbed = 3
	campaign.combat_maps_completed = 1
	campaign.players[0].sections = {"roster": {"version": 1, "data": {"units": ["u1"]}}}
	campaign.combat_in_progress = true
	SaveFile.write(TEST_PATH, campaign.to_envelope())

	var loaded: CampaignData = CampaignData.new()
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check("campaign solo: load OK", err == OK, error_string(err))
	_check("campaign solo: mode", loaded.mode == CampaignData.Mode.SOLO)
	_check("campaign solo: seed", loaded.run_seed == 123456)
	_check(
			"campaign solo: difficulty and modifiers",
			loaded.difficulty == "hard" and loaded.modifiers == PackedStringArray(["fog", "famine"])
	)
	_check(
			"campaign solo: timestamps",
			loaded.started_at == campaign.started_at and loaded.started_at > 0
	)
	_check("campaign solo: checkpoint_seq from envelope", loaded.checkpoint_seq == 4)
	_check(
			"campaign solo: progress",
			loaded.level_id == "forest_2" and loaded.floors_climbed == 3
			and loaded.combat_maps_completed == 1 and loaded.play_time_seconds == 90
	)
	_check("campaign solo: one seat 0", loaded.players.size() == 1 and loaded.players[0].seat == 0)
	_check("campaign solo: no Steam id", loaded.players[0].steam_id.is_empty())
	_check("campaign solo: player sections kept", loaded.players[0].sections.has("roster"))
	_check("campaign solo: battle flag kept", loaded.combat_in_progress)
	var fresh: CampaignData = CampaignData.create_solo(1)
	_check("campaign solo: battle flag defaults off", not fresh.combat_in_progress)
	var solo_file: String = CampaignData.get_file_name(CampaignData.Mode.SOLO)
	_check("campaign solo: file name", solo_file == "campaign_solo.json")


# Run seeds are saved as plain JSON numbers, not strings: every seed is below 2^52, where JSON
# numbers are exact (save-system.md, Data rules). "seed" is CampaignData's core key.
func _test_campaign_run_seed_exact_in_json() -> void:
	var seeds: Array[int] = [RunSeed.MAX_SEED, 0, 0xFFFFFFFF, RunSeed.generate()]
	for run_seed: int in seeds:
		_clear_test_dir()
		SaveFile.write(TEST_PATH, CampaignData.create_solo(run_seed).to_envelope())
		var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)
		var saved: Variant = _core(result).get("seed")
		var loaded: CampaignData = CampaignData.new()
		var err: Error = loaded.load_envelope(result.envelope)
		_check(
				"run seed %s: saved as a JSON number" % [RunSeed.format(run_seed)],
				typeof(saved) == TYPE_FLOAT, type_string(typeof(saved))
		)
		_check(
				"run seed %s: loads back exactly" % [RunSeed.format(run_seed)],
				err == OK and loaded.run_seed == run_seed, str(loaded.run_seed)
		)


func _test_campaign_multiplayer_shape() -> void:
	_clear_test_dir()
	var campaign: CampaignData = CampaignData.create_solo(1)
	campaign.mode = CampaignData.Mode.MULTIPLAYER
	campaign.players[0].steam_id = STEAM_ID
	for seat: int in range(1, 4):
		var player: CampaignData.PlayerRun = CampaignData.PlayerRun.new()
		player.seat = seat
		player.steam_id = "7656119800000000%d" % [seat + 1]
		campaign.players.append(player)
	SaveFile.write(TEST_PATH, campaign.to_envelope())

	var loaded: CampaignData = CampaignData.new()
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check("campaign multi: load OK", err == OK, error_string(err))
	_check("campaign multi: mode", loaded.mode == CampaignData.Mode.MULTIPLAYER)
	_check("campaign multi: four seats", loaded.players.size() == 4 and loaded.players[3].seat == 3)
	_check("campaign multi: host Steam id exact", loaded.players[0].steam_id == STEAM_ID)


func _test_campaign_rejects_bad_data() -> void:
	var good_player: Dictionary = {"seat": 0, "steam_id": "", "sections": {}}
	var cases: Dictionary[String, Dictionary] = {
		"unknown mode": {"mode": "coop", "players": [good_player]},
		"missing players": {"mode": "solo"},
		"empty players": {"mode": "solo", "players": []},
		"player without seat": {"mode": "solo", "players": [{"steam_id": ""}]},
		"player not a dictionary": {"mode": "solo", "players": ["seat 0"]},
	}
	for case_name: String in cases:
		var campaign: CampaignData = CampaignData.new()
		campaign.level_id = "unchanged"
		var err: Error = campaign.load_envelope(SaveFile.make_envelope(1, cases[case_name], {}, 1))
		_check(
				"campaign bad data: %s refused" % [case_name],
				err == ERR_INVALID_DATA and campaign.level_id == "unchanged"
		)


func _test_sections_capture_keeps_unregistered() -> void:
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	var unlocks: FakeSection = FakeSection.new("unlocks", 1)
	unlocks.data = {"knight": true}
	registry.register(SaveSection.Block.PROFILE, unlocks)

	var on_disk: Dictionary = {"removed_feature": {"version": 3, "data": {"x": 1}}}
	var captured: Dictionary = registry.capture(SaveSection.Block.PROFILE, on_disk)
	_check(
			"sections capture: unregistered kept",
			(captured.get("removed_feature") == on_disk["removed_feature"]) as bool
	)
	_check(
			"sections capture: registered written with version",
			(captured.get("unlocks") == {"version": 1, "data": {"knight": true}}) as bool
	)
	_check("sections capture: input not modified", not on_disk.has("unlocks"))
	_check(
			"sections capture: other blocks untouched",
			registry.capture(SaveSection.Block.CAMPAIGN, {}).is_empty()
	)


func _test_sections_restore_and_reset() -> void:
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	var present: FakeSection = FakeSection.new("present", 1)
	var missing: FakeSection = FakeSection.new("missing", 1)
	missing.data = {"stale": true}
	registry.register(SaveSection.Block.CAMPAIGN, present)
	registry.register(SaveSection.Block.CAMPAIGN, missing)

	var sections: Dictionary = {"present": {"version": 1, "data": {"gold": 7}}}
	var err: Error = registry.restore(SaveSection.Block.CAMPAIGN, sections)
	_check("sections restore: OK", err == OK, error_string(err))
	_check("sections restore: data handed over", present.data == {"gold": 7})
	_check(
			"sections restore: missing section reset",
			missing.reset_count == 1 and missing.data.is_empty()
	)

	registry.reset(SaveSection.Block.CAMPAIGN)
	_check("sections reset: every section", present.reset_count == 1 and missing.reset_count == 2)


func _test_sections_migrate_and_refuse() -> void:
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	var upgraded: FakeSection = FakeSection.new("upgraded", 2)
	registry.register(SaveSection.Block.PROFILE, upgraded)
	var err: Error = registry.restore(
			SaveSection.Block.PROFILE, {"upgraded": {"version": 1, "data": {"old": true}}}
	)
	_check("sections migrate: OK", err == OK, error_string(err))
	_check("sections migrate: from version 1", upgraded.migrated_from == 1)
	_check(
			"sections migrate: restored migrated data",
			(upgraded.data.get("migrated") == true) as bool
	)

	var two_phase: SaveSectionRegistry = SaveSectionRegistry.new()
	var fine: FakeSection = FakeSection.new("fine", 1)
	var future: FakeSection = FakeSection.new("future", 1)
	two_phase.register(SaveSection.Block.PROFILE, fine)
	two_phase.register(SaveSection.Block.PROFILE, future)
	var newer: Dictionary = {
		"fine": {"version": 1, "data": {}},
		"future": {"version": 2, "data": {}},
	}
	var newer_err: Error = two_phase.restore(SaveSection.Block.PROFILE, newer)
	_check("sections newer version: refused", newer_err == ERR_FILE_UNRECOGNIZED)
	_check("sections newer version: nothing restored", fine.restore_count == 0)

	var malformed_err: Error = two_phase.restore(
			SaveSection.Block.PROFILE, {"fine": {"version": 1, "data": "not a dictionary"}}
	)
	_check("sections malformed: refused", malformed_err == ERR_INVALID_DATA)

	var no_migration: FakeSection = FakeSection.new("no_migration", 2)
	no_migration.use_default_migrate = true
	var strict: SaveSectionRegistry = SaveSectionRegistry.new()
	strict.register(SaveSection.Block.PROFILE, no_migration)
	var missing_err: Error = strict.restore(
			SaveSection.Block.PROFILE, {"no_migration": {"version": 1, "data": {}}}
	)
	_check("sections default migrate: fails loudly", missing_err == ERR_UNAVAILABLE)

	var refusing: FakeSection = FakeSection.new("refusing", 1)
	refusing.refuse_restore = true
	var picky: SaveSectionRegistry = SaveSectionRegistry.new()
	picky.register(SaveSection.Block.PROFILE, refusing)
	var refused_err: Error = picky.restore(
			SaveSection.Block.PROFILE, {"refusing": {"version": 1, "data": {}}}
	)
	_check("sections restore refusal: reported", refused_err == ERR_INVALID_DATA)


func _test_sections_raw_and_replace() -> void:
	var raw: RawSaveSection = RawSaveSection.new("unlocks")
	raw.restore({"keep": [1, 2]})
	_check("raw section: passes data through", raw.capture() == {"keep": [1, 2]})
	raw.reset()
	_check("raw section: reset empties", raw.capture().is_empty())

	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	registry.register(SaveSection.Block.PROFILE, RawSaveSection.new("unlocks"))
	var real: FakeSection = FakeSection.new("unlocks", 1)
	real.data = {"real": true}
	registry.register(SaveSection.Block.PROFILE, real)
	var captured: Dictionary = registry.capture(SaveSection.Block.PROFILE, {})
	_check(
			"raw section: replaced by the real one",
			(captured["unlocks"]["data"] == {"real": true}) as bool
	)
	_check("raw section: has_section", registry.has_section(SaveSection.Block.PROFILE, "unlocks"))


func _test_player_sections_per_seat() -> void:
	for seat_count: int in [1, 2, 4]:
		var registry: SaveSectionRegistry = SaveSectionRegistry.new()
		var inventory: FakePlayerSection = FakePlayerSection.new()
		registry.register_player(inventory)

		var players: Array[CampaignData.PlayerRun] = []
		for seat: int in seat_count:
			var player: CampaignData.PlayerRun = CampaignData.PlayerRun.new()
			player.seat = seat
			# The last seat has no saved inventory, as if the section was added mid-campaign.
			if seat < seat_count - 1 or seat_count == 1:
				player.sections = {"inventory": {"version": 1, "data": {"items": seat}}}
			players.append(player)

		var label: String = "player sections x%d" % [seat_count]
		var err: Error = registry.restore_players(players)
		_check("%s: OK" % [label], err == OK, error_string(err))
		_check("%s: cleared first" % [label], inventory.clear_count == 1)
		var expected_restores: int = seat_count if seat_count == 1 else seat_count - 1
		_check(
				"%s: restored once per saved seat" % [label],
				inventory.restored_seats.size() == expected_restores
		)
		if seat_count > 1:
			_check(
					"%s: missing seat reset" % [label],
					inventory.reset_seats == [seat_count - 1]
			)

		registry.capture_players(players)
		var all_written: bool = true
		for player: CampaignData.PlayerRun in players:
			var entry: Dictionary = player.sections.get("inventory", {})
			var expected: Dictionary = {"seat": player.seat}
			all_written = all_written and entry.get("data") == expected
		_check("%s: captured into every player" % [label], all_written)

	var fresh: SaveSectionRegistry = SaveSectionRegistry.new()
	var section: FakePlayerSection = FakePlayerSection.new()
	fresh.register_player(section)
	var two: Array[CampaignData.PlayerRun] = [
		CampaignData.PlayerRun.new(),
		CampaignData.PlayerRun.new(),
	]
	two[1].seat = 1
	fresh.reset_players(two)
	_check(
			"player sections reset: clear then each seat",
			section.clear_count == 1 and section.reset_seats == [0, 1]
	)


func _test_combat_round_trip() -> void:
	_clear_test_dir()
	var combat: CombatData = CombatData.new()
	_check(
			"combat: starts turn 1, player phase",
			combat.turn == 1 and combat.phase == CombatData.Phase.PLAYER
	)
	combat.turn = 3
	combat.phase = CombatData.Phase.ENEMY
	combat.checkpoint_seq = 12
	combat.sections = {"enemy_units": {"version": 1, "data": {"count": 4}}}
	SaveFile.write(TEST_PATH, combat.to_envelope())

	var loaded: CombatData = CombatData.new()
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check("combat: load OK", err == OK, error_string(err))
	_check("combat: turn and phase", loaded.turn == 3 and loaded.phase == CombatData.Phase.ENEMY)
	_check("combat: checkpoint_seq from envelope", loaded.checkpoint_seq == 12)
	_check("combat: sections kept", loaded.sections.has("enemy_units"))
	_check(
			"combat: file names",
			CombatData.get_file_name(CampaignData.Mode.SOLO) == "combat_solo.json"
			and CombatData.get_file_name(CampaignData.Mode.MULTIPLAYER) == "combat_multi.json"
	)


func _test_combat_rejects_bad_data() -> void:
	var cases: Dictionary[String, Dictionary] = {
		"unknown phase": {"turn": 1, "phase": "neutral"},
		"turn 0": {"turn": 0, "phase": "player"},
		"missing phase": {"turn": 2},
	}
	for case_name: String in cases:
		var combat: CombatData = CombatData.new()
		combat.turn = 9
		var err: Error = combat.load_envelope(SaveFile.make_envelope(1, cases[case_name], {}, 1))
		_check(
				"combat bad data: %s refused" % [case_name],
				err == ERR_INVALID_DATA and combat.turn == 9
		)


func _test_archive_from_campaign() -> void:
	var campaign: CampaignData = CampaignData.create_solo(77)
	campaign.mode = CampaignData.Mode.MULTIPLAYER
	campaign.difficulty = "hard"
	campaign.floors_climbed = 5
	campaign.combat_maps_completed = 2
	campaign.play_time_seconds = 600
	campaign.players[0].steam_id = STEAM_ID
	campaign.players[0].sections = {
		"roster": {"version": 1, "data": {"units": ["knight"]}},
		"inventory": {"version": 1, "data": {}},
	}
	var guest: CampaignData.PlayerRun = CampaignData.PlayerRun.new()
	guest.seat = 1
	campaign.players.append(guest)

	var names: Dictionary[int, String] = {0: "Host"}
	var record: ArchiveRecord = ArchiveRecord.from_campaign(campaign, true, names)
	_check("archive: outcome and mode", record.won and record.mode == CampaignData.Mode.MULTIPLAYER)
	_check(
			"archive: run fields copied",
			record.run_seed == 77 and record.difficulty == "hard" and record.floors_climbed == 5
			and record.combat_maps_completed == 2 and record.play_time_seconds == 600
	)
	_check("archive: ended now", record.ended_at >= record.started_at and record.ended_at > 0)
	_check("archive: one entry per seat", record.players.size() == 2)
	_check(
			"archive: names by seat",
			record.players[0].name == "Host" and record.players[1].name.is_empty()
	)
	_check("archive: Steam id kept", record.players[0].steam_id == STEAM_ID)
	_check(
			"archive: only the roster copied",
			record.players[0].roster == {"version": 1, "data": {"units": ["knight"]}}
	)
	_check("archive: no roster is empty", record.players[1].roster.is_empty())
	var expected_name: String = "multiplayer_%d.json" % [record.ended_at]
	_check("archive: file name", record.get_file_name() == expected_name)


func _test_archive_round_trip_and_bad_data() -> void:
	_clear_test_dir()
	var record: ArchiveRecord = ArchiveRecord.from_campaign(CampaignData.create_solo(5), false, {})
	record.modifiers = PackedStringArray(["fog"])
	SaveFile.write(TEST_PATH, record.to_envelope())

	var loaded: ArchiveRecord = ArchiveRecord.new()
	loaded.won = true
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check("archive round trip: load OK", err == OK, error_string(err))
	_check("archive round trip: lost", not loaded.won and loaded.mode == CampaignData.Mode.SOLO)
	_check(
			"archive round trip: fields",
			loaded.run_seed == 5 and loaded.ended_at == record.ended_at
			and loaded.modifiers == PackedStringArray(["fog"]) and loaded.players.size() == 1
	)

	var bad: Dictionary[String, Dictionary] = {
		"unknown outcome": {"mode": "solo", "outcome": "draw", "players": []},
		"unknown mode": {"mode": "coop", "outcome": "won", "players": []},
		"missing players": {"mode": "solo", "outcome": "won"},
	}
	for case_name: String in bad:
		var target: ArchiveRecord = ArchiveRecord.new()
		var bad_err: Error = target.load_envelope(SaveFile.make_envelope(1, bad[case_name]))
		_check("archive bad data: %s refused" % [case_name], bad_err == ERR_INVALID_DATA)


func _test_multiplayer_campaign() -> void:
	_clear_test_dir()
	var ids: PackedStringArray = [STEAM_ID, "76561198000000002", "76561198000000003"]
	var campaign: CampaignData = CampaignData.create_multiplayer(9, ids)
	_check("multi: mode", campaign.mode == CampaignData.Mode.MULTIPLAYER)
	_check("multi: one seat per id", campaign.players.size() == 3 and campaign.players[2].seat == 2)
	_check("multi: host is seat 0", campaign.get_host_steam_id() == 76561198000000001)
	var required: PackedInt64Array = campaign.get_required_steam_ids()
	_check(
			"multi: required ids in seat order",
			required == PackedInt64Array([76561198000000001, 76561198000000002, 76561198000000003])
	)

	SaveFile.write(TEST_PATH, campaign.to_envelope())
	var loaded: CampaignData = CampaignData.new()
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check("multi: round trip OK", err == OK, error_string(err))
	_check("multi: required ids survive", loaded.get_required_steam_ids() == required)

	var solo: CampaignData = CampaignData.create_solo(1)
	_check(
			"multi: solo has no required ids or host",
			solo.get_required_steam_ids().is_empty() and solo.get_host_steam_id() == 0
	)


func _test_multiplayer_campaign_rejects_bad_ids() -> void:
	var cases: Dictionary[String, Array] = {
		"empty Steam id": ["", "76561198000000002"],
		"repeated Steam id": [STEAM_ID, STEAM_ID],
		"non-numeric Steam id": ["host", "76561198000000002"],
	}
	for case_name: String in cases:
		var players: Array[Dictionary] = []
		var ids: Array = cases[case_name]
		for seat: int in ids.size():
			players.append({"seat": seat, "steam_id": ids[seat], "sections": {}})
		var campaign: CampaignData = CampaignData.new()
		var core: Dictionary = {"mode": "multiplayer", "players": players}
		var err: Error = campaign.load_envelope(SaveFile.make_envelope(1, core, {}, 1))
		_check("multi bad ids: %s refused" % [case_name], err == ERR_INVALID_DATA)


func _test_lobby_admission() -> void:
	var host: String = "0.1.0"
	var joiner: int = 76561198000000002
	var anyone: PackedInt64Array = []
	var campaign_ids: PackedInt64Array = [76561198000000001, joiner]
	var members: PackedInt64Array = [76561198000000001]

	_check(
			"admission: new lobby admits a matching version",
			LobbyAdmission.decide(host, host, joiner, anyone, members) == LobbyAdmission.ADMIT
	)
	_check(
			"admission: other version refused",
			LobbyAdmission.decide(host, "0.2.0", joiner, anyone, members)
			== LobbyAdmission.Refusal.VERSION_MISMATCH
	)
	_check(
			"admission: oversized version refused",
			LobbyAdmission.decide(host, "0.1.0".repeat(20), joiner, anyone, members)
			== LobbyAdmission.Refusal.VERSION_MISMATCH
	)
	_check(
			"admission: campaign player admitted on resume",
			LobbyAdmission.decide(host, host, joiner, campaign_ids, members)
			== LobbyAdmission.ADMIT
	)
	_check(
			"admission: outsider refused on resume",
			LobbyAdmission.decide(host, host, 76561198000000099, campaign_ids, members)
			== LobbyAdmission.Refusal.NOT_IN_CAMPAIGN
	)
	var with_joiner: PackedInt64Array = [76561198000000001, joiner]
	_check(
			"admission: same account twice refused",
			LobbyAdmission.decide(host, host, joiner, anyone, with_joiner)
			== LobbyAdmission.Refusal.ALREADY_JOINED
	)
	_check(
			"admission: version checked before membership",
			LobbyAdmission.decide(host, "9.9.9", 76561198000000099, campaign_ids, members)
			== LobbyAdmission.Refusal.VERSION_MISMATCH
	)
	_check(
			"admission: every refusal has text, unknown ones too",
			not LobbyAdmission.describe(LobbyAdmission.Refusal.NOT_IN_CAMPAIGN).is_empty()
			and not LobbyAdmission.describe(99).is_empty()
	)


func _step_add_gold(envelope: Dictionary) -> Error:
	envelope[SaveFile.KEY_CORE]["gold"] = 100
	return OK


func _step_rename_gold(envelope: Dictionary) -> Error:
	var core: Dictionary = envelope[SaveFile.KEY_CORE]
	core["coins"] = core.get("gold", 0)
	core.erase("gold")
	return OK


func _step_fail(_envelope: Dictionary) -> Error:
	return ERR_INVALID_DATA


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])


func _envelope_with_seq(seq: int) -> Dictionary:
	return SaveFile.make_envelope(1, {"seq_marker": seq}, {}, seq)


# A complete envelope as raw text, for planting files a crash would leave behind.
func _envelope_text(seq: int, game_version: String) -> String:
	var envelope: Dictionary = SaveFile.make_envelope(1, {"seq_marker": seq}, {}, seq)
	envelope[SaveFile.KEY_GAME_VERSION] = game_version
	envelope[SaveFile.KEY_SAVED_AT] = 1
	return JSON.stringify(envelope)


func _core(result: SaveFile.ReadResult) -> Dictionary:
	if result.error != OK:
		return {}
	return result.envelope[SaveFile.KEY_CORE]


func _seq(result: SaveFile.ReadResult) -> int:
	return _core(result).get("seq_marker", -1) as int


# Reads checkpoint_seq straight from one file on disk, bypassing SaveFile's recovery.
func _seq_on_disk(path: String) -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return -1
	var envelope: Dictionary = data
	return envelope.get(SaveFile.KEY_CHECKPOINT_SEQ, -1) as int


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_err: Error = FileAccess.get_open_error()
		push_error("run_all: can't open %s - %s" % [path, error_string(open_err)])
		return
	file.store_string(text)
	file.close()


func _clear_test_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	for file_name: String in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR + file_name)


func _temp() -> String:
	return TEST_PATH + SaveFile.TEMP_SUFFIX


func _backup() -> String:
	return TEST_PATH + SaveFile.BACKUP_SUFFIX


## A file-level section that records what the registry asked of it.
class FakeSection:
	extends SaveSection

	var key: String = ""
	var version: int = 1
	var data: Dictionary = {}
	var restore_count: int = 0
	var reset_count: int = 0
	var migrated_from: int = 0
	var refuse_restore: bool = false
	var use_default_migrate: bool = false

	func _init(section_key: String, section_version: int) -> void:
		key = section_key
		version = section_version

	func get_key() -> String:
		return key

	func get_version() -> int:
		return version

	func capture() -> Dictionary:
		return data.duplicate(true)

	func restore(restored: Dictionary) -> Error:
		restore_count += 1
		if refuse_restore:
			return ERR_INVALID_DATA
		data = restored
		return OK

	func reset() -> void:
		reset_count += 1
		data = {}

	func migrate(old: Dictionary, from_version: int) -> Error:
		if use_default_migrate:
			return super.migrate(old, from_version)
		migrated_from = from_version
		old["migrated"] = true
		return OK


## A per-player section that records which seats it was asked about.
class FakePlayerSection:
	extends PlayerSaveSection

	var restored_seats: Array[int] = []
	var reset_seats: Array[int] = []
	var clear_count: int = 0

	func get_key() -> String:
		return "inventory"

	func get_version() -> int:
		return 1

	func capture(seat: int) -> Dictionary:
		return {"seat": seat}

	func restore(seat: int, _data: Dictionary) -> Error:
		restored_seats.append(seat)
		return OK

	func reset(seat: int) -> void:
		reset_seats.append(seat)

	func clear() -> void:
		clear_count += 1
		restored_seats.clear()
		reset_seats.clear()
