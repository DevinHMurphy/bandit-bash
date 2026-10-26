# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_value.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name CombatValue
extends RefCounted
## Value and permission keys read during combat, other than the damage stages ([DamageStage]).
##
## Seeded with the combat core's keys (combat core plan, Value keys, permissions and facts). The
## units plan appends the base stats. Never instantiated.
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
	## The move budget, in movement cost.
	MOVEMENT = 15,
}

## A combat permission: a yes or no answer, where any denial beats any grant. Values live in this
## class's permission block (3000 to 3999). [b]Append only[/b], with explicit values.
enum Permission {
	## May counter when the weapon's range covers the distance. Allowed by default; denied while
	## holding a staff.
	CAN_COUNTER = 3000,
	# ASSUMPTION: a boss's Unshovable grants this key. The plan says denial beats grant so that
	# Unshovable can't be cancelled, which holds only if the key is inverted (a "can be shoved"
	# permission that the boss denies). Needs an answer before content uses it.
	## Can't be shoved. Off by default.
	UNSHOVABLE = 3001,
	## May spend the remaining movement after acting (Skirmisher). Off by default.
	MAY_MOVE_AFTER_ACTING = 3002,
	## Swaps weapons for free once per unit turn, before acting (Sidearm). Off by default.
	FREE_WEAPON_SWAP = 3003,
	## A crit skips the Mitigation stage (Kukri). Off by default.
	SKIP_MITIGATION_ON_CRIT = 3004,
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
	Permission.UNSHOVABLE: false,
	Permission.MAY_MOVE_AFTER_ACTING: false,
	Permission.FREE_WEAPON_SWAP: false,
	Permission.SKIP_MITIGATION_ON_CRIT: false,
}
