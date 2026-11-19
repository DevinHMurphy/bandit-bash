# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     contract_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Build fingerprint cases for tests/net/run_all.gd ([NetContract]): the fingerprint is stable and
## built from its parts; the parts read the live wire enums, patterns, command names and RPC
## configs; an appended or renumbered enum value, a changed pattern, snapshot format, command
## name, RPC mode or version changes it; key order doesn't; the content digest follows an edit, a
## rename and a remap pointer. Prints the boot cost of the fingerprint.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

# Content fixtures: same is a copy of base; edited changes one byte of one file; renamed renames
# one file; remapped has a .remap pointer to base's file in place of that file.
const FIXTURES: String = "res://tests/net/fixtures/"


func run() -> void:
	_test_stable()
	_test_parts_read_the_live_format()
	_test_format_changes()
	_test_key_order()
	_test_content_digest()
	_test_boot_cost()


func _test_stable() -> void:
	var expected: int = NetContract.combine(
			SaveFile.get_running_version(),
			NetContract.format_parts(),
			NetContract.content_digest(NetContract.CONTENT_ROOTS)
	)
	var first: int = NetContract.fingerprint()
	var again: int = NetContract.fingerprint()
	_check("contract: the fingerprint is stable and built from its parts", (
			first == again and first == expected
	), "%d, %d and %d" % [first, again, expected])


func _test_parts_read_the_live_format() -> void:
	var parts: Dictionary = NetContract.format_parts()
	# Typed, since a comparison of a Dictionary's Variant values is a Variant.
	var is_live: bool = (
			parts["CombatFact.Kind"] == CombatFact.Kind
			and parts["CombatFact.Source"] == CombatFact.Source
			and parts["CombatFact.CombatSide"] == CombatFact.CombatSide
			and parts["CombatFact.DamageType"] == CombatFact.DamageType
			and parts["CombatFact.Flag"] == CombatFact.Flag
			and parts["CampaignFact.Kind"] == CampaignFact.Kind
			and parts["LobbyAdmission.Refusal"] == LobbyAdmission.Refusal
			and parts["SeatDirectory.State"] == SeatDirectory.State
			and parts["CombatFact.WIRE_PATTERN"] == CombatFact.WIRE_PATTERN
			and parts["CampaignFact.WIRE_PATTERN"] == CampaignFact.WIRE_PATTERN
			and (parts["CombatSession.snapshot_format"] as int) > 0
			and (parts["CombatEncounter.snapshot_format"] as int) > 0
	)
	_check("contract: the parts are the live wire enums and patterns", is_live, str(parts.keys()))

	var commands: Dictionary[String, String] = NetContract.command_wire_types()
	var expected: Dictionary[String, String] = {
		"StartCommand": StartCommand.WIRE_TYPE,
		"EndTurnCommand": EndTurnCommand.WIRE_TYPE,
		"UnitTurnCommand": UnitTurnCommand.WIRE_TYPE,
		"CastRuneCommand": CastRuneCommand.WIRE_TYPE,
		"DiscardRuneCommand": DiscardRuneCommand.WIRE_TYPE,
	}
	var is_complete: bool = true
	for class_id: String in expected:
		is_complete = is_complete and commands.get(class_id, "") == expected[class_id]
	var has_blank: bool = commands.values().has("")
	_check("contract: every command type's wire name is found, none blank", (
			is_complete and not has_blank
	), str(commands))

	var rpcs: Dictionary[String, Variant] = NetContract.rpc_configs()
	var steam: Dictionary = rpcs.get("SteamNetwork", {})
	_check("contract: the RPC configs of every autoload with RPCs", (
			steam.has("_request_admission")
			and steam.has("_join_refused")
			and rpcs.has("SaveService")
			and rpcs.has("SceneRouter")
			and not rpcs.has("NetLog")
	), str(rpcs.keys()))


func _test_format_changes() -> void:
	var version: String = SaveFile.get_running_version()
	var content: String = "content"
	var parts: Dictionary = NetContract.format_parts()
	var base: int = NetContract.combine(version, parts, content)

	var appended: Dictionary = _with_enum_entry(parts, "CombatFact.Kind", "NEW_KIND", 999)
	var campaign: Dictionary = _with_enum_entry(parts, "CampaignFact.Kind", "NEW_KIND", 999)
	var refusal: Dictionary = _with_enum_entry(parts, "LobbyAdmission.Refusal", "NEW_REASON", 99)
	var renumbered: Dictionary = _with_enum_entry(parts, "CombatFact.Source", "NONE", 77)
	_check("contract: an appended or renumbered wire enum value changes the fingerprint", (
			NetContract.combine(version, appended, content) != base
			and NetContract.combine(version, campaign, content) != base
			and NetContract.combine(version, refusal, content) != base
			and NetContract.combine(version, renumbered, content) != base
	))

	var pattern: Dictionary = parts.duplicate(true)
	pattern["CombatFact.WIRE_PATTERN"] = (parts["CombatFact.WIRE_PATTERN"] as String) + "i"
	var campaign_pattern: Dictionary = parts.duplicate(true)
	campaign_pattern["CampaignFact.WIRE_PATTERN"] = "s" + (
			parts["CampaignFact.WIRE_PATTERN"] as String
	)
	_check("contract: a changed wire pattern changes the fingerprint", (
			NetContract.combine(version, pattern, content) != base
			and NetContract.combine(version, campaign_pattern, content) != base
	))

	var snapshot: Dictionary = parts.duplicate(true)
	snapshot["CombatSession.snapshot_format"] = (parts["CombatSession.snapshot_format"] as int) + 1
	var command: Dictionary = parts.duplicate(true)
	(command["commands"] as Dictionary)["EndTurnCommand"] = "end_turn_2"
	var added_command: Dictionary = parts.duplicate(true)
	(added_command["commands"] as Dictionary)["VoteCommand"] = "vote"
	var rpc: Dictionary = parts.duplicate(true)
	var steam: Dictionary = (rpc["rpc"] as Dictionary)["SteamNetwork"]
	(steam["_request_ready"] as Dictionary)["rpc_mode"] = MultiplayerAPI.RPC_MODE_AUTHORITY
	var added_rpc: Dictionary = parts.duplicate(true)
	((added_rpc["rpc"] as Dictionary)["SteamNetwork"] as Dictionary)["_new_rpc"] = {}
	_check("contract: a snapshot format, command name or RPC change changes the fingerprint", (
			NetContract.combine(version, snapshot, content) != base
			and NetContract.combine(version, command, content) != base
			and NetContract.combine(version, added_command, content) != base
			and NetContract.combine(version, rpc, content) != base
			and NetContract.combine(version, added_rpc, content) != base
	))

	_check("contract: another game version or content changes the fingerprint", (
			NetContract.combine(version + ".1", parts, content) != base
			and NetContract.combine(version, parts, content + "x") != base
	))


func _test_key_order() -> void:
	var parts: Dictionary = NetContract.format_parts()
	var reversed: Dictionary = {}
	var keys: Array = parts.keys()
	keys.reverse()
	for key: Variant in keys:
		reversed[key] = parts[key]
	_check("contract: the parts' key order doesn't change the fingerprint", (
			NetContract.combine("v", reversed, "c") == NetContract.combine("v", parts, "c")
	))


func _test_content_digest() -> void:
	var base: String = _digest("base")
	_check("contract: identical content folders give the same digest", (
			not base.is_empty() and _digest("same") == base
	), base)
	_check("contract: one edited byte changes the digest", _digest("edited") != base)
	_check("contract: a renamed file changes the digest", _digest("renamed") != base)
	_check("contract: a remap pointer counts as the file it points to", (
			_digest("remapped") == base
	), "%s and %s" % [_digest("remapped"), base])
	_check("contract: an edited data file changes the fingerprint", (
			NetContract.combine("v", {}, base) != NetContract.combine("v", {}, _digest("edited"))
	))
	var both: PackedStringArray = [FIXTURES.path_join("base"), FIXTURES.path_join("same")]
	var swapped: PackedStringArray = [FIXTURES.path_join("same"), FIXTURES.path_join("base")]
	var moved: PackedStringArray = [FIXTURES.path_join("base"), FIXTURES.path_join("edited")]
	var moved_back: PackedStringArray = [FIXTURES.path_join("edited"), FIXTURES.path_join("base")]
	_check("contract: a file moved to another content root changes the digest", (
			NetContract.content_digest(both) == NetContract.content_digest(swapped)
			and NetContract.content_digest(moved) != NetContract.content_digest(moved_back)
	))


# Not a check: prints what the fingerprint cost at boot, where SteamNetwork computed it, and one
# more content digest of the real roots, for the step report.
func _test_boot_cost() -> void:
	var started: int = Time.get_ticks_usec()
	NetContract.content_digest(NetContract.CONTENT_ROOTS)
	var digest_usec: int = Time.get_ticks_usec() - started
	print("    (fingerprint at boot: %.1f ms; content digest again: %.1f ms)" % [
		NetContract.build_usec() / 1000.0, digest_usec / 1000.0,
	])
	_check("contract: the fingerprint's first computation was timed", NetContract.build_usec() > 0)


func _digest(folder: String) -> String:
	return NetContract.content_digest(PackedStringArray([FIXTURES.path_join(folder)]))


# A deep copy of parts with key set to value in the enum at part.
func _with_enum_entry(parts: Dictionary, part: String, key: String, value: int) -> Dictionary:
	var copy: Dictionary = parts.duplicate(true)
	var values: Dictionary = (copy[part] as Dictionary).duplicate()
	values[key] = value
	copy[part] = values
	return copy
