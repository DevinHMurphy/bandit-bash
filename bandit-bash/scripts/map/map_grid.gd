# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_grid.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name MapGrid
extends CombatGrid
## The real [CombatGrid]: a loaded map's terrain, read from its [MapLayout].
##
## Terrain only: a tile is on the map when the layout gives it a terrain, its movement cost and
## bonuses are that terrain's, and nothing here changes after construction, so every sandbox
## shares one grid. Map objects are [MapState]'s and units [CombatState]'s.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

## The layout this grid reads. Never changed.
var layout: MapLayout = null

# Answered off the map, so callers never get null.
var _no_bonus: CombatGrid.TileBonus = CombatGrid.TileBonus.new()


## [param map_layout]: the loaded map; must not be null.
func _init(map_layout: MapLayout) -> void:
	layout = map_layout


func move_cost(tile: Vector2i, movement_type: CombatGrid.MovementType) -> int:
	var terrain: MapLayout.Terrain = layout.terrain_at(tile)
	return 0 if terrain == null else terrain.cost(movement_type)


func step(tile: Vector2i, direction: Vector2i) -> Vector2i:
	var next: Vector2i = tile + direction
	return next if layout.has_tile(next) else CombatFact.NO_TILE


## Whether the terrain lets [param movement_type] in: it has a cost for it and nothing on the
## tile is a blocker.
func can_stand(tile: Vector2i, movement_type: CombatGrid.MovementType) -> bool:
	return move_cost(tile, movement_type) > 0 and blocker_at(tile) == CombatGrid.Blocker.NONE


func blocker_at(tile: Vector2i) -> CombatGrid.Blocker:
	var terrain: MapLayout.Terrain = layout.terrain_at(tile)
	return CombatGrid.Blocker.PLAIN if terrain == null else terrain.blocker


func is_slick(tile: Vector2i) -> bool:
	var terrain: MapLayout.Terrain = layout.terrain_at(tile)
	return terrain != null and terrain.is_slick


func tile_bonus(tile: Vector2i) -> CombatGrid.TileBonus:
	var terrain: MapLayout.Terrain = layout.terrain_at(tile)
	return _no_bonus if terrain == null else terrain.bonus
