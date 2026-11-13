# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_map_pool.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name CombatMapPool
extends Resource
## The maps one kind of combat node draws from on a range of floors: one difficulty step's
## Standard, Key or Boss maps (game-vision.md, Run structure).
##
## Rules data, an entry of [CombatMapPools] in [code]res://data/campaign/[/code]; read-only at
## runtime. A battle's map is drawn from the pool's maps the run hasn't used since the pool last
## refilled ([method CampaignRunState.battle_request]).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The node type this pool serves: [constant CampaignGraph.NodeType.STANDARD],
## [constant CampaignGraph.NodeType.KEY] or [constant CampaignGraph.NodeType.BOSS]. Any other type
## never draws a map.
@export var node_type: CampaignGraph.NodeType = CampaignGraph.NodeType.STANDARD

## The first campaign floor the pool serves, counted from 1. Keep the pools of one node type from
## overlapping: the first pool listed that covers a floor wins.
@export_range(1, 99, 1) var first_floor: int = 1

## The last campaign floor the pool serves, counted from 1; equal to [member first_floor] for a
## single floor. Below [member first_floor], the pool serves no floor.
@export_range(1, 99, 1) var last_floor: int = 1

## The maps, in a fixed order: setup draws one by index, so reordering them changes which map a
## seed gives. [b]Empty:[/b] the pool can't begin a battle.
@export var maps: Array[CombatMapDefinition] = []


## Whether the pool serves a node of [param type] on floor [param floor_number].
func covers(type: CampaignGraph.NodeType, floor_number: int) -> bool:
	return type == node_type and floor_number >= first_floor and floor_number <= last_floor


## Ids of [member maps], in order; a missing map is left out.
func map_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for map: CombatMapDefinition in maps:
		if map != null:
			ids.append(map.id)
	return ids
