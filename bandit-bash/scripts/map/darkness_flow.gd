# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_flow.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name DarknessFlow
extends RefCounted
## Where the darkness can flow on a map and what it costs to get there: floodable tiles, each
## tile's height above the drain, the step cost between neighbors, and a source's flow costs
## (the-darkness.md, Waves and creep).
##
## Pure, static and deterministic rules code reading a [CombatState]: terrain through its grid,
## doors and breakables through its [member CombatState.map]. Units never matter. Nothing is
## cached: [DarknessState] derives heights and flow costs afresh for each operation, so a break or
## a door change needs no invalidation. Every search walks the four directions only.
##
## @tutorial(The darkness): docs/design/the-darkness.md
## @tutorial(The darkness plan): docs/plans/2026-11-03-the-darkness.md

## The height of a tile that can't reach the drain, and of every tile when there is no drain.
const NO_HEIGHT: int = -1

## Step cost to a lower neighbor: downhill (the-darkness.md, Values: step costs 1 / 2 / 3).
const STEP_DOWNHILL: int = 1

## Step cost to a neighbor of the same height, or when either tile has no height: level
## (the-darkness.md, Values).
const STEP_LEVEL: int = 2

## Step cost to a higher neighbor: uphill (the-darkness.md, Values).
const STEP_UPHILL: int = 3


## Whether the darkness may flood [param tile]: on the map, standable by some movement type but
## Flier, and not a closed door or an unbroken breakable (plan question 10;
## [method MapObjects.is_floodable]). Units never block it.
static func is_floodable(state: CombatState, tile: Vector2i) -> bool:
	return MapObjects.is_floodable(state, tile)


## Each floodable tile's walking distance to [param drain] over floodable tiles, 4-directional,
## the drain at 0. A tile that can't reach the drain is absent: its height is
## [constant NO_HEIGHT]. Empty when [param drain] is [constant CombatFact.NO_TILE] or isn't
## floodable.
static func heights(state: CombatState, drain: Vector2i) -> Dictionary[Vector2i, int]:
	var found: Dictionary[Vector2i, int] = {}
	if drain == CombatFact.NO_TILE or not is_floodable(state, drain):
		return found
	found[drain] = 0
	var frontier: Array[Vector2i] = [drain]
	var next_index: int = 0
	# Breadth first: every step costs 1, so a tile's first visit is its distance.
	while next_index < frontier.size():
		var tile: Vector2i = frontier[next_index]
		next_index += 1
		for next: Vector2i in state.grid.neighbors(tile):
			if found.has(next) or not is_floodable(state, next):
				continue
			found[next] = found[tile] + 1
			frontier.append(next)
	return found


## The cost of the darkness stepping from [param from] to its neighbor [param to], by their
## [param tile_heights] ([method heights]): [constant STEP_DOWNHILL], [constant STEP_LEVEL] or
## [constant STEP_UPHILL].
static func step_cost(
		tile_heights: Dictionary[Vector2i, int], from: Vector2i, to: Vector2i
) -> int:
	var from_height: int = tile_heights.get(from, NO_HEIGHT)
	var to_height: int = tile_heights.get(to, NO_HEIGHT)
	if from_height == NO_HEIGHT or to_height == NO_HEIGHT or from_height == to_height:
		return STEP_LEVEL
	return STEP_DOWNHILL if to_height < from_height else STEP_UPHILL


## The flow cost of every floodable tile the source on [param source_tiles] can reach: the
## cheapest total [method step_cost] from any of its floodable tiles, which are at 0. A tile it
## can't reach is absent. [param tile_heights]: [method heights] for the current drain.
static func flow_costs(
		state: CombatState,
		source_tiles: Array[Vector2i],
		tile_heights: Dictionary[Vector2i, int]
) -> Dictionary[Vector2i, int]:
	var settled: Dictionary[Vector2i, int] = {}
	var best: Dictionary[Vector2i, int] = {}
	var frontier: Array[Vector2i] = []
	for tile: Vector2i in source_tiles:
		if best.has(tile) or not is_floodable(state, tile):
			continue
		best[tile] = 0
		frontier.append(tile)
	# A linear pick of the cheapest open tile: maps hold at most a few hundred tiles, so a heap
	# isn't worth its code (a full recalculation's cost is measured in tests/darkness).
	while not frontier.is_empty():
		var pick: int = 0
		for i: int in range(1, frontier.size()):
			if best[frontier[i]] < best[frontier[pick]]:
				pick = i
		var tile: Vector2i = frontier.pop_at(pick)
		settled[tile] = best[tile]
		for next: Vector2i in state.grid.neighbors(tile):
			if settled.has(next) or not is_floodable(state, next):
				continue
			var total: int = best[tile] + step_cost(tile_heights, tile, next)
			if best.has(next) and best[next] <= total:
				continue
			if not best.has(next):
				frontier.append(next)
			best[next] = total
	return settled
