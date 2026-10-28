# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     terrain_definition.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name TerrainDefinition
extends Resource
## One kind of terrain: what each movement type pays to enter it, and what it gives a unit
## standing on it.
##
## Content data, read-only at runtime. The values are unit-roster.md's terrain table. A map's
## terrain layer names a terrain by [member id], and the definition lives at
## [code]res://data/terrain/<id>.tres[/code]; [MapLoader] copies its values into the map's
## [MapLayout], so no rules code ever holds this resource.
##
## @tutorial(Unit roster, Movement and tags): docs/design/unit-roster.md

## The cost meaning "can't enter" ("—" in unit-roster.md's table).
const IMPASSABLE: int = 0

## The id a map's terrain layer uses for this terrain, and the file name under
## [code]res://data/terrain/[/code]. Lowercase with underscores, such as [code]wooded_knoll[/code].
@export var id: String = ""

## The name shown to the player, such as "Wooded Knoll".
@export var display_name: String = ""

@export_group("Movement cost")

## Movement points a Default unit pays to enter this tile.[br]
## [b]0:[/b] Default units can't enter or stand here.
@export_range(0, 9) var cost_default: int = 1

## Movement points a Heavy unit pays to enter this tile.[br]
## [b]0:[/b] Heavy units can't enter or stand here.
@export_range(0, 9) var cost_heavy: int = 1

## Movement points a Mobile unit pays to enter this tile.[br]
## [b]0:[/b] Mobile units can't enter or stand here.
@export_range(0, 9) var cost_mobile: int = 1

## Movement points a Mounted unit pays to enter this tile.[br]
## [b]0:[/b] Mounted units can't enter or stand here.
@export_range(0, 9) var cost_mounted: int = 1

## Movement points a Flier pays to enter this tile.[br]
## [b]0:[/b] fliers can't enter or stand here.
@export_range(0, 9) var cost_flier: int = 1

@export_group("Standing bonuses")

## Added to the avoid of a defender standing here. Terrain and effects are the only sources of
## avoid.[br]
## [b]Units:[/b] Hit percent. Negative values (a pit) make the defender easier to hit.
@export_range(-100, 100) var avoid: int = 0

## Added to Physical mitigation for a unit standing here (half of it against Split damage).
@export_range(0, 20) var defense: int = 0

## Added to Magic mitigation for a unit standing here (half of it against Split damage).
@export_range(0, 20) var resistance: int = 0

## HP healed at its side's Phase Start for a unit standing here.[br]
## [b]0:[/b] no flat healing. Adds to [member heal_percent] if both are set.
@export_range(0, 99) var heal_flat: int = 0

## Percent of maximum HP healed at its side's Phase Start for a unit standing here.[br]
## [b]0:[/b] no percent healing.
@export_range(0, 100) var heal_percent: int = 0

@export_group("Shove")

## What stops a shoved unit at this tile.[br]
## [b]NONE:[/b] nothing beyond the movement costs: a unit that can't stand here stops before it.
## [b]SPIKED_WALL:[/b] every shove stops, and the shoved unit takes spike damage. [b]PLAIN[/b]
## stops every unit, fliers included, so walls fliers cross stay [b]NONE[/b].
@export var blocker: CombatGrid.Blocker = CombatGrid.Blocker.NONE

## Whether a shoved unit landing here keeps sliding in the same direction (spilled oil).
@export var is_slick: bool = false

@export_group("")


## Movement points [param movement_type] pays to enter this tile; [constant IMPASSABLE] when it
## can't.
func cost(movement_type: CombatGrid.MovementType) -> int:
	return costs()[movement_type]


## Every movement type's cost, indexed by [enum CombatGrid.MovementType].
func costs() -> PackedInt32Array:
	return PackedInt32Array([cost_default, cost_heavy, cost_mobile, cost_mounted, cost_flier])
