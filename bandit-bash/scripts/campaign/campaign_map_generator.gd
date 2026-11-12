# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_map_generator.gd
# Author:
# Created:  November 12, 2026
# Modified: November 12, 2026
# ==============================================================================

class_name CampaignMapGenerator
extends RefCounted
## Builds a run's [CampaignGraph] from [CampaignMapRules] and the run's map stream. Pure and
## static; never instantiated.
##
## [b]Shape:[/b] [member CampaignMapRules.path_count] walks start on floor 1 (at least two apart)
## and climb one floor at a time to the same or an adjacent column, redrawn whenever a step would
## cross an edge already drawn; every node on the floor below the boss leads to the one boss node
## in the middle column.[br]
## [b]Types,[/b] floor by floor, left to right: a node picks by weight among only the types its
## hard rules allow, the same odds as rolling until a roll is legal, in one draw. Parents are
## typed first, so each node knows the most and fewest of every type on any path reaching it,
## which is all the caps and targets need. The same rules and stream state give the same map.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# At least this many walks start in different columns; the starts are redrawn until they do.
# Godot_FE's generator (map_generator.gd, _get_random_starting_points).
const _MIN_DISTINCT_STARTS: int = 2

const _NO_TYPE: int = -1
const _NO_GROUP: int = -1
const _NO_CAP: int = -1


## A new map, or [code]null[/code] (with an error) if [param rules] or [param stream] is missing,
## the rules fail [method CampaignMapRules.validate], or they leave a node no legal type.
## Draws only from [param stream]: give it the run's
## [constant RngKey.RngPurpose.MAP_GENERATION] stream.
static func generate(rules: CampaignMapRules, stream: RngStream) -> CampaignGraph:
	if rules == null or stream == null:
		push_error("CampaignMapGenerator: generate needs rules and a stream")
		return null
	var problems: PackedStringArray = rules.validate()
	if not problems.is_empty():
		push_error("CampaignMapGenerator: unusable rules - %s" % ["; ".join(problems)])
		return null

	var graph: CampaignGraph = _build_shape(rules, stream)
	if not _assign_types(graph, rules, stream):
		return null
	return graph


# Draws the walks and returns the graph with every node typed STANDARD. Each floor's edges are
# kept as one int per column: bit c means an edge to column c on the floor above.
static func _build_shape(rules: CampaignMapRules, stream: RngStream) -> CampaignGraph:
	var floors: int = rules.floor_count
	var columns: int = rules.column_count
	var last_walked: int = floors - 1
	var edges: Array[PackedInt32Array] = []
	var visited: PackedInt32Array = []
	for floor_index: int in floors + 1:
		var row: PackedInt32Array = []
		row.resize(columns)
		edges.append(row)
		visited.append(0)

	for start: int in _draw_starts(rules, stream):
		var column: int = start
		visited[1] |= 1 << column
		for floor_number: int in range(1, last_walked):
			var next: int = _draw_step(edges[floor_number], column, columns, stream)
			var row: PackedInt32Array = edges[floor_number]
			row[column] |= 1 << next
			edges[floor_number] = row
			visited[floor_number + 1] |= 1 << next
			column = next

	var graph: CampaignGraph = CampaignGraph.new(floors, columns)
	for floor_number: int in range(1, floors):
		for column: int in columns:
			if visited[floor_number] & (1 << column) != 0:
				graph.add_node(floor_number, column, CampaignGraph.NodeType.STANDARD)
	var boss_column: int = floori(columns * 0.5)
	var boss_id: int = graph.add_node(floors, boss_column, CampaignGraph.NodeType.STANDARD)

	for floor_number: int in range(1, last_walked):
		for parent_id: int in graph.nodes_on_floor(floor_number):
			var mask: int = edges[floor_number][graph.column_of(parent_id)]
			for column: int in columns:
				if mask & (1 << column) != 0:
					graph.link(parent_id, graph.node_at(floor_number + 1, column))
	for parent_id: int in graph.nodes_on_floor(last_walked):
		graph.link(parent_id, boss_id)
	return graph


# The walks' first columns, redrawn as a set until enough of them differ.
static func _draw_starts(rules: CampaignMapRules, stream: RngStream) -> PackedInt32Array:
	var starts: PackedInt32Array = []
	var distinct: int = 0
	while distinct < _MIN_DISTINCT_STARTS:
		starts.clear()
		var seen: int = 0
		for walk: int in rules.path_count:
			var column: int = stream.randi_range(0, rules.column_count - 1)
			seen |= 1 << column
			starts.append(column)
		distinct = _bit_count(seen)
	return starts


# The column the walk at `column` steps to: one of the three nearest, clamped to the grid, so an
# edge column goes straight two times in three. A step that would cross an edge already drawn on
# this floor is redrawn; going straight never crosses, so this ends.
static func _draw_step(
		row: PackedInt32Array, column: int, columns: int, stream: RngStream
) -> int:
	while true:
		var next: int = clampi(stream.randi_range(column - 1, column + 1), 0, columns - 1)
		var is_crossing: bool = (
				(next > column and row[column + 1] & (1 << column) != 0)
				or (next < column and row[column - 1] & (1 << column) != 0)
		)
		if not is_crossing:
			return next
	return column


# Types every node: fixed rows first, then each rolled node in id order (floor by floor, left to
# right). Returns false, with an error, if a node has no legal type.
static func _assign_types(
		graph: CampaignGraph, rules: CampaignMapRules, stream: RngStream
) -> bool:
	var type_count: int = CampaignGraph.NodeType.size()
	var group_of: PackedInt32Array = _groups_by_type(rules, type_count)
	# fixed_ahead[f * type_count + t]: fixed rows of type t on floors from f up.
	var fixed_ahead: PackedInt32Array = []
	fixed_ahead.resize((rules.floor_count + 2) * type_count)
	for floor_number: int in range(rules.floor_count, 0, -1):
		var fixed_type: int = rules.fixed_rows.get(floor_number, _NO_TYPE)
		for counted: int in type_count:
			var here: int = 1 if fixed_type == counted else 0
			fixed_ahead[floor_number * type_count + counted] = (
					fixed_ahead[(floor_number + 1) * type_count + counted] + here
			)

	# Fewest and most of each type on any path from floor 1 through each node, the node included.
	var fewest: PackedInt32Array = []
	var most: PackedInt32Array = []
	fewest.resize(graph.node_count() * type_count)
	most.resize(graph.node_count() * type_count)
	var fewest_before: PackedInt32Array = []
	var most_before: PackedInt32Array = []
	fewest_before.resize(type_count)
	most_before.resize(type_count)

	for id: int in graph.node_count():
		var floor_number: int = graph.floor_of(id)
		var parents: PackedInt32Array = graph.parents_of(id)
		for counted: int in type_count:
			var low: int = 0
			var high: int = 0
			for i: int in parents.size():
				var count: int = fewest[parents[i] * type_count + counted]
				low = count if i == 0 else mini(low, count)
				high = maxi(high, most[parents[i] * type_count + counted])
			fewest_before[counted] = low
			most_before[counted] = high

		var node_type: int = rules.fixed_rows.get(floor_number, _NO_TYPE)
		if node_type == _NO_TYPE:
			var ahead_start: int = (floor_number + 1) * type_count
			node_type = _roll_type(
					graph, rules, stream, id, group_of, fewest_before, most_before,
					fixed_ahead.slice(ahead_start, ahead_start + type_count)
			)
		if node_type == _NO_TYPE:
			push_error(
					"CampaignMapGenerator: the rules leave no legal type at floor %d, column %d"
					% [floor_number, graph.column_of(id)]
			)
			return false
		graph.set_node_type(id, node_type as CampaignGraph.NodeType)

		for counted: int in type_count:
			var own: int = 1 if counted == node_type else 0
			fewest[id * type_count + counted] = fewest_before[counted] + own
			most[id * type_count + counted] = most_before[counted] + own
	return true


# One rolled node's type, or _NO_TYPE if none is legal. `fewest_before` and `most_before` count
# each type on the paths reaching the node; `ahead` counts the fixed rows above it.
static func _roll_type(
		graph: CampaignGraph,
		rules: CampaignMapRules,
		stream: RngStream,
		id: int,
		group_of: PackedInt32Array,
		fewest_before: PackedInt32Array,
		most_before: PackedInt32Array,
		ahead: PackedInt32Array
) -> int:
	var floor_number: int = graph.floor_of(id)
	var next_fixed: int = rules.fixed_rows.get(floor_number + 1, _NO_TYPE)
	var parent_groups: int = 0
	var sibling_types: int = 0
	for parent_id: int in graph.parents_of(id):
		var parent_group: int = group_of[graph.type_of(parent_id)]
		if parent_group != _NO_GROUP:
			parent_groups |= 1 << parent_group
		# Siblings to the left are already typed; those to the right check against this one.
		for sibling_id: int in graph.children_of(parent_id):
			if sibling_id < id:
				sibling_types |= 1 << graph.type_of(sibling_id)

	var types: PackedInt32Array = []
	var weights: PackedInt32Array = []
	for type: int in CampaignGraph.NodeType.size():
		var weight: int = rules.weights.get(type, 0)
		if weight <= 0 or sibling_types & (1 << type) != 0:
			continue
		if floor_number < rules.earliest_floor.get(type, 1):
			continue
		var banned: PackedInt32Array = rules.banned_floors.get(type, PackedInt32Array())
		if banned.has(floor_number):
			continue
		var group: int = group_of[type]
		if group != _NO_GROUP:
			if parent_groups & (1 << group) != 0:
				continue
			if next_fixed != _NO_TYPE and group_of[next_fixed] == group:
				continue
		var cap: int = rules.path_caps.get(type, _NO_CAP)
		if cap != _NO_CAP and most_before[type] + 1 + ahead[type] > cap:
			continue
		if fewest_before[type] + ahead[type] < rules.path_targets.get(type, 0):
			weight += rules.target_boost
		types.append(type)
		weights.append(weight)

	if types.is_empty():
		return _NO_TYPE
	return types[stream.pick_weighted(weights)]


# Each type's index in rules.no_repeat_groups, or _NO_GROUP.
static func _groups_by_type(rules: CampaignMapRules, type_count: int) -> PackedInt32Array:
	var group_of: PackedInt32Array = []
	group_of.resize(type_count)
	group_of.fill(_NO_GROUP)
	for group: int in rules.no_repeat_groups.size():
		for type: int in rules.no_repeat_groups[group]:
			if type >= 0 and type < type_count:
				group_of[type] = group
	return group_of


static func _bit_count(mask: int) -> int:
	var count: int = 0
	var rest: int = mask
	while rest > 0:
		count += rest & 1
		rest >>= 1
	return count
