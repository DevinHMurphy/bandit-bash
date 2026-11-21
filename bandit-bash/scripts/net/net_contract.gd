# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     net_contract.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name NetContract
extends RefCounted
## The build fingerprint a host compares at admission: peers must be one build, since RPCs travel
## by method index and readers refuse what they don't know.
##
## [method fingerprint] covers the game version, the network format ([method format_parts]: the
## wire enums and patterns, the snapshot formats, every command's wire name, every autoload's RPC
## config) and the content ([method content_digest] of [constant CONTENT_ROOTS]). It is computed,
## never kept by hand: appending a fact kind, adding a command type or an RPC, or editing a data
## file changes it with no edit here. A new wire enum or pattern is added to
## [method format_parts]; a new command base class to [constant COMMAND_BASES].
##
## @tutorial(Net transport plan): docs/plans/2026-11-19-net-transport.md

## The folders whose every file the content digest covers: clients mirror rules with their own
## content, so different content desyncs silently.
const CONTENT_ROOTS: PackedStringArray = ["res://data/", "res://maps/"]

## Classes whose descendants under [constant SCRIPTS_ROOT] travel by their [code]WIRE_TYPE[/code]
## constant: the combat commands and the campaign and event commands.
const COMMAND_BASES: PackedStringArray = ["Command", "CampaignCommand"]

## Only classes in this folder count as command types: test fixtures elsewhere are never sent.
const SCRIPTS_ROOT: String = "res://scripts/"

# An exported build keeps a converted resource as a binary file and leaves this pointer at the
# original path, so the digest follows it to the content.
const _REMAP_SUFFIX: String = ".remap"
const _REMAP_SECTION: String = "remap"
const _REMAP_KEY: String = "path"

# The snapshot format constant CombatSession and CombatEncounter each declare.
const _SNAPSHOT_FORMAT_CONSTANT: String = "_SNAPSHOT_FORMAT"

static var _fingerprint: int = 0
static var _has_fingerprint: bool = false
static var _build_usec: int = 0


## This build's fingerprint, computed on the first call and kept for the process.
## [code]SteamNetwork[/code] calls it at boot, so the content hash never stalls a join.
static func fingerprint() -> int:
	if not _has_fingerprint:
		var started: int = Time.get_ticks_usec()
		_fingerprint = combine(
				SaveFile.get_running_version(), format_parts(), content_digest(CONTENT_ROOTS)
		)
		_build_usec = Time.get_ticks_usec() - started
		_has_fingerprint = true
	return _fingerprint


## How long the first [method fingerprint] took, in microseconds; 0 before it ran.
static func build_usec() -> int:
	return _build_usec


## The fingerprint of [param version], the format [param parts] and the [param content] digest:
## the first 8 bytes of a SHA-256 over their canonical JSON, keys sorted. Pure.
static func combine(version: String, parts: Dictionary, content: String) -> int:
	var text: String = JSON.stringify(
			{"version": version, "format": parts, "content": content}, "", true
	)
	return text.sha256_buffer().decode_s64(0)


## The network format as plain values, each part under its own name: every wire enum (name to
## value), wire pattern and snapshot format, the command wire names ([method command_wire_types])
## and the autoloads' RPC configs ([method rpc_configs]).
static func format_parts() -> Dictionary:
	return {
		"CombatFact.Kind": CombatFact.Kind,
		"CombatFact.Source": CombatFact.Source,
		"CombatFact.CombatSide": CombatFact.CombatSide,
		"CombatFact.DamageType": CombatFact.DamageType,
		"CombatFact.Flag": CombatFact.Flag,
		"CombatFact.WIRE_PATTERN": CombatFact.WIRE_PATTERN,
		"CampaignFact.Kind": CampaignFact.Kind,
		"CampaignFact.WIRE_PATTERN": CampaignFact.WIRE_PATTERN,
		"LobbyAdmission.Refusal": LobbyAdmission.Refusal,
		"SeatDirectory.State": SeatDirectory.State,
		"CombatSession.snapshot_format": _snapshot_format(CombatSession),
		"CombatEncounter.snapshot_format": _snapshot_format(CombatEncounter),
		"commands": command_wire_types(),
		"rpc": rpc_configs(),
	}


## Every command type's wire name, by class name: each global class under
## [constant SCRIPTS_ROOT] descending from a [constant COMMAND_BASES] class that declares a
## [code]WIRE_TYPE[/code] constant.
static func command_wire_types() -> Dictionary[String, String]:
	var bases: Dictionary[String, String] = {}
	var paths: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		bases[entry["class"] as String] = entry["base"] as String
		paths[entry["class"] as String] = entry["path"] as String
	var found: Dictionary[String, String] = {}
	for class_id: String in bases:
		if not paths[class_id].begins_with(SCRIPTS_ROOT) or not _descends(class_id, bases):
			continue
		var script: Script = load(paths[class_id]) as Script
		if script == null:
			push_error("NetContract: a command script can't load - %s" % [paths[class_id]])
			continue
		var constants: Dictionary = script.get_script_constant_map()
		if constants.has("WIRE_TYPE"):
			found[class_id] = str(constants["WIRE_TYPE"])
	found.sort()
	return found


## Every autoload's [method Script.get_rpc_config], by autoload name; an autoload that isn't a
## script with RPCs adds nothing. RPCs are indexed by method name in sorted order, so the config
## is what peers must share.
static func rpc_configs() -> Dictionary[String, Variant]:
	var configs: Dictionary[String, Variant] = {}
	for property: Dictionary in ProjectSettings.get_property_list():
		var key: String = property["name"]
		if not key.begins_with("autoload/"):
			continue
		var path: String = (ProjectSettings.get_setting(key) as String).trim_prefix("*")
		var script: Script = load(path) as Script
		if script == null:
			continue
		var config: Variant = script.get_rpc_config()
		if config is Dictionary and not (config as Dictionary).is_empty():
			configs[key.trim_prefix("autoload/")] = config
	configs.sort()
	return configs


## An MD5 over every file under [param roots]: each file's path inside its root, the root's
## index and the file's MD5, sorted. A [constant _REMAP_SUFFIX] pointer counts as the file it
## points to, under the original name, so an export's content is what it covers.
static func content_digest(roots: PackedStringArray) -> String:
	var lines: PackedStringArray = []
	for i: int in roots.size():
		_digest_folder(roots[i], "", i, lines)
	lines.sort()
	return "\n".join(lines).md5_text()


# Adds one line per file under root/relative, at any depth, to lines.
static func _digest_folder(
		root: String, relative: String, root_index: int, lines: PackedStringArray
) -> void:
	var folder: String = root.path_join(relative)
	if not DirAccess.dir_exists_absolute(folder):
		push_error("NetContract: a content folder is missing - %s" % [folder])
		return
	for file: String in DirAccess.get_files_at(folder):
		var listed: String = relative.path_join(file)
		var path: String = folder.path_join(file)
		if file.ends_with(_REMAP_SUFFIX):
			listed = listed.trim_suffix(_REMAP_SUFFIX)
			path = _remap_target(path)
		lines.append("%d:%s=%s" % [root_index, listed, FileAccess.get_md5(path)])
	for child: String in DirAccess.get_directories_at(folder):
		_digest_folder(root, relative.path_join(child), root_index, lines)


# The file a remap pointer at path names, or path itself when it names none.
static func _remap_target(path: String) -> String:
	var remap: ConfigFile = ConfigFile.new()
	if remap.load(path) != OK:
		push_error("NetContract: a remap can't be read - %s" % [path])
		return path
	var target: String = str(remap.get_value(_REMAP_SECTION, _REMAP_KEY, ""))
	if target.is_empty():
		push_error("NetContract: a remap names no file - %s" % [path])
		return path
	return target


# The private _SNAPSHOT_FORMAT of script, read through its constant map: it guards dumped data,
# still bumps by hand, and has no public accessor. A rename fails here loudly, never silently.
static func _snapshot_format(script: Script) -> int:
	var constants: Dictionary = script.get_script_constant_map()
	if not constants.has(_SNAPSHOT_FORMAT_CONSTANT):
		push_error("NetContract: no snapshot format - %s" % [script.resource_path])
		return -1
	return constants[_SNAPSHOT_FORMAT_CONSTANT] as int


# Whether class_id has a COMMAND_BASES class among its ancestors in bases (class to base class).
static func _descends(class_id: String, bases: Dictionary[String, String]) -> bool:
	var current: String = bases.get(class_id, "")
	while not current.is_empty():
		if COMMAND_BASES.has(current):
			return true
		current = bases.get(current, "")
	return false
