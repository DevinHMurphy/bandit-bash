# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_prefix_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name UnitPrefixDefinition
extends EffectCarrierDefinition
## A unit prefix, shown before the unit type ("Sturdy Lancer"): a permanent shift of a few stats
## and their growths in the same direction (unit-roster.md, Prefixes).
##
## Lives in [code]res://data/prefixes/units/[/code]. A recruit rolls one, or none, which is the
## baseline. The deltas apply as modifiers sourced to the prefix, so breakdowns name it. Prefixes
## never touch MOV or CON, and never take a stat or growth below 0. Commanders never roll one.
##
## @tutorial(Unit roster, Prefixes): docs/design/unit-roster.md

## Quality tier, from +2 (strongest) to -2; the UI colors the name by it. No prefix is the
## baseline, so 0 is not a prefix tier.
@export_range(-2, 2) var tier: int = 1

## Stat changes, by [enum CombatValue.Stat] (HP, MGT, SPD, DEF, RES only).[br]
## [b]Units:[/b] stat points; negative lowers. [b]Empty:[/b] none.
@export var stat_deltas: Dictionary[CombatValue.Stat, int] = {}

## Growth changes, by [enum CombatValue.Stat] (HP, MGT, SPD, DEF, RES only).[br]
## [b]Units:[/b] percentage points (15 is +15%). [b]Empty:[/b] none.
@export var growth_deltas: Dictionary[CombatValue.Stat, int] = {}

## Hit change, which is not a stat (Keen's +20).[br]
## [b]Units:[/b] Hit percent. [b]0:[/b] none.
@export_range(-50, 50) var hit_delta: int = 0
