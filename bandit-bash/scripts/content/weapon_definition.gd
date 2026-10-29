# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     weapon_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name WeaponDefinition
extends ItemDefinition
## A weapon: its type, triangle profile and combat numbers (game-vision.md, Weapons and equipment).
##
## Lives in [code]res://data/items/weapons/<weapon_type>/[/code]; the content test checks the
## folder against [member weapon_type]. Its [member EffectCarrierDefinition.effects] apply while
## it is equipped (Dark Sword's lifesteal, Colossus's stats). The loadout turns it into the combat
## state's weapon record; a weapon prefix and an item's deltas apply there as sourced modifiers,
## never here. Staves are [StaffDefinition]s.
##
## @tutorial(Weapons): docs/design/weapons.md

## Weapon type, from [constant ContentIds.WEAPON_TYPES]: which units can wield it.
@export var weapon_type: String = ""

## Triangle profile. [b]None:[/b] takes no part in the triangle (bows, gauntlets, staves).
@export var profile: WeaponTriangle.Profile = WeaponTriangle.Profile.NONE

@export_group("Damage")

## Weapon damage before the scaling stat: the Attack stage's base, and what the triangle and
## effectiveness measure.[br]
## [b]Units:[/b] HP.
@export_range(0, 30, 1, "or_greater") var damage: int = 0

## Which mitigation stat the damage meets. Magic weapons and attack staves deal Magic.
@export var damage_type: CombatFact.DamageType = CombatFact.DamageType.PHYSICAL

## The stat added to [member damage]. Every MVP weapon scales with Might.
@export var scaling_stat: CombatValue.Stat = CombatValue.Stat.MGT

## How much of [member scaling_stat] is added. [b]1.0:[/b] one-for-one, as on every MVP weapon.
## [b]0.0:[/b] the stat adds nothing.
@export_range(0.0, 3.0, 0.05, "or_greater") var scaling_modifier: float = 1.0

## Attacks per turn, before the defender's Parry.
@export_range(1, 5, 1, "or_greater") var atk_x: int = 1

@export_group("Accuracy")

## Hit before the triangle, effects and the defender's avoid.[br]
## [b]Units:[/b] percent. Over 100 still matters against avoid.
@export_range(0, 150, 1, "or_greater") var hit: int = 0

## Crit chance added to the base, against an Exposed defender only.[br]
## [b]Units:[/b] percent. [b]0:[/b] the base chance only.
@export_range(0, 100) var crit: int = 0

## The crit multiplier. Gauntlets use 2, daggers 5; most weapons 3.
@export_range(1.0, 10.0, 0.5, "or_greater") var crit_x: float = 3.0

@export_group("Range")

## Shortest distance it reaches. Attacks start at 1; [b]0:[/b] a staff that targets its user.[br]
## [b]Units:[/b] tiles, by grid distance.
@export_range(0, 10, 1, "or_greater") var range_min: int = 1

## Longest distance it reaches; never below [member range_min].[br]
## [b]Units:[/b] tiles, by grid distance.
@export_range(0, 10, 1, "or_greater") var range_max: int = 1

@export_group("")

## Unit tags it is effective against, from [constant ContentIds.TAGS]: its damage counts
## [constant CombatValue.Key.EFFECTIVE_MODIFIER] times against them. Every bow lists
## [code]flier[/code]. [b]Empty:[/b] effective against nothing.
@export var effective_against: PackedStringArray = []


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "weapon_type":
		ContentIds.apply_hint(property, ContentIds.WEAPON_TYPES)
	elif property["name"] == "effective_against":
		ContentIds.apply_hint(property, ContentIds.TAGS)


func _get_kind() -> String:
	return ContentIds.ITEM_WEAPON
