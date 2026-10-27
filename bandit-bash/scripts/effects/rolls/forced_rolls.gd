# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forced_rolls.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name ForcedRolls
extends RollSource
## Rolls a given outcome sequence, for AI branch enumeration: one branch per sequence.
##
## Each roll takes the next outcome: 1 or 0 for a hit or percent roll, the index for a pick. Rolls
## past the end take 0 (a miss, a failure, the first candidate), so [ExchangeOutcome] can extend a
## sequence one roll at a time. [method RollSource.probability] is the branch's probability; a
## forced outcome that can't happen (a hit at 0%) gives 0.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

var _outcomes: PackedInt32Array = []
var _next: int = 0


func _init(outcomes: PackedInt32Array = PackedInt32Array()) -> void:
	_outcomes = outcomes


## How many rolls took their outcome from the given sequence.
func forced_count() -> int:
	return mini(_next, _outcomes.size())


func _draw_hit_2rn(_hit_percent: int, _odds: float) -> bool:
	return _take() != 0


func _draw_percent(_chance: int, _odds: float) -> bool:
	return _take() != 0


func _draw_index(_count: int) -> int:
	return _take()


func _take() -> int:
	var outcome: int = _outcomes[_next] if _next < _outcomes.size() else 0
	_next += 1
	return outcome
