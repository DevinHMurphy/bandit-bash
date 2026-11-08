# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_save_section.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name DarknessSaveSection
extends SaveSection
## The darkness of each map in the combat block: the [code]darkness[/code] section, version 1
## (darkness plan question 6).
##
## [code]CampaignService[/code] registers it after the [CombatMapSection] pair and attaches it to
## the run's [CampaignSession]. Each capture reads the battle's [method CombatEncounter.snapshot]
## and keeps each map's [code]darkness[/code] part ([method DarknessState.capture]) but its
## [code]first_release[/code]: the active sources, the drain, each wave's source index, reach and
## tiles entered, each tile's layer, each breakable's contact count, and whether the darkness has
## arrived. Heights and flow costs are derived, never saved. The sources, drain and first release
## are setup results the rebuilt battle places again ([method DarknessSetup.place]); the saved
## sources and drain are checked against it, as [CombatMapSection] checks its object spots, and
## the arrival against the map's [member MapState.has_darkness_arrived].[br]
## [b]Load order:[/b] [method restore] only checks the data and holds it. On a [code]BATTLE[/code]
## resume, with the battle rebuilt as Begin set it up: [method CombatMapSection.load_into], then
## [method load_into], then [method CombatStateSection.load_into], whose reload carries each map's
## darkness with it. On any error, drop the battle and restart it from Begin.[br]
## [b]Resets:[/b] a reset (Begin, battle end, [code]BATTLE_RETRY[/code]) drops held data only.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(The darkness plan): docs/plans/2026-11-03-the-darkness.md

# Never change it: it is how saved data finds this section (save-system.md).
const _KEY: String = "darkness"
const _VERSION: int = 1

# The key of DarknessState.capture() this section leaves out: the rebuild places it.
const _FIRST_RELEASE_KEY: String = "first_release"

# The run whose battle capture() reads; null until attach() and after detach().
var _session: CampaignSession = null

# Data restore() checked, waiting for load_into(); only meaningful while _is_holding.
var _held: Dictionary = {}
var _is_holding: bool = false


func get_key() -> String:
	return _KEY


func get_version() -> int:
	return _VERSION


## The attached run's battle: [code]{"sessions": [...]}[/code], each map's darkness by session id,
## without its first release. With no battle, the held data, else empty (no battle to save).
func capture() -> Dictionary:
	var battle: CombatEncounter = null if _session == null else _session.encounter
	if battle == null:
		return _held.duplicate(true) if _is_holding else {}
	var taken: Dictionary = battle.snapshot()
	var sessions: Array = []
	for entry: Variant in taken["sessions"]:
		var map_part: Dictionary = (entry as Dictionary)["map"]
		var part: Dictionary = (map_part["darkness"] as Dictionary).duplicate(true)
		part.erase(_FIRST_RELEASE_KEY)
		sessions.append(part)
	return {"sessions": sessions}


## Checks [param data] and holds it for [method load_into]: every map's part is restored on a
## scratch [DarknessState]. Empty data (written with no battle) holds nothing. Returns
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
		if not entry is Dictionary or (entry as Dictionary).has(_FIRST_RELEASE_KEY):
			return _refuse("a map's darkness is malformed")
		var whole: Dictionary = (entry as Dictionary).duplicate(true)
		whole[_FIRST_RELEASE_KEY] = DarknessState.NO_RELEASE
		if DarknessState.new().restore(whole) != OK:
			return _refuse("a map's darkness is malformed")
	_held = data.duplicate(true)
	_is_holding = true
	return OK


## Drops the held data; the attached run stays attached.
func reset() -> void:
	_held = {}
	_is_holding = false


## Reads [param session]'s battle in [method capture] from now on. Held data stays held until
## [method load_into]. Returns [constant OK], or [constant ERR_INVALID_PARAMETER] for null.
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("DarknessSaveSection: attach needs a session")
		return ERR_INVALID_PARAMETER
	_session = session
	return OK


## Stops reading the attached run: it was closed or replaced.
func detach() -> void:
	_session = null


## Whether it holds a saved battle's darkness, so a resumed battle can [method load_into] it. False
## for a file from before this section.
func is_holding() -> bool:
	return _is_holding


## Replaces each map's [member MapState.darkness] in [param battle], rebuilt the way it was set up
## and its maps loaded ([method CombatMapSection.load_into]), with the held one, keeping the
## rebuilt first release, and drops the held data. Call it before
## [method CombatStateSection.load_into]. Returns [constant OK]; [constant ERR_UNCONFIGURED] when
## nothing is held (restart the battle from Begin); [constant ERR_INVALID_PARAMETER] for null;
## [constant ERR_INVALID_DATA], changing nothing, for another number of maps, other sources or
## drain, an arrival the map disagrees with, or a contact with an object the map doesn't have.
func load_into(battle: CombatEncounter) -> Error:
	if battle == null:
		return ERR_INVALID_PARAMETER
	if not is_holding():
		return ERR_UNCONFIGURED
	var held_maps: Array = _held["sessions"]
	var sessions: Array[CombatSession] = battle.get_sessions()
	if held_maps.size() != sessions.size():
		return _refuse("it holds %d maps and the battle has %d" % [
			held_maps.size(), sessions.size(),
		])
	var restored: Array[DarknessState] = []
	for index: int in sessions.size():
		var map: MapState = sessions[index].state.map
		var held: Dictionary = held_maps[index]
		var rebuilt: Dictionary = map.darkness.capture()
		if (
				JSON.stringify(held["sources"]) != JSON.stringify(rebuilt["sources"])
				or held["drain"] != rebuilt["drain"]
		):
			return _refuse("map %d's sources or drain differ from the battle's" % [index])
		if held["arrived"] != map.has_darkness_arrived:
			return _refuse("map %d's arrival disagrees with its combat_map" % [index])
		for object_id: Variant in held["contacts"]:
			if map.object(object_id as String) == null:
				return _refuse("map %d has no object %s in contact" % [index, object_id])
		var whole: Dictionary = held.duplicate(true)
		whole[_FIRST_RELEASE_KEY] = map.darkness.first_release
		var darkness: DarknessState = DarknessState.new()
		# Checked by restore(), so it can't fail here.
		darkness.restore(whole)
		restored.append(darkness)
	for index: int in sessions.size():
		sessions[index].state.map.darkness = restored[index]
	reset()
	return OK


static func _refuse(reason: String) -> Error:
	push_error("DarknessSaveSection: the darkness section can't be restored - %s" % [reason])
	return ERR_INVALID_DATA
