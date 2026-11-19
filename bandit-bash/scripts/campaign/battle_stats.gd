# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_stats.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name BattleStats
extends RefCounted
## How each player unit fought in the battle in progress, for the victory recap: kills, damage
## dealt to enemies, damage taken from every source, and HP healed on allies.
##
## A host-side observer beside [BattleTally], fed the same facts by [CampaignSession]; it changes no
## rules state and earns no XP. Kept apart from the tally so the tally stays "XP-earning actions"
## and its saved shape is untouched. Damage dealt and taken are a fact's whole amount, Block and
## HP; the darkness records its own fact, never a [constant CombatFact.Kind.DAMAGE_TAKEN], so it
## counts once. Heals count overhealing, as the tally does. Saved in the combat block as
## [code]battle_stats[/code] ([BattleTallySection]), and per seat in the combat report. Pure.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## A number counted per unit. Saved by name ([constant STAT_IDS]), so values may be renumbered,
## never renamed without a migration.
enum Stat {
	## Enemies defeated.
	KILLS,
	## Damage that got through to an enemy's Block or HP.
	DAMAGE_DEALT,
	## Damage taken from any source: attacks, splash, spikes, bumps and the darkness.
	DAMAGE_TAKEN,
	## HP restored to another player unit, overhealing included.
	HEALED,
}

## The saved name of each [enum Stat]. Never change one: saved data is read by these names.
const STAT_IDS: Dictionary[Stat, String] = {
	Stat.KILLS: "kills",
	Stat.DAMAGE_DEALT: "damage_dealt",
	Stat.DAMAGE_TAKEN: "damage_taken",
	Stat.HEALED: "healed",
}

# capture()'s key. Never change it: saved data is read by this name.
const _KEY_UNITS: String = "units"

# Each unit's numbers by unit id, indexed by Stat; a unit with none has no entry.
var _values: Dictionary[String, PackedInt32Array] = {}


## [param unit_id]'s [param stat] this battle; 0 for a unit with none.
func value(unit_id: String, stat: Stat) -> int:
	var values: PackedInt32Array = _values.get(unit_id, PackedInt32Array())
	return values[stat] if stat < values.size() else 0


## Whether [param unit_id] has any number above 0.
func has_unit(unit_id: String) -> bool:
	return _values.has(unit_id)


## Ids of the units with any number above 0, sorted.
func unit_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray(_values.keys())
	ids.sort()
	return ids


## Forgets every number, as a battle begins.
func clear() -> void:
	_values.clear()


## Counts [param fact], recorded on the map whose state is [param state]:
## [constant CombatFact.Kind.DEFEATED_AN_ENEMY] and [constant CombatFact.Kind.DAMAGE_DEALT] by a
## player unit on an enemy (a breakable is no enemy); [constant CombatFact.Kind.DAMAGE_TAKEN] and
## [constant CombatFact.Kind.DARKNESS_DAMAGE_TAKEN] by a player unit; and
## [constant CombatFact.Kind.HEALED_AN_ALLY] from one player unit to another. Amounts of 0 or less
## count nothing.
func record(fact: CombatFact, state: CombatState) -> void:
	if fact == null or state == null:
		return
	match fact.kind:
		CombatFact.Kind.DEFEATED_AN_ENEMY:
			if _is_player(state, fact.actor_id) and _is_enemy(state, fact.target_id):
				_add(fact.actor_id, Stat.KILLS, 1)
		CombatFact.Kind.DAMAGE_DEALT:
			if _is_player(state, fact.actor_id) and _is_enemy(state, fact.target_id):
				_add(fact.actor_id, Stat.DAMAGE_DEALT, fact.amount)
		CombatFact.Kind.DAMAGE_TAKEN, CombatFact.Kind.DARKNESS_DAMAGE_TAKEN:
			if _is_player(state, fact.actor_id):
				_add(fact.actor_id, Stat.DAMAGE_TAKEN, fact.amount)
		CombatFact.Kind.HEALED_AN_ALLY:
			var is_ally: bool = (
					fact.actor_id != fact.target_id
					and _is_player(state, fact.actor_id)
					and _is_player(state, fact.target_id)
			)
			if is_ally:
				_add(fact.actor_id, Stat.HEALED, fact.amount)


## The numbers as plain JSON, for the [code]battle_stats[/code] section:
## [code]{"units": {"unit:57": {"kills": 1, "damage_dealt": 14, ...}}}[/code], every stat named
## for each unit listed.
func capture() -> Dictionary:
	var units: Dictionary = {}
	for unit_id: String in unit_ids():
		units[unit_id] = capture_unit(unit_id)
	return {_KEY_UNITS: units}


## [param unit_id]'s numbers as plain JSON, every stat named:
## [code]{"kills": 1, "damage_dealt": 14, "damage_taken": 6, "healed": 0}[/code].
func capture_unit(unit_id: String) -> Dictionary:
	var entry: Dictionary = {}
	for stat: Stat in STAT_IDS:
		entry[STAT_IDS[stat]] = value(unit_id, stat)
	return entry


## Takes [param data], as [method capture] wrote it, numbers as whole floats too. Returns
## [constant ERR_INVALID_DATA], changing nothing, for a unit id that isn't a non-empty string or an
## entry [method read_unit] refuses.
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
		var values: PackedInt32Array = read_unit(entry as Dictionary)
		if values.is_empty():
			return _refuse(data)
		read[unit_id as String] = values
	_values = read
	return OK


func _add(unit_id: String, stat: Stat, amount: int) -> void:
	if amount <= 0:
		return
	# A packed array is a value: change a copy, then store it back.
	var values: PackedInt32Array = _values.get(unit_id, _empty_values())
	values[stat] += amount
	_values[unit_id] = values


func _refuse(data: Dictionary) -> Error:
	push_error("BattleStats: not a battle's stats - %s" % [data])
	return ERR_INVALID_DATA


## One unit's numbers from [param entry], as [method capture_unit] wrote it, indexed by
## [enum Stat]; empty for a missing or unknown stat, or a number that isn't a whole number of at
## least 0.
static func read_unit(entry: Dictionary) -> PackedInt32Array:
	if entry.size() != STAT_IDS.size():
		return PackedInt32Array()
	var values: PackedInt32Array = _empty_values()
	for stat: Stat in STAT_IDS:
		var number: Variant = CampaignRunState.whole_number(entry.get(STAT_IDS[stat]))
		if number == null or (number as int) < 0:
			return PackedInt32Array()
		values[stat] = number as int
	return values


# Read through CombatState.unit(), which keeps a defeated unit: a unit can fall in the same
# exchange its damage landed in.
static func _is_player(state: CombatState, unit_id: String) -> bool:
	return _side(state, unit_id) == CombatFact.CombatSide.PLAYER


static func _is_enemy(state: CombatState, unit_id: String) -> bool:
	return _side(state, unit_id) == CombatFact.CombatSide.ENEMY


# The unit's side; NONE for an unknown unit or a breakable.
static func _side(state: CombatState, unit_id: String) -> CombatFact.CombatSide:
	var unit: CombatUnitState = null if unit_id.is_empty() else state.unit(unit_id)
	return CombatFact.CombatSide.NONE if unit == null else unit.side


static func _empty_values() -> PackedInt32Array:
	var values: PackedInt32Array = []
	values.resize(STAT_IDS.size())
	values.fill(0)
	return values
