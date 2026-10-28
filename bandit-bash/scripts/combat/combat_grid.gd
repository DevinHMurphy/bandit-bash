# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_grid.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

@abstract
class_name CombatGrid
extends RefCounted
## The map's terrain as the combat rules see it: distances, movement costs, walls, never units or
## map objects.
##
## The narrow interface between the combat core and the maps plan (P04): [MapGrid] implements it,
## the combat core's tests use a stub. Anything that changes during a combat lives in
## [CombatState]: occupancy, and map objects in its [member CombatState.map]. So the questions
## that depend on them are [CombatState]'s ([method CombatState.can_stand],
## [method CombatState.blocker_at], [method CombatState.validate_path]), and rules code asks it
## rather than the grid.[br]
## [b]Pure and shared:[/b] a sandbox copy of [CombatState] keeps the same grid, so rules code
## never changes a grid.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

## How a unit crosses terrain (unit-roster.md, Movement and tags). [b]Append only[/b], with
## explicit values.
enum MovementType {
	## Most units on foot.
	DEFAULT = 0,
	## Armored units, slowed most in rough terrain.
	HEAVY = 1,
	## Light, quick units.
	MOBILE = 2,
	## Riders.
	MOUNTED = 3,
	## Fliers cross everything except doors.
	FLIER = 4,
}

## What stands in the way of a shoved unit on a tile. [b]Append only[/b], with explicit values.
enum Blocker {
	## Nothing: the tile can be entered, terrain permitting.
	NONE = 0,
	## A unit. The grid never answers this; [method CombatState.blocker_at] does, from occupancy.
	UNIT = 1,
	## A wall, a door or a map object: a shove stops, with no damage.
	PLAIN = 2,
	## A spiked wall: a shove stops and the shoved unit takes spike damage.
	SPIKED_WALL = 3,
}

## The four orthogonal directions, in a fixed order: right, down, left, up.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]


## Tiles up plus tiles across between [param a] and [param b], ignoring walls and terrain: weapon
## range, "within N tiles" and "no ally closer".
func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## The tiles orthogonally next to [param tile] that are on the map, in [constant DIRECTIONS]
## order.
func neighbors(tile: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		var next: Vector2i = step(tile, direction)
		if next != CombatFact.NO_TILE:
			found.append(next)
	return found


## The terrain cost of walking [param path] for [param movement_type]: the sum of
## [method move_cost] over every tile after the first. Units and objects are not counted;
## [method CombatState.validate_path] checks those.
## Returns -1 when a step isn't to an orthogonal neighbor on the map, or enters a tile
## [param movement_type] can't.
func path_cost(path: Array[Vector2i], movement_type: MovementType) -> int:
	var total: int = 0
	for i: int in range(1, path.size()):
		var cost: int = move_cost(path[i], movement_type)
		if distance(path[i - 1], path[i]) != 1 or cost <= 0:
			return -1
		total += cost
	return total


## Movement points [param movement_type] pays to enter [param tile], terrain only; 0 when it
## can't enter it or the tile is off the map.
@abstract func move_cost(tile: Vector2i, movement_type: MovementType) -> int


## The tile one step from [param tile] in [param direction] (one of [constant DIRECTIONS]), or
## [constant CombatFact.NO_TILE] off the map.
@abstract func step(tile: Vector2i, direction: Vector2i) -> Vector2i


## Whether a unit of [param movement_type] may stand on [param tile]; false off the map.
@abstract func can_stand(tile: Vector2i, movement_type: MovementType) -> bool


## What terrain or object blocks [param tile]: never [constant Blocker.UNIT]. Off the map counts
## as [constant Blocker.PLAIN].
@abstract func blocker_at(tile: Vector2i) -> Blocker


## Whether [param tile] is slick (spilled oil): a shoved unit landing there keeps sliding.
@abstract func is_slick(tile: Vector2i) -> bool


## The terrain bonuses of [param tile]: avoid, DEF, RES and Phase Start healing.
@abstract func tile_bonus(tile: Vector2i) -> TileBonus


## A tile's terrain bonuses (unit-roster.md, the terrain table). All 0 on plain ground.
class TileBonus:
	extends RefCounted

	## Added to a defender's avoid on this tile. [b]Units:[/b] Hit percent.
	var avoid: int = 0
	## Added to Physical mitigation on this tile (half of it for Split damage).
	var defense: int = 0
	## Added to Magic mitigation on this tile (half of it for Split damage).
	var resistance: int = 0
	## HP healed at its side's Phase Start on this tile.
	var heal_flat: int = 0
	## Percent of maximum HP healed at its side's Phase Start on this tile.
	var heal_percent: int = 0


## The answer of [method CombatState.validate_path].
class PathCheck:
	extends RefCounted

	## Whether the path is legal.
	var is_legal: bool = false
	## Why it isn't; empty when it is.
	var reason: String = ""
	## Steps taken: the path's length less its first tile.
	var tiles_moved: int = 0
	## Movement cost spent, against the unit's [constant CombatValue.Key.MOVEMENT].
	var cost: int = 0
