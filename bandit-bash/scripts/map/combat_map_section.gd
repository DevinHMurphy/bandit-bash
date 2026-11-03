# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_map_section.gd
# Author:
# Created:  November 3, 2026
# Modified: November 3, 2026
# ==============================================================================

class_name CombatMapSection
extends SaveSection
## The battle's maps in the combat block: the [code]combat_map[/code] section, with its partner
## [member entities], the [code]entities[/code] section, both at version 1.
##
## [code]CampaignService[/code] registers this section, then [member entities], after
## [CombatStateSection]'s pair, and attaches both to the run's [CampaignSession]. Each capture
## reads the battle's [method CombatEncounter.snapshot] and keeps its part of each map's
## [code]map[/code] ([method MapState.capture]): [code]combat_map[/code] holds the reinforcement
## points (waves, waves sent, closed, waiting units), the flags and the leader marks, with the map
## id and the active object spots to check a rebuilt battle against; [code]entities[/code] holds
## every map object by stable id with its state, the containers' contents and the loot found and
## carried. A breakable's HP is its unit's, saved in [code]combat_state[/code].[br]
## [b]Load order:[/b] each section's [method restore] only checks its own data and holds it, in
## either order: [code]entities[/code] takes over a slot SaveService reserved, which restores
## before [code]combat_map[/code]. They pair up in [method is_holding] and [method load_into]. On a
## [code]BATTLE[/code] resume, with the battle rebuilt as Begin set it up and both this and
## [CombatStateSection] holding: [method load_into] first, then
## [method CombatStateSection.load_into], whose reload carries these maps and checks each breakable
## against its unit. On any error, drop the battle and restart it from Begin.[br]
## [b]Resets:[/b] a reset (Begin, battle end, [code]BATTLE_RETRY[/code]) drops held data only.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

# Never change it: it is how saved data finds this section (save-system.md).
const _KEY: String = "combat_map"
const _VERSION: int = 1

## The [code]entities[/code] section: register it in the same block.
var entities: EntitiesSection = null

# The run whose battle capture() reads; null until attach() and after detach().
var _session: CampaignSession = null

# Data restore() checked, waiting for load_into(); only meaningful while _is_holding.
var _held: Dictionary = {}
var _is_holding: bool = false


func _init() -> void:
	entities = EntitiesSection.new()


func get_key() -> String:
	return _KEY


func get_version() -> int:
	return _VERSION


# ASSUMPTION: turns survived, whether the Defend tile held and whether COMBAT_ENDED was recorded
# aren't saved here: combat_state's turn, phase and finished flag already decide them, and a
# second copy could only disagree.
## The attached run's battle: [code]{"sessions": [...]}[/code], each map's [code]combat_map[/code]
## part by session id, with its [code]map_id[/code] and active [code]object_spots[/code]. With no
## battle, the held data, else empty (no battle to save).
func capture() -> Dictionary:
	var battle: CombatEncounter = null if _session == null else _session.encounter
	if battle == null:
		return _held.duplicate(true) if _is_holding else {}
	var taken: Dictionary = battle.snapshot()
	var sessions: Array = []
	var maps: Array = taken["sessions"]
	for index: int in maps.size():
		var map_part: Dictionary = (maps[index] as Dictionary)["map"]
		var part: Dictionary = (map_part["combat_map"] as Dictionary).duplicate(true)
		part["map_id"] = battle.get_session(index).layout.map_id
		part["object_spots"] = Array(_spots_of(map_part["entities"] as Dictionary))
		sessions.append(part)
	return {"sessions": sessions}


## Checks [param data] and holds it for [method load_into]: every map's part is restored on a
## scratch map. Empty data (written with no battle) holds nothing. Returns
## [constant ERR_INVALID_DATA], holding nothing, when it is malformed.
func restore(data: Dictionary) -> Error:
	reset()
	if data.is_empty():
		return OK
	var sessions: Variant = data.get("sessions", null)
	if not sessions is Array:
		return _refuse("its maps are missing")
	# Untyped: the parts come from JSON and are checked entry by entry.
	for entry: Variant in sessions:
		var part: Dictionary = entry if entry is Dictionary else {}
		var map_id: Variant = part.get("map_id", null)
		if (
				not map_id is String
				or (map_id as String).is_empty()
				or _spot_list(part.get("object_spots", null)).has(-1)
		):
			return _refuse("a map's id or object spots are malformed")
		var scratch: MapState = MapState.new()
		var whole: Dictionary = scratch.capture()
		whole["combat_map"] = part
		if scratch.restore(whole) != OK:
			return _refuse("a map's points or flags are malformed")
	_held = data.duplicate(true)
	_is_holding = true
	return OK


## Drops the held data; the attached run stays attached.
func reset() -> void:
	_held = {}
	_is_holding = false


## Reads [param session]'s battle in [method capture] from now on, and has [member entities] do the
## same. Held data stays held until [method load_into]. Returns [constant OK], or
## [constant ERR_INVALID_PARAMETER] for null.
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("CombatMapSection: attach needs a session")
		return ERR_INVALID_PARAMETER
	_session = session
	entities.attach(session)
	return OK


## Stops reading the attached run, as does [member entities]: it was closed or replaced.
func detach() -> void:
	_session = null
	entities.detach()


## Whether both sections hold the same saved battle's maps, as many of each, so a resumed battle
## can [method load_into] them. False when either is missing (a file from before them).
func is_holding() -> bool:
	if not _is_holding or not entities.is_holding():
		return false
	return (_held["sessions"] as Array).size() == entities.held_sessions().size()


## Replaces each map's [member CombatState.map] in [param battle], rebuilt the way it was set up
## (same node, seats and setup, sessions open, nothing loaded yet), with the held one, and drops
## the held data. Call it before [method CombatStateSection.load_into]. Returns [constant OK];
## [constant ERR_UNCONFIGURED] when [method is_holding] is false (a file from before these
## sections, or with one of them only: restart the battle from Begin);
## [constant ERR_INVALID_PARAMETER] for null; [constant ERR_INVALID_DATA], changing nothing, for
## another number of maps, another map or other object spots.
func load_into(battle: CombatEncounter) -> Error:
	if battle == null:
		return ERR_INVALID_PARAMETER
	if not is_holding():
		return ERR_UNCONFIGURED
	var held_maps: Array = _held["sessions"]
	var held_entities: Array = entities.held_sessions()
	var sessions: Array[CombatSession] = battle.get_sessions()
	if held_maps.size() != sessions.size() or held_entities.size() != sessions.size():
		return _refuse("it holds %d maps and the battle has %d" % [
			held_maps.size(), sessions.size(),
		])
	for index: int in sessions.size():
		var held: Dictionary = held_maps[index]
		var spots: PackedInt32Array = _spot_list(held["object_spots"])
		var rebuilt: Dictionary = sessions[index].state.map.capture()["entities"]
		if held["map_id"] != sessions[index].layout.map_id:
			return _refuse("map %d is %s, not %s" % [
				index, held["map_id"], sessions[index].layout.map_id,
			])
		if (
				spots != _spots_of(held_entities[index] as Dictionary)
				or spots != _spots_of(rebuilt)
		):
			return _refuse("map %d's object spots differ from the battle's" % [index])
	for index: int in sessions.size():
		# Checked by restore() on both sections, so it can't fail here.
		sessions[index].state.map.restore({
			"entities": held_entities[index],
			"combat_map": held_maps[index],
		})
	reset()
	entities.reset()
	return OK


# The spot indexes of the objects in an entities part, ascending.
static func _spots_of(entities_part: Dictionary) -> PackedInt32Array:
	var spots: PackedInt32Array = []
	# Untyped: the parts come from JSON; restore() checked them.
	for entry: Variant in entities_part.get("objects", []):
		var index: float = (entry as Dictionary)["index"]
		spots.append(roundi(index))
	spots.sort()
	return spots


# The whole numbers in value, ascending; a list holding -1 when it isn't a list of them.
static func _spot_list(value: Variant) -> PackedInt32Array:
	if not value is Array:
		return PackedInt32Array([-1])
	var spots: PackedInt32Array = []
	for entry: Variant in value:
		if not (entry is int or entry is float):
			return PackedInt32Array([-1])
		var number: float = entry
		if number != floorf(number) or number < 0.0:
			return PackedInt32Array([-1])
		spots.append(roundi(number))
	spots.sort()
	return spots


static func _refuse(reason: String) -> Error:
	push_error("CombatMapSection: the combat_map section can't be restored - %s" % [reason])
	return ERR_INVALID_DATA


# NOTE: Never name the outer class in here. The outer script holds this one, so a reference back
# makes a script cycle, which 4.7.1 leaks at exit (godotengine/godot#117975; see
# combat_state_section.gd).
## The [code]entities[/code] section: [code]{"sessions": [...]}[/code], each map's
## [code]entities[/code] part ([method MapState.capture]) by session id. Its partner
## [CombatMapSection] pairs it up and loads it.
class EntitiesSection:
	extends SaveSection

	# Never change it: it is how saved data finds this section (save-system.md).
	const _KEY: String = "entities"
	const _VERSION: int = 1

	var _session: CampaignSession = null
	var _held: Dictionary = {}
	var _is_holding: bool = false

	func get_key() -> String:
		return _KEY

	func get_version() -> int:
		return _VERSION

	## The attached run's battle's map objects; with no battle, the held data, else empty.
	func capture() -> Dictionary:
		var battle: CombatEncounter = null if _session == null else _session.encounter
		if battle == null:
			return _held.duplicate(true) if _is_holding else {}
		var taken: Dictionary = battle.snapshot()
		var sessions: Array = []
		for entry: Variant in taken["sessions"]:
			var map_part: Dictionary = (entry as Dictionary)["map"]
			sessions.append(map_part["entities"])
		return {"sessions": sessions}

	## Checks [param data] and holds it: every map's part is restored on a scratch map. Empty data
	## holds nothing. Returns [constant ERR_INVALID_DATA], holding nothing, when it is malformed.
	func restore(data: Dictionary) -> Error:
		reset()
		if data.is_empty():
			return OK
		var sessions: Variant = data.get("sessions", null)
		if not sessions is Array:
			return _refuse("its maps are missing")
		# Untyped: the parts come from JSON and are checked entry by entry.
		for entry: Variant in sessions:
			var scratch: MapState = MapState.new()
			var whole: Dictionary = scratch.capture()
			whole["entities"] = entry
			if not entry is Dictionary or scratch.restore(whole) != OK:
				return _refuse("a map's objects are malformed")
		_held = data.duplicate(true)
		_is_holding = true
		return OK

	## Drops the held data.
	func reset() -> void:
		_held = {}
		_is_holding = false

	## Reads [param session]'s battle in [method capture]; [method CombatMapSection.attach] calls
	## it.
	func attach(session: CampaignSession) -> void:
		_session = session

	## Stops reading the attached run.
	func detach() -> void:
		_session = null

	## Whether it holds a saved battle's map objects.
	func is_holding() -> bool:
		return _is_holding

	## The held entities part of each map, by session id; empty when none is held.
	func held_sessions() -> Array:
		return (_held.get("sessions", []) as Array).duplicate(true)

	static func _refuse(reason: String) -> Error:
		push_error("CombatMapSection: the entities section can't be restored - %s" % [reason])
		return ERR_INVALID_DATA
