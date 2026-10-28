# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_world.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## A test map for the combat map's cases: a [MapLayout] built from rows of terrain ids, its
## [MapGrid], a [CombatState] and an [EffectEngine] over it, with a helper to place units.
##
## Test-only. Terrain comes from the real definitions in [code]res://data/terrain/[/code]. The
## engine runs in verify mode, so a stale cached stat sheet shows up in
## [member EffectEngine.diagnostics].

## The map's layout.
var layout: MapLayout = null

## The map's terrain.
var grid: MapGrid = null

## The map's combat state.
var state: CombatState = null

## The engine resolving on [member state].
var engine: EffectEngine = null


## [param rows]: one string per row, terrain ids separated by spaces, such as
## [code]"plain forest river"[/code].
func _init(rows: Array[String]) -> void:
	layout = MapLayout.new()
	layout.map_id = "test"
	var cache: Dictionary[String, MapLayout.Terrain] = {}
	for y: int in rows.size():
		var ids: PackedStringArray = rows[y].split(" ", false)
		for x: int in ids.size():
			if not cache.has(ids[x]):
				cache[ids[x]] = MapLayout.Terrain.from_definition(MapLoader.load_terrain(ids[x]))
			layout.set_terrain(Vector2i(x, y), cache[ids[x]])
	grid = MapGrid.new(layout)
	state = CombatState.new(grid)
	engine = EffectEngine.new(state, ForcedRolls.new(PackedInt32Array()))
	engine.verify = true


## Places a unit with [param movement] movement points and Stance 2. Returns its state, or null
## if it couldn't be placed.
func add_unit(
		id: String,
		side: CombatFact.CombatSide,
		tile: Vector2i,
		movement_type: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT,
		movement: int = 5,
		seat: int = 0
) -> CombatUnitState:
	engine.set_base(id, CombatValue.Key.MOVEMENT, movement)
	engine.set_base(id, CombatValue.Key.HP, 20.0)
	engine.set_base(id, CombatValue.Key.STANCE_MAX, 2.0)
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.side = side
	unit.seat = seat if side == CombatFact.CombatSide.PLAYER else -1
	unit.tile = tile
	unit.movement_type = movement_type
	unit.hp = 20
	return unit if state.place_unit(engine, unit) else null


## [param tiles] as "(x, y)=cost" entries, row-major, joined by spaces.
static func describe(tiles: Dictionary[Vector2i, int]) -> String:
	var keys: Array[Vector2i] = []
	keys.assign(tiles.keys())
	keys.sort_custom(MapLayout.is_before)
	var parts: PackedStringArray = []
	for tile: Vector2i in keys:
		parts.append("%s=%d" % [tile, tiles[tile]])
	return " ".join(parts)
