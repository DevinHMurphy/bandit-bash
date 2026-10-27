# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stub_combat_grid.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends CombatGrid
## An open rectangle of configurable tiles, standing in for the maps plan's grid in the combat
## core's tests.
##
## Test-only. Tiles from (0, 0) to [member size] minus one are on the map. Walls, spiked walls,
## oil, tiles some movement types can't stand on, and terrain bonuses are set per tile. Walking
## distance is the grid distance between two tiles on the map: the stub has no pathing, so walls,
## units and terrain cost never lengthen a walk (the maps plan decides those).

## The map's width and height in tiles.
var size: Vector2i = Vector2i(8, 8)

# Blockers per tile; tiles not listed are open.
var _blockers: Dictionary[Vector2i, CombatGrid.Blocker] = {}

# Slick (oiled) tiles.
var _slick: Dictionary[Vector2i, bool] = {}

# Movement types that can't stand on a tile, per tile.
var _no_stand: Dictionary[Vector2i, PackedInt32Array] = {}

var _bonuses: Dictionary[Vector2i, CombatGrid.TileBonus] = {}


## [param map_size]: width and height in tiles.
func _init(map_size: Vector2i = Vector2i(8, 8)) -> void:
	size = map_size


## Puts [param blocker] on [param tile] (a wall, a door, a spiked wall).
func set_blocker(tile: Vector2i, blocker: CombatGrid.Blocker) -> void:
	_blockers[tile] = blocker


## Spills oil on [param tile].
func set_slick(tile: Vector2i) -> void:
	_slick[tile] = true


## Forbids [param movement_type] from standing on [param tile] (water for units on foot).
func forbid(tile: Vector2i, movement_type: CombatGrid.MovementType) -> void:
	if not _no_stand.has(tile):
		_no_stand[tile] = PackedInt32Array()
	_no_stand[tile].append(movement_type)


## Gives [param tile] terrain bonuses.
func set_bonus(tile: Vector2i, bonus: CombatGrid.TileBonus) -> void:
	_bonuses[tile] = bonus


## Whether [param tile] is on the map.
func contains(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y


func walking_distance(
		a: Vector2i, b: Vector2i, _movement_type: CombatGrid.MovementType
) -> int:
	if not contains(a) or not contains(b):
		return -1
	return distance(a, b)


func step(tile: Vector2i, direction: Vector2i) -> Vector2i:
	var next: Vector2i = tile + direction
	return next if contains(next) else CombatFact.NO_TILE


func can_stand(tile: Vector2i, movement_type: CombatGrid.MovementType) -> bool:
	if not contains(tile) or blocker_at(tile) != CombatGrid.Blocker.NONE:
		return false
	return not _no_stand.has(tile) or not _no_stand[tile].has(movement_type)


func blocker_at(tile: Vector2i) -> CombatGrid.Blocker:
	if not contains(tile):
		return CombatGrid.Blocker.PLAIN
	return _blockers.get(tile, CombatGrid.Blocker.NONE)


func is_slick(tile: Vector2i) -> bool:
	return _slick.has(tile)


func tile_bonus(tile: Vector2i) -> CombatGrid.TileBonus:
	return _bonuses.get(tile, CombatGrid.TileBonus.new())


## Legal when every step goes to an orthogonal neighbor that is on the map and unblocked; each
## step costs 1.
func validate_path(_unit_id: String, path: Array[Vector2i]) -> CombatGrid.PathCheck:
	var check: CombatGrid.PathCheck = CombatGrid.PathCheck.new()
	if path.is_empty():
		check.reason = "empty path"
		return check
	for i: int in range(1, path.size()):
		if distance(path[i - 1], path[i]) != 1 or blocker_at(path[i]) != CombatGrid.Blocker.NONE:
			check.reason = "blocked at %s" % [path[i]]
			return check
	check.is_legal = true
	check.tiles_moved = path.size() - 1
	check.cost = check.tiles_moved
	return check
