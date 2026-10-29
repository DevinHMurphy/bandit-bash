# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_value.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name CombatValue
extends RefCounted
## Value and permission keys read during combat, other than the damage stages ([DamageStage]).
##
## Seeded with the combat core's keys (combat core plan, Value keys, permissions and facts) and the
## base stats; the units plan owns the stats' growths and meaning. Never instantiated.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## A combat value. Values live in this class's block (0 to 999), unique across every value key
## class. [b]Append only[/b], with explicit values.
enum Key {
	## SPD minus the weight CON doesn't carry; the gap gives bonus turns.
	ATTACK_SPEED = 0,
	## Weapon slot, Equipment, Pouch and effect weight.
	NET_WEIGHT = 1,
	## Attacks per turn, before the defender's Parry.
	ATK_X = 2,
	## Removes that many of the attacker's attacks per turn, down to 1.
	PARRY = 3,
	## Hit chance before the defender's avoid.
	HIT = 4,
	## Avoid from terrain and effects.
	AVOID = 5,
	## Crit chance added to the base, against an Exposed defender only.
	CRIT_CHANCE = 6,
	## The crit multiplier of the damage stage [constant DamageStage.CRITICAL].
	CRIT_X = 7,
	## Stance after a refresh.
	STANCE_MAX = 8,
	## Tiles a shove pushes.
	SHOVE_DISTANCE = 9,
	## Shortest weapon range, in tiles.
	RANGE_MIN = 10,
	## Longest weapon range, in tiles.
	RANGE_MAX = 11,
	## The attack's [enum CombatFact.DamageType]. Enum-valued: replace-base and fixed modes only.
	DAMAGE_TYPE = 12,
	## How many times weapon damage counts against a unit the weapon is effective against.
	EFFECTIVE_MODIFIER = 13,
	## A staff's heal or Block amount.
	STAFF_AMOUNT = 14,
	## The move budget, in movement cost. The base stat MOV.
	MOVEMENT = 15,
	## Maximum HP.
	HP = 16,
	## Might: scales weapon damage.
	MGT = 17,
	## Speed: the base of Attack Speed.
	SPD = 18,
	## Defense: mitigates physical damage.
	DEF = 19,
	## Resistance: mitigates magic damage.
	RES = 20,
	## Constitution: carries weight without slowing Attack Speed.
	CON = 21,
}

## A base stat, for modifiers of per-stat keys ([constant CampaignValue.STAT_CAN_GROW],
## [constant CampaignValue.LEVEL_UP_GUARANTEED_GAINS]) and for the units plan's growths. Saved as an
## int: [b]append only[/b], with explicit values.
enum Stat {
	## Maximum HP.
	HP = 0,
	## Might.
	MGT = 1,
	## Speed.
	SPD = 2,
	## Defense.
	DEF = 3,
	## Resistance.
	RES = 4,
	## Constitution.
	CON = 5,
	## Movement.
	MOV = 6,
}

## A combat permission: a yes or no answer, where any denial beats any grant. Values live in this
## class's permission block (3000 to 3999). [b]Append only[/b], with explicit values.
enum Permission {
	## May counter when the weapon's range covers the distance. Allowed by default; denied while
	## holding a staff.
	CAN_COUNTER = 3000,
	## May be shoved. Allowed by default; the Unshovable trait denies it, so no grant can cancel it.
	CAN_BE_SHOVED = 3001,
	## May spend the remaining movement after acting (Skirmisher). Off by default.
	MAY_MOVE_AFTER_ACTING = 3002,
	## Swaps weapons for free once per unit turn, before acting (Sidearm). Off by default.
	FREE_WEAPON_SWAP = 3003,
	## A crit skips the Mitigation stage (Kukri). Off by default.
	SKIP_MITIGATION_ON_CRIT = 3004,
	## Opens a chest or door with a Lockpick (the Thief's innate grant). Denied by default.
	CAN_PICK_LOCKS = 3005,
}

## The value key of each [enum Stat]; MOV is [constant MOVEMENT].
const STAT_KEYS: Dictionary[int, int] = {
	Stat.HP: Key.HP,
	Stat.MGT: Key.MGT,
	Stat.SPD: Key.SPD,
	Stat.DEF: Key.DEF,
	Stat.RES: Key.RES,
	Stat.CON: Key.CON,
	Stat.MOV: Key.MOVEMENT,
}

## The base of each key a unit has without one being set; keys not listed start at 0.
## Effectiveness is [code]EffectiveModifier = 3[/code] (game-vision.md, Damage;
## [code]Godot_FE[/code] ×3); a shove pushes 1 tile (game-vision.md, Shove: "1 tile by default").
const DEFAULT_BASES: Dictionary[int, float] = {
	Key.EFFECTIVE_MODIFIER: 3.0,
	Key.SHOVE_DISTANCE: 1.0,
}

## Rounding of each key; keys not listed round [constant ValueBreakdown.HALF_UP].
const ROUNDING: Dictionary[int, int] = {}

## Keys whose value is an enum value, not a number: only replace-base and fixed modifiers apply.
const ENUM_KEYS: Array[int] = [Key.DAMAGE_TYPE]

## Game-rule lower bounds, applied after every modifier. None.
const RULE_MIN: Dictionary[int, float] = {}

## Game-rule upper bounds, applied after every modifier. None.
const RULE_MAX: Dictionary[int, float] = {}

## The answer of each permission that no modifier grants or denies.
const PERMISSION_DEFAULTS: Dictionary[int, bool] = {
	Permission.CAN_COUNTER: true,
	Permission.CAN_BE_SHOVED: true,
	Permission.MAY_MOVE_AFTER_ACTING: false,
	Permission.FREE_WEAPON_SWAP: false,
	Permission.SKIP_MITIGATION_ON_CRIT: false,
	Permission.CAN_PICK_LOCKS: false,
}
