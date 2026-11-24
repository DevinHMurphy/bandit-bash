# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     contract_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 24, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Build fingerprint cases for tests/net/run_all.gd ([NetContract]): the fingerprint is stable and
## built from its parts, which it reports for the boot log; the parts read the live wire enums,
## patterns, command names and RPC configs; an appended or renumbered enum value, a changed
## pattern, snapshot format, command name, RPC mode or version changes it; key order doesn't; the
## content digest follows an edit, a rename and a remap pointer, and ignores the line endings and
## uid attributes an editor resave or a checkout changes (BUG-055). Prints the boot cost.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

# Content fixtures: same is a copy of base; edited changes one byte of one file; renamed renames
# one file; remapped has a .remap pointer to base's file in place of that file.
const FIXTURES: String = "res://tests/net/fixtures/"

# Where the editor-churn cases write their variants: written at run time, since the repository
# checks text out with LF endings, and a fixture resource under res:// would register its uid.
const CHURN_ROOT: String = "user://contract_churn/"

# The text resource and the scene each churn variant holds, as the editor writes them; the %s
# are where a resave puts uid attributes. The resource's link value is a uid that is content.
const CHURN_RESOURCE: String = (
		"[gd_resource type=\"Resource\" script_class=\"Probe\" format=3%s]\n\n"
		+ "[ext_resource type=\"Script\"%s path=\"res://scripts/probe.gd\" id=\"1_probe\"]\n\n"
		+ "[resource]\nscript = ExtResource(\"1_probe\")\nvalue = %d\nlink = \"%s\"\n"
)
const CHURN_SCENE: String = (
		"[gd_scene format=4%s]\n\n"
		+ "[ext_resource type=\"TileSet\"%s path=\"res://maps/probe.tres\" id=\"1_tiles\"]\n\n"
		+ "[node name=\"Probe\" type=\"Node2D\" unique_id=1]\n"
)
const CHURN_VALUE: int = 3
const CHURN_LINK: String = "uid://bprobelink"

# A file the digest hashes as stored, in LF and CRLF form.
const CHURN_DATA_NAME: String = "data.bin"
const CHURN_DATA_LF: String = "alpha\nbeta\n"


func run() -> void:
	_test_stable()
	_test_parts_read_the_live_format()
	_test_format_changes()
	_test_key_order()
	_test_fingerprint_parts()
	_test_content_digest()
	_test_editor_churn()
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


func _test_fingerprint_parts() -> void:
	var parts: Dictionary[String, String] = NetContract.fingerprint_parts()
	var format: Dictionary = NetContract.format_parts()
	var version: String = parts.get("version", "")
	var format_hash: String = parts.get("format", "")
	var content: String = parts.get("content", "")
	_check("contract: the logged parts are the version, the format hash and the content digest", (
			parts.size() == 3
			and version == SaveFile.get_running_version()
			and format_hash == NetContract.format_hash(format)
			and content == NetContract.content_digest(NetContract.CONTENT_ROOTS)
			and NetContract.combine(version, format, content) == NetContract.fingerprint()
	), str(parts))

	var reversed: Dictionary = {}
	var keys: Array = format.keys()
	keys.reverse()
	for key: Variant in keys:
		reversed[key] = format[key]
	var changed: Dictionary = _with_enum_entry(format, "CombatFact.Kind", "NEW_KIND", 999)
	_check("contract: the format's hash follows a format change, not key order", (
			NetContract.format_hash(reversed) == NetContract.format_hash(format)
			and NetContract.format_hash(changed) != NetContract.format_hash(format)
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


# BUG-055: what an editor resave or another checkout changes without changing content leaves the
# digest alone (CRLF endings; uid attributes on the header and ext_resource lines, random per
# machine), and any other change still counts. Each variant folder holds one text resource and one
# scene, as content folders do.
func _test_editor_churn() -> void:
	_write_variant("lf", "", "", CHURN_VALUE, CHURN_LINK, false)
	_write_variant("crlf", "", "", CHURN_VALUE, CHURN_LINK, true)
	_write_variant("uids", _new_uid(), _new_uid(), CHURN_VALUE, CHURN_LINK, false)
	_write_variant("uids_crlf", _new_uid(), _new_uid(), CHURN_VALUE, CHURN_LINK, true)
	_write_variant("edited", "", "", CHURN_VALUE + 1, CHURN_LINK, false)
	_write_variant("edited_uids", _new_uid(), _new_uid(), CHURN_VALUE + 1, CHURN_LINK, true)
	_write_variant("linked", "", "", CHURN_VALUE, CHURN_LINK + "2", false)
	var base: String = _churn_digest("lf")
	_check("contract: a CRLF copy of a text resource digests as its LF copy", (
			not base.is_empty() and _churn_digest("crlf") == base
	), "%s and %s" % [_churn_digest("crlf"), base])
	_check("contract: uid attributes on header and ext_resource lines don't change the digest", (
			_churn_digest("uids") == base and _churn_digest("uids_crlf") == base
	), "%s, %s and %s" % [_churn_digest("uids"), _churn_digest("uids_crlf"), base])
	_check("contract: a changed value or a uid in a value still changes the digest", (
			_churn_digest("edited") != base
			and _churn_digest("edited_uids") == _churn_digest("edited")
			and _churn_digest("linked") != base
	))

	_write_file("data_lf".path_join(CHURN_DATA_NAME), CHURN_DATA_LF)
	_write_file("data_crlf".path_join(CHURN_DATA_NAME), CHURN_DATA_LF.replace("\n", "\r\n"))
	_check("contract: any other file is hashed as stored, its line endings included", (
			_churn_digest("data_lf") != _churn_digest("data_crlf")
	))

	# An export's converted resource: the pointer under the text resource's name, the file it
	# names hashed as stored. An LF target matches the LF variant; a CRLF one is not normalized.
	var resource: String = _churn_resource("", "", CHURN_VALUE, CHURN_LINK)
	_write_file("targets/lf.res", resource)
	_write_file("targets/crlf.res", resource.replace("\n", "\r\n"))
	for kind: String in ["lf", "crlf"]:
		var folder: String = "remapped_%s" % [kind]
		_write_file(folder.path_join("sub/probe.tres.remap"), "[remap]\n\npath=\"%s\"\n" % [
			CHURN_ROOT.path_join("targets/%s.res" % [kind]),
		])
		_write_file(folder.path_join("probe.tscn"), _churn_scene("", ""))
	_check("contract: a remapped resource is the file it points to, hashed as stored", (
			_churn_digest("remapped_lf") == base and _churn_digest("remapped_crlf") != base
	), "%s, %s and %s" % [_churn_digest("remapped_lf"), _churn_digest("remapped_crlf"), base])
	_remove_tree(CHURN_ROOT)


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


func _churn_digest(folder: String) -> String:
	return NetContract.content_digest(PackedStringArray([CHURN_ROOT.path_join(folder)]))


# The probe resource with header_uid and ext_uid ("" for none) as a resave writes them.
func _churn_resource(header_uid: String, ext_uid: String, value: int, link: String) -> String:
	return CHURN_RESOURCE % [_uid_attribute(header_uid), _uid_attribute(ext_uid), value, link]


func _churn_scene(header_uid: String, ext_uid: String) -> String:
	return CHURN_SCENE % [_uid_attribute(header_uid), _uid_attribute(ext_uid)]


func _uid_attribute(uid: String) -> String:
	if uid.is_empty():
		return ""
	return " uid=\"%s\"" % [uid]


# A new random uid, as the editor gives a scene that has none.
func _new_uid() -> String:
	return ResourceUID.id_to_text(ResourceUID.create_id())


# Writes a variant folder under CHURN_ROOT: the probe resource (sub/probe.tres) and scene.
func _write_variant(
		folder: String,
		header_uid: String,
		ext_uid: String,
		value: int,
		link: String,
		is_crlf: bool,
) -> void:
	var resource: String = _churn_resource(header_uid, ext_uid, value, link)
	var scene: String = _churn_scene(_new_uid() if not header_uid.is_empty() else "", ext_uid)
	if is_crlf:
		resource = resource.replace("\n", "\r\n")
		scene = scene.replace("\n", "\r\n")
	_write_file(folder.path_join("sub/probe.tres"), resource)
	_write_file(folder.path_join("probe.tscn"), scene)


# Writes text as stored (no line-ending conversion) at relative under CHURN_ROOT.
func _write_file(relative: String, text: String) -> void:
	var path: String = CHURN_ROOT.path_join(relative)
	var made: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK and made != ERR_ALREADY_EXISTS:
		push_error("contract_cases: a folder can't be made - %s" % [path.get_base_dir()])
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("contract_cases: a file can't be written - %s" % [path])
		return
	file.store_string(text)
	file.close()


# Removes folder and everything under it.
func _remove_tree(folder: String) -> void:
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		_remove_tree(folder.path_join(child))
	DirAccess.remove_absolute(folder)


# A deep copy of parts with key set to value in the enum at part.
func _with_enum_entry(parts: Dictionary, part: String, key: String, value: int) -> Dictionary:
	var copy: Dictionary = parts.duplicate(true)
	var values: Dictionary = (copy[part] as Dictionary).duplicate()
	values[key] = value
	copy[part] = values
	return copy
