# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     admission_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Build check cases for tests/net/run_all.gd ([LobbyAdmission]): a matching fingerprint is
## admitted, another one refused with BUILD_MISMATCH (its value pinned at 3), the version is
## checked before the build and the build before the campaign and membership, and the refusal has
## its own text. The version and membership rules are in the save suite's multiplayer cases.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const HOST_STEAM_ID: int = 76561198000000001
const JOINER_STEAM_ID: int = 76561198000000002
const OUTSIDER_STEAM_ID: int = 76561198000000099


func run() -> void:
	_test_build_check()
	_test_check_order()
	_test_refusal_contract()


func _test_build_check() -> void:
	var version: String = SaveFile.get_running_version()
	var host: int = NetContract.fingerprint()
	var other_parts: Dictionary = NetContract.format_parts()
	other_parts["CampaignFact.WIRE_PATTERN"] = "i"
	var other: int = NetContract.combine(
			version, other_parts, NetContract.content_digest(NetContract.CONTENT_ROOTS)
	)
	var anyone: PackedInt64Array = []
	var members: PackedInt64Array = [HOST_STEAM_ID]
	_check("admission: the same build is admitted", (
			LobbyAdmission.decide(version, version, host, host, JOINER_STEAM_ID, anyone, members)
			== LobbyAdmission.ADMIT
	))
	_check("admission: another build of the same version is refused as BUILD_MISMATCH", (
			other != host
			and LobbyAdmission.decide(
					version, version, host, other, JOINER_STEAM_ID, anyone, members
			) == LobbyAdmission.Refusal.BUILD_MISMATCH
	))


func _test_check_order() -> void:
	var campaign: PackedInt64Array = [HOST_STEAM_ID, JOINER_STEAM_ID]
	var members: PackedInt64Array = [HOST_STEAM_ID, JOINER_STEAM_ID]
	var nobody: PackedInt64Array = []
	_check("admission: the version is checked before the build", (
			LobbyAdmission.decide("0.1.0", "0.2.0", 1, 2, JOINER_STEAM_ID, campaign, nobody)
			== LobbyAdmission.Refusal.VERSION_MISMATCH
	))
	_check("admission: the build is checked before the campaign and membership", (
			LobbyAdmission.decide("0.1.0", "0.1.0", 1, 2, OUTSIDER_STEAM_ID, campaign, members)
			== LobbyAdmission.Refusal.BUILD_MISMATCH
			and LobbyAdmission.decide("0.1.0", "0.1.0", 1, 2, JOINER_STEAM_ID, campaign, members)
			== LobbyAdmission.Refusal.BUILD_MISMATCH
	))


func _test_refusal_contract() -> void:
	var text: String = LobbyAdmission.describe(LobbyAdmission.Refusal.BUILD_MISMATCH)
	_check("admission: BUILD_MISMATCH is 3, appended", (
			LobbyAdmission.Refusal.BUILD_MISMATCH == 3
			and LobbyAdmission.Refusal.size() == 4
	))
	_check("admission: BUILD_MISMATCH has its own text", (
			not text.is_empty()
			and text != LobbyAdmission.describe(LobbyAdmission.Refusal.VERSION_MISMATCH)
			and text != LobbyAdmission.describe(99)
	), text)
