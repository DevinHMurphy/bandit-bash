# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_matchup_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name WhileMatchupCondition
extends EffectCondition
## Passes while this unit has a weapon-triangle result against its opponent: "while this unit has
## triangle Advantage" (Professional).
##
## The combat core computes the attacker's result and puts it in
## [member EffectContext.matchup]; the defender's is its mirror. Applies only from Before Combat to
## After Combat; outside an exchange it fails.
##
## @tutorial(Unit roster): docs/design/unit-roster.md

## A weapon-triangle result. Saved as an int: [b]append only[/b].
enum Matchup {
	## This unit's profile beats the opponent's.
	ADVANTAGE = 0,
	## Same profile, or either has profile None.
	STANDOFF = 1,
	## The opponent's profile beats this unit's.
	DISADVANTAGE = 2,
}

## The result that must hold.
@export var matchup: Matchup = Matchup.ADVANTAGE


func describe() -> String:
	return "while this unit has triangle %s" % [String(Matchup.find_key(matchup)).capitalize()]


func test(ctx: EffectContext) -> bool:
	return ctx.matchup_of(ctx.subject_id) == matchup
