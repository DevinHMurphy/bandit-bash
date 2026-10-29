# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     staff_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name StaffDefinition
extends WeaponDefinition
## A staff: a weapon of type [code]staff[/code], used as the unit's action (weapons.md, Staves).
##
## Lives in [code]res://data/items/weapons/staff/[/code]. Block and heal staves give
## [member base_amount] plus Might; attack staves (Harm, Ruin) attack with the weapon fields and
## never counter. A holder of any staff never counters. [member WeaponDefinition.range_min] 0
## targets the user (Everwall).
##
## @tutorial(Weapons, Staves): docs/design/weapons.md

## What the staff does, from [constant ContentIds.STAFF_KINDS]. Status staves are stubs.
@export var staff_kind: String = ""

## Block or HP a Block or heal staff gives before Might, such as 3 for Shelter. Attack staves use
## [member WeaponDefinition.damage] instead and leave this 0.[br]
## [b]Units:[/b] Block or HP.
@export_range(0, 30, 1, "or_greater") var base_amount: int = 0

## Content id of the [TargetShape] it covers around its target, or around its user at range 0,
## such as Sanctuary's adjacent allies. [b]Empty:[/b] the target only.
@export var area_shape_id: String = ""

## Uses per map, refilled at the start of every combat.[br]
## [b]0:[/b] unlimited, as on Shelter and the everyday Block staves.
@export_range(0, 9, 1, "or_greater") var uses: int = 0


func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property["name"] == "staff_kind":
		ContentIds.apply_hint(property, ContentIds.STAFF_KINDS)
