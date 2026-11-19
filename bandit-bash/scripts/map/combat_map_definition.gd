# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_map_definition.gd
# Author:
# Created:  October 27, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name CombatMapDefinition
extends Resource
## One hand-authored combat map's rules data: its scene, combat type, pool, objective, turn par
## and, for a scripted map, its fixed enemies.
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

## A scripted map's enemies: the pack, by content id, setup places as it is instead of drawing one
## ([method EnemySetup.draw]), its units in the enemy slots in order and its leader on the leader
## slot, as the boss map's are (game-vision.md, Combat maps). [b]Empty:[/b] setup draws a pack.
@export var fixed_pack_id: String = ""

## The level of a scripted map's units other than its leader, before the difficulty ladder's
## modifier. [b]Units:[/b] levels. [b]0:[/b] the floor's step sets it, as on drawn maps.
@export_range(0, 20) var fixed_enemy_level: int = 0

## The level of a scripted map's leader (the boss), before the difficulty ladder's modifier.
## [b]Units:[/b] levels. [b]0:[/b] the leader's usual level, its step's +2.
@export_range(0, 20) var fixed_leader_level: int = 0

## The prefix a scripted map's leader carries, by content id, such as the Powder Baron's
## [code]stalwart[/code]. [b]Empty:[/b] a positive prefix drawn as for any elite.
@export var fixed_leader_prefix_id: String = ""
