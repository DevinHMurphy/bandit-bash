# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     roll_record.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name RollRecord
extends RefCounted
## One random decision a [RollSource] made: what was rolled, its odds, and what happened.
##
## The forecast displays these; the AI's branch enumeration multiplies their
## [method outcome_probability] values into a branch's probability.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## What was rolled.
enum Kind {
	## A 2RN hit roll ([method RollSource.roll_hit_2rn]).
	HIT_2RN = 0,
	## One d100 against a chance: crits and Chance conditions ([method RollSource.roll_percent]).
	PERCENT = 1,
	## A uniform pick among candidates ([method RollSource.pick_index]).
	PICK = 2,
}

## What was rolled.
var kind: Kind = Kind.PERCENT

## The displayed number: the Hit or the chance in percent (clamped to 0 to 100), or the candidate
## count of a pick.
var value: int = 0

## The probability of success: the true two-roll odds for a hit, the chance / 100 for a percent
## roll, 1 / count for each candidate of a pick.
var probability: float = 0.0

## What happened: 1 for a hit or a success, 0 for a miss or a failure, the index for a pick.
var outcome: int = 0

## Whether [member outcome] only stands in for a random pick the source didn't make: a forecast
## keeps the first candidate, so the display says the pick is random ("a random ally") instead of
## naming it (event bus plan, question 35). False for every decided roll.
var is_placeholder: bool = false


func _init(roll_kind: Kind, shown: int, odds: float, result: int) -> void:
	kind = roll_kind
	value = shown
	probability = odds
	outcome = result


## Whether a hit or percent roll succeeded.
func succeeded() -> bool:
	return outcome != 0


## The probability of the outcome that happened: [member probability] for a success or a pick,
## its complement for a failure.
func outcome_probability() -> float:
	if kind == Kind.PICK or succeeded():
		return probability
	return 1.0 - probability


## How many outcomes the roll had: 2, or the candidate count of a pick.
func outcome_count() -> int:
	return value if kind == Kind.PICK else 2
