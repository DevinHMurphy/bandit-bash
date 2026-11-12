# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_checks.gd
# Author:
# Created:  November 12, 2026
# Modified: November 12, 2026
# ==============================================================================

extends RefCounted
## Checks a generated [CampaignGraph] against its [CampaignMapRules], for the campaign suite and
## the map bench. Written from the rules, not from [CampaignMapGenerator]'s code, so a generator
## bug isn't repeated here. A "route" is any path a run can take, floor 1 to the boss; caps and
## targets are judged over every route. Static; never instantiated.

# route_stats()'s keys.
const ROUTES: String = "routes"
const MISSED: String = "missed"
const MEANS: String = "means"


## Every hard rule [param graph] breaks, one line each; empty when it follows them all.
static func violations(graph: CampaignGraph, rules: CampaignMapRules) -> PackedStringArray:
	var problems: PackedStringArray = []
	if graph == null:
		problems.append("no graph")
		return problems
	_check_shape(graph, rules, problems)
	_check_types(graph, rules, problems)
	_check_caps(graph, rules, problems)
	return problems


## Counts over every route of [param graph]: [constant ROUTES], the number of routes;
## [constant MISSED], by type, how many routes hold fewer of it than its target in
## [param rules] (target types only); [constant MEANS], by type, the average count per route.
static func route_stats(graph: CampaignGraph, rules: CampaignMapRules) -> Dictionary:
	var type_count: int = CampaignGraph.NodeType.size()
	var cap: int = 0
	for type: int in rules.path_targets:
		cap = maxi(cap, rules.path_targets[type])
	var buckets: int = cap + 1
	# Per node: routes reaching it; per type, the sum of counts over them, and how many routes
	# hold 0, 1, ... of it, the last bucket meaning "cap or more".
	var routes: PackedInt64Array = []
	var sums: PackedInt64Array = []
	var histogram: PackedInt64Array = []
	routes.resize(graph.node_count())
	sums.resize(graph.node_count() * type_count)
	histogram.resize(graph.node_count() * type_count * buckets)

	var boss_id: int = CampaignGraph.NO_NODE
	for id: int in graph.node_count():
		var own_type: int = graph.type_of(id)
		var parents: PackedInt32Array = graph.parents_of(id)
		if parents.is_empty():
			routes[id] = 1
		for parent_id: int in parents:
			routes[id] += routes[parent_id]
		for type: int in type_count:
			var own: int = 1 if own_type == type else 0
			var sum: int = routes[id] * own
			for parent_id: int in parents:
				sum += sums[parent_id * type_count + type]
			sums[id * type_count + type] = sum
			var base: int = (id * type_count + type) * buckets
			if parents.is_empty():
				histogram[base + mini(own, cap)] = 1
			for parent_id: int in parents:
				var parent_base: int = (parent_id * type_count + type) * buckets
				for bucket: int in buckets:
					var to: int = mini(bucket + own, cap)
					histogram[base + to] += histogram[parent_base + bucket]
		if graph.floor_of(id) == graph.get_floor_count():
			boss_id = id

	var missed: Dictionary[int, int] = {}
	var means: Dictionary[int, float] = {}
	if boss_id == CampaignGraph.NO_NODE:
		return {ROUTES: 0, MISSED: missed, MEANS: means}
	var total: int = routes[boss_id]
	for type: int in type_count:
		means[type] = float(sums[boss_id * type_count + type]) / float(total)
	for type: int in rules.path_targets:
		var target: int = rules.path_targets[type]
		var short: int = 0
		for bucket: int in target:
			short += histogram[(boss_id * type_count + type) * buckets + bucket]
		missed[type] = short
	return {ROUTES: total, MISSED: missed, MEANS: means}


# Grid, starts, edges that climb one floor to an adjacent column without crossing, and the boss.
static func _check_shape(
		graph: CampaignGraph, rules: CampaignMapRules, problems: PackedStringArray
) -> void:
	var floors: int = rules.floor_count
	if graph.get_floor_count() != floors or graph.get_column_count() != rules.column_count:
		problems.append("grid is %d x %d" % [graph.get_floor_count(), graph.get_column_count()])
	var starts: PackedInt32Array = graph.nodes_on_floor(1)
	if starts.size() < 2 or starts.size() > rules.path_count:
		problems.append("%d starting nodes" % [starts.size()])
	var bosses: PackedInt32Array = graph.nodes_on_floor(floors)
	if bosses.size() != 1:
		problems.append("%d nodes on the boss floor" % [bosses.size()])
	elif graph.column_of(bosses[0]) != floori(rules.column_count * 0.5):
		problems.append("the boss isn't in the middle column")

	for id: int in graph.node_count():
		var floor_number: int = graph.floor_of(id)
		var children: PackedInt32Array = graph.children_of(id)
		if floor_number > 1 and graph.parents_of(id).is_empty():
			problems.append("%s can't be reached" % [_name(graph, id)])
		if floor_number < floors and children.is_empty():
			problems.append("%s is a dead end" % [_name(graph, id)])
		if floor_number == floors - 1 and children != bosses:
			problems.append("%s doesn't lead to the boss" % [_name(graph, id)])
		for child_id: int in children:
			if graph.floor_of(child_id) != floor_number + 1:
				problems.append("%s skips a floor" % [_name(graph, id)])
			var step: int = absi(graph.column_of(child_id) - graph.column_of(id))
			if floor_number < floors - 1 and step > 1:
				problems.append("%s steps %d columns" % [_name(graph, id), step])

	# Two edges a->b and c->d on one floor cross when a is left of c but b is right of d.
	for floor_number: int in range(1, floors - 1):
		var edges: Array[Vector2i] = []
		for id: int in graph.nodes_on_floor(floor_number):
			for child_id: int in graph.children_of(id):
				edges.append(Vector2i(graph.column_of(id), graph.column_of(child_id)))
		for a: Vector2i in edges:
			for b: Vector2i in edges:
				if a.x < b.x and a.y > b.y:
					problems.append("edges cross on floor %d" % [floor_number])


# Fixed rows, floor limits, no repeats on a path, and distinct children.
static func _check_types(
		graph: CampaignGraph, rules: CampaignMapRules, problems: PackedStringArray
) -> void:
	for id: int in graph.node_count():
		var floor_number: int = graph.floor_of(id)
		var type: CampaignGraph.NodeType = graph.type_of(id)
		var is_fixed: bool = rules.fixed_rows.has(floor_number)
		if is_fixed and type != rules.fixed_rows[floor_number]:
			problems.append("%s breaks its fixed row" % [_name(graph, id)])
		if not is_fixed:
			if type == CampaignGraph.NodeType.BOSS:
				problems.append("%s is a second boss" % [_name(graph, id)])
			if floor_number < rules.earliest_floor.get(type, 1):
				problems.append("%s is below its earliest floor" % [_name(graph, id)])
			var banned: PackedInt32Array = rules.banned_floors.get(type, PackedInt32Array())
			if banned.has(floor_number):
				problems.append("%s is on a banned floor" % [_name(graph, id)])

		var children: PackedInt32Array = graph.children_of(id)
		for child_id: int in children:
			if _same_group(rules, type, graph.type_of(child_id)):
				problems.append("%s repeats into its child" % [_name(graph, id)])
		if rules.fixed_rows.has(floor_number + 1):
			continue
		var child_types: Array[int] = []
		for child_id: int in children:
			if child_types.has(graph.type_of(child_id)):
				problems.append("%s has two children of one type" % [_name(graph, id)])
			child_types.append(graph.type_of(child_id))


# The most of each capped type on any route, fixed rows included, against its cap.
static func _check_caps(
		graph: CampaignGraph, rules: CampaignMapRules, problems: PackedStringArray
) -> void:
	for type: int in rules.path_caps:
		var most: PackedInt32Array = []
		most.resize(graph.node_count())
		var highest: int = 0
		for id: int in graph.node_count():
			var before: int = 0
			for parent_id: int in graph.parents_of(id):
				before = maxi(before, most[parent_id])
			most[id] = before + (1 if graph.type_of(id) == type else 0)
			highest = maxi(highest, most[id])
		if highest > rules.path_caps[type]:
			problems.append("a route holds %d of type %d, cap %d" % [
				highest, type, rules.path_caps[type],
			])


static func _same_group(rules: CampaignMapRules, a: int, b: int) -> bool:
	for group: PackedInt32Array in rules.no_repeat_groups:
		if group.has(a) and group.has(b):
			return true
	return false


static func _name(graph: CampaignGraph, id: int) -> String:
	return "node %d (floor %d, column %d, type %d)" % [
		id, graph.floor_of(id), graph.column_of(id), graph.type_of(id),
	]
