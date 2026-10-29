# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     faction_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name FactionDefinition
extends EffectCarrierDefinition
## A player faction: its commander, fixed starting army and max army size (game-vision.md, Run
## structure; content catalog plan, question 10).
##
## Lives in [code]res://data/factions/[/code]. The run start reads it to build the army. Every id
## it names must exist in the catalog; the content test checks them.
##
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## Content id of the commander's unit type, such as [code]drengr[/code]; it must be a commander.
@export var commander_id: String = ""

## Content ids of the starting army's unit types, the commander not included, such as the
## Mercenary's Hakkapel, Archer and Battle Medic. A type may appear more than once.
@export var starting_unit_type_ids: PackedStringArray = []

# ASSUMPTION: gear is listed per starting unit, by index, in slot order; the plan says "with their
# gear" without a shape, and a unit with no entry carries only its type's starting weapon.
## Each starting unit's gear, at the same index as [member starting_unit_type_ids]: item content
## ids for the Weapon, Equipment and Pouch slots, [code]""[/code] for an empty slot.
@export var starting_gear: Array[PackedStringArray] = []

## The army's size limit at run start, commander included. Heirlooms and events raise it, never
## past the hard ceiling of 8.[br]
## [b]Units:[/b] units. The Mercenary's is 4, and it starts full.
@export_range(1, 8) var max_army_size: int = 4
