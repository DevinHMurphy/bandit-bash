# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     profile_settings_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/save/save_case_base.gd"
## [ProfileData] and [SettingsData] cases for tests/save/run_all.gd: round trips, defaults,
## newer schemas, repaired hand edits, the opening swap setting and volume levels.


func run() -> void:
	_test_profile_round_trip()
	_test_profile_defaults_and_newer_schema()
	_test_settings_round_trip_and_copy()
	_test_settings_repairs_hand_edits()
	_test_settings_opening_swap_round_trip()
	_test_settings_opening_swap_repairs()
	_test_settings_volume_db()


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


# The opening-swap setting: on by default, saved off and read back off through a file, copied, and
# a version 1 file (from before it) migrated to version 2 with the setting on.
func _test_settings_opening_swap_round_trip() -> void:
	_clear_test_dir()
	var defaults: SettingsData = SettingsData.new()
	_check("settings opening swap: on by default", defaults.is_opening_swap_on)

	var settings: SettingsData = SettingsData.new()
	settings.is_opening_swap_on = false
	var envelope: Dictionary = settings.to_envelope()
	var written: Dictionary = envelope[SaveFile.KEY_CORE]
	var written_version: int = envelope[SaveFile.KEY_SCHEMA_VERSION]
	_check(
			"settings opening swap: written at schema 2 under its key",
			written_version == 2 and is_same(written.get(SettingsData.OPENING_SWAP_KEY), false)
	)
	SaveFile.write(TEST_PATH, envelope)
	var loaded: SettingsData = SettingsData.new()
	var err: Error = loaded.load_envelope(SaveFile.read(TEST_PATH).envelope)
	_check(
			"settings opening swap: off survives the file",
			err == OK and not loaded.is_opening_swap_on,
			error_string(err)
	)
	var copied: SettingsData = loaded.copy()
	copied.is_opening_swap_on = true
	_check(
			"settings opening swap: copied, and the copy is independent",
			not loaded.is_opening_swap_on and loaded.copy().is_opening_swap_on == false
	)

	var old: Dictionary = SaveFile.make_envelope(1, {"master_volume": 4})
	var migrated: SettingsData = SettingsData.new()
	migrated.is_opening_swap_on = false
	var migrate_err: Error = migrated.load_envelope(old)
	var old_core: Dictionary = old[SaveFile.KEY_CORE]
	var old_version: int = old[SaveFile.KEY_SCHEMA_VERSION]
	_check(
			"settings opening swap: a version 1 file migrates to 2 with it on",
			migrate_err == OK
			and migrated.is_opening_swap_on
			and migrated.master_volume == 4
			and old_version == 2
			and is_same(old_core.get(SettingsData.OPENING_SWAP_KEY), true),
			error_string(migrate_err)
	)


# A hand-edited opening swap that isn't a JSON bool is repaired to on, the file still loading.
func _test_settings_opening_swap_repairs() -> void:
	var bad_values: Array = [0, 1, "false", null, [], {}, 0.0]
	var wrong: PackedStringArray = []
	for bad: Variant in bad_values:
		var settings: SettingsData = SettingsData.new()
		settings.is_opening_swap_on = false
		var core: Dictionary = {SettingsData.OPENING_SWAP_KEY: bad, "music_volume": 2}
		var err: Error = settings.load_envelope(SaveFile.make_envelope(2, core))
		if err != OK or not settings.is_opening_swap_on or settings.music_volume != 2:
			wrong.append("%s: %s, swap %s" % [var_to_str(bad), error_string(err), str(
					settings.is_opening_swap_on
			)])
	_check("settings opening swap: a bad value is repaired to on", wrong.is_empty(), ", ".join(wrong))
	var newer: SettingsData = SettingsData.new()
	newer.is_opening_swap_on = false
	var newer_err: Error = newer.load_envelope(SaveFile.make_envelope(3, {}))
	_check(
			"settings opening swap: a newer schema is refused, unchanged",
			newer_err == ERR_FILE_UNRECOGNIZED and not newer.is_opening_swap_on
	)


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
