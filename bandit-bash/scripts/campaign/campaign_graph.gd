# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_graph.gd
# Author:
# Created:  November 12, 2026
# Modified: November 12, 2026
# ==============================================================================

class_name CampaignGraph
extends RefCounted
## A run's campaign map: nodes on floors and columns, each with a type, its parents on the floor
## below and its children on the floor above.
##
## Pure data. [CampaignMapGenerator] builds it; the run saves it whole through [method to_dict]
## and [method from_dict], so a resumed run walks the same map. Floors count from 1 (the first
## node a run enters) to [method get_floor_count] (the boss); columns from 0. A node's id is its
## index in the order nodes were added; the generator adds them floor by floor, left to right, so
## parents always have lower ids than their children. Edges only join adjacent floors, and
## [method children_of] and [method parents_of] list ids in column order.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## What a node is. Append-only with explicit values: [method to_dict] writes the numbers, so
## renumbering or reusing one changes saved maps. Names may change freely.
enum NodeType {
	## A small skirmish.
	STANDARD = 0,
	## A combat with mini-bosses that pays an heirloom.
	KEY = 1,
	## The run's final combat, alone on the last floor.
	BOSS = 2,
	## The shop for items and heirlooms.
	ARMORY = 3,
	## The shop for recruits, runes and prefix re-rolls.
	GUILDHALL = 4,
	## The [code]?[/code] node, resolved on entry.
	UNKNOWN = 5,
	## Feast or Train.
	CAMP = 6,
	## A guaranteed chest.
	TREASURE = 7,
}

## Returned by lookups that find no node.
const NO_NODE: int = -1

# to_dict()'s keys. Never change them: saved maps are read by these names.
const _KEY_FLOORS: String = "floors"
const _KEY_COLUMNS: String = "columns"
const _KEY_NODES: String = "nodes"
const _KEY_FLOOR: String = "floor"
const _KEY_COLUMN: String = "column"
const _KEY_TYPE: String = "type"
const _KEY_CHILDREN: String = "children"

var _floor_count: int = 0
var _column_count: int = 0

# Per node, by id.
var _floors: PackedInt32Array = []
var _columns: PackedInt32Array = []
var _types: PackedInt32Array = []
var _children: Array[PackedInt32Array] = []
var _parents: Array[PackedInt32Array] = []

# Floor and column to id, for node_at().
var _by_cell: Dictionary[Vector2i, int] = {}


## An empty map of [param floor_count] floors and [param column_count] columns.
func _init(floor_count: int = 0, column_count: int = 0) -> void:
	_floor_count = maxi(floor_count, 0)
	_column_count = maxi(column_count, 0)


## Floors in the map, the boss's floor included.
func get_floor_count() -> int:
	return _floor_count


## Columns in the map's grid.
func get_column_count() -> int:
	return _column_count


## Nodes in the map; ids run from 0 to this minus 1.
func node_count() -> int:
	return _types.size()


## Adds a node and returns its id. Returns [constant NO_NODE], adding nothing, if the floor or
## column is outside the map or a node already sits there.
func add_node(floor_number: int, column: int, type: NodeType) -> int:
	var cell: Vector2i = Vector2i(floor_number, column)
	if not _is_in_map(floor_number, column) or _by_cell.has(cell):
		push_error(
				"CampaignGraph: can't add a node at floor %d, column %d" % [floor_number, column]
		)
		return NO_NODE
	var id: int = _types.size()
	_floors.append(floor_number)
	_columns.append(column)
	_types.append(type)
	_children.append(PackedInt32Array())
	_parents.append(PackedInt32Array())
	_by_cell[cell] = id
	return id


## Joins [param parent_id] to [param child_id] on the floor above it. Linking a pair twice keeps
## one edge. Returns false, changing nothing, if either id is unknown or the floors aren't
## adjacent.
func link(parent_id: int, child_id: int) -> bool:
	if not has_node_id(parent_id) or not has_node_id(child_id):
		push_error("CampaignGraph: can't link unknown nodes %d and %d" % [parent_id, child_id])
		return false
	if _floors[child_id] != _floors[parent_id] + 1:
		push_error(
				"CampaignGraph: nodes %d and %d aren't on adjacent floors" % [parent_id, child_id]
		)
		return false
	_children[parent_id] = _with_sorted(_children[parent_id], child_id)
	_parents[child_id] = _with_sorted(_parents[child_id], parent_id)
	return true


## Sets a node's type. Does nothing for an unknown id.
func set_node_type(id: int, type: NodeType) -> void:
	if not has_node_id(id):
		push_error("CampaignGraph: no node %d to type" % [id])
		return
	_types[id] = type


## Whether [param id] names a node of this map.
func has_node_id(id: int) -> bool:
	return id >= 0 and id < _types.size()


## The floor of node [param id], from 1; 0 for an unknown id.
func floor_of(id: int) -> int:
	return _floors[id] if has_node_id(id) else 0


## The column of node [param id], from 0; [constant NO_NODE] for an unknown id.
func column_of(id: int) -> int:
	return _columns[id] if has_node_id(id) else NO_NODE


## The type of node [param id]; [constant NodeType.STANDARD] for an unknown id.
func type_of(id: int) -> NodeType:
	return _types[id] as NodeType if has_node_id(id) else NodeType.STANDARD


## The ids of the nodes [param id] leads to, in column order.
func children_of(id: int) -> PackedInt32Array:
	return _children[id] if has_node_id(id) else PackedInt32Array()


## The ids of the nodes that lead to [param id], in column order.
func parents_of(id: int) -> PackedInt32Array:
	return _parents[id] if has_node_id(id) else PackedInt32Array()


## The ids of every node on [param floor_number], in column order.
func nodes_on_floor(floor_number: int) -> PackedInt32Array:
	var ids: PackedInt32Array = []
	for column: int in _column_count:
		var id: int = node_at(floor_number, column)
		if id != NO_NODE:
			ids.append(id)
	return ids


## The id of the node at [param floor_number] and [param column], or [constant NO_NODE].
func node_at(floor_number: int, column: int) -> int:
	return _by_cell.get(Vector2i(floor_number, column), NO_NODE)


## The map as JSON-safe data: [code]{"floors", "columns", "nodes"}[/code], each node a
## [code]{"floor", "column", "type", "children"}[/code] at its id's index, the type as its
## [enum NodeType] number. Parents aren't written: [method from_dict] rebuilds them from children.
func to_dict() -> Dictionary:
	var nodes: Array[Dictionary] = []
	for id: int in _types.size():
		var children: Array[int] = []
		for child_id: int in _children[id]:
			children.append(child_id)
		nodes.append({
			_KEY_FLOOR: _floors[id],
			_KEY_COLUMN: _columns[id],
			_KEY_TYPE: _types[id],
			_KEY_CHILDREN: children,
		})
	return {
		_KEY_FLOORS: _floor_count,
		_KEY_COLUMNS: _column_count,
		_KEY_NODES: nodes,
	}


# True when floor and column fall inside the grid.
func _is_in_map(floor_number: int, column: int) -> bool:
	return (
			floor_number >= 1 and floor_number <= _floor_count
			and column >= 0 and column < _column_count
	)


# A copy of a sorted id list with `id` inserted in order, or unchanged if it's already there.
func _with_sorted(ids: PackedInt32Array, id: int) -> PackedInt32Array:
	if ids.has(id):
		return ids
	var sorted_ids: PackedInt32Array = ids.duplicate()
	sorted_ids.append(id)
	sorted_ids.sort()
	return sorted_ids


## Reads data written by [method to_dict], numbers as ints or whole floats (JSON gives floats).
## Returns [code]null[/code] if a key is missing, a number isn't whole, a type isn't a
## [enum NodeType], two nodes share a cell, or an edge doesn't climb one floor.
static func from_dict(data: Dictionary) -> CampaignGraph:
	var floor_count: int = _whole(data.get(_KEY_FLOORS))
	var column_count: int = _whole(data.get(_KEY_COLUMNS))
	var nodes: Variant = data.get(_KEY_NODES)
	if floor_count < 1 or column_count < 1 or not nodes is Array:
		return null

	var graph: CampaignGraph = CampaignGraph.new(floor_count, column_count)
	var entries: Array = nodes
	var all_children: Array[Array] = []
	for entry: Variant in entries:
		if not entry is Dictionary:
			return null
		var node_data: Dictionary = entry
		var type: int = _whole(node_data.get(_KEY_TYPE))
		var children: Variant = node_data.get(_KEY_CHILDREN)
		if not NodeType.values().has(type) or not children is Array:
			return null
		var floor_number: int = _whole(node_data.get(_KEY_FLOOR))
		var column: int = _whole(node_data.get(_KEY_COLUMN))
		var is_in_map: bool = (
				floor_number >= 1 and floor_number <= floor_count
				and column >= 0 and column < column_count
		)
		if not is_in_map or graph.node_at(floor_number, column) != NO_NODE:
			return null
		graph.add_node(floor_number, column, type as NodeType)
		all_children.append(children)

	for id: int in all_children.size():
		for child: Variant in all_children[id]:
			var child_id: int = _whole(child)
			if not graph.has_node_id(child_id):
				return null
			if graph.floor_of(child_id) != graph.floor_of(id) + 1:
				return null
			graph.link(id, child_id)
	return graph


# The int in `value` if it is an int or a whole float; -1 otherwise. Every number to_dict()
# writes is 0 or more, so -1 always fails the caller's range check.
static func _whole(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if number == floorf(number):
			return roundi(number)
	return -1
