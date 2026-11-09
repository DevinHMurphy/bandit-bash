# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/save/save_case_base.gd"
## [CampaignData] cases for tests/save/run_all.gd: a solo round trip, exact run seeds in JSON,
## the multiplayer shape and refused data.


func run() -> void:
	_test_campaign_solo_round_trip()
	_test_campaign_run_seed_exact_in_json()
	_test_campaign_multiplayer_shape()
	_test_campaign_rejects_bad_data()


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
