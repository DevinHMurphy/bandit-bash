# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_loader.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name MapLoader
extends RefCounted
## Turns a map scene and its [CombatMapDefinition] into a pure [MapLayout] at battle start.
##
## [b]Scene format:[/b] a [TileMapLayer] named [code]Terrain[/code] whose tiles carry a
## [code]terrain[/code] custom data string, a [member TerrainDefinition.id]; every other
## [TileMapLayer] is a marker layer whose tiles carry a [code]marker[/code] custom data string,
## a key of [constant MARKERS] or [constant OBJECTS]. Marker layers may overlap, so one tile can
## hold several markers. A tile on the map is a tile with terrain; markers off it are problems.[br]
## Touches scenes and resources, so it runs on the main thread before any rules code; nothing it
## returns references them. Problems are collected in [member MapLayout.problems], not logged.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

## The name of the terrain layer in a map scene.
const TERRAIN_LAYER: StringName = &"Terrain"

## The custom data layer, on the terrain layer's tile set, naming each tile's terrain.
const TERRAIN_DATA: String = "terrain"

## The custom data layer, on a marker layer's tile set, naming each tile's marker.
const MARKER_DATA: String = "marker"

## Where terrain definitions live, one [code]<id>.tres[/code] each.
const TERRAIN_DIR: String = "res://data/terrain/"

## Marker names a marker layer may use, other than objects.
const MARKERS: Dictionary[String, MapLayout.MarkerKind] = {
	"deployment": MapLayout.MarkerKind.DEPLOYMENT,
	"seize": MapLayout.MarkerKind.SEIZE,
	"defend": MapLayout.MarkerKind.DEFEND,
	"leader_slot": MapLayout.MarkerKind.LEADER_SLOT,
	"reinforcement_point": MapLayout.MarkerKind.REINFORCEMENT_POINT,
	"enemy_slot": MapLayout.MarkerKind.ENEMY_SLOT,
	"darkness_source": MapLayout.MarkerKind.DARKNESS_SOURCE,
}

# ASSUMPTION: the Door and "Debris, Barrel" rows of unit-roster.md's terrain table are objects
# (plan question 8), so they are object markers here and have no terrain definition; a barrel is
# not a separate object.
## Marker names for object spots, each an [constant MapLayout.MarkerKind.OBJECT_SPOT].
const OBJECTS: Dictionary[String, MapLayout.ObjectKind] = {
	"chest": MapLayout.ObjectKind.CHEST,
	"door": MapLayout.ObjectKind.DOOR,
	"lever": MapLayout.ObjectKind.LEVER,
	"house": MapLayout.ObjectKind.HOUSE,
	"food_shelf": MapLayout.ObjectKind.FOOD_SHELF,
	"book_shelf": MapLayout.ObjectKind.BOOK_SHELF,
	"weapon_rack": MapLayout.ObjectKind.WEAPON_RACK,
	"wooden_debris": MapLayout.ObjectKind.WOODEN_DEBRIS,
	"stone_debris": MapLayout.ObjectKind.STONE_DEBRIS,
	"passage": MapLayout.ObjectKind.PASSAGE,
	"powder_keg": MapLayout.ObjectKind.POWDER_KEG,
	"brazier": MapLayout.ObjectKind.BRAZIER,
}


## The layout of [param definition]'s map, its markers indexed; null, with an error logged, when
## the definition has no scene or the scene has no terrain layer.
static func load_layout(definition: CombatMapDefinition) -> MapLayout:
	if definition == null or definition.scene == null:
		push_error("MapLoader: no map scene - %s" % ["" if definition == null else definition.id])
		return null
	var root: Node = definition.scene.instantiate()
	var layout: MapLayout = from_scene(root, definition.id)
	root.free()
	if layout == null:
		push_error("MapLoader: no %s layer - %s" % [TERRAIN_LAYER, definition.id])
	return layout


## The layout of an instanced map scene [param root], its markers indexed; null when it has no
## terrain layer. Leaves [param root] unchanged; the caller frees it.
static func from_scene(root: Node, map_id: String) -> MapLayout:
	var terrain_layer: TileMapLayer = (
			root.get_node_or_null(NodePath(TERRAIN_LAYER)) as TileMapLayer
	)
	if terrain_layer == null:
		return null
	var layout: MapLayout = MapLayout.new()
	layout.map_id = map_id
	_read_terrain(layout, terrain_layer)
	for child: Node in root.get_children():
		var marker_layer: TileMapLayer = child as TileMapLayer
		if marker_layer != null and marker_layer != terrain_layer:
			_read_markers(layout, marker_layer)
	layout.index_markers()
	return layout


## The terrain definition [param id]; null when there is none.
static func load_terrain(id: String) -> TerrainDefinition:
	var path: String = TERRAIN_DIR + id + ".tres"
	if id.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as TerrainDefinition


static func _read_terrain(layout: MapLayout, layer: TileMapLayer) -> void:
	var cache: Dictionary[String, MapLayout.Terrain] = {}
	var cells: Array[Vector2i] = layer.get_used_cells()
	cells.sort_custom(MapLayout.is_before)
	for cell: Vector2i in cells:
		var id: String = _custom_string(layer, cell, TERRAIN_DATA)
		if not cache.has(id):
			var definition: TerrainDefinition = load_terrain(id)
			if definition == null:
				layout.problems.append("no terrain \"%s\" at %s" % [id, cell])
				continue
			cache[id] = MapLayout.Terrain.from_definition(definition)
		layout.set_terrain(cell, cache[id])


static func _read_markers(layout: MapLayout, layer: TileMapLayer) -> void:
	var cells: Array[Vector2i] = layer.get_used_cells()
	cells.sort_custom(MapLayout.is_before)
	for cell: Vector2i in cells:
		var marker_name: String = _custom_string(layer, cell, MARKER_DATA)
		if not layout.has_tile(cell):
			layout.problems.append("marker \"%s\" off the map at %s" % [marker_name, cell])
		elif MARKERS.has(marker_name):
			layout.add_marker(MARKERS[marker_name], cell)
		elif OBJECTS.has(marker_name):
			layout.add_marker(MapLayout.MarkerKind.OBJECT_SPOT, cell, OBJECTS[marker_name])
		else:
			layout.problems.append(
					"unknown marker \"%s\" at %s on %s" % [marker_name, cell, layer.name]
			)


# The custom data string of [param cell]; empty when the tile set has no such layer or the value
# isn't a string.
static func _custom_string(layer: TileMapLayer, cell: Vector2i, data_name: String) -> String:
	var tile_data: TileData = layer.get_cell_tile_data(cell)
	if tile_data == null or layer.tile_set.get_custom_data_layer_by_name(data_name) < 0:
		return ""
	var value: Variant = tile_data.get_custom_data(data_name)
	return value if value is String else ""
