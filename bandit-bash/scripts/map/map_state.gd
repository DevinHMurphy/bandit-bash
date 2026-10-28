# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_state.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name MapState
extends RefCounted
## The parts of one map that change during a combat: which tiles map objects block.
##
## Held by [CombatState] as [member CombatState.map] and copied with it for a sandbox, so a
## forecast that opens a door never opens the real one. [MapGrid] stays terrain-only and shared.
## Movement asks this state whether an object stops a unit; standing on an object's tile is
## decided by occupancy, as for units. Plain data with no ids of nodes or Resources.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

## Which units an object on a tile stops (map-objects.md). Saved as an int: [b]append only[/b].
enum Blocking {
	## Nothing: the tile's terrain decides.
	NONE = 0,
	## Every unit, fliers included: a closed door.
	ALL = 1,
	## Every unit except fliers: debris and powder kegs.
	ALL_BUT_FLIERS = 2,
}

var _blocking: Dictionary[Vector2i, Blocking] = {}


## Sets what the object on [param tile] blocks; [constant Blocking.NONE] clears it (a door opened,
## debris destroyed).
func set_blocking(tile: Vector2i, blocking: Blocking) -> void:
	if blocking == Blocking.NONE:
		_blocking.erase(tile)
	else:
		_blocking[tile] = blocking


## What the object on [param tile] blocks; [constant Blocking.NONE] when nothing does.
func blocking_at(tile: Vector2i) -> Blocking:
	return _blocking.get(tile, Blocking.NONE)


## Whether an object on [param tile] stops a unit of [param movement_type] entering it.
func blocks(tile: Vector2i, movement_type: CombatGrid.MovementType) -> bool:
	match blocking_at(tile):
		Blocking.ALL:
			return true
		Blocking.ALL_BUT_FLIERS:
			return movement_type != CombatGrid.MovementType.FLIER
	return false


## A copy sharing nothing mutable, for a sandbox.
func copy() -> MapState:
	var map_copy: MapState = MapState.new()
	map_copy._blocking = _blocking.duplicate()
	return map_copy
