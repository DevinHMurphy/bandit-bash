# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_layout.gd
# Author:
# Created:  October 27, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name MapLayout
extends RefCounted
## One combat map as pure data: the terrain of every tile and the authored markers.
##
## [MapLoader] builds it from a map scene and its [CombatMapDefinition]; [MapGrid] and the map's
## rules read it. It holds no node, scene or Resource, and nothing changes it after loading, so
## every sandbox and every co-op copy of the map can share one.[br]
## [b]Stable ids:[/b] [method index_markers] puts the markers in the fixed order (row-major by
## tile, then [enum MarkerKind]) and numbers object spots, containers and reinforcement points in
## that order, so the same map gives the same ids on every load and every co-op copy: the
## [code]MAP_LOOT[/code] index and the object ids in facts and saves. Changing the order, or the
## values of [enum MarkerKind], renumbers every authored map.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

## What a marker marks. Its value orders markers that share a tile. Saved as an int:
## [b]append only[/b].
enum MarkerKind {
	## A tile the player's army may deploy on.
	DEPLOYMENT = 0,
	## The Seize objective's tile.
	SEIZE = 1,
	## The Defend objective's tile.
	DEFEND = 2,
	## Where the Defeat the Leader objective's marked enemy is placed.
	LEADER_SLOT = 3,
	## Where reinforcement waves arrive.
	REINFORCEMENT_POINT = 4,
	## A candidate spot for a map object of [member Marker.object_kind].
	OBJECT_SPOT = 5,
	## A tile an enemy group may be placed on.
	ENEMY_SLOT = 6,
	## A candidate source of the darkness.
	DARKNESS_SOURCE = 7,
}

## The map object an [constant MarkerKind.OBJECT_SPOT] holds (map-objects.md). Saved as an int:
## [b]append only[/b].
enum ObjectKind {
	## Not an object spot.
	NONE = 0,
	## Opened with a lockpick for one item. A container.
	CHEST = 1,
	## Blocks every unit while closed.
	DOOR = 2,
	## Toggles its group's doors.
	LEVER = 3,
	## Searched once for gold or a consumable. A container.
	HOUSE = 4,
	## Searched once for an ingredient. A container.
	FOOD_SHELF = 5,
	## Searched once for a rune. A container.
	BOOK_SHELF = 6,
	## Searched once for a weapon. A container.
	WEAPON_RACK = 7,
	## Breakable debris, 25 HP; blocks every unit but fliers.
	WOODEN_DEBRIS = 8,
	## Breakable debris, 35 HP; blocks every unit but fliers.
	STONE_DEBRIS = 9,
	## One end of a linked pair.
	PASSAGE = 10,
	## Explodes when hit; blocks every unit but fliers.
	POWDER_KEG = 11,
	## Lit or doused by an adjacent unit.
	BRAZIER = 12,
}

# ASSUMPTION: every object that gives loot from MAP_LOOT is a container, weapon racks included;
# the plan lists "chest, house, shelf".
## The object kinds that give loot from [code]MAP_LOOT[/code] and so get a
## [member Marker.container_index].
const CONTAINERS: Array[ObjectKind] = [
	ObjectKind.CHEST,
	ObjectKind.HOUSE,
	ObjectKind.FOOD_SHELF,
	ObjectKind.BOOK_SHELF,
	ObjectKind.WEAPON_RACK,
]

## The [member CombatMapDefinition.id] this layout was loaded from.
var map_id: String = ""

## The distinct terrains on the map, by first use in row-major order. Tiles refer to them by
## index.
var terrains: Array[Terrain] = []

## Every marker, in the fixed order once [method index_markers] has run.
var markers: Array[Marker] = []

## What the loader couldn't read: tiles without a terrain, unknown terrain ids, unknown markers.
## The authoring check fails a map with any.
var problems: PackedStringArray = []

var _terrain_at: Dictionary[Vector2i, int] = {}


## Whether [param tile] is on the map: it has a terrain.
func has_tile(tile: Vector2i) -> bool:
	return _terrain_at.has(tile)


## The terrain of [param tile]; null off the map.
func terrain_at(tile: Vector2i) -> Terrain:
	return terrains[_terrain_at[tile]] if _terrain_at.has(tile) else null


## Gives [param tile] the terrain [param terrain], adding it to [member terrains] the first time.
## For the loader and for tests that build a layout by hand.
func set_terrain(tile: Vector2i, terrain: Terrain) -> void:
	var index: int = terrains.find(terrain)
	if index < 0:
		index = terrains.size()
		terrains.append(terrain)
	_terrain_at[tile] = index


## Every tile on the map, row-major (by row, then column).
func tiles() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	found.assign(_terrain_at.keys())
	found.sort_custom(MapLayout.is_before)
	return found


## The smallest rectangle holding every tile; empty for an empty map.
func get_rect() -> Rect2i:
	var rect: Rect2i = Rect2i()
	var is_first: bool = true
	for tile: Vector2i in _terrain_at:
		var cell: Rect2i = Rect2i(tile, Vector2i.ONE)
		rect = cell if is_first else rect.merge(cell)
		is_first = false
	return rect


## Adds a marker. Call [method index_markers] once every marker is in.
func add_marker(
		kind: MarkerKind, tile: Vector2i, object_kind: ObjectKind = ObjectKind.NONE
) -> Marker:
	var marker: Marker = Marker.new()
	marker.kind = kind
	marker.tile = tile
	marker.object_kind = object_kind
	markers.append(marker)
	return marker


## Puts [member markers] in the fixed order and numbers them: object spots, containers and
## reinforcement points each count from 0 in that order. Running it twice gives the same ids.
func index_markers() -> void:
	markers.sort_custom(_is_marker_before)
	var next_object: int = 0
	var next_container: int = 0
	var next_point: int = 0
	for marker: Marker in markers:
		marker.index = -1
		marker.container_index = -1
		if marker.kind == MarkerKind.REINFORCEMENT_POINT:
			marker.index = next_point
			next_point += 1
		elif marker.kind == MarkerKind.OBJECT_SPOT:
			marker.index = next_object
			next_object += 1
			if CONTAINERS.has(marker.object_kind):
				marker.container_index = next_container
				next_container += 1


## The markers of [param kind], in the fixed order.
func markers_of(kind: MarkerKind) -> Array[Marker]:
	var found: Array[Marker] = []
	for marker: Marker in markers:
		if marker.kind == kind:
			found.append(marker)
	return found


## The tiles of the markers of [param kind], in the fixed order.
func tiles_of(kind: MarkerKind) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for marker: Marker in markers:
		if marker.kind == kind:
			found.append(marker.tile)
	return found


# Row-major, then by kind, then by object kind, so two markers on one tile still sort the same way.
func _is_marker_before(a: Marker, b: Marker) -> bool:
	if a.tile != b.tile:
		return MapLayout.is_before(a.tile, b.tile)
	if a.kind != b.kind:
		return a.kind < b.kind
	return a.object_kind < b.object_kind


## Whether [param a] comes before [param b] in row-major order: by row, then by column.
static func is_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y if a.y != b.y else a.x < b.x


## One terrain's rules, copied from its [TerrainDefinition]: read-only once loaded.
class Terrain:
	extends RefCounted

	## The [member TerrainDefinition.id].
	var id: String = ""
	## Movement points to enter, indexed by [enum CombatGrid.MovementType];
	## [constant TerrainDefinition.IMPASSABLE] where it can't.
	var costs: PackedInt32Array = PackedInt32Array([1, 1, 1, 1, 1])
	## Avoid, DEF, RES and Phase Start healing for a unit standing here.
	var bonus: CombatGrid.TileBonus = CombatGrid.TileBonus.new()
	## What stops a shoved unit here.
	var blocker: CombatGrid.Blocker = CombatGrid.Blocker.NONE
	## Whether a shoved unit landing here keeps sliding.
	var is_slick: bool = false

	## Movement points [param movement_type] pays to enter; 0 when it can't.
	func cost(movement_type: CombatGrid.MovementType) -> int:
		return costs[movement_type]


	## The rules of [param definition].
	static func from_definition(definition: TerrainDefinition) -> Terrain:
		var terrain: Terrain = Terrain.new()
		terrain.id = definition.id
		terrain.costs = definition.costs()
		terrain.bonus.avoid = definition.avoid
		terrain.bonus.defense = definition.defense
		terrain.bonus.resistance = definition.resistance
		terrain.bonus.heal_flat = definition.heal_flat
		terrain.bonus.heal_percent = definition.heal_percent
		terrain.blocker = definition.blocker
		terrain.is_slick = definition.is_slick
		return terrain


## One authored marker on one tile, from a marker layer or a [MapMarker] node. Parameters a kind
## doesn't use keep their defaults.
class Marker:
	extends RefCounted

	## What it marks.
	var kind: MarkerKind = MarkerKind.DEPLOYMENT
	## Where.
	var tile: Vector2i = Vector2i.ZERO
	## The object on an object spot; [constant ObjectKind.NONE] otherwise.
	var object_kind: ObjectKind = ObjectKind.NONE
	## The stable index among object spots, or among reinforcement points; -1 for other kinds.
	var index: int = -1
	## The stable index among containers, the [code]MAP_LOOT[/code] index; -1 when not one.
	var container_index: int = -1
	## An enemy slot's position variance: how far from [member tile] its enemy may be placed
	## ([member MapMarker.variance_tiles]). 0 for a fixed slot and for other kinds.
	var variance_tiles: int = 0
	## An enemy slot's group slot ([member MapMarker.group_slot]); empty for none.
	var group_slot: String = ""
	## The lever group a door or lever belongs to; -1 for none. [MapCheck] matches them up.
	var group_id: int = -1
	## The pair a passage end belongs to; -1 for none. [MapCheck] matches them up.
	var pair_id: int = -1
