# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_tally.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name BattleTally
extends RefCounted
## How many XP-earning actions each player unit took in the battle in progress: hits, defeats,
## heals, Block given and non-combat actions (game-vision.md, Units: Experience).
##
## A host-side observer: [CampaignSession] hands it every fact a battle records ([method record])
## and it counts, changing no rules state. Turning counts into XP, the cap and the Standout is the
## results' work, after combat. A killing blow counts a hit and a defeat. Saved in the combat block
## as [code]battle_tally[/code] ([BattleTallySection]), because a resumed battle's fact log starts
## empty and can't rebuild it. Pure: no nodes, no logging.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## An XP-earning action. Saved by name ([constant ACTION_IDS]), so values may be renumbered,
## never renamed without a migration.
enum Action {
	## A hit on an enemy, even fully absorbed.
	HIT,
	## An enemy defeated.
	DEFEAT,
	## HP restored to another player unit, overhealing included.
	HEAL,
	## Block given to another player unit.
	BLOCK,
	## A reinforcement point closed, a house or shelf searched, or a chest opened.
	NON_COMBAT,
}

## The saved name of each [enum Action]. Never change one: saved battles are read by these names.
const ACTION_IDS: Dictionary[Action, String] = {
	Action.HIT: "hit",
	Action.DEFEAT: "defeat",
	Action.HEAL: "heal",
	Action.BLOCK: "block",
	Action.NON_COMBAT: "non_combat",
}

# capture()'s key. Never change it: saved battles are read by this name.
const _KEY_UNITS: String = "units"

# Each unit's counts by unit id, indexed by Action; a unit with no action has no entry.
var _counts: Dictionary[String, PackedInt32Array] = {}


## How many times [param unit_id] took [param action] this battle.
func count(unit_id: String, action: Action) -> int:
	var counts: PackedInt32Array = _counts.get(unit_id, PackedInt32Array())
	return counts[action] if action < counts.size() else 0


## Every action [param unit_id] took this battle, of every kind.
func total(unit_id: String) -> int:
	var sum: int = 0
	for value: int in _counts.get(unit_id, PackedInt32Array()):
		sum += value
	return sum


## Ids of the units with at least one action, sorted.
func unit_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray(_counts.keys())
	ids.sort()
	return ids


## Forgets every count, as a battle begins.
func clear() -> void:
	_counts.clear()


## Counts [param fact], recorded on the map whose state is [param state], when it is an XP action
## of a player unit: [constant CombatFact.Kind.HIT_DEALT] and
## [constant CombatFact.Kind.DEFEATED_AN_ENEMY] on an enemy (a breakable is no enemy); a
## [constant CombatFact.Kind.HEALED_AN_ALLY] or a non-zero [constant CombatFact.Kind.BLOCK_GAINED]
## for another player unit; and the unit named in a reinforcement point's closing, a search or a
## chest's opening. Anything else counts nothing.
func record(fact: CombatFact, state: CombatState) -> void:
	if fact == null or state == null:
		return
	match fact.kind:
		CombatFact.Kind.HIT_DEALT:
			if _is_player(state, fact.actor_id) and _is_enemy(state, fact.target_id):
				_add(fact.actor_id, Action.HIT)
		CombatFact.Kind.DEFEATED_AN_ENEMY:
			if _is_player(state, fact.actor_id) and _is_enemy(state, fact.target_id):
				_add(fact.actor_id, Action.DEFEAT)
		CombatFact.Kind.HEALED_AN_ALLY:
			if _is_ally_pair(state, fact.actor_id, fact.target_id):
				_add(fact.actor_id, Action.HEAL)
		CombatFact.Kind.BLOCK_GAINED:
			# The actor gained it; the target gave it.
			if fact.amount > 0 and _is_ally_pair(state, fact.target_id, fact.actor_id):
				_add(fact.target_id, Action.BLOCK)
		CombatFact.Kind.OBJECT_STATE_CHANGED:
			if _is_looting(state, fact) and _is_player(state, fact.target_id):
				_add(fact.target_id, Action.NON_COMBAT)


## The counts as plain JSON, for the [code]battle_tally[/code] section:
## [code]{"units": {"unit:57": {"hit": 3, "defeat": 1, ...}}}[/code], every action named for each
## unit listed.
func capture() -> Dictionary:
	var units: Dictionary = {}
	for unit_id: String in unit_ids():
		var entry: Dictionary = {}
		for action: Action in ACTION_IDS:
			entry[ACTION_IDS[action]] = count(unit_id, action)
		units[unit_id] = entry
	return {_KEY_UNITS: units}


## Takes [param data], as [method capture] wrote it, numbers as whole floats too. Returns
## [constant ERR_INVALID_DATA], changing nothing, for a missing or unknown action, a count that
## isn't a whole number of at least 0, or a unit id that isn't a non-empty string.
func restore(data: Dictionary) -> Error:
	var units: Variant = data.get(_KEY_UNITS)
	if not units is Dictionary:
		return _refuse(data)
	var read: Dictionary[String, PackedInt32Array] = {}
	var unit_data: Dictionary = units
	for unit_id: Variant in unit_data:
		var entry: Variant = unit_data[unit_id]
		if not unit_id is String or (unit_id as String).is_empty() or not entry is Dictionary:
			return _refuse(data)
		var entry_data: Dictionary = entry
		if entry_data.size() != ACTION_IDS.size():
			return _refuse(data)
		var counts: PackedInt32Array = _empty_counts()
		for action: Action in ACTION_IDS:
			var value: Variant = CampaignRunState.whole_number(entry_data.get(ACTION_IDS[action]))
			if value == null or (value as int) < 0:
				return _refuse(data)
			counts[action] = value as int
		read[unit_id as String] = counts
	_counts = read
	return OK


func _add(unit_id: String, action: Action) -> void:
	# A packed array is a value: change a copy, then store it back.
	var counts: PackedInt32Array = _counts.get(unit_id, _empty_counts())
	counts[action] += 1
	_counts[unit_id] = counts


func _refuse(data: Dictionary) -> Error:
	push_error("BattleTally: not a battle tally's data - %s" % [data])
	return ERR_INVALID_DATA


# Whether giver and receiver are two different player units.
static func _is_ally_pair(state: CombatState, giver: String, receiver: String) -> bool:
	return giver != receiver and _is_player(state, giver) and _is_player(state, receiver)


# Read through CombatState.unit(), which keeps a defeated unit: an attacker can fall in the same
# exchange its hit landed in.
static func _is_player(state: CombatState, unit_id: String) -> bool:
	return _side(state, unit_id) == CombatFact.CombatSide.PLAYER


static func _is_enemy(state: CombatState, unit_id: String) -> bool:
	return _side(state, unit_id) == CombatFact.CombatSide.ENEMY


# The unit's side; NONE for an unknown unit or a breakable.
static func _side(state: CombatState, unit_id: String) -> CombatFact.CombatSide:
	var unit: CombatUnitState = null if unit_id.is_empty() else state.unit(unit_id)
	return CombatFact.CombatSide.NONE if unit == null else unit.side


# Whether an OBJECT_STATE_CHANGED fact is a non-combat action: a point closed, a container
# searched, or a chest opened (a door opening is not one).
static func _is_looting(state: CombatState, fact: CombatFact) -> bool:
	match fact.key:
		MapObjects.Change.POINT_CLOSED, MapObjects.Change.SEARCHED:
			return true
		MapObjects.Change.OPENED:
			var opened: MapState.ObjectState = state.map.object(fact.actor_id)
			return opened != null and opened.kind == MapLayout.ObjectKind.CHEST
	return false


static func _empty_counts() -> PackedInt32Array:
	var counts: PackedInt32Array = []
	counts.resize(ACTION_IDS.size())
	counts.fill(0)
	return counts
