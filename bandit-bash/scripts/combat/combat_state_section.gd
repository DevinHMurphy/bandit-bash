# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_state_section.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name CombatStateSection
extends SaveSection
## The battle in progress in the combat block: the [code]combat_state[/code] section, with its
## partner [member effects], the [code]effects[/code] section, both at version 1.
##
## [code]CampaignService[/code] registers this section, then [member effects], and attaches both
## to the run's [CampaignSession]. Each capture reads the battle's [method CombatEncounter.snapshot]
## and keeps its own part, so saving and rejoining can't drift apart (event bus plan, Rejoin and
## resume): [code]combat_state[/code] holds the encounter's own part (seqs, arrivals, units on
## their way) and each map's session part and [method CombatState.capture]; [code]effects[/code]
## holds each map's [method EffectEngine.capture] and the cross-map instances. The roll streams
## are the combat [code]rng[/code] section's. Capturing also keeps the combat block's core turn and
## phase equal to the battle's ([method _init]).[br]
## [b]Load order:[/b] [code]SaveService[/code] restores sections before any battle exists, so
## [method restore] only checks the data and holds it, and [member effects] restores after this
## section, refusing data without it. [method load_into] then loads both into a battle rebuilt the
## way this one was set up, units and turn before effects.[br]
## [b]Resets:[/b] a reset (Begin, battle end, [code]BATTLE_RETRY[/code]) drops held data only.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

# Never change it: it is how saved data finds this section (save-system.md).
const _KEY: String = "combat_state"
const _VERSION: int = 1

## The [code]effects[/code] section: register it after this one, in the same block.
var effects: EffectsSection = null

## Finds each saved effect definition, as [method EffectInstance.from_capture] calls it.
## [b]Invalid (the default):[/b] the content catalog. Tests set their own lookup.
var resolve: Callable = Callable():
	set(value):
		resolve = value
		effects.resolve = value

# Returns the combat block's CombatData, or null outside a battle.
var _core: Callable = Callable()

# The run whose battle capture() reads; null until attach() and after detach().
var _session: CampaignSession = null

# Data restore() checked, waiting for load_into(); only meaningful while _is_holding.
var _held: Dictionary = {}
var _is_holding: bool = false


## [param core]: [code]core() -> CombatData[/code], the combat block's data (null outside a
## battle), whose turn and phase each capture sets to the battle's. [b]Invalid:[/b] nothing is
## kept equal.
func _init(core: Callable = Callable()) -> void:
	_core = core
	effects = EffectsSection.new(self)


func get_key() -> String:
	return _KEY


func get_version() -> int:
	return _VERSION


## The attached run's battle: [code]{"encounter": ..., "sessions": [...]}[/code], each map by
## session id with its [code]session[/code] and [code]combat_state[/code] parts. With no battle,
## the held data, else empty (no battle to save).
func capture() -> Dictionary:
	var battle: CombatEncounter = null if _session == null else _session.encounter
	if battle == null:
		return _held.duplicate(true) if _is_holding else {}
	var taken: Dictionary = battle.snapshot()
	_keep_core_equal(battle)
	var encounter_part: Dictionary = (taken["encounter"] as Dictionary).duplicate()
	encounter_part.erase("cross_map")
	var sessions: Array = []
	for entry: Variant in taken["sessions"]:
		var map: Dictionary = entry
		sessions.append({"session": map["session"], "combat_state": map["combat_state"]})
	return {"encounter": encounter_part, "sessions": sessions}


## Checks [param data] and holds it for [method load_into]: every map's units and turn are
## restored on a scratch state. Empty data (written with no battle) holds nothing. Returns
## [constant ERR_INVALID_DATA], holding nothing, when it is malformed.
func restore(data: Dictionary) -> Error:
	reset()
	if data.is_empty():
		return OK
	var encounter_part: Variant = data.get("encounter", null)
	var sessions: Variant = data.get("sessions", null)
	if not encounter_part is Dictionary or not sessions is Array:
		return _refuse("its parts are missing")
	# Untyped: the parts come from JSON and are checked entry by entry.
	for entry: Variant in sessions:
		var map: Dictionary = entry if entry is Dictionary else {}
		var units: Variant = map.get("combat_state", null)
		if (
				not map.get("session", null) is Dictionary
				or not units is Dictionary
				or CombatState.new().restore(units as Dictionary) != OK
		):
			return _refuse("a map's state is malformed")
	_held = data.duplicate(true)
	_is_holding = true
	return OK


## Drops the held data; the attached run stays attached.
func reset() -> void:
	_held = {}
	_is_holding = false


## Reads [param session]'s battle in [method capture] from now on, and has [member effects] do the
## same. Held data stays held until [method load_into]. Returns [constant OK], or
## [constant ERR_INVALID_PARAMETER] for null.
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("CombatStateSection: attach needs a session")
		return ERR_INVALID_PARAMETER
	_session = session
	effects.attach(session)
	return OK


## Stops reading the attached run, as does [member effects]: it was closed or replaced.
func detach() -> void:
	_session = null
	effects.detach()


## Whether both sections hold a saved battle, so a resumed battle can [method load_into] it.
func is_holding() -> bool:
	return _is_holding and effects.is_holding()


## How many maps the held battle has; [code]-1[/code] when none is held.
func held_map_count() -> int:
	return (_held["sessions"] as Array).size() if _is_holding else -1


## Loads the held battle into [param battle], rebuilt the way it was set up (same node, seats and
## setup, sessions open): the held parts replace those of the rebuilt battle's own
## [method CombatEncounter.snapshot], which [method CombatEncounter.load_snapshot] then loads, and
## the held data is dropped. Each map's roll stream stays as the [code]rng[/code] section
## restored it, so nothing may draw from one before this. Returns [constant OK];
## [constant ERR_UNCONFIGURED] when no battle is held (a file from before these sections: restart
## the battle from Begin); [constant ERR_INVALID_PARAMETER] for null; or the load's error,
## [constant ERR_INVALID_DATA] for a battle with another number of maps.
func load_into(battle: CombatEncounter) -> Error:
	if battle == null:
		return ERR_INVALID_PARAMETER
	if not is_holding():
		return ERR_UNCONFIGURED
	var held_maps: Array = _held["sessions"]
	var held_effects: Array = effects.held_sessions()
	var rebuilt: Dictionary = battle.snapshot()
	var maps: Array = rebuilt["sessions"]
	if held_maps.size() != maps.size() or held_effects.size() != maps.size():
		return _refuse("it holds %d maps and the battle has %d" % [held_maps.size(), maps.size()])
	var encounter_part: Dictionary = (_held["encounter"] as Dictionary).duplicate(true)
	encounter_part["cross_map"] = effects.held_cross_map()
	rebuilt["encounter"] = encounter_part
	for index: int in maps.size():
		var map: Dictionary = maps[index]
		var held: Dictionary = held_maps[index]
		map["session"] = held["session"]
		map["combat_state"] = held["combat_state"]
		map["effects"] = held_effects[index]
		map["rolls"] = ""
	var err: Error = battle.load_snapshot(rebuilt, resolve)
	if err != OK:
		return err
	reset()
	effects.reset()
	return OK


# ASSUMPTION: with several maps, the core follows the lowest seat's map (session 0) until P11
# decides what the core means for parallel maps (combat core plan, Save Impact).
# The core's turn starts at 1 and its phase has no "none", so the opening swap window, before turn
# 1's Phase Start, is saved as turn 1's player phase.
func _keep_core_equal(battle: CombatEncounter) -> void:
	if not _core.is_valid():
		return
	var combat: CombatData = _core.call()
	var first: CombatSession = battle.get_session(0)
	if combat == null or first == null:
		return
	combat.turn = maxi(1, first.state.turn)
	combat.phase = (
			CombatData.Phase.ENEMY if first.state.phase_side == CombatFact.CombatSide.ENEMY
			else CombatData.Phase.PLAYER
	)


static func _refuse(reason: String) -> Error:
	push_error("CombatStateSection: the combat_state section can't be restored - %s" % [reason])
	return ERR_INVALID_DATA


## The [code]effects[/code] section: [code]{"encounter": {"cross_map": [...]}, "sessions":
## [...]}[/code], each map's [method EffectEngine.capture] by session id, and the encounter's
## cross-map instances. It restores after [CombatStateSection], whose partner it is.
class EffectsSection:
	extends SaveSection

	# Never change it: it is how saved data finds this section (save-system.md).
	const _KEY: String = "effects"
	const _VERSION: int = 1

	## Finds each saved effect definition; set through [member CombatStateSection.resolve].
	var resolve: Callable = Callable()

	# Weak, since its partner holds it: a strong pair would never be freed.
	var _partner: WeakRef = null
	var _session: CampaignSession = null
	var _held: Dictionary = {}
	var _is_holding: bool = false

	func _init(partner: CombatStateSection) -> void:
		_partner = weakref(partner)

	func get_key() -> String:
		return _KEY

	func get_version() -> int:
		return _VERSION

	## The attached run's battle's effects; with no battle, the held data, else empty.
	func capture() -> Dictionary:
		var battle: CombatEncounter = null if _session == null else _session.encounter
		if battle == null:
			return _held.duplicate(true) if _is_holding else {}
		var taken: Dictionary = battle.snapshot()
		var sessions: Array = []
		for entry: Variant in taken["sessions"]:
			var map: Dictionary = entry
			sessions.append(map["effects"])
		var cross_map: Array = (taken["encounter"] as Dictionary)["cross_map"]
		return {"encounter": {"cross_map": cross_map}, "sessions": sessions}

	## Checks [param data] and holds it: every map's engine state is restored on a scratch engine
	## and every cross-map instance rebuilt, so every definition is found. Effects need the
	## battle's units, so it refuses data when its partner holds no battle, or one with another
	## number of maps. Empty data holds nothing. Returns [constant ERR_INVALID_DATA], holding
	## nothing, when it is malformed.
	func restore(data: Dictionary) -> Error:
		reset()
		if data.is_empty():
			return OK
		var encounter_part: Variant = data.get("encounter", null)
		var sessions: Variant = data.get("sessions", null)
		if not encounter_part is Dictionary or not sessions is Array:
			return _refuse("its parts are missing")
		var cross_map: Variant = (encounter_part as Dictionary).get("cross_map", null)
		if not cross_map is Array:
			return _refuse("its cross-map instances are missing")
		var partner: CombatStateSection = _partner.get_ref() as CombatStateSection
		var maps: int = -1 if partner == null else partner.held_map_count()
		if maps < 0:
			return _refuse("there is no combat_state to go with it")
		if maps != (sessions as Array).size():
			return _refuse("it is for %d maps, combat_state for %d" % [
				(sessions as Array).size(), maps,
			])
		# Untyped: the parts come from JSON and are checked entry by entry.
		for entry: Variant in cross_map:
			var instance: EffectInstance = (
					EffectInstance.from_capture(entry as Dictionary, resolve)
					if entry is Dictionary else null
			)
			if instance == null:
				return _refuse("a cross-map instance is malformed")
		for entry: Variant in sessions:
			var scratch: EffectEngine = EffectEngine.new(CombatState.new(), null)
			if not entry is Dictionary or scratch.restore(entry as Dictionary, resolve) != OK:
				return _refuse("a map's effects are malformed")
		_held = data.duplicate(true)
		_is_holding = true
		return OK

	## Drops the held data.
	func reset() -> void:
		_held = {}
		_is_holding = false

	## Reads [param session]'s battle in [method capture]; [method CombatStateSection.attach] calls
	## it.
	func attach(session: CampaignSession) -> void:
		_session = session

	## Stops reading the attached run.
	func detach() -> void:
		_session = null

	## Whether it holds a saved battle's effects.
	func is_holding() -> bool:
		return _is_holding

	## The held engine state of each map, by session id; empty when none is held.
	func held_sessions() -> Array:
		return (_held.get("sessions", []) as Array).duplicate(true)

	## The held cross-map instances; empty when none are held.
	func held_cross_map() -> Array:
		var encounter_part: Dictionary = _held.get("encounter", {})
		return (encounter_part.get("cross_map", []) as Array).duplicate(true)

	static func _refuse(reason: String) -> Error:
		push_error("CombatStateSection: the effects section can't be restored - %s" % [reason])
		return ERR_INVALID_DATA
