# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     bonus_turns.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name BonusTurns
extends RefCounted
## Bonus turns from the Attack Speed gap: one at a gap of 4 or more, two at 10, three at 18, then
## each threshold 2 further from the last than the one before (28, 40, 54...), with no cap
## (combat core plan, question 4).
##
## The test is "or more", Fire Emblem's rule; [code]Godot_FE[/code]'s strict "more than" read as
## an off-by-one and is not ported. Bonus turns never fall as the gap grows. Pure and static; never
## instantiated.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## The gap that gives the first bonus turn: [code]ExtraTurnConstant[/code] (game-vision.md;
## [code]Godot_FE[/code] [code]combat_exchange.gd[/code]).
const FIRST_THRESHOLD: int = 4

## How much wider each step between thresholds is than the one before ([code]Godot_FE[/code]'s
## spacing: 4, then 6, 8, 10...).
const STEP_GROWTH: int = 2


## The bonus turns the faster unit gets at an Attack Speed gap of [param gap]. A gap of 0 or less
## gives none; pass the gap from the faster unit's side.
static func count(gap: int) -> int:
	var turns: int = 0
	var step: int = FIRST_THRESHOLD
	var threshold: int = FIRST_THRESHOLD
	while gap >= threshold:
		turns += 1
		step += STEP_GROWTH
		threshold += step
	return turns


## The smallest gap that gives [param turns] bonus turns; 0 for none.
static func threshold_for(turns: int) -> int:
	var threshold: int = 0
	var step: int = FIRST_THRESHOLD
	for i: int in turns:
		threshold += step
		step += STEP_GROWTH
	return threshold
