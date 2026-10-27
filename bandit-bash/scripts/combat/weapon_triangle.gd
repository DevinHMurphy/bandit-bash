# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     weapon_triangle.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name WeaponTriangle
extends RefCounted
## The Weapon Profile Triangle: Balance beats Nimble, Power beats Balance, Nimble beats Power; the
## same profile is a Standoff (game-vision.md, Combat).
##
## Advantage gives [constant HIT_CHANGE] Hit and [method damage_change] damage, Disadvantage the
## same taken away. A weapon with profile [constant Profile.NONE] (bows, gauntlets) never takes
## part: both sides get a Standoff. Advantage and Disadvantage are mirror images by construction.
## Pure and static; never instantiated.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## A weapon's profile. Saved as an int: [b]append only[/b], with explicit values.
enum Profile {
	## Takes no part in the triangle.
	NONE = 0,
	## Beats Nimble; loses to Power.
	BALANCE = 1,
	## Beats Balance; loses to Nimble.
	POWER = 2,
	## Beats Power; loses to Balance.
	NIMBLE = 3,
}

## Hit gained on Advantage and lost on Disadvantage (game-vision.md; [code]Godot_FE[/code] used
## 20, changed by the vision).
const HIT_CHANGE: int = 15

## Weapon damage is divided by this for the damage change (game-vision.md, WPTAE).
const DAMAGE_DIVISOR: float = 4.0

# The profile each profile beats.
const _BEATS: Dictionary[int, int] = {
	Profile.BALANCE: Profile.NIMBLE,
	Profile.POWER: Profile.BALANCE,
	Profile.NIMBLE: Profile.POWER,
}


## The result for a weapon of [param attacker] profile against [param defender] profile.
static func matchup(attacker: Profile, defender: Profile) -> WhileMatchupCondition.Matchup:
	if attacker == Profile.NONE or defender == Profile.NONE or attacker == defender:
		return WhileMatchupCondition.Matchup.STANDOFF
	if _BEATS[attacker] == defender:
		return WhileMatchupCondition.Matchup.ADVANTAGE
	return WhileMatchupCondition.Matchup.DISADVANTAGE


## The other side's result: Advantage and Disadvantage swap; a Standoff stays.
static func mirror(result: WhileMatchupCondition.Matchup) -> WhileMatchupCondition.Matchup:
	match result:
		WhileMatchupCondition.Matchup.ADVANTAGE:
			return WhileMatchupCondition.Matchup.DISADVANTAGE
		WhileMatchupCondition.Matchup.DISADVANTAGE:
			return WhileMatchupCondition.Matchup.ADVANTAGE
	return WhileMatchupCondition.Matchup.STANDOFF


## The Hit change of [param result]: +15, -15 or 0.
static func hit_change(result: WhileMatchupCondition.Matchup) -> int:
	match result:
		WhileMatchupCondition.Matchup.ADVANTAGE:
			return HIT_CHANGE
		WhileMatchupCondition.Matchup.DISADVANTAGE:
			return -HIT_CHANGE
	return 0


## The damage change of [param result] for a weapon of [param weapon_damage]: a quarter of it,
## rounded once with halves up and at least 1, added on Advantage and taken away on Disadvantage
## (the triangle keeps its own rounding, combat core plan question 5); 0 on a Standoff.
static func damage_change(result: WhileMatchupCondition.Matchup, weapon_damage: float) -> int:
	if result == WhileMatchupCondition.Matchup.STANDOFF:
		return 0
	var change: int = maxi(
			ValueBreakdown.round_to_int(
					weapon_damage / DAMAGE_DIVISOR, ValueBreakdown.Rounding.HALF_UP
			),
			1
	)
	return change if result == WhileMatchupCondition.Matchup.ADVANTAGE else -change
