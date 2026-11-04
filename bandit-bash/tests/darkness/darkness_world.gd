# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_world.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## A test map for the darkness cases: a [MapLayout] from rows of terrain ids and object spots, a
## [CombatSession] over it with the objects placed ([method MapObjects.place]), and helpers to
## set up the darkness, open and close doors, light braziers, break breakables and place units.
##
## Test-only. Terrain comes from the real definitions in [code]res://data/terrain/[/code]. The
## engine runs in verify mode.

## The session; its state holds the darkness in [member CombatState.map].
var session: CombatSession = null


## [param rows]: one string per row, terrain ids separated by spaces. [param spots]:
## [code][tile, MapLayout.ObjectKind][/code] each.
func _init(rows: Array[String], spots: Array = []) -> void:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "darkness"
	var cache: Dictionary[String, MapLayout.Terrain] = {}
	for y: int in rows.size():
		var terrain_ids: PackedStringArray = rows[y].split(" ", false)
		for x: int in terrain_ids.size():
			if not cache.has(terrain_ids[x]):
				cache[terrain_ids[x]] = MapLayout.Terrain.from_definition(
						MapLoader.load_terrain(terrain_ids[x])
				)
			layout.set_terrain(Vector2i(x, y), cache[terrain_ids[x]])
	# Untyped: each spot is an array literal.
	for spot: Variant in spots:
		var entry: Array = spot
		layout.add_marker(
				MapLayout.MarkerKind.OBJECT_SPOT, entry[0] as Vector2i, entry[1] as int
		)
	layout.index_markers()
	session = CombatSession.new(
			0,
			PackedInt32Array([0]),
			MapGrid.new(layout),
			ForcedRolls.new(PackedInt32Array()),
			InstanceIdAllocator.new()
	)
	session.engine.verify = true
	MapObjects.place(session)


## The session's state.
func state() -> CombatState:
	return session.state


## The session's engine.
func engine() -> EffectEngine:
	return session.engine


## The state's darkness.
func darkness() -> DarknessState:
	return session.state.map.darkness


## Gives the darkness one active source per entry of [param source_tiles] and the drain
## [param drain].
func set_up(source_tiles: Array, drain: Vector2i) -> void:
	# Untyped: each entry is an array literal of tiles.
	for tiles: Variant in source_tiles:
		var source: DarknessState.Source = DarknessState.Source.new()
		source.tiles.assign(tiles as Array)
		darkness().sources.append(source)
	darkness().drain = drain


## The object on [param tile], destroyed or not; null when there is none.
func object_at(tile: Vector2i) -> MapState.ObjectState:
	for object_id: String in state().map.objects:
		if state().map.objects[object_id].tile == tile:
			return state().map.objects[object_id]
	return null


## Opens or closes the door on [param tile] as a lever does: its state and what it blocks.
func set_door(tile: Vector2i, is_open: bool) -> void:
	var door: MapState.ObjectState = object_at(tile)
	door.is_open = is_open
	state().map.set_blocking(tile, MapState.Blocking.NONE if is_open else MapState.Blocking.ALL)


## Lights or douses the brazier on [param tile].
func set_lit(tile: Vector2i, is_lit: bool) -> void:
	object_at(tile).is_lit = is_lit


## Breaks the breakable on [param tile] as the darkness's erosion does. Returns whether it broke.
func erode(tile: Vector2i) -> bool:
	return MapObjects.erode(engine(), state(), object_at(tile).id)


## Places a unit with 20 HP. Returns whether it was placed.
func add_unit(id: String, side: CombatFact.CombatSide, tile: Vector2i) -> bool:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.side = side
	unit.seat = 0 if side == CombatFact.CombatSide.PLAYER else -1
	unit.tile = tile
	unit.hp = 20
	return session.add_unit(unit, {
		CombatValue.Key.HP: 20.0,
		CombatValue.Key.STANCE_MAX: 2.0,
		CombatValue.Key.MOVEMENT: 5.0,
	})


## The layers of a row of [param width] tiles at row [param y], as a string such as "1 1 2 0".
func row_layers(y: int, width: int) -> String:
	var parts: PackedStringArray = []
	for x: int in width:
		parts.append(str(darkness().layer_at(Vector2i(x, y))))
	return " ".join(parts)


## [param tiles] as "(x, y)=value" entries, row-major, joined by spaces.
static func describe(tiles: Dictionary[Vector2i, int]) -> String:
	var keys: Array[Vector2i] = []
	keys.assign(tiles.keys())
	keys.sort_custom(MapLayout.is_before)
	var parts: PackedStringArray = []
	for tile: Vector2i in keys:
		parts.append("%s=%d" % [tile, tiles[tile]])
	return " ".join(parts)


## [param deepened] as "(x, y)>layer@source" entries, in order, joined by spaces.
static func describe_deepened(deepened: Array[DarknessState.Deepening]) -> String:
	var parts: PackedStringArray = []
	for entry: DarknessState.Deepening in deepened:
		parts.append("%s>%d@%d" % [entry.tile, entry.layer, entry.source])
	return " ".join(parts)
