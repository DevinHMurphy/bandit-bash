# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     auto_deploy.gd
# Author:
# Created:  October 27, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name AutoDeploy
extends RefCounted
## Automatic deployment: places an army on a map's deployment tiles by role, with no random draw,
## and the legality rule of the opening swap.
##
## Rules code: pure and static. Deployment tiles are ranked by grid distance to the nearest enemy
## starting tile; a "row" is every tile at one such distance, nearest first. The commander takes
## the second row; then front units take the nearest tiles, strikers the next, ranged units the
## tiles 1–2 behind a front unit (behind a striker when no front unit is placed), and support
## units the tiles behind the line next to the most allies. Tiles at the same distance rank
## row-major; units tie by roster order. A unit is only placed on a tile it can stand on.[br]
## There is no prep screen: the opening swap, a player setting, is how the player changes this
## layout ([member MapState.opening_swap_open]).
##
## @tutorial(Combat map plan, Deployment): docs/plans/2026-10-27-combat-map.md

## A unit's place in the deployment order, from its data. Saved as an int: [b]append only[/b].
enum Role {
	## Melee and built to hold: Armored, Heavy or the shover role. Takes the nearest tiles.
	FRONT = 0,
	## Every other melee unit. Mounted units and fliers prefer the edges of their row.
	STRIKER = 1,
	## Its equipped weapon can't attack at distance 1, or deals magic damage (a tome). Stands 1–2
	## tiles behind a front unit.
	RANGED = 2,
	## Holds a staff, equipped or stowed. Stands behind the line, next to the most allies.
	SUPPORT = 3,
}

## The tag that counts as Armored for [constant Role.FRONT].
const ARMORED_TAG: String = ContentIds.TAG_ARMORED

## The weapon minimum range from which a unit is [constant Role.RANGED]: it can't attack at
## distance 1. A 1–2 physical weapon (a javelin, a hand axe) stays melee.
const RANGED_MIN_RANGE: int = 2


## Where [param units] start: each unit, in roster order, on a deployment tile it can stand on,
## or in [member Placement.unplaced] when no such tile is left. Changes nothing.
## [param units]: the army, roster order, not yet on the map; their weapons in [param state].
## [param enemy_tiles]: the enemies' starting tiles; none ranks every tile equally.
## [param commander_id]: the commander's instance id; empty when the army has none here.
## Returns the same placement for the same inputs, every time.
static func deploy(
		engine: EffectEngine,
		state: CombatState,
		units: Array[CombatUnitState],
		deployment_tiles: Array[Vector2i],
		enemy_tiles: Array[Vector2i],
		commander_id: String
) -> Placement:
	var plan: _Plan = _Plan.new(state, deployment_tiles, enemy_tiles)
	var fronts: Array[CombatUnitState] = []
	var strikers: Array[CombatUnitState] = []
	var ranged: Array[CombatUnitState] = []
	var supports: Array[CombatUnitState] = []
	for unit: CombatUnitState in units:
		if unit.id == commander_id:
			var tile: Vector2i = plan.first_free(unit, plan.second_row())
			if tile == CombatFact.NO_TILE:
				tile = plan.first_free(unit, plan.ranked)
			plan.place(unit, tile)
			continue
		match role_of(state, unit):
			Role.FRONT:
				fronts.append(unit)
			Role.STRIKER:
				strikers.append(unit)
			Role.RANGED:
				ranged.append(unit)
			Role.SUPPORT:
				supports.append(unit)
	_sort_by_bulk(engine, fronts)
	for unit: CombatUnitState in fronts:
		plan.place(unit, plan.first_free(unit, plan.ranked))
	for unit: CombatUnitState in strikers:
		var tile: Vector2i = plan.first_free(unit, plan.ranked)
		if _prefers_edges(unit):
			tile = plan.edge_in_row_of(unit, tile)
		plan.place(unit, tile)
	var line: Array[Vector2i] = plan.tiles_of(fronts)
	if line.is_empty():
		line = plan.tiles_of(strikers)
	for unit: CombatUnitState in ranged:
		var tile: Vector2i = plan.first_free(unit, plan.behind(line, 1, 2))
		if tile == CombatFact.NO_TILE:
			tile = plan.first_free(unit, plan.ranked)
		plan.place(unit, tile)
	var melee_line: Array[Vector2i] = plan.tiles_of(fronts)
	melee_line.append_array(plan.tiles_of(strikers))
	for unit: CombatUnitState in supports:
		plan.place(unit, plan.most_neighbors(unit, melee_line))
	return plan.finish(units)


## [param unit]'s role from its data: a staff makes it support; then an equipped weapon that can't
## attack at distance 1 or deals magic damage makes it ranged; then Armored, Heavy or the
## [constant ContentIds.ROLE_SHOVER] role ([member CombatUnitState.role]) make it front; every
## other unit is a striker. A unit with no weapon counts as melee.
static func role_of(state: CombatState, unit: CombatUnitState) -> Role:
	var held: CombatState.WeaponStats = state.weapon(unit.equipped_weapon_id)
	var stowed: CombatState.WeaponStats = state.weapon(unit.stowed_weapon_id)
	if (held != null and held.is_staff()) or (stowed != null and stowed.is_staff()):
		return Role.SUPPORT
	if held != null and (
			held.range_min >= RANGED_MIN_RANGE
			or held.damage_type == CombatFact.DamageType.MAGIC
	):
		return Role.RANGED
	if (
			unit.tags.has(ARMORED_TAG)
			or unit.movement_type == CombatGrid.MovementType.HEAVY
			or unit.role == ContentIds.ROLE_SHOVER
	):
		return Role.FRONT
	return Role.STRIKER


## Why [param seat] may not swap its units [param first_id] and [param second_id] now; empty when
## it may. Legal only while [member MapState.opening_swap_open] is set (the window before turn 1),
## and only between two of the seat's own units on [param deployment_tiles], each able to stand on
## the other's tile, as for Recall. Opening and closing the window, and the swap itself, are the
## unit-turn command path's (P02 CC6).
static func check_opening_swap(
		state: CombatState,
		seat: int,
		first_id: String,
		second_id: String,
		deployment_tiles: Array[Vector2i]
) -> String:
	if not state.map.opening_swap_open:
		return "the opening swap is closed"
	if first_id == second_id:
		return "not two of the seat's units"
	for unit_id: String in [first_id, second_id]:
		if not state.has_unit(unit_id) or state.seat_of(unit_id) != seat:
			return "not two of the seat's units"
		if not deployment_tiles.has(state.tile_of(unit_id)):
			return "not on a deployment tile"
	var first: CombatUnitState = state.unit(first_id)
	var second: CombatUnitState = state.unit(second_id)
	if (
			not state.can_stand(second.tile, first.movement_type)
			or not state.can_stand(first.tile, second.movement_type)
	):
		return "a unit can't stand on the other's tile"
	return ""


# Front units by HP + DEF, highest first; equal bulk keeps roster order.
static func _sort_by_bulk(engine: EffectEngine, fronts: Array[CombatUnitState]) -> void:
	var bulk: Dictionary[String, int] = {}
	var roster: Dictionary[String, int] = {}
	for i: int in fronts.size():
		var stats: StatSheet = engine.stats(fronts[i].id)
		bulk[fronts[i].id] = (
				stats.get_int(CombatValue.Key.HP) + stats.get_int(CombatValue.Key.DEF)
		)
		roster[fronts[i].id] = i
	fronts.sort_custom(
			func(a: CombatUnitState, b: CombatUnitState) -> bool:
				if bulk[a.id] != bulk[b.id]:
					return bulk[a.id] > bulk[b.id]
				return roster[a.id] < roster[b.id]
	)


static func _prefers_edges(unit: CombatUnitState) -> bool:
	return (
			unit.movement_type == CombatGrid.MovementType.MOUNTED
			or unit.movement_type == CombatGrid.MovementType.FLIER
	)


## Where an army was deployed.
class Placement:
	extends RefCounted

	## Each placed unit's tile, by instance id, in roster order.
	var tiles: Dictionary[String, Vector2i] = {}
	## Units left off the map for want of a tile, in roster order.
	var unplaced: PackedStringArray = []


# The deployment tiles of one deployment, ranked, and which are taken.
class _Plan:
	extends RefCounted

	# Deployment tiles by grid distance to the nearest enemy, then row-major.
	var ranked: Array[Vector2i] = []

	var _state: CombatState = null
	var _enemy_distance: Dictionary[Vector2i, int] = {}
	var _zone: Dictionary[Vector2i, bool] = {}
	var _taken: Dictionary[String, Vector2i] = {}
	var _used: Dictionary[Vector2i, bool] = {}

	func _init(
			state: CombatState, deployment_tiles: Array[Vector2i], enemy_tiles: Array[Vector2i]
	) -> void:
		_state = state
		for tile: Vector2i in deployment_tiles:
			if _zone.has(tile):
				continue
			_zone[tile] = true
			var nearest: int = -1
			for enemy: Vector2i in enemy_tiles:
				var distance: int = state.grid.distance(tile, enemy)
				if nearest < 0 or distance < nearest:
					nearest = distance
			_enemy_distance[tile] = maxi(nearest, 0)
			ranked.append(tile)
		ranked.sort_custom(_is_ranked_before)

	# The tiles of the second row, or of the first when there is only one.
	func second_row() -> Array[Vector2i]:
		var rows: Array[int] = []
		for tile: Vector2i in ranked:
			if not rows.has(_enemy_distance[tile]):
				rows.append(_enemy_distance[tile])
		if rows.is_empty():
			return []
		var wanted: int = rows[1] if rows.size() > 1 else rows[0]
		var found: Array[Vector2i] = []
		for tile: Vector2i in ranked:
			if _enemy_distance[tile] == wanted:
				found.append(tile)
		return found

	# The first free edge tile for `unit` in the row of `nearest` (its nearest free tile), else
	# `nearest` itself.
	# A striker that prefers edges still takes the nearest row with a free tile. An edge tile has at
	# most 2 deployment-tile neighbors: a corner of a rectangular zone, the end of a line.
	func edge_in_row_of(unit: CombatUnitState, nearest: Vector2i) -> Vector2i:
		if nearest == CombatFact.NO_TILE:
			return nearest
		for tile: Vector2i in ranked:
			if _enemy_distance[tile] != _enemy_distance[nearest] or not _is_free_for(unit, tile):
				continue
			var inside: int = 0
			for direction: Vector2i in CombatGrid.DIRECTIONS:
				if _zone.has(tile + direction):
					inside += 1
			if inside <= 2:
				return tile
		return nearest

	# Ranked tiles 1 to `far` tiles (grid distance) from a tile of `line`, at least `near`, and
	# farther from the enemy than that line tile.
	func behind(line: Array[Vector2i], near: int, far: int) -> Array[Vector2i]:
		var found: Array[Vector2i] = []
		for tile: Vector2i in ranked:
			for anchor: Vector2i in line:
				var gap: int = _state.grid.distance(tile, anchor)
				if gap >= near and gap <= far and _enemy_distance[tile] > _enemy_distance[anchor]:
					found.append(tile)
					break
		return found

	# The free tile for `unit` behind the nearest tile of `line` (every tile when nothing is
	# behind it) with the most placed units next to it; ties by rank.
	func most_neighbors(unit: CombatUnitState, line: Array[Vector2i]) -> Vector2i:
		var front_depth: int = -1
		for anchor: Vector2i in line:
			if front_depth < 0 or _enemy_distance[anchor] < front_depth:
				front_depth = _enemy_distance[anchor]
		var candidates: Array[Vector2i] = []
		for tile: Vector2i in ranked:
			if _enemy_distance[tile] > front_depth:
				candidates.append(tile)
		if first_free(unit, candidates) == CombatFact.NO_TILE:
			candidates = ranked
		var best: Vector2i = CombatFact.NO_TILE
		var best_count: int = -1
		for tile: Vector2i in candidates:
			if not _is_free_for(unit, tile):
				continue
			var count: int = 0
			for direction: Vector2i in CombatGrid.DIRECTIONS:
				if _used.has(tile + direction):
					count += 1
			if count > best_count:
				best = tile
				best_count = count
		return best

	# The first tile of `tiles` that is free and `unit` can stand on; NO_TILE when none.
	func first_free(unit: CombatUnitState, tiles: Array[Vector2i]) -> Vector2i:
		for tile: Vector2i in tiles:
			if _is_free_for(unit, tile):
				return tile
		return CombatFact.NO_TILE

	# Takes `tile` for `unit`; NO_TILE leaves it unplaced.
	func place(unit: CombatUnitState, tile: Vector2i) -> void:
		if tile == CombatFact.NO_TILE:
			return
		_taken[unit.id] = tile
		_used[tile] = true

	# The tiles taken by `units`, in their order, leaving out any not placed.
	func tiles_of(units: Array[CombatUnitState]) -> Array[Vector2i]:
		var found: Array[Vector2i] = []
		for unit: CombatUnitState in units:
			if _taken.has(unit.id):
				found.append(_taken[unit.id])
		return found

	# The placement, in roster order.
	func finish(units: Array[CombatUnitState]) -> Placement:
		var placement: Placement = Placement.new()
		for unit: CombatUnitState in units:
			if _taken.has(unit.id):
				placement.tiles[unit.id] = _taken[unit.id]
			else:
				placement.unplaced.append(unit.id)
		return placement

	func _is_free_for(unit: CombatUnitState, tile: Vector2i) -> bool:
		return (
				not _used.has(tile)
				and _state.occupant_at(tile).is_empty()
				and _state.can_stand(tile, unit.movement_type)
		)

	func _is_ranked_before(a: Vector2i, b: Vector2i) -> bool:
		if _enemy_distance[a] != _enemy_distance[b]:
			return _enemy_distance[a] < _enemy_distance[b]
		return MapLayout.is_before(a, b)
