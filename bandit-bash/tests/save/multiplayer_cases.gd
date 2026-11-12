# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     multiplayer_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/save/save_case_base.gd"
## Multiplayer cases for tests/save/run_all.gd: seats and required Steam ids in [CampaignData],
## refused ids, and the lobby admission rules ([LobbyAdmission]).


func run() -> void:
	_test_multiplayer_campaign()
	_test_multiplayer_campaign_rejects_bad_ids()
	_test_lobby_admission()


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
