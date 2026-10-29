# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_type_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name UnitTypeDefinition
extends EffectCarrierDefinition
## One unit type: role, weapons, movement, tags, Stance, base stats and growths, trait and upgrade.
##
## Content data in [code]res://data/units/[/code], commanders in [code]units/commanders/[/code];
## read-only at runtime. [member EffectCarrierDefinition.effects] is the trait (Volley);
## [member upgraded_effects] replaces it on an upgraded unit (Volley+). A unit's stats are computed
## from these bases plus its prefix, upgrade and permanent deltas, never stored here.[br]
## [b]Commanders[/b] ([member is_commander]) keep these stats every run, never roll a prefix and
## are never upgraded, so their upgrade fields stay empty. Enemy classes extend this class (P05).
##
## @tutorial(Unit roster): docs/design/unit-roster.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## [member upgrade_movement_type] when the upgrade keeps the unit's movement type.
const KEEP_MOVEMENT: int = -1

## The trait's name, such as "Volley"; an upgraded unit shows it with "+"
## ([method trait_label]). [b]Empty:[/b] the type has no trait.
@export var trait_name: String = ""

# ASSUMPTION: a commander has no role; unit-roster.md's Role column doesn't list the Drengr.
## What the unit type is for, from [constant ContentIds.ROLES], such as [code]shover[/code], which
## auto-deployment looks for. [b]Empty:[/b] no role.
@export var role: String = ""

## Weapon types it can wield, from [constant ContentIds.WEAPON_TYPES]; [code]staff[/code] for
## staves. [b]Empty:[/b] it wields nothing.
@export var weapon_types: PackedStringArray = []

## How it crosses terrain (unit-roster.md, Movement and tags).
@export var movement_type: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT

## What it is, from [constant ContentIds.TAGS]; effectiveness, heirlooms and traits test them.
## [b]Empty:[/b] no tags.
@export var tags: PackedStringArray = []

## Stance after each refresh; at 0 the unit is Exposed.[br]
## [b]1:[/b] fragile or evasive. [b]2:[/b] standard. [b]3:[/b] bulky.
@export_range(1, 3, 1, "or_greater") var stance: int = 2

## Content id of the weapon a new unit of this type carries, such as [code]simple_bow[/code].
## [b]Empty:[/b] it starts unarmed.
@export var starting_weapon_id: String = ""

## Always-on effects that aren't trait text, such as the Thief's lock-picking permission. They
## apply whether or not the unit is upgraded. [b]Empty:[/b] none.
@export var innate_effects: Array[EffectDefinition] = []

@export_group("Stats")

## Stats at level 1, by [enum CombatValue.Stat]: HP, MGT, SPD, DEF, RES, MOV and CON. A stat left
## out is 0.[br]
## [b]Units:[/b] stat points; MOV in movement cost.
@export var base_stats: Dictionary[CombatValue.Stat, int] = {}

## Chance each stat rises on a level-up, by [enum CombatValue.Stat]. A stat left out never grows;
## the MVP gives MOV and CON no growths.[br]
## [b]Units:[/b] percent; may pass 100 (the Sellsword's HP is 110).
@export var growths: Dictionary[CombatValue.Stat, int] = {}

@export_group("Upgrade")

## The "+" trait, which replaces [member EffectCarrierDefinition.effects] on an upgraded unit.
## [b]Empty:[/b] an upgrade changes no trait (commanders, never upgraded).
@export var upgraded_effects: Array[EffectDefinition] = []

## Stat points an upgrade adds, by [enum CombatValue.Stat]. Upgrades never change growths.[br]
## [b]Units:[/b] stat points. [b]Empty:[/b] none.
@export var upgrade_stat_gains: Dictionary[CombatValue.Stat, int] = {}

## Weapon types a big upgrade adds, from [constant ContentIds.WEAPON_TYPES]. Adding any also grants
## Sidearm, a free weapon swap once per unit turn ([method grants_sidearm]). [b]Empty:[/b] none.
@export var upgrade_weapon_types: PackedStringArray = []

## Movement type of an upgraded unit, a [enum CombatGrid.MovementType] such as Mounted for Lancer+.
## [b][constant KEEP_MOVEMENT]:[/b] the upgrade keeps [member movement_type].
@export var upgrade_movement_type: int = KEEP_MOVEMENT

## Tags a big upgrade adds, from [constant ContentIds.TAGS], such as [code]mounted[/code] for
## Lancer+. [b]Empty:[/b] none.
@export var upgrade_tags: PackedStringArray = []

@export_group("Commander")

## Whether this is a faction's commander. Only files in [code]units/commanders/[/code] set it, and
## every file there does (the content test checks both).
@export var is_commander: bool = false

## Content id of the commander's Commander Heirloom, such as [code]iron_heart[/code]. Commanders
## only. [b]Empty:[/b] none.
@export var commander_heirloom_id: String = ""

@export_group("")


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "role":
		ContentIds.apply_hint(property, ContentIds.ROLES)
	elif property["name"] == "weapon_types" or property["name"] == "upgrade_weapon_types":
		ContentIds.apply_hint(property, ContentIds.WEAPON_TYPES)
	elif property["name"] == "tags" or property["name"] == "upgrade_tags":
		ContentIds.apply_hint(property, ContentIds.TAGS)
	elif property["name"] == "upgrade_movement_type":
		var entries: PackedStringArray = ["Unchanged:%d" % [KEEP_MOVEMENT]]
		for name: String in CombatGrid.MovementType:
			entries.append("%s:%d" % [name.capitalize(), CombatGrid.MovementType[name]])
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = ",".join(entries)


## The trait's name as shown on a unit: [member trait_name], with "+" when
## [param is_upgraded] (unit-roster.md, Upgrades: "Volley+"). Empty when there is no trait.
func trait_label(is_upgraded: bool) -> String:
	if trait_name.is_empty() or not is_upgraded:
		return trait_name
	return trait_name + "+"


## Whether an upgrade changes the movement type ([member upgrade_movement_type]).
func upgrade_changes_movement() -> bool:
	return upgrade_movement_type != KEEP_MOVEMENT


## Whether an upgraded unit of this type has Sidearm: true when the upgrade adds a weapon type.
func grants_sidearm() -> bool:
	return not upgrade_weapon_types.is_empty()
