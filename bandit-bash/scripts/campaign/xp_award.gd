# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     xp_award.gd
# Author:
# Created:  November 14, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name XpAward
extends RefCounted
## The XP one unit earned from a won combat (game-vision.md, Units: Experience).
##
## [b]Shared[/b] XP by combat type, times the seat's [constant CampaignValue.Key.SHARED_XP_PERCENT];
## [b]personal[/b] XP from its tallied actions, capped; the [b]Standout[/b]'s bonus on top of the
## cap; the sum times the unit's [constant CampaignValue.Key.UNIT_XP_PERCENT] (Family Ring). Each
## percent rounds halves up. Only a won seat's units standing at the battle's end earn any, on
## any map. The Standout has the most actions; a tie goes to the lower level, then the more
## personal XP (capped), then roster order; no Standout when nobody acted. Pure rules code; saved
## as [method capture].
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_UNIT: String = "unit_id"
const _KEY_SHARED: String = "shared"
const _KEY_PERSONAL: String = "personal"
const _KEY_STANDOUT: String = "standout"
const _KEY_PERCENT: String = "percent"
const _KEY_TOTAL: String = "total"

const _PERCENT: float = 100.0

## Instance id of the unit.
var unit_id: String = ""

## Shared XP, after the seat's percent.[br]
## [b]Units:[/b] XP.
var shared: int = 0

## Personal XP from its actions, after the cap.[br]
## [b]Units:[/b] XP.
var personal: int = 0

## Whether the unit was the combat's Standout.
var is_standout: bool = false

## The Standout's bonus; 0 for every other unit.[br]
## [b]Units:[/b] XP.
var standout: int = 0

## The unit's own XP percent (Family Ring), applied last.[br]
## [b]Units:[/b] percent; 100 when nothing modifies it.
var percent: int = 100

## What the unit gains: shared, personal and Standout XP, times [member percent]; never below 0.[br]
## [b]Units:[/b] XP.
var total: int = 0


## The award as plain JSON, for the seat's combat report.
func capture() -> Dictionary:
	return {
		_KEY_UNIT: unit_id,
		_KEY_SHARED: shared,
		_KEY_PERSONAL: personal,
		_KEY_STANDOUT: is_standout,
		_KEY_PERCENT: percent,
		_KEY_TOTAL: total,
	}


## The award [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null when a field is missing or of the wrong type, or the unit id is empty. The Standout's
## bonus is saved only inside the total, so it is read from [param rules]
## ([member CombatRewardRules.standout_xp]), as [method award] gave it.
static func restore(data: Dictionary, rules: CombatRewardRules) -> XpAward:
	var unit: Variant = data.get(_KEY_UNIT)
	var is_best: Variant = data.get(_KEY_STANDOUT)
	var numbers: Array = [
		CampaignRunState.whole_number(data.get(_KEY_SHARED)),
		CampaignRunState.whole_number(data.get(_KEY_PERSONAL)),
		CampaignRunState.whole_number(data.get(_KEY_PERCENT)),
		CampaignRunState.whole_number(data.get(_KEY_TOTAL)),
	]
	if not unit is String or (unit as String).is_empty() or not is_best is bool:
		return null
	if numbers.has(null) or rules == null:
		return null
	var read: XpAward = XpAward.new()
	read.unit_id = unit as String
	read.is_standout = is_best as bool
	read.standout = rules.standout_xp if read.is_standout else 0
	read.shared = numbers[0] as int
	read.personal = numbers[1] as int
	read.percent = numbers[2] as int
	read.total = numbers[3] as int
	return read


## Each of [param units]' awards from a won combat of [param outcome]'s seat, in their order (the
## roster's). [param tally]: the battle's actions. [param unit_percents]: each unit's XP percent
## by instance id, 100 for one not listed. [param unshared]: units that earn no shared XP (a
## co-op visitor on a partner's map that failed), still their personal XP and the Standout. Empty
## for a lost map.
static func award(
		units: Array[UnitInstance],
		tally: BattleTally,
		outcome: CampaignSession.SeatOutcome,
		unit_percents: Dictionary[String, int],
		rules: CombatRewardRules,
		unshared: PackedStringArray = PackedStringArray()
) -> Array[XpAward]:
	var awards: Array[XpAward] = []
	if outcome == null or rules == null or tally == null or not outcome.is_won:
		return awards
	var shared_xp: int = _percent_of(
			rules.shared_xp_for(outcome.combat_type), outcome.shared_xp_percent
	)
	var standout_id: String = standout_of(units, tally, rules)
	for unit: UnitInstance in units:
		var earned: XpAward = XpAward.new()
		earned.unit_id = unit.instance_id
		earned.shared = 0 if unshared.has(unit.instance_id) else shared_xp
		earned.personal = capped_personal_xp(tally, unit.instance_id, rules)
		if unit.instance_id == standout_id:
			earned.is_standout = true
			earned.standout = rules.standout_xp
		earned.percent = unit_percents.get(unit.instance_id, 100)
		earned.total = maxi(
				_percent_of(earned.shared + earned.personal + earned.standout, earned.percent), 0
		)
		awards.append(earned)
	return awards


## [param unit_id]'s personal XP from [param tally], before the cap.
static func personal_xp(tally: BattleTally, unit_id: String, rules: CombatRewardRules) -> int:
	var sum: int = 0
	for action: BattleTally.Action in BattleTally.ACTION_IDS:
		sum += tally.count(unit_id, action) * rules.personal_xp_for(action)
	return sum


## [param unit_id]'s personal XP from [param tally], after the cap.
static func capped_personal_xp(
		tally: BattleTally, unit_id: String, rules: CombatRewardRules
) -> int:
	return mini(personal_xp(tally, unit_id, rules), rules.personal_xp_cap)


## The instance id of the Standout among [param units] (see the class doc); empty when none of
## them took an action.
static func standout_of(
		units: Array[UnitInstance], tally: BattleTally, rules: CombatRewardRules
) -> String:
	var best: UnitInstance = null
	var best_actions: int = 0
	var best_personal: int = 0
	for unit: UnitInstance in units:
		var actions: int = tally.total(unit.instance_id)
		if actions <= 0:
			continue
		var earned: int = capped_personal_xp(tally, unit.instance_id, rules)
		var is_better: bool = (
				best == null
				or actions > best_actions
				or (actions == best_actions and unit.level < best.level)
				or (
						actions == best_actions
						and unit.level == best.level
						and earned > best_personal
				)
		)
		if is_better:
			best = unit
			best_actions = actions
			best_personal = earned
	return "" if best == null else best.instance_id


# value times percent / 100, halves rounding up.
static func _percent_of(value: int, percent: int) -> int:
	return ValueBreakdown.round_to_int(value * percent / _PERCENT, ValueBreakdown.Rounding.HALF_UP)
