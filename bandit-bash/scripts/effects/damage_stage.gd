# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     damage_stage.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name DamageStage
extends RefCounted
## Value keys for the damage stages that effects modify (game-vision.md, Combat).
##
## Stages 1 to 4 take modifiers; the floor, Block, HP and after-hit stages are rules, not keys.
## Every stage is [constant ValueBreakdown.EXACT]: the combat core's stage 5 rounds the whole
## damage once, halves up. Never instantiated.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## A damage stage. Values live in this class's block (1000 to 1999), unique across every value
## key class. [b]Append only[/b], with explicit values.
enum Key {
	## Stage 1: weapon damage, scaling, flat attack bonuses, the triangle and effectiveness.
	ATTACK = 1000,
	## Stage 2: the defender's mitigation, subtracted. "Take 5 less damage" is +5 here, "takes 2
	## more damage" -2; it may go below 0, which adds damage.
	MITIGATION = 1001,
	## Stage 3: the crit multiplier, on a crit only.
	CRITICAL = 1002,
	## Stage 4, the attacker's side: every percent modifier on the damage it deals ("deals ×2
	## damage to Beasts"), multiplied together.
	MULTIPLIERS = 1003,
	## Stage 4, the defender's side: every percent modifier on the damage it takes ("takes ×2
	## damage from magic"), multiplied together and then with the attacker's [constant MULTIPLIERS].
	INCOMING_MULTIPLIERS = 1004,
}

## Rounding of each key; keys not listed round [constant ValueBreakdown.HALF_UP].
const ROUNDING: Dictionary[int, int] = {
	Key.ATTACK: ValueBreakdown.Rounding.EXACT,
	Key.MITIGATION: ValueBreakdown.Rounding.EXACT,
	Key.CRITICAL: ValueBreakdown.Rounding.EXACT,
	Key.MULTIPLIERS: ValueBreakdown.Rounding.EXACT,
	Key.INCOMING_MULTIPLIERS: ValueBreakdown.Rounding.EXACT,
}

## Game-rule lower bounds, applied after every modifier. None.
const RULE_MIN: Dictionary[int, float] = {}

## Game-rule upper bounds, applied after every modifier. None.
const RULE_MAX: Dictionary[int, float] = {}
