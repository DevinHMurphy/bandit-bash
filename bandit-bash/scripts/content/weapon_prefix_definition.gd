# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     weapon_prefix_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name WeaponPrefixDefinition
extends EffectCarrierDefinition
## A weapon prefix: changes to a weapon's combat numbers that a weapon can roll (content catalog
## plan, question 15).
##
## Lives in [code]res://data/prefixes/weapons/all/[/code] when any weapon can roll it, or in
## [code]prefixes/weapons/<weapon_type>/[/code] when only that type can; the content test checks
## the folder against [member weapon_types]. The deltas apply as modifiers sourced to the prefix,
## so breakdowns name it. Which weapons roll prefixes, from which sources and with what odds is
## not in the vision yet; nothing in the MVP's first content rolls one.
##
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## Quality tier, from +2 (strongest) to -2. 0 is not a prefix tier.
@export_range(-2, 2) var tier: int = 1

## Weapon types that can roll it, from [constant ContentIds.WEAPON_TYPES].
## [b]Empty:[/b] every weapon type.
@export var weapon_types: PackedStringArray = []

## For a prefix staves can roll: the staff kinds it fits, from [constant ContentIds.STAFF_KINDS]
## (a Hit prefix is useless on a Block staff). [b]Empty:[/b] every staff kind.
@export var staff_kinds: PackedStringArray = []

@export_group("Deltas")

## Change to [member WeaponDefinition.damage].[br]
## [b]Units:[/b] HP. [b]0:[/b] none.
@export_range(-10, 10) var damage_delta: int = 0

## Change to [member WeaponDefinition.hit].[br]
## [b]Units:[/b] Hit percent. [b]0:[/b] none.
@export_range(-50, 50) var hit_delta: int = 0

## Change to [member WeaponDefinition.crit].[br]
## [b]Units:[/b] crit percent. [b]0:[/b] none.
@export_range(-50, 50) var crit_delta: int = 0

## Change to [member WeaponDefinition.crit_x]. [b]0:[/b] none.
@export_range(-3.0, 3.0, 0.5) var crit_x_delta: float = 0.0

## Change to [member WeaponDefinition.atk_x]. [b]0:[/b] none.
@export_range(-2, 2) var atk_x_delta: int = 0

## Change to [member ItemDefinition.weight]; negative makes the weapon lighter.[br]
## [b]Units:[/b] weight points. [b]0:[/b] none.
@export_range(-10, 10) var weight_delta: int = 0

# ASSUMPTION: a range prefix changes the longest range only; the plan names "range" without saying
# which end, and the vision has no weapon prefix rules yet.
## Change to [member WeaponDefinition.range_max].[br]
## [b]Units:[/b] tiles. [b]0:[/b] none.
@export_range(-3, 3) var range_max_delta: int = 0

@export_group("")


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "weapon_types":
		ContentIds.apply_hint(property, ContentIds.WEAPON_TYPES)
	elif property["name"] == "staff_kinds":
		ContentIds.apply_hint(property, ContentIds.STAFF_KINDS)
