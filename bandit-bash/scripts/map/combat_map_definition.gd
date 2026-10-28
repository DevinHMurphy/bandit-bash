# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_map_definition.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name CombatMapDefinition
extends Resource
## One hand-authored combat map's rules data: its scene, combat type, pool, objective and turn par.
##
## Content data, read-only at runtime. The scene holds the painted terrain and marker layers;
## this resource holds everything that isn't painted. [MapLoader] turns the pair into a pure
## [MapLayout] at battle start.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

## Which kind of combat the map is drawn for. Saved as an int: [b]append only[/b].
enum CombatType {
	## An ordinary combat node.
	STANDARD = 0,
	## A key combat, with mini-bosses.
	KEY = 1,
	## A boss combat.
	BOSS = 2,
}

## How the combat is won. Saved as an int: [b]append only[/b].
enum Objective {
	## No enemy is left on the map; waves not yet arrived are cancelled.
	ROUT = 0,
	## The enemy on the leader slot is defeated.
	DEFEAT_LEADER = 1,
	## The mini-boss or boss is defeated.
	DEFEAT_BOSS = 2,
	## A player unit ends its turn on the seize tile.
	SEIZE = 3,
	## The enemy phase of turn [member survive_turns] ends.
	SURVIVE = 4,
	## As [constant SURVIVE], but lost when an enemy ends its turn on the defend tile.
	DEFEND = 5,
}

## The map's id in saves and logs, such as [code]m1_greybox[/code]. Unique across every map.
@export var id: String = ""

## The map scene: a [TileMapLayer] named Terrain and the marker layers ([MapLoader]).[br]
## [b]Unset:[/b] the map can't load; [method MapLoader.load_layout] reports it and returns null.
@export var scene: PackedScene = null

## Which kind of combat the map is drawn for.
@export var combat_type: CombatType = CombatType.STANDARD

# ASSUMPTION: a pool is a name shared by the maps one node can draw from; the plan names pools
# per combat type but no format for them.
## The pool this map belongs to; maps with the same combat type and pool are drawn from together.
## [b]Empty:[/b] the combat type's default pool.
@export var pool: String = ""

## How the combat is won.
@export var objective: Objective = Objective.ROUT

## Turns a good clear takes, for the combat's grade. Set by hand for each map.[br]
## [b]Units:[/b] turns. [b]0:[/b] not set yet.
@export_range(0, 99) var turn_par: int = 0

## For [constant Objective.SURVIVE] and [constant Objective.DEFEND]: the turn whose enemy phase
## ends the combat. Ignored by the other objectives.[br]
## [b]Units:[/b] turns. [b]0:[/b] not set yet.
@export_range(0, 99) var survive_turns: int = 0
