# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_section_registry.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name SaveSectionRegistry
extends RefCounted
## Routes the sections of a save file to the [SaveSection]s and [PlayerSaveSection]s that own
## them.
##
## [code]SaveService[/code] owns one instance and calls it whenever a block loads or saves; it
## lives outside the autoload so the headless tests can drive it.[br]
## [b]Rules:[/b] sections nobody registered are kept and written back unchanged, so removing a
## feature never destroys its data (a new run starts without them). A registered section missing
## from the file is reset. Loading is two-phase: every section is checked and migrated before any
## is restored, so a bad section stops the load before any system holds half-loaded state. A
## section version newer than the registered one is refused, like a newer file.
##
## @tutorial(Save system design): docs/design/save-system.md

## Key of the version number in a section entry.
const KEY_VERSION: String = "version"
## Key of the data in a section entry.
const KEY_DATA: String = "data"

# Block -> (section key -> SaveSection). The inner Dictionary can't be typed: typed collections
# don't nest.
var _by_block: Dictionary[SaveSection.Block, Dictionary] = {}
var _player_sections: Dictionary[String, PlayerSaveSection] = {}


func _init() -> void:
	for block: SaveSection.Block in SaveSection.Block.values():
		_by_block[block] = {}


## Registers [param section] in [param block], replacing any section with the same key.
##
## Replacing a [RawSaveSection] is the normal way a new system takes over its reserved key;
## replacing anything else logs a warning.
func register(block: SaveSection.Block, section: SaveSection) -> void:
	var key: String = section.get_key()
	if key.is_empty():
		push_error("SaveSectionRegistry: refusing a section with an empty key.")
		return
	var bucket: Dictionary = _by_block[block]
	if bucket.has(key) and not bucket[key] is RawSaveSection:
		push_warning("SaveSectionRegistry: replacing section '%s'." % [key])
	bucket[key] = section


## Registers [param section] for every player, replacing any with the same key.
func register_player(section: PlayerSaveSection) -> void:
	var key: String = section.get_key()
	if key.is_empty():
		push_error("SaveSectionRegistry: refusing a player section with an empty key.")
		return
	if _player_sections.has(key):
		push_warning("SaveSectionRegistry: replacing player section '%s'." % [key])
	_player_sections[key] = section


## True when a section with [param key] is registered in [param block].
func has_section(block: SaveSection.Block, key: String) -> bool:
	var bucket: Dictionary = _by_block[block]
	return bucket.has(key)


## Hands each registered section of [param block] its data from [param sections] (the block's
## raw section entries), resetting the ones the file doesn't have.
##
## Returns [constant OK]; [constant ERR_INVALID_DATA] for a malformed entry;
## [constant ERR_FILE_UNRECOGNIZED] for a newer section version; or a migrate or restore error.
## Nothing is restored unless every entry checks and migrates.
func restore(block: SaveSection.Block, sections: Dictionary) -> Error:
	var bucket: Dictionary = _by_block[block]
	var prepared: Dictionary = {}
	for key: String in bucket:
		if not sections.has(key):
			continue
		var section: SaveSection = bucket[key]
		var data: Dictionary = {}
		var err: Error = _prepare(key, sections[key], section.get_version(), section.migrate, data)
		if err != OK:
			return err
		prepared[key] = data

	for key: String in bucket:
		var section: SaveSection = bucket[key]
		if not prepared.has(key):
			section.reset()
			continue
		var restore_err: Error = section.restore(prepared[key])
		if restore_err != OK:
			push_error("SaveSectionRegistry: '%s' refused its data." % [key])
			return restore_err
	return OK


## Returns [param sections] with every registered section of [param block] replaced by its
## current data. Unregistered entries are copied through unchanged.
func capture(block: SaveSection.Block, sections: Dictionary) -> Dictionary:
	var result: Dictionary = sections.duplicate(true)
	var bucket: Dictionary = _by_block[block]
	for key: String in bucket:
		var section: SaveSection = bucket[key]
		result[key] = _make_entry(section.get_version(), section.capture())
	return result


## Resets every registered section of [param block].
func reset(block: SaveSection.Block) -> void:
	var bucket: Dictionary = _by_block[block]
	for key: String in bucket:
		var section: SaveSection = bucket[key]
		section.reset()


## Hands every player section the data of each player in [param players].
##
## Clears every player section first, then restores or resets each seat. Same return values and
## two-phase rule as [method restore].
func restore_players(players: Array[CampaignData.PlayerRun]) -> Error:
	var prepared: Dictionary = {}
	for player: CampaignData.PlayerRun in players:
		for key: String in _player_sections:
			if not player.sections.has(key):
				continue
			var section: PlayerSaveSection = _player_sections[key]
			var data: Dictionary = {}
			var label: String = "%s (seat %d)" % [key, player.seat]
			var entry: Variant = player.sections[key]
			var err: Error = _prepare(label, entry, section.get_version(), section.migrate, data)
			if err != OK:
				return err
			prepared[_player_key(player.seat, key)] = data

	clear_players()
	for player: CampaignData.PlayerRun in players:
		for key: String in _player_sections:
			var section: PlayerSaveSection = _player_sections[key]
			var prepared_key: String = _player_key(player.seat, key)
			if not prepared.has(prepared_key):
				section.reset(player.seat)
				continue
			var restore_err: Error = section.restore(player.seat, prepared[prepared_key])
			if restore_err != OK:
				push_error("SaveSectionRegistry: '%s' refused seat %d." % [key, player.seat])
				return restore_err
	return OK


## Writes every player section's current data into each player's [code]sections[/code].
## Unregistered entries are kept.
func capture_players(players: Array[CampaignData.PlayerRun]) -> void:
	for player: CampaignData.PlayerRun in players:
		var result: Dictionary = player.sections.duplicate(true)
		for key: String in _player_sections:
			var section: PlayerSaveSection = _player_sections[key]
			result[key] = _make_entry(section.get_version(), section.capture(player.seat))
		player.sections = result


## Starts a new run for [param players]: clears every player section, then resets each seat.
func reset_players(players: Array[CampaignData.PlayerRun]) -> void:
	clear_players()
	for player: CampaignData.PlayerRun in players:
		for key: String in _player_sections:
			var section: PlayerSaveSection = _player_sections[key]
			section.reset(player.seat)


## Makes every player section forget every seat.
func clear_players() -> void:
	for key: String in _player_sections:
		var section: PlayerSaveSection = _player_sections[key]
		section.clear()


func _make_entry(version: int, data: Dictionary) -> Dictionary:
	return {KEY_VERSION: version, KEY_DATA: data}


# Checks one raw section entry and fills out_data with a migrated copy of its data.
static func _prepare(
		label: String,
		entry: Variant,
		current_version: int,
		migrate: Callable,
		out_data: Dictionary
) -> Error:
	if typeof(entry) != TYPE_DICTIONARY:
		push_error("SaveSectionRegistry: section '%s' is not an entry." % [label])
		return ERR_INVALID_DATA
	var section_entry: Dictionary = entry
	var version_type: int = typeof(section_entry.get(KEY_VERSION))
	var has_number: bool = version_type == TYPE_INT or version_type == TYPE_FLOAT
	if not has_number or typeof(section_entry.get(KEY_DATA)) != TYPE_DICTIONARY:
		push_error("SaveSectionRegistry: section '%s' is malformed." % [label])
		return ERR_INVALID_DATA

	var version: int = int(section_entry[KEY_VERSION])
	if version < 1:
		push_error("SaveSectionRegistry: section '%s' has version %d." % [label, version])
		return ERR_INVALID_DATA
	if version > current_version:
		push_error(
				"SaveSectionRegistry: section '%s' version %d is newer than this build's %d."
				% [label, version, current_version]
		)
		return ERR_FILE_UNRECOGNIZED

	var data: Dictionary = section_entry[KEY_DATA]
	out_data.merge(data.duplicate(true), true)
	if version == current_version:
		return OK
	var migrate_err: Error = migrate.call(out_data, version)
	if migrate_err != OK:
		push_error("SaveSectionRegistry: migrating section '%s' failed." % [label])
	return migrate_err


static func _player_key(seat: int, key: String) -> String:
	return "%d/%s" % [seat, key]
