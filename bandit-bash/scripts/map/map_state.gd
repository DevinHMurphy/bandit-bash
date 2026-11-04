# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_state.gd
# Author:
# Created:  October 27, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name MapState
extends RefCounted
## The parts of one map that change during a combat: its map objects, which tiles they block, the
## containers' contents, the loot taken from them, its reinforcement points and their waves, the
## enemies marked as leaders, whether the opening swap window is open, and the darkness.
##
## Held by [CombatState] as [member CombatState.map] and copied with it for a sandbox, so a
## forecast that opens a door or breaks a keg never touches the real map. [MapGrid] stays
## terrain-only and shared. Movement asks this state whether an object stops a unit; standing on an
## object's tile is decided by occupancy, as for units. [MapObjects] and [Reinforcements] change it
## and record the facts. Plain data with ids only.[br]
## [b]Saves and mirrors:[/b] [method capture] and [method restore] carry it as plain JSON in two
## parts, [code]entities[/code] (the objects, contents and loot) and [code]combat_map[/code] (the
## points, flags and leader marks), for [method CombatSession.snapshot] and the [CombatMapSection]
## pair. A breakable's HP is its unit's, in [method CombatState.capture]. A mirror follows the
## objects and points through [method CombatState.follow]. [member darkness] is in neither.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md
## @tutorial(Save system design): docs/design/save-system.md
##
## @todo: TOD-001 - Save and restore [member darkness] in its own COMBAT section, version 1
## (darkness plan question 6); a snapshot or Save & Quit loses it until then.

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

## Every reinforcement point on the map, by point index ([member MapLayout.Marker.index]), with
## its waves ([method Reinforcements.load_waves]).
var points: Dictionary[int, PointState] = {}

## Whether every wave not yet arrived is cancelled: Rout's win ([method Reinforcements.cancel]).
var are_waves_cancelled: bool = false

## Whether the darkness has arrived, so no reinforcement point sends again; read only through
## [method Reinforcements.has_darkness_arrived]. The darkness step sets it at the first release
## ([method Darkness.advance]).
var has_darkness_arrived: bool = false

# TODO(TOD-001): Carry it in saves and snapshots (darkness plan question 6).
## The darkness on this map: sources, drain, waves, layers and contacts. Copied for a sandbox, so
## [method CombatState.darkness_layer] answers the same in a forecast. Never null.
var darkness: DarknessState = DarknessState.new()

## Enemies marked as leaders before the battle was last loaded: those that appeared on a leader
## slot. Read only through [method Objectives.marked_ids], which adds the ones whose arrival is in
## the fact log since.
var leader_ids: PackedStringArray = []

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
	for point_index: int in points:
		map_copy.points[point_index] = points[point_index].copy()
	map_copy.are_waves_cancelled = are_waves_cancelled
	map_copy.has_darkness_arrived = has_darkness_arrived
	map_copy.darkness = darkness.copy()
	map_copy.leader_ids = leader_ids.duplicate()
	return map_copy


## This state as plain JSON values in two parts: [code]entities[/code] (every object by spot index
## with its state, kind by name and tile as [code][x, y][/code]; contents by container index; the
## loot found, by seat; the loot carried, by unit id) and [code]combat_map[/code] (every point by
## index with its waves, how many arrived and its waiting units; the flags; [member leader_ids]).
## Keys are written in order, so equal states write equal text. [method restore] reverses it.
func capture() -> Dictionary:
	var object_list: Array = []
	for object_id: String in _sorted_ids():
		object_list.append(_capture_object(objects[object_id]))
	var by_container: Dictionary = {}
	var containers: Array[int] = contents.keys()
	containers.sort()
	for container_index: int in containers:
		by_container[str(container_index)] = _plain(contents[container_index])
	var by_seat: Dictionary = {}
	var seats: Array[int] = found.keys()
	seats.sort()
	for seat: int in seats:
		by_seat[str(seat)] = _plain(found[seat])
	var by_unit: Dictionary = {}
	var carriers: Array[String] = carried.keys()
	carriers.sort()
	for unit_id: String in carriers:
		by_unit[unit_id] = _plain(carried[unit_id])
	var point_list: Array = []
	var point_indexes: Array[int] = points.keys()
	point_indexes.sort()
	for point_index: int in point_indexes:
		point_list.append(_capture_point(points[point_index]))
	return {
		"entities": {
			"objects": object_list,
			"contents": by_container,
			"found": by_seat,
			"carried": by_unit,
		},
		"combat_map": {
			"points": point_list,
			"are_waves_cancelled": are_waves_cancelled,
			"has_darkness_arrived": has_darkness_arrived,
			"opening_swap_open": opening_swap_open,
			"leader_ids": Array(leader_ids),
		},
	}


## Replaces everything [method capture] holds with [param data], also after a trip through JSON,
## where whole numbers in loot and waves come back as ints. What each object blocks is rebuilt
## from its state: a closed door every unit, an unbroken breakable every unit but fliers. Returns
## [constant OK], or [constant ERR_INVALID_DATA], changing nothing, when a part is missing or
## malformed or an object, point or container repeats.
func restore(data: Dictionary) -> Error:
	var entities: Variant = data.get("entities", null)
	var map_part: Variant = data.get("combat_map", null)
	if not entities is Dictionary or not map_part is Dictionary:
		return ERR_INVALID_DATA
	var object_data: Variant = (entities as Dictionary).get("objects", null)
	var content_data: Variant = (entities as Dictionary).get("contents", null)
	var found_data: Variant = (entities as Dictionary).get("found", null)
	var carried_data: Variant = (entities as Dictionary).get("carried", null)
	var point_data: Variant = (map_part as Dictionary).get("points", null)
	var leader_data: Variant = (map_part as Dictionary).get("leader_ids", null)
	var flags: Array[bool] = []
	for flag: String in ["are_waves_cancelled", "has_darkness_arrived", "opening_swap_open"]:
		var value: Variant = (map_part as Dictionary).get(flag, null)
		if not value is bool:
			return ERR_INVALID_DATA
		flags.append(value as bool)
	if (
			not object_data is Array
			or not content_data is Dictionary
			or not found_data is Dictionary
			or not carried_data is Dictionary
			or not point_data is Array
			or not leader_data is Array
	):
		return ERR_INVALID_DATA
	# Untyped: the parts come from JSON and are checked entry by entry.
	var restored_objects: Dictionary[String, ObjectState] = {}
	var indexes: Dictionary[int, bool] = {}
	for entry: Variant in object_data:
		var restored: ObjectState = (
				_object_from(entry as Dictionary) if entry is Dictionary else null
		)
		if restored == null or restored_objects.has(restored.id) or indexes.has(restored.index):
			return ERR_INVALID_DATA
		restored_objects[restored.id] = restored
		indexes[restored.index] = true
	var restored_contents: Dictionary[int, Variant] = {}
	for key: Variant in content_data:
		if not str(key).is_valid_int():
			return ERR_INVALID_DATA
		restored_contents[str(key).to_int()] = _plain((content_data as Dictionary)[key])
	var restored_found: Dictionary[int, Array] = {}
	for key: Variant in found_data:
		var loot: Variant = (found_data as Dictionary)[key]
		if not str(key).is_valid_int() or not loot is Array:
			return ERR_INVALID_DATA
		restored_found[str(key).to_int()] = _plain(loot) as Array
	var restored_carried: Dictionary[String, Array] = {}
	for key: Variant in carried_data:
		var loot: Variant = (carried_data as Dictionary)[key]
		if not key is String or not loot is Array:
			return ERR_INVALID_DATA
		restored_carried[key as String] = _plain(loot) as Array
	var restored_points: Dictionary[int, PointState] = {}
	for entry: Variant in point_data:
		var restored_point: PointState = (
				_point_from(entry as Dictionary) if entry is Dictionary else null
		)
		if restored_point == null or restored_points.has(restored_point.index):
			return ERR_INVALID_DATA
		restored_points[restored_point.index] = restored_point
	var leaders: PackedStringArray = []
	for leader_id: Variant in leader_data:
		if not leader_id is String:
			return ERR_INVALID_DATA
		leaders.append(leader_id as String)

	objects = restored_objects
	contents = restored_contents
	found = restored_found
	carried = restored_carried
	points = restored_points
	are_waves_cancelled = flags[0]
	has_darkness_arrived = flags[1]
	opening_swap_open = flags[2]
	leader_ids = leaders
	_blocking.clear()
	for object_id: String in objects:
		var placed: ObjectState = objects[object_id]
		if placed.kind == MapLayout.ObjectKind.DOOR and not placed.is_open:
			set_blocking(placed.tile, Blocking.ALL)
		elif MapObjects.BREAKABLE_STATS.has(placed.kind) and not placed.is_destroyed:
			set_blocking(placed.tile, Blocking.ALL_BUT_FLIERS)
	return OK


## The reinforcement point with id [param point_id]; null if there is none.
func point(point_id: String) -> PointState:
	for point_index: int in points:
		if points[point_index].id == point_id:
			return points[point_index]
	return null


# Object ids by spot index, so iteration doesn't depend on insertion order.
func _sorted_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(objects.keys())
	ids.sort_custom(func(a: String, b: String) -> bool:
		return objects[a].index < objects[b].index
	)
	return ids


# value, plain data, deep-copied with every whole float in JSON's exact range turned back into an
# int: JSON reads every number as a float, and loot and waves only ever hold ints, so a restored
# map captures the same text as the one saved.
# NOTE: The same whole-number rule as CombatState._whole; keep them in step.
static func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var copied: Dictionary = {}
		for key: Variant in value:
			copied[key] = _plain((value as Dictionary)[key])
		return copied
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_plain(item))
		return items
	if value is float:
		var number: float = value
		if number == floorf(number) and absf(number) <= CombatFact.MAX_EXACT_JSON_INT:
			return int(number)
	return value


# value as an int when it is one, or a whole float within JSON's exact range; null otherwise.
# NOTE: The same rule as CombatState._whole; keep them in step.
static func _whole(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var number: float = value
	if number != floorf(number) or absf(number) > CombatFact.MAX_EXACT_JSON_INT:
		return null
	return int(number)


# A tile written as [x, y]; NO_TILE when it isn't one.
static func _tile_from(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return CombatFact.NO_TILE
	var x: Variant = _whole((value as Array)[0])
	var y: Variant = _whole((value as Array)[1])
	if x == null or y == null:
		return CombatFact.NO_TILE
	return Vector2i(x as int, y as int)


# The inner classes are captured and read here: an inner class never names its outer one.
# NOTE: A reference back from an inner class to its outer script makes a script cycle, which 4.7.1
# leaks at exit (godotengine/godot#117975; see combat_state_section.gd).
static func _capture_object(placed: ObjectState) -> Dictionary:
	return {
		"id": placed.id,
		"index": placed.index,
		"kind": MapLayout.ObjectKind.find_key(placed.kind) as String,
		"tile": [placed.tile.x, placed.tile.y],
		"group_id": placed.group_id,
		"pair_id": placed.pair_id,
		"container_index": placed.container_index,
		"is_open": placed.is_open,
		"is_lit": placed.is_lit,
		"is_used": placed.is_used,
		"is_destroyed": placed.is_destroyed,
	}


# An object from _capture_object(); null when malformed.
static func _object_from(data: Dictionary) -> ObjectState:
	var id: Variant = data.get("id", null)
	var kind_name: String = str(data.get("kind", ""))
	var numbers: Array = []
	for field: String in ["index", "group_id", "pair_id", "container_index"]:
		numbers.append(_whole(data.get(field, null)))
	var tile: Vector2i = _tile_from(data.get("tile", null))
	if (
			not id is String
			or (id as String).is_empty()
			or not MapLayout.ObjectKind.has(kind_name)
			or numbers.has(null)
			or (numbers[0] as int) < 0
			or tile == CombatFact.NO_TILE
	):
		return null
	for flag: String in ["is_open", "is_lit", "is_used", "is_destroyed"]:
		if not data.get(flag, null) is bool:
			return null
	var placed: ObjectState = ObjectState.new()
	placed.is_open = data["is_open"]
	placed.is_lit = data["is_lit"]
	placed.is_used = data["is_used"]
	placed.is_destroyed = data["is_destroyed"]
	placed.id = id
	placed.index = numbers[0]
	var kind_value: int = MapLayout.ObjectKind[kind_name]
	placed.kind = kind_value as MapLayout.ObjectKind
	placed.tile = tile
	placed.group_id = numbers[1]
	placed.pair_id = numbers[2]
	placed.container_index = numbers[3]
	return placed


static func _capture_point(sender: PointState) -> Dictionary:
	return {
		"id": sender.id,
		"index": sender.index,
		"tile": [sender.tile.x, sender.tile.y],
		"waves": _plain(sender.waves),
		"sent": sender.sent,
		"is_closed": sender.is_closed,
		"waiting": _plain(sender.waiting),
	}


# A point from _capture_point(); null when malformed or when more waves arrived than it has.
static func _point_from(data: Dictionary) -> PointState:
	var id: Variant = data.get("id", null)
	var index: Variant = _whole(data.get("index", null))
	var sent: Variant = _whole(data.get("sent", null))
	var tile: Vector2i = _tile_from(data.get("tile", null))
	var wave_data: Variant = data.get("waves", null)
	var waiting_data: Variant = data.get("waiting", null)
	if (
			not id is String
			or index == null
			or (index as int) < 0
			or sent == null
			or tile == CombatFact.NO_TILE
			or not wave_data is Array
			or not waiting_data is Array
			or not data.get("is_closed", null) is bool
			or (sent as int) < 0
			or (sent as int) > (wave_data as Array).size()
	):
		return null
	var restored: PointState = PointState.new()
	# Untyped: the parts come from JSON and are checked entry by entry.
	for entry: Variant in wave_data:
		if not entry is Dictionary:
			return null
		restored.waves.append(_plain(entry) as Dictionary)
	for entry: Variant in waiting_data:
		if not entry is Dictionary:
			return null
		restored.waiting.append(_plain(entry) as Dictionary)
	restored.id = id
	restored.index = index
	restored.tile = tile
	restored.sent = sent
	restored.is_closed = data["is_closed"]
	return restored


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


## One reinforcement point's state: its waves in arrival order, how many have arrived, and whether
## a player unit closed it ([Reinforcements]).
class PointState:
	extends RefCounted

	## Its id ([method InstanceIdAllocator.point_id]).
	var id: String = ""
	## Its stable point index, [member MapLayout.Marker.index].
	var index: int = -1
	## Where its waves arrive.
	var tile: Vector2i = CombatFact.NO_TILE
	## Its waves, drawn at battle start, by arrival turn: plain data in the shape of
	## [constant Objectives.WAVES_KEY].
	var waves: Array[Dictionary] = []
	## How many of [member waves], from the first, have arrived.
	var sent: int = 0
	## Closed for good by a player unit ending its turn on it.
	var is_closed: bool = false
	## Units of arrived waves that found no free tile, in arrival order: their group entries
	## ([constant Reinforcements.GROUP_KEY]). They try again after the next enemy phase, ahead of
	## that turn's wave, and count as a wave still to come ([method Reinforcements.waves_left]).
	var waiting: Array[Dictionary] = []

	## A copy sharing nothing mutable.
	func copy() -> PointState:
		var state_copy: PointState = PointState.new()
		state_copy.id = id
		state_copy.index = index
		state_copy.tile = tile
		for wave: Dictionary in waves:
			state_copy.waves.append(wave.duplicate(true))
		state_copy.sent = sent
		state_copy.is_closed = is_closed
		for entry: Dictionary in waiting:
			state_copy.waiting.append(entry.duplicate(true))
		return state_copy
