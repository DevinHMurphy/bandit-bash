# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_grades.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name CombatGrades
extends RefCounted
## One seat's grades for a won combat and the gold they pay (game-vision.md, Gold).
##
## Two grades, each paying [constant CampaignValue.Key.GRADE_BONUS_PERCENT] of the combat's base
## gold, halves rounding up: [b]under par[/b] (ending on a turn below the map's turn par; a Survive
## or Defend map ending early; never for a map with no par or one that received sent units) and
## [b]no losses[/b] (none of the seat's units fell). [constant CampaignValue.Key.COMBAT_GOLD]
## (Bounty Ledger) is added flat after the grades and never multiplied. Pure rules code; built by
## [method grade] and saved as [method capture] in the seat's combat report.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_UNDER_PAR: String = "is_under_par"
const _KEY_NO_LOSSES: String = "is_without_losses"
const _KEY_BASE: String = "base_gold"
const _KEY_BONUS: String = "bonus_per_grade"
const _KEY_EXTRA: String = "extra_gold"
const _KEY_GOLD: String = "gold"

const _PERCENT: float = 100.0

## Whether the combat ended under par.
var is_under_par: bool = false

## Whether the seat lost no units.
var is_without_losses: bool = false

## The combat's own gold ([method CombatRewardRules.gold_for]).[br]
## [b]Units:[/b] gold.
var base_gold: int = 0

## Gold each grade earned adds: the grade percent of [member base_gold], halves rounding up.[br]
## [b]Units:[/b] gold.
var bonus_per_grade: int = 0

## Flat gold from [constant CampaignValue.Key.COMBAT_GOLD], after the grades.[br]
## [b]Units:[/b] gold.
var extra_gold: int = 0

## Everything the combat pays: base, each grade's bonus and the extra gold; never below 0.[br]
## [b]Units:[/b] gold.
var gold: int = 0


## How many grades were earned, 0 to 2.
func grade_count() -> int:
	return int(is_under_par) + int(is_without_losses)


## The grades and gold as plain JSON, for the seat's combat report.
func capture() -> Dictionary:
	return {
		_KEY_UNDER_PAR: is_under_par,
		_KEY_NO_LOSSES: is_without_losses,
		_KEY_BASE: base_gold,
		_KEY_BONUS: bonus_per_grade,
		_KEY_EXTRA: extra_gold,
		_KEY_GOLD: gold,
	}


## The grades [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null when a field is missing or of the wrong type.
static func restore(data: Dictionary) -> CombatGrades:
	var under_par: Variant = data.get(_KEY_UNDER_PAR)
	var no_losses: Variant = data.get(_KEY_NO_LOSSES)
	var numbers: Array = [
		CampaignRunState.whole_number(data.get(_KEY_BASE)),
		CampaignRunState.whole_number(data.get(_KEY_BONUS)),
		CampaignRunState.whole_number(data.get(_KEY_EXTRA)),
		CampaignRunState.whole_number(data.get(_KEY_GOLD)),
	]
	if not under_par is bool or not no_losses is bool or numbers.has(null):
		return null
	var grades: CombatGrades = CombatGrades.new()
	grades.is_under_par = under_par as bool
	grades.is_without_losses = no_losses as bool
	grades.base_gold = numbers[0] as int
	grades.bonus_per_grade = numbers[1] as int
	grades.extra_gold = numbers[2] as int
	grades.gold = numbers[3] as int
	return grades


## The grades [param outcome]'s seat earned and the gold they pay, by [param rules]. A lost map
## earns no grade and pays nothing.
static func grade(
		outcome: CampaignSession.SeatOutcome, rules: CombatRewardRules
) -> CombatGrades:
	var grades: CombatGrades = CombatGrades.new()
	if outcome == null or rules == null or not outcome.is_won:
		return grades
	grades.is_under_par = is_under_par_for(outcome)
	grades.is_without_losses = outcome.units_lost == 0
	grades.base_gold = rules.gold_for(outcome.combat_type)
	grades.bonus_per_grade = ValueBreakdown.round_to_int(
			grades.base_gold * outcome.grade_bonus_percent / _PERCENT,
			ValueBreakdown.Rounding.HALF_UP
	)
	grades.extra_gold = outcome.combat_gold
	grades.gold = maxi(
			grades.base_gold + grades.bonus_per_grade * grades.grade_count() + grades.extra_gold,
			0
	)
	return grades


## Whether [param outcome]'s map ended under par: Survive and Defend by ending early, every other
## objective on a turn below a set turn par. Never with sent units received.
static func is_under_par_for(outcome: CampaignSession.SeatOutcome) -> bool:
	if outcome.has_received_units:
		return false
	match outcome.objective:
		CombatMapDefinition.Objective.SURVIVE, CombatMapDefinition.Objective.DEFEND:
			return outcome.turns_early > 0
	return outcome.turn_par > 0 and outcome.turn < outcome.turn_par
