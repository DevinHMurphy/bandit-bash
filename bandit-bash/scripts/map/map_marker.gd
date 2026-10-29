# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_marker.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
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
## layers, so a marker's stable id is the same whichever way it was authored.[br]
## Authoring data only: nothing here runs in a battle. The loader reads the exports and frees the
## scene.
##
## @tutorial(Combat map plan, Authoring and loading): docs/plans/2026-10-27-combat-map.md

## What the marker marks, each one [enum MapLayout.MarkerKind] ([constant LAYOUT_KINDS]). Saved as
## an int in map scenes: [b]append only[/b].
enum Kind {
	## A tile an enemy may be placed on, with its position variance and group slot.
	ENEMY_SLOT = 0,
}

## The layout marker kind of each [enum Kind].
const LAYOUT_KINDS: Dictionary[Kind, MapLayout.MarkerKind] = {
	Kind.ENEMY_SLOT: MapLayout.MarkerKind.ENEMY_SLOT,
}

# The editor drawing: the slot's fill, the variance outline, and the slot's radius in tiles.
const _SLOT_COLOR: Color = Color(1.0, 0.45, 0.1, 0.85)
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
	draw_circle(Vector2.ZERO, tile_size.x * _SLOT_RADIUS, _SLOT_COLOR)
	if variance_tiles <= 0:
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
