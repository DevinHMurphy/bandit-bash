# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     level_up.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name LevelUp
extends RefCounted
## One level-up of one unit: the level reached and every stat point it gained.
##
## [method gain_xp] levels up once per [member CombatRewardRules.xp_per_level], the rest carrying.
## Each level-up, in the event bus plan's order: (1) roll each of [constant GROWTH_STATS] that may
## grow: growth ÷ 100 points, plus one d100 roll of the rest; (2) add the guaranteed gains
## (Training Weights), pending gains (Feast), then each random gain (Resonant Ore) to one of
## [constant RANDOM_GAIN_STATS] that may grow; (3) raise unraised stats that may grow until
## [constant CampaignValue.Key.LEVEL_UP_MIN_STATS] are (Royal Crest). Gains are one
## [constant SOURCE_ID] delta per stat; HP gained raises current HP too. Draws come from the
## seat's [code]LEVEL_UPS[/code] stream, in roster order. Pure rules code.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The stats a level-up can raise by growth, in roll order. MOV and CON never grow.
const GROWTH_STATS: Array[CombatValue.Stat] = [
	CombatValue.Stat.HP,
	CombatValue.Stat.MGT,
	CombatValue.Stat.SPD,
	CombatValue.Stat.DEF,
	CombatValue.Stat.RES,
]

## The stats a random gain can raise: every growth stat but Speed (items.md, Resonant Ore).
const RANDOM_GAIN_STATS: Array[CombatValue.Stat] = [
	CombatValue.Stat.HP,
	CombatValue.Stat.MGT,
	CombatValue.Stat.DEF,
	CombatValue.Stat.RES,
]

## The source id of every level-up's stat deltas on a unit.
const SOURCE_ID: String = "level_up"

## The label of every level-up's stat deltas, as breakdowns show it.
const SOURCE_LABEL: String = "Level-ups"

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_UNIT: String = "unit_id"
const _KEY_LEVEL: String = "level"
const _KEY_GAINS: String = "gains"

const _PERCENT: int = 100

## Instance id of the unit.
var unit_id: String = ""

## The level it reached.
var level: int = 0

## Points gained per [enum CombatValue.Stat]; a stat with none is left out.
var gains: Dictionary[int, int] = {}


## The level-up as plain JSON, for the seat's combat report: gains keyed by stat number as text.
func capture() -> Dictionary:
	var gained: Dictionary = {}
	for stat: int in gains:
		gained[str(stat)] = gains[stat]
	return {_KEY_UNIT: unit_id, _KEY_LEVEL: level, _KEY_GAINS: gained}


## Adds [param xp] to [param unit] and runs one [method level_up] for each
## [member CombatRewardRules.xp_per_level] it then holds, in order. [param values]: the unit's
## level-up values from its battle. Returns the level-ups; none for no level reached.
static func gain_xp(
		unit: UnitInstance,
		xp: int,
		values: Values,
		stream: RngStream,
		catalog: EffectCatalog.Index,
		rules: CombatRewardRules
) -> Array[LevelUp]:
	var reached: Array[LevelUp] = []
	if unit == null or rules == null or xp <= 0:
		return reached
	unit.xp += xp
	while unit.xp >= rules.xp_per_level:
		unit.xp -= rules.xp_per_level
		reached.append(level_up(unit, values, stream, catalog))
	return reached


## One level-up of [param unit] (see the class doc), applied to it. [param values] null: no item
## changes anything, and every stat may grow.
static func level_up(
		unit: UnitInstance, values: Values, stream: RngStream, catalog: EffectCatalog.Index
) -> LevelUp:
	var read: Values = values if values != null else Values.new()
	var gains: Dictionary[int, int] = {}
	for stat: CombatValue.Stat in GROWTH_STATS:
		if read.can_grow(stat):
			_add(gains, stat, _growth_points(unit.growth(catalog, stat), stream))
	for stat: int in read.guaranteed:
		_add(gains, stat, read.guaranteed[stat])
	_take_pending(unit, gains)
	var random_stats: Array[CombatValue.Stat] = read.allowed(RANDOM_GAIN_STATS)
	for _gain: int in maxi(read.random_gains, 0):
		if random_stats.is_empty():
			break
		_add(gains, random_stats[_pick(stream, random_stats.size())], 1)
	var fill: Array[CombatValue.Stat] = []
	for stat: CombatValue.Stat in read.allowed(GROWTH_STATS):
		if gains.get(stat, 0) <= 0:
			fill.append(stat)
	while _raised_count(gains) < read.min_stats and not fill.is_empty():
		var filled: CombatValue.Stat = fill.pop_at(_pick(stream, fill.size()))
		_add(gains, filled, 1)
	unit.level += 1
	_apply_gains(unit, gains)
	var result: LevelUp = LevelUp.new()
	result.unit_id = unit.instance_id
	result.level = unit.level
	result.gains = gains
	return result


static func _add(gains: Dictionary[int, int], stat: int, points: int) -> void:
	if points == 0:
		return
	var total: int = gains.get(stat, 0) + points
	if total == 0:
		gains.erase(stat)
	else:
		gains[stat] = total


static func _raised_count(gains: Dictionary[int, int]) -> int:
	var raised: int = 0
	for stat: int in gains:
		if gains[stat] > 0:
			raised += 1
	return raised


# gains as the unit's level-up deltas, one per stat, merged into the deltas earlier level-ups
# left; an HP gain raises a hurt unit's current HP too (a unit at full HP stays full).
static func _apply_gains(unit: UnitInstance, gains: Dictionary[int, int]) -> void:
	for stat: int in gains:
		var key: int = CombatValue.STAT_KEYS.get(stat, -1)
		if key < 0:
			continue
		var merged: bool = false
		for delta: ItemInstance.StatDelta in unit.stat_deltas:
			if delta.key == key and delta.source_id == SOURCE_ID:
				delta.amount += float(gains[stat])
				merged = true
				break
		if not merged:
			unit.stat_deltas.append(ItemInstance.StatDelta.new(
					key, float(gains[stat]), SOURCE_ID, SOURCE_LABEL
			))
	var hp_gain: int = gains.get(CombatValue.Stat.HP, 0)
	if hp_gain > 0 and unit.hp != UnitInstance.FULL_HP:
		unit.hp += hp_gain


# Each of unit's pending gains with uses left adds once and uses one; spent ones are dropped.
static func _take_pending(unit: UnitInstance, gains: Dictionary[int, int]) -> void:
	var kept: Array[UnitInstance.PendingGain] = []
	for gain: UnitInstance.PendingGain in unit.pending_gains:
		if gain.remaining <= 0:
			continue
		_add(gains, gain.stat, gain.amount)
		gain.remaining -= 1
		if gain.remaining > 0:
			kept.append(gain)
	unit.pending_gains = kept


# A growth of growth percent: one point per full 100, plus one more when a d100 falls below the
# rest. Always draws once, so the stream moves the same whatever the growth.
static func _growth_points(growth: int, stream: RngStream) -> int:
	var points: int = floori(growth / float(_PERCENT))
	if stream.roll_percent(growth % _PERCENT):
		points += 1
	return points


# An index below count, drawing nothing for a single choice (RngStream.pick_index does the same).
static func _pick(stream: RngStream, count: int) -> int:
	return 0 if count == 1 else stream.pick_index(count)


## What a unit's items and effects set for its level-ups, read on the unit as its battle ends
## ([method read]), since items count only in battle.
class Values:
	extends RefCounted

	## Points each level-up adds per [enum CombatValue.Stat]; a stat with none is left out.
	var guaranteed: Dictionary[int, int] = {}
	## Random +1 gains each level-up adds ([constant CampaignValue.Key.LEVEL_UP_RANDOM_GAINS]).
	var random_gains: int = 0
	## Fewest stats each level-up raises ([constant CampaignValue.Key.LEVEL_UP_MIN_STATS]).
	var min_stats: int = 0
	## The stats denied growth; every other stat may grow.
	var denied: Array[int] = []

	## Whether [param stat] may grow.
	func can_grow(stat: int) -> bool:
		return not denied.has(stat)

	## The stats of [param stats] that may grow, in their order.
	func allowed(stats: Array[CombatValue.Stat]) -> Array[CombatValue.Stat]:
		var found: Array[CombatValue.Stat] = []
		for stat: CombatValue.Stat in stats:
			if can_grow(stat):
				found.append(stat)
		return found

	## The level-up values on [param sheet], a unit's in battle.
	static func read(sheet: StatSheet) -> Values:
		var values: Values = Values.new()
		if sheet == null:
			return values
		for stat: int in CombatValue.Stat.values():
			var points: int = sheet.get_int(
					CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS, null, stat
			)
			if points != 0:
				values.guaranteed[stat] = points
			if not sheet.is_allowed(CampaignValue.Permission.STAT_CAN_GROW, null, stat):
				values.denied.append(stat)
		values.random_gains = sheet.get_int(CampaignValue.Key.LEVEL_UP_RANDOM_GAINS)
		values.min_stats = sheet.get_int(CampaignValue.Key.LEVEL_UP_MIN_STATS)
		return values
