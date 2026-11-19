# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_archive_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/save/save_case_base.gd"
## [CombatData] and [ArchiveRecord] cases for tests/save/run_all.gd: round trips and refused
## data, and archive records built from a campaign.


# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "save"

func run() -> void:
	_test_combat_round_trip()
	_test_combat_rejects_bad_data()
	_test_archive_from_campaign()
	_test_archive_round_trip_and_bad_data()


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
