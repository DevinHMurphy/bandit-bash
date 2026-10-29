# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rng_streams.gd
# Author:
# Created:  October 26, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name RngStreams
extends RefCounted
## One run's live random streams, each created on first use of its [RngKey].
##
## Held by the campaign session, which hands each consumer the one [RngStream] it needs; rules code
## never sees the registry. Every stream's seed is re-derived from [member run_seed] and its key,
## so a save holds only each live stream's position; [method drop_node] drops a node's streams
## when the node ends.[br]
## Streams fall into save sections by purpose: [method capture_combat] holds every
## [constant RngKey.COMBAT_ROLLS] stream, [method capture_campaign] every other purpose except
## [constant RngKey.ENCOUNTER_SETUP] and [constant RngKey.MAP_LOOT]. Those two are never saved: a
## battle's setup draws them whole at battle start and their results are battle state (container
## contents included), and a battle restarted from Begin re-derives them from their keys like
## every other battle stream. [RngSaveSection] saves the two sections.
##
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

# Purposes saved in the combat section; the unsaved ones are in no section.
const _COMBAT_PURPOSES: Array[RngKey.RngPurpose] = [
	RngKey.RngPurpose.COMBAT_ROLLS,
]
const _UNSAVED_PURPOSES: Array[RngKey.RngPurpose] = [
	RngKey.RngPurpose.ENCOUNTER_SETUP,
	RngKey.RngPurpose.MAP_LOOT,
]

## The run's seed, fixed at construction. Assigning it is an error: every live stream and every
## saved position depends on it.
var run_seed: int:
	get:
		return _run_seed
	set(_value):
		push_error("RngStreams: run_seed is fixed at construction")

var _run_seed: int = 0

# Live streams and a private copy of each one's key, both by save key.
var _streams: Dictionary[String, RngStream] = {}
var _keys: Dictionary[String, RngKey] = {}


func _init(seed_of_run: int) -> void:
	_run_seed = seed_of_run


## The stream named by [param key], created from its derived seed on first use. An equal key
## returns the same stream, so a shared key (no seat) gives every seat the same stream.
## Returns [code]null[/code] if [param key] is null.
func stream(key: RngKey) -> RngStream:
	if key == null:
		push_error("RngStreams: stream needs a key")
		return null
	var save_key: String = key.to_save_key()
	if _streams.has(save_key):
		return _streams[save_key]
	return _add(RngKey.new(key.purpose, key.floor_number, key.node, key.seat, key.index))


## Drops every stream whose key has exactly this floor and node, whatever its purpose, seat or
## index. A later [method stream] call for one of them starts again from its key.
## Run-level streams are dropped only by [code]drop_node(-1, -1)[/code].
func drop_node(floor_number: int, node: int) -> void:
	for save_key: String in _keys.keys():
		var key: RngKey = _keys[save_key]
		if key.floor_number == floor_number and key.node == node:
			_remove(save_key)


## The campaign section's live streams as [code]{save key: captured state}[/code], all strings.
func capture_campaign() -> Dictionary[String, String]:
	return _capture(false)


## The combat section's live streams as [code]{save key: captured state}[/code], all strings.
func capture_combat() -> Dictionary[String, String]:
	return _capture(true)


## Replaces every campaign-section stream with those in [param data], as written by
## [method capture_campaign]. An empty [param data] clears the section.
## Returns false, changing nothing, if any entry is malformed or belongs to another section.
func restore_campaign(data: Dictionary) -> bool:
	return _restore(data, false)


## Replaces every combat-section stream with those in [param data], as written by
## [method capture_combat]. An empty [param data] clears the section.
## Returns false, changing nothing, if any entry is malformed or belongs to another section.
func restore_combat(data: Dictionary) -> bool:
	return _restore(data, true)


# Registers a stream for a key the registry owns (never a caller's object, which could change).
func _add(key: RngKey) -> RngStream:
	var save_key: String = key.to_save_key()
	var created: RngStream = RngStream.new(RngKey.derive_seed(
			_run_seed, key.purpose, key.floor_number, key.node, key.seat, key.index
	))
	_streams[save_key] = created
	_keys[save_key] = key
	return created


func _remove(save_key: String) -> void:
	_streams.erase(save_key)
	_keys.erase(save_key)


func _capture(is_combat: bool) -> Dictionary[String, String]:
	var data: Dictionary[String, String] = {}
	for save_key: String in _keys:
		if _is_saved_in(_keys[save_key].purpose, is_combat):
			data[save_key] = _streams[save_key].capture()
	return data


# Validates every entry before touching the registry, so a bad section never leaves half of it
# restored and half rerolled.
func _restore(data: Dictionary, is_combat: bool) -> bool:
	var section: String = "combat" if is_combat else "campaign"
	var restored: Dictionary[String, RngStream] = {}
	var keys: Dictionary[String, RngKey] = {}
	for entry: Variant in data:
		var entry_text: String = entry if entry is String else ""
		var key: RngKey = RngKey.from_save_key(entry_text)
		if key == null or not _is_saved_in(key.purpose, is_combat):
			push_error("RngStreams: not a %s stream key - %s" % [section, entry])
			return false
		var state: Variant = data[entry]
		if not state is String:
			push_error("RngStreams: %s stream state for %s isn't a string - %s"
					% [section, entry_text, state])
			return false
		# The seed doesn't matter: a restored state fixes the whole sequence.
		var restored_stream: RngStream = RngStream.new(0)
		var state_text: String = state
		if not restored_stream.restore(state_text):
			return false
		restored[key.to_save_key()] = restored_stream
		keys[key.to_save_key()] = key

	for save_key: String in _keys.keys():
		if _is_saved_in(_keys[save_key].purpose, is_combat):
			_remove(save_key)
	_streams.merge(restored)
	_keys.merge(keys)
	return true


# Whether streams of this purpose are saved in the combat section (is_combat) or the campaign one.
static func _is_saved_in(purpose: RngKey.RngPurpose, is_combat: bool) -> bool:
	if _UNSAVED_PURPOSES.has(purpose):
		return false
	return _COMBAT_PURPOSES.has(purpose) == is_combat
