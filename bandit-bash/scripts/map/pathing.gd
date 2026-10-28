# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pathing.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name Pathing
extends RefCounted
## Movement on a combat map: one cost-bounded flood over the four directions, and the path check,
## reach and nearest free tile built on it.
##
## Rules code: pure and static, reading a [CombatState] (terrain through its grid, objects through
## its [member CombatState.map], units through occupancy), so a sandbox runs it unchanged. A
## mover pays its terrain cost per tile entered; units of its own side are passable, other units
## and object tiles that block it are solid, and it can't end on a taken tile (Godot_FE's
## FR-GRID-2). Nothing is cached: maps are small enough to flood per query (unmeasured).[br]
## One flood replaces separate range searches, and no A* graph is rebuilt per mover: passability
## differs per mover and side.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md


## Movement points [param unit_id] has left this turn: its [constant CombatValue.Key.MOVEMENT]
## less the cost already spent; 0 for a unit off the map.
static func budget_of(engine: EffectEngine, state: CombatState, unit_id: String) -> int:
	if not state.has_unit(unit_id):
		return 0
	var movement: int = engine.stats(unit_id).get_int(CombatValue.Key.MOVEMENT)
	return maxi(0, movement - state.unit(unit_id).movement_spent)


## Whether [param unit_id] may walk [param path] now: it starts on the unit's tile, every step
## enters an orthogonal neighbor the unit can enter, the terrain cost is within
## [method budget_of], and the last tile is free (or its own). [method CombatState.validate_path]
## calls this.
static func check_path(
		engine: EffectEngine, state: CombatState, unit_id: String, path: Array[Vector2i]
) -> CombatGrid.PathCheck:
	var check: CombatGrid.PathCheck = CombatGrid.PathCheck.new()
	if not state.has_unit(unit_id):
		check.reason = "not on the map"
		return check
	if path.is_empty():
		check.reason = "empty path"
		return check
	if path[0] != state.tile_of(unit_id):
		check.reason = "doesn't start on its tile"
		return check
	var mover: CombatUnitState = state.unit(unit_id)
	for i: int in range(1, path.size()):
		if not can_enter(state, path[i], mover.movement_type, mover.side):
			check.reason = "blocked at %s" % [path[i]]
			return check
	var cost: int = state.grid.path_cost(path, mover.movement_type)
	if cost < 0:
		check.reason = "not a walk of single steps"
		return check
	if cost > budget_of(engine, state, unit_id):
		check.reason = "too far"
		return check
	var last: String = state.occupant_at(path[path.size() - 1])
	if not last.is_empty() and last != unit_id:
		check.reason = "ends on a taken tile"
		return check
	check.is_legal = true
	check.tiles_moved = path.size() - 1
	check.cost = cost
	return check


## Every tile [param unit_id] can end its move on now, with the cost to get there: its own tile
## at 0, then each free tile within [method budget_of]. Empty for a unit off the map.
static func reach(
		engine: EffectEngine, state: CombatState, unit_id: String
) -> Dictionary[Vector2i, int]:
	var ends: Dictionary[Vector2i, int] = {}
	if not state.has_unit(unit_id):
		return ends
	var mover: CombatUnitState = state.unit(unit_id)
	var budget: int = budget_of(engine, state, unit_id)
	var reached: Dictionary[Vector2i, int] = flood(
			state, mover.tile, budget, mover.movement_type, mover.side
	)
	for tile: Vector2i in reached:
		var occupant: String = state.occupant_at(tile)
		if occupant.is_empty() or occupant == unit_id:
			ends[tile] = reached[tile]
	return ends


## The free tile nearest [param origin] that [param movement_type] can stand on, by that
## movement type's terrain cost, ties in [constant CombatGrid.DIRECTIONS] order; [param origin]
## itself when free. For arrivals on a taken tile (reinforcements, allies sent from another map).
## Returns [constant CombatFact.NO_TILE] when no tile is reachable.
static func nearest_free_tile(
		state: CombatState, origin: Vector2i, movement_type: CombatGrid.MovementType
) -> Vector2i:
	# ASSUMPTION: the search crosses units of either side, since an arrival is placed, not walked;
	# terrain and objects still bound it.
	var reached: Dictionary[Vector2i, int] = flood(
			state, origin, -1, movement_type, CombatFact.CombatSide.NONE
	)
	for tile: Vector2i in reached:
		if state.occupant_at(tile).is_empty() and state.can_stand(tile, movement_type):
			return tile
	return CombatFact.NO_TILE


## The cost of reaching every tile [param movement_type] can enter from [param origin] within
## [param budget], [param origin] at 0. Keys are in the order tiles are settled: by cost, then
## by when they were found, neighbors in [constant CombatGrid.DIRECTIONS] order.
## [param budget]: movement points; -1 for no limit. [param side]: the mover's side, whose units
## it passes; [constant CombatFact.CombatSide.NONE] passes every unit.
static func flood(
		state: CombatState,
		origin: Vector2i,
		budget: int,
		movement_type: CombatGrid.MovementType,
		side: CombatFact.CombatSide
) -> Dictionary[Vector2i, int]:
	var settled: Dictionary[Vector2i, int] = {}
	var best: Dictionary[Vector2i, int] = {origin: 0}
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		var pick: int = 0
		for i: int in range(1, frontier.size()):
			if best[frontier[i]] < best[frontier[pick]]:
				pick = i
		var tile: Vector2i = frontier.pop_at(pick)
		settled[tile] = best[tile]
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			var next: Vector2i = state.grid.step(tile, direction)
			if next == CombatFact.NO_TILE or settled.has(next):
				continue
			if not can_enter(state, next, movement_type, side):
				continue
			var total: int = best[tile] + state.grid.move_cost(next, movement_type)
			if budget >= 0 and total > budget:
				continue
			if best.has(next) and best[next] <= total:
				continue
			best[next] = total
			if not frontier.has(next):
				frontier.append(next)
	return settled


## Whether a mover of [param movement_type] on [param side] may enter [param tile] on its way:
## the terrain and objects let it in ([method CombatState.can_stand]) and no unit of another side
## stands there. An object's own tile is decided by [MapState] alone.
static func can_enter(
		state: CombatState,
		tile: Vector2i,
		movement_type: CombatGrid.MovementType,
		side: CombatFact.CombatSide
) -> bool:
	if not state.can_stand(tile, movement_type):
		return false
	var occupant: String = state.occupant_at(tile)
	if side == CombatFact.CombatSide.NONE or occupant.is_empty():
		return true
	var other: CombatFact.CombatSide = state.side_of(occupant)
	return other == side or other == CombatFact.CombatSide.NONE
