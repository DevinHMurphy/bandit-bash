# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_map_rules.gd
# Author:
# Created:  November 12, 2026
# Modified: November 12, 2026
# ==============================================================================

class_name CampaignMapRules
extends Resource
## The campaign map's shape and node rules, read by [CampaignMapGenerator]: grid size, rolled
## weights, fixed rows, floor limits, per-path caps and soft targets.
##
## The run's copy lives in [code]res://data/campaign/campaign_map_rules.tres[/code]; values come
## from game-vision.md (Run structure, Node placement), with the grid and path count from
## Godot_FE's generator. Read-only at runtime. A "path" is any route from floor 1 to the boss.
## Hard rules (fixed rows, floor limits, no repeats, caps, distinct children) are never broken;
## targets only raise weights. [method validate] lists what would stop a map being built.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Most columns the generator can track: it keeps each floor's edges as bits of one int.
const MAX_COLUMNS: int = 31

@export_group("Shape")

## Floors in the map, the boss's floor included; the boss is alone on the last one.[br]
## [b]Units:[/b] floors. At least 3: a first floor, one more, and the boss.
@export_range(3, 40, 1) var floor_count: int = 3

## Columns in the grid. Paths step to the same or an adjacent column on each floor.[br]
## [b]Units:[/b] columns. At least 2, so two paths can start apart.
@export_range(2, MAX_COLUMNS, 1) var column_count: int = 2

## Walks drawn from floor 1 to the boss. Starts may share a column (paths then merge), but at
## least two differ. More walks give more nodes and more crossings between paths.[br]
## [b]Units:[/b] walks. At least 2.
@export_range(2, 20, 1) var path_count: int = 2

@export_group("Node types")

## Each [enum CampaignGraph.NodeType]'s weight on a rolled floor; a type that's absent or 0 is
## never rolled. A node picks among the types its rules allow, each with weight over their total.
## [b]Units:[/b] relative weight, whole numbers.
@export var weights: Dictionary[CampaignGraph.NodeType, int] = {}

## Floors whose every node is one type, by floor number (from 1). The last floor must be
## [constant CampaignGraph.NodeType.BOSS]. Fixed rows skip floor limits and the distinct-children
## rule, but count toward caps, targets and the no-repeat rule.
@export var fixed_rows: Dictionary[int, CampaignGraph.NodeType] = {}

@export_group("Floor limits")

## The lowest floor a type can be rolled on; a type that's absent can be rolled anywhere.[br]
## [b]Units:[/b] floor number. [b]1:[/b] no limit.
@export var earliest_floor: Dictionary[CampaignGraph.NodeType, int] = {}

## Floors a type is never rolled on, by type; absent means none.
@export var banned_floors: Dictionary[CampaignGraph.NodeType, PackedInt32Array] = {}

## Groups of types that never follow one another on a path: a node never has a parent from its
## own group. Types outside every group may repeat.
@export var no_repeat_groups: Array[PackedInt32Array] = []

@export_group("Per-path counts")

## The most nodes of a type any path may hold, fixed rows included; absent means no cap.[br]
## [b]Units:[/b] nodes per path. [b]0:[/b] the type is never rolled, and must have no fixed row.
@export var path_caps: Dictionary[CampaignGraph.NodeType, int] = {}

## How many nodes of a type every path should hold, fixed rows included. Not guaranteed: while
## some path through a node is below a type's target, that type's weight there gains
## [member target_boost]. [b]Units:[/b] nodes per path. [b]0:[/b] no target.
@export var path_targets: Dictionary[CampaignGraph.NodeType, int] = {}

# ASSUMPTION: the boost's value in the .tres is a measured proposal awaiting the user's approval.
## Weight added to a type with a target at a node where some path through it is still short of
## that target. Compare with [member weights] (the vision's total is 12).[br]
## [b]Units:[/b] relative weight. [b]0:[/b] targets have no effect.
@export_range(0, 100, 1) var target_boost: int = 0

@export_group("")


## What stops a map being built from these rules, one line each; empty when they're usable.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if floor_count < 3:
		problems.append("floor_count must be at least 3, not %d" % [floor_count])
	if column_count < 2 or column_count > MAX_COLUMNS:
		problems.append("column_count must be 2 to %d, not %d" % [MAX_COLUMNS, column_count])
	if path_count < 2:
		problems.append("path_count must be at least 2, not %d" % [path_count])
	if fixed_rows.get(floor_count, -1) != CampaignGraph.NodeType.BOSS:
		problems.append("the last floor, %d, must be a fixed Boss row" % [floor_count])
	if weights.get(CampaignGraph.NodeType.BOSS, 0) > 0:
		problems.append("Boss can't be rolled")
	for type: CampaignGraph.NodeType in weights:
		if weights[type] < 0:
			problems.append("weight of type %d is negative" % [type])
	for floor_number: int in fixed_rows:
		var is_boss: bool = fixed_rows[floor_number] == CampaignGraph.NodeType.BOSS
		if floor_number < 1 or floor_number > floor_count:
			problems.append("fixed row %d is outside the map" % [floor_number])
		elif is_boss and floor_number != floor_count:
			problems.append("Boss is fixed on floor %d, not the last" % [floor_number])
	for type: CampaignGraph.NodeType in path_caps:
		if fixed_count(type) > path_caps[type]:
			problems.append("type %d's fixed rows exceed its cap" % [type])
	return problems


## How many fixed rows of [param type] lie on floors from [param from_floor] up; every path
## crosses each of them once.
func fixed_count(type: CampaignGraph.NodeType, from_floor: int = 1) -> int:
	var count: int = 0
	for floor_number: int in fixed_rows:
		if floor_number >= from_floor and fixed_rows[floor_number] == type:
			count += 1
	return count
