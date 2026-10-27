# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     roll_source.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@abstract
class_name RollSource
extends RefCounted
## Every random decision in rules code goes through one of these, which reports its probability.
##
## Rolls follow [code]Godot_FE[/code]'s [code]random_rolls_bool[/code]: a d100 is an integer from 0
## to 99. Subclasses decide outcomes: [LiveRolls] draws from a stream, [ForecastRolls] assumes
## hits land and chances fail, [ForcedRolls] replays a given sequence, [SampledRolls] draws from a
## generator seeded per candidate. This base reports the odds and appends one [RollRecord] per
## call, so the forecast can show them and branch enumeration can multiply them.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

# A d100's sides; its rolls are 0 to 99.
const _D100: int = 100

# Pairs of two d100 rolls.
const _D100_PAIRS: float = 10000.0

## Every roll made, in order.
var records: Array[RollRecord] = []


## Two d100; a hit if their integer average is below [param hit_percent]. The record carries the
## true two-roll probability, not the displayed Hit.
func roll_hit_2rn(hit_percent: int) -> bool:
	var shown: int = clampi(hit_percent, 0, _D100)
	var odds: float = hit_2rn_probability(shown)
	var hit: bool = _draw_hit_2rn(shown, odds)
	records.append(RollRecord.new(RollRecord.Kind.HIT_2RN, shown, odds, 1 if hit else 0))
	return hit


## One d100; a success if it is below [param chance] (crits, Chance conditions).
func roll_percent(chance: int) -> bool:
	var shown: int = clampi(chance, 0, _D100)
	var odds: float = shown / float(_D100)
	var success: bool = _draw_percent(shown, odds)
	records.append(RollRecord.new(RollRecord.Kind.PERCENT, shown, odds, 1 if success else 0))
	return success


## A uniform index from 0 to [param count] - 1 ([RandomOf] selectors).
## Returns -1, recording nothing, if [param count] is below 1.
func pick_index(count: int) -> int:
	if count < 1:
		return -1
	var picked: int = clampi(_draw_index(count), 0, count - 1)
	records.append(RollRecord.new(RollRecord.Kind.PICK, count, 1.0 / count, picked))
	return picked


## The combined probability of every outcome recorded so far: 1.0 before any roll.
func probability() -> float:
	var combined: float = 1.0
	for record: RollRecord in records:
		combined *= record.outcome_probability()
	return combined


## The probability that a 2RN roll hits at [param hit_percent]: pairs of d100 summing to at most
## [code]2 × hit_percent − 1[/code], over 10,000.
static func hit_2rn_probability(hit_percent: int) -> float:
	var highest_sum: int = 2 * clampi(hit_percent, 0, _D100) - 1
	var pairs: int = 0
	for first: int in _D100:
		pairs += clampi(highest_sum - first + 1, 0, _D100)
	return pairs / _D100_PAIRS


## Decides a 2RN hit. [param odds] is the true probability, for sources that don't roll.
@abstract func _draw_hit_2rn(hit_percent: int, odds: float) -> bool


## Decides a percent roll. [param odds] is [param chance] / 100.
@abstract func _draw_percent(chance: int, odds: float) -> bool


## Decides a pick among [param count] candidates (at least 1).
@abstract func _draw_index(count: int) -> int
