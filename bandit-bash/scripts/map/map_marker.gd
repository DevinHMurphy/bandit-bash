# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_marker.gd
# Author:
# Created:  October 28, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name MapMarker
extends Node2D
## A marker that carries parameters, placed in a map scene as a node and snapped to the grid.
##
## Plain markers are tiles on a marker layer ([MapLoader]); a marker with parameters is a
## [MapMarker] instead. Its tile is the terrain layer's cell under its position, and in the editor
## it snaps to that cell's center whenever it moves. [MapLoader] reads every [MapMarker] in the
## scene, at any depth under [Node2D] parents, into the same [MapLayout.Marker]s as the marker
## layers, so a marker's stable id is the same whichever way it was authored. A door marker covers
## [member door_size] tiles and becomes one door marker per tile.[br]
## Authoring data only: nothing here runs in a battle. The loader reads the exports and frees the
## scene. Each kind reads only its own exports. A reinforcement point may also be a plain marker
## tile, which has no arrival turns.
##
## @tutorial(Combat map plan, Authoring and loading): docs/plans/2026-10-27-combat-map.md

## What the marker marks, each one [enum MapLayout.MarkerKind] ([constant LAYOUT_KINDS]), and for
## an object spot one [enum MapLayout.ObjectKind] ([constant OBJECT_KINDS]). Saved as an int in
## map scenes: [b]append only[/b].
enum Kind {
	## A tile an enemy may be placed on, with its position variance and group slot.
	ENEMY_SLOT = 0,
	## A door of [member door_size] tiles, in lever group [member group_id] or none.
	DOOR = 1,
	## A lever toggling the doors of lever group [member group_id].
	LEVER = 2,
	## One end of passage pair [member pair_id].
	PASSAGE = 3,
	## A reinforcement point, sending a wave on each of its [member arrival_turns].
	REINFORCEMENT_POINT = 4,
}

## The layout marker kind of each [enum Kind].
const LAYOUT_KINDS: Dictionary[Kind, MapLayout.MarkerKind] = {
	Kind.ENEMY_SLOT: MapLayout.MarkerKind.ENEMY_SLOT,
	Kind.DOOR: MapLayout.MarkerKind.OBJECT_SPOT,
	Kind.LEVER: MapLayout.MarkerKind.OBJECT_SPOT,
	Kind.PASSAGE: MapLayout.MarkerKind.OBJECT_SPOT,
	Kind.REINFORCEMENT_POINT: MapLayout.MarkerKind.REINFORCEMENT_POINT,
}

## The object of each [enum Kind] that marks an object spot.
const OBJECT_KINDS: Dictionary[Kind, MapLayout.ObjectKind] = {
	Kind.DOOR: MapLayout.ObjectKind.DOOR,
	Kind.LEVER: MapLayout.ObjectKind.LEVER,
	Kind.PASSAGE: MapLayout.ObjectKind.PASSAGE,
}

# The editor drawing: each kind's fill, the variance outline, and a marker's radius in tiles.
const _KIND_COLORS: Dictionary[Kind, Color] = {
	Kind.ENEMY_SLOT: Color(1.0, 0.45, 0.1, 0.85),
	Kind.DOOR: Color(0.45, 0.25, 0.1, 0.6),
	Kind.LEVER: Color(0.7, 0.7, 0.7, 0.85),
	Kind.PASSAGE: Color(0.25, 0.75, 0.65, 0.85),
	Kind.REINFORCEMENT_POINT: Color(0.85, 0.15, 0.2, 0.85),
}
const _VARIANCE_COLOR: Color = Color(1.0, 0.45, 0.1, 0.5)
const _SLOT_RADIUS: float = 0.3

## What the marker marks.
@export var kind: Kind = Kind.ENEMY_SLOT:
	set(value):
		kind = value
		if is_node_ready():
			queue_redraw()

# ASSUMPTION: grid distance (plan question 12), not Godot_FE's movement-cost range.
## An enemy slot's position variance: at setup its enemy may be placed this far from the marker's
## tile instead of on it, on a tile it can stand on (P05 draws which).[br]
## [b]Units:[/b] tiles, grid distance. [b]0:[/b] the enemy is always placed on this tile.
@export_range(0, 9) var variance_tiles: int = 0:
	set(value):
		variance_tiles = value
		if is_node_ready():
			queue_redraw()

# ASSUMPTION: a group slot is a name, as Godot_FE's unit_group letters; P05 owns groups.
## An enemy slot's group slot: slots with the same name are filled from one of the map's enemy
## groups (P05), such as [code]A[/code] or [code]B[/code].[br]
## [b]Empty:[/b] the slot belongs to no group; P05 decides what fills it.
@export var group_slot: String = ""

## A door's or lever's lever group: pulling a lever toggles every door with its group id
## ([method MapObjects.use]).[br]
## [b]-1:[/b] no group. A door opens only with a key or lockpick; a lever fails [MapCheck].
@export_range(-1, 99) var group_id: int = -1

## A passage end's pair: a unit on one end can use it to arrive at the other end with the same id.
## [br][b]-1:[/b] no pair, which fails [MapCheck]. Exactly two ends share an id.
@export_range(-1, 99) var pair_id: int = -1

## A door's size: the tiles it covers, counted right (x) and down (y) from the marker's tile. The
## tiles open and close as one door.[br]
## [b]Units:[/b] tiles. [b](1, 1):[/b] a one-tile door. A value below 1 counts as 1.
@export var door_size: Vector2i = Vector2i.ONE:
	set(value):
		door_size = value
		if is_node_ready():
			queue_redraw()

## A reinforcement point's arrival turns: one wave each, arriving after that turn's enemy phase
## ([Reinforcements]); its group is drawn at battle start. Order doesn't matter; a turn listed
## twice sends two waves.[br]
## [b]Units:[/b] turns. [b]Empty:[/b] the point never sends, so it counts as closed.
@export_range(1, 99) var arrival_turns: Array[int] = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	set_notify_local_transform(true)
	_snap_to_grid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_snap_to_grid()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var terrain: TileMapLayer = _find_terrain()
	if terrain == null or terrain.tile_set == null:
		return
	var tile_size: Vector2 = Vector2(terrain.tile_set.tile_size)
	var color: Color = _KIND_COLORS.get(kind, Color.WHITE)
	if kind == Kind.DOOR:
		var size: Vector2 = Vector2(door_tiles_size()) * tile_size
		draw_rect(Rect2(-tile_size * 0.5, size), color)
		return
	draw_circle(Vector2.ZERO, tile_size.x * _SLOT_RADIUS, color)
	if kind != Kind.ENEMY_SLOT or variance_tiles <= 0:
		return
	# Every tile within grid distance variance_tiles: a diamond reaching that many tiles out.
	var reach: Vector2 = tile_size * (float(variance_tiles) + 0.5)
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -reach.y),
		Vector2(reach.x, 0.0),
		Vector2(0.0, reach.y),
		Vector2(-reach.x, 0.0),
		Vector2(0.0, -reach.y),
	])
	draw_polyline(diamond, _VARIANCE_COLOR, 2.0)


## The cell of [param terrain] under this marker. Works out of the scene tree, from the local
## transforms of both nodes' [Node2D] ancestors.
func tile_on(terrain: TileMapLayer) -> Vector2i:
	var point: Vector2 = (
			MapMarker._scene_transform(terrain).affine_inverse()
			* MapMarker._scene_transform(self).origin
	)
	return terrain.local_to_map(point)


## [member door_size] with each side at least 1.
func door_tiles_size() -> Vector2i:
	return Vector2i(maxi(door_size.x, 1), maxi(door_size.y, 1))


# Moves the marker to the center of the cell it is over. Only in the editor; the loader reads
# the cell under any position, snapped or not.
func _snap_to_grid() -> void:
	var terrain: TileMapLayer = _find_terrain()
	if terrain == null or terrain.tile_set == null:
		return
	var parent_2d: Node2D = get_parent() as Node2D
	var to_parent: Transform2D = (
			Transform2D.IDENTITY if parent_2d == null
			else MapMarker._scene_transform(parent_2d).affine_inverse()
	)
	var center: Vector2 = (
			to_parent * MapMarker._scene_transform(terrain) * terrain.map_to_local(tile_on(terrain))
	)
	if not position.is_equal_approx(center):
		position = center
	queue_redraw()


# The map scene's terrain layer: under the scene root in the editor, else under the parent.
func _find_terrain() -> TileMapLayer:
	var root: Node = owner if owner != null else get_parent()
	if root == null:
		return null
	return root.get_node_or_null(NodePath(MapLoader.TERRAIN_LAYER)) as TileMapLayer


# [param node]'s transform relative to the top of its chain of [Node2D] ancestors: the map scene
# root when every parent between is a [Node2D].
static func _scene_transform(node: Node2D) -> Transform2D:
	var transform_to_top: Transform2D = Transform2D.IDENTITY
	var current: Node2D = node
	while current != null:
		transform_to_top = current.transform * transform_to_top
		current = current.get_parent() as Node2D
	return transform_to_top
