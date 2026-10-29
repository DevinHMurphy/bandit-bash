# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_state.gd
# Author:
# Created:  October 27, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name MapState
extends RefCounted
## The parts of one map that change during a combat: its map objects, which tiles they block, the
## containers' contents, the loot taken from them, and whether the opening swap window is open.
##
## Held by [CombatState] as [member CombatState.map] and copied with it for a sandbox, so a
## forecast that opens a door or breaks a keg never touches the real map. [MapGrid] stays
## terrain-only and shared. Movement asks this state whether an object stops a unit; standing on an
## object's tile is decided by occupancy, as for units. [MapObjects] changes it and records the
## facts. Plain data with ids only.[br]
## [b]Not saved yet:[/b] [member objects], [member contents], [member found] and [member carried]
## join the [code]entities[/code] section in P04 MP8.
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

## Whether the opening swap window is open: before turn 1, when the seat's opening-swap setting
## is on. The command path (P02 CC6) opens it at battle start and the seat's Start command closes
## it; [method AutoDeploy.check_opening_swap] reads it. False with the setting off: no window.
var opening_swap_open: bool = false

## Every map object on the map, by object id ([method InstanceIdAllocator.object_id]).
var objects: Dictionary[String, ObjectState] = {}

## Each container's contents, by [member MapLayout.Marker.container_index]: plain data rolled by
## setup step 7 ([method MapObjects.roll_contents]) from this seat's [code]MAP_LOOT[/code] streams.
## An entry stays after the container is emptied; [member ObjectState.is_used] says it was.
var contents: Dictionary[int, Variant] = {}

## The loot each seat's units took this battle, by seat: the contents they found and what they
## took back from a defeated Cutthroat, in order. The battle-end bridge grants it (P08).
var found: Dictionary[int, Array] = {}

## The loot each Cutthroat carries, by unit id, until it is defeated ([method MapObjects.loot]).
var carried: Dictionary[String, Array] = {}

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


## The object [param object_id]; null if there is none.
func object(object_id: String) -> ObjectState:
	return objects.get(object_id, null)


## The objects on [param tile] that are still there (not destroyed), in object id order.
func objects_at(tile: Vector2i) -> Array[ObjectState]:
	var found_here: Array[ObjectState] = []
	for object_id: String in _sorted_ids():
		var here: ObjectState = objects[object_id]
		if here.tile == tile and not here.is_destroyed:
			found_here.append(here)
	return found_here


## Every object of [param kind], destroyed ones included, in spot index order.
func objects_of(kind: MapLayout.ObjectKind) -> Array[ObjectState]:
	var of_kind: Array[ObjectState] = []
	for object_id: String in _sorted_ids():
		if objects[object_id].kind == kind:
			of_kind.append(objects[object_id])
	return of_kind


## A copy sharing nothing mutable, for a sandbox.
func copy() -> MapState:
	var map_copy: MapState = MapState.new()
	map_copy.opening_swap_open = opening_swap_open
	map_copy._blocking = _blocking.duplicate()
	for object_id: String in objects:
		map_copy.objects[object_id] = objects[object_id].copy()
	map_copy.contents = contents.duplicate(true)
	for seat: int in found:
		map_copy.found[seat] = found[seat].duplicate(true)
	for unit_id: String in carried:
		map_copy.carried[unit_id] = carried[unit_id].duplicate(true)
	return map_copy


# Object ids by spot index, so iteration doesn't depend on insertion order.
func _sorted_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(objects.keys())
	ids.sort_custom(func(a: String, b: String) -> bool:
		return objects[a].index < objects[b].index
	)
	return ids


## One map object's state. Breakables (debris, powder kegs) are also units of side
## [constant CombatFact.CombatSide.NONE] in [CombatState], which holds their HP.
class ObjectState:
	extends RefCounted

	## Its instance id ([method InstanceIdAllocator.object_id]).
	var id: String = ""
	## Its stable spot index, [member MapLayout.Marker.index].
	var index: int = -1
	## What it is.
	var kind: MapLayout.ObjectKind = MapLayout.ObjectKind.NONE
	## Where it stands.
	var tile: Vector2i = CombatFact.NO_TILE
	## A door's or lever's lever group; -1 for none.
	var group_id: int = -1
	## A passage end's pair; -1 for none.
	var pair_id: int = -1
	## A container's [code]MAP_LOOT[/code] index; -1 when not one.
	var container_index: int = -1
	## A door: open.
	var is_open: bool = false
	## A brazier: lit.
	var is_lit: bool = false
	## A chest opened or a searchable searched: its contents are gone.
	var is_used: bool = false
	## A breakable broken: it is off the map and its tile is clear.
	var is_destroyed: bool = false

	## A copy sharing nothing mutable.
	func copy() -> ObjectState:
		var state_copy: ObjectState = ObjectState.new()
		state_copy.id = id
		state_copy.index = index
		state_copy.kind = kind
		state_copy.tile = tile
		state_copy.group_id = group_id
		state_copy.pair_id = pair_id
		state_copy.container_index = container_index
		state_copy.is_open = is_open
		state_copy.is_lit = is_lit
		state_copy.is_used = is_used
		state_copy.is_destroyed = is_destroyed
		return state_copy
