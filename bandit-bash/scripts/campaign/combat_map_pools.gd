# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_map_pools.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name CombatMapPools
extends Resource
## Every combat node's map pool, by node type and floor: the data a battle's map is drawn from.
##
## Rules data at [constant PATH], read-only at runtime. [method CampaignRunState.battle_request]
## looks a node's pool up with [method pool_for] and offers setup the maps the run hasn't used
## since the pool last refilled ([method available]), so no map repeats until its pool is used up
## (game-vision.md, Run structure). Adding maps or steps is a data change only.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Where the game's pools are.
const PATH: String = "res://data/campaign/combat_map_pools.tres"

## The pools, searched in order: the first that covers a node's type and floor is its pool.
## [b]Empty:[/b] no combat node can begin a battle.
@export var pools: Array[CombatMapPool] = []


## The pool of a node of [param type] on floor [param floor_number]; null when none covers it.
func pool_for(type: CampaignGraph.NodeType, floor_number: int) -> CombatMapPool:
	for pool: CombatMapPool in pools:
		if pool != null and pool.covers(type, floor_number):
			return pool
	return null


## The maps of [param pool] whose ids aren't in [param used], in pool order; every map of the pool
## when all of them are used, which is the pool refilling. Empty for a null or empty pool.
static func available(pool: CombatMapPool, used: PackedStringArray) -> Array[CombatMapDefinition]:
	var fresh: Array[CombatMapDefinition] = []
	var every: Array[CombatMapDefinition] = []
	if pool == null:
		return fresh
	for map: CombatMapDefinition in pool.maps:
		if map == null:
			continue
		every.append(map)
		if not used.has(map.id):
			fresh.append(map)
	return fresh if not fresh.is_empty() else every


## The game's pools from [constant PATH]; null, with an error, when they don't load.
static func load_default() -> CombatMapPools:
	var loaded: CombatMapPools = load(PATH) as CombatMapPools
	if loaded == null:
		push_error("CombatMapPools: no map pools at %s" % [PATH])
	return loaded
