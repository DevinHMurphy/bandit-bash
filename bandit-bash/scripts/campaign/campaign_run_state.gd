# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_run_state.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name CampaignRunState
extends RefCounted
## A run's campaign state: its map, the floor and node it has reached, its [RunFlow], each seat's
## [SeatRun] and the campaign fact log.
##
## Pure rules state, held by [member CampaignSession.run] and built by [RunStart]. It changes only
## through [method resolve], which checks a [CampaignCommand] against the state as it is when the
## command arrives, so the first arrival wins and a rejected command changes nothing; every change
## records a [CampaignFact]. [b]Route invariant:[/b] [member visited] holds one node per floor from
## floor 1 up to [member floor_number], each a child of the one before, and [member node] is its
## last (or [constant CampaignGraph.NO_NODE] before the first). Choosing a node locks its floor.
## Saved as the [code]campaign_map[/code] and [code]run_flow[/code] sections and each seat's four
## ([RunSaveSections]).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# capture_map()'s keys. Never change them: saved runs are read by these names.
const _KEY_GRAPH: String = "graph"
const _KEY_VISITED: String = "visited"
const _KEY_FLOOR: String = "floor"
const _KEY_NODE: String = "node"

## The run's map. Null only in a state not yet built or restored.
var graph: CampaignGraph = null

## Ids of the nodes entered, one per floor, floor 1 first.
var visited: PackedInt32Array = []

## The floor of [member node]; 0 before the first node is chosen.
var floor_number: int = 0

## The node the run last entered; [constant CampaignGraph.NO_NODE] before the first.
var node: int = CampaignGraph.NO_NODE

## The stage within [member node], and the state every seat shares.
var flow: RunFlow = RunFlow.new()

## Each seat's part of the run, by seat.
var seats: Dictionary[int, SeatRun] = {}

## Every campaign fact recorded this session, in order. Not saved: like a battle's log, it
## starts empty when a run is continued.
var fact_log: Array[CampaignFact] = []


## The seat [param seat]'s part of the run; null for a seat not in it.
func seat_run(seat: int) -> SeatRun:
	return seats.get(seat, null)


## The run's seats, ascending.
func seat_numbers() -> PackedInt32Array:
	var numbers: PackedInt32Array = PackedInt32Array(seats.keys())
	numbers.sort()
	return numbers


## Whether the run is on the map, between nodes.
func is_on_map() -> bool:
	return flow.is_on_map()


## Records [param fact] at the end of [member fact_log], numbering it from 1.
func record(fact: CampaignFact) -> void:
	fact.seq = fact_log.size() + 1
	fact_log.append(fact)


## Checks [param command] against the run as it stands, then resolves it. Returns its batch: the
## facts it recorded, or the reason it was rejected, which records nothing. A seat outside the run
## is rejected before [method CampaignCommand.validate].
func resolve(command: CampaignCommand) -> CampaignBatch:
	var batch: CampaignBatch = CampaignBatch.new()
	batch.seat = command.seat
	batch.arrival = command.arrival
	batch.label = command.get_label()
	if not seats.has(command.seat):
		batch.rejected_reason = "seat %d isn't in the run" % [command.seat]
		return batch
	batch.rejected_reason = command.validate(self)
	if batch.is_rejected():
		return batch
	var first: int = fact_log.size()
	command.resolve(self)
	batch.facts = fact_log.slice(first)
	return batch


## Enters [param node_id] on the next floor and locks that floor: the rules of
## [ChooseNodeCommand], which checks the move first.
func enter_node(node_id: int) -> void:
	visited.append(node_id)
	floor_number = graph.floor_of(node_id)
	node = node_id
	flow.stage = RunFlow.Stage.NODE


## The map and the route taken as plain JSON, for the [code]campaign_map[/code] section.
func capture_map() -> Dictionary:
	var route: Array[int] = []
	for node_id: int in visited:
		route.append(node_id)
	return {
		_KEY_GRAPH: graph.to_dict() if graph != null else {},
		_KEY_VISITED: route,
		_KEY_FLOOR: floor_number,
		_KEY_NODE: node,
	}


## Takes the map [param data], as [method capture_map] wrote it. Returns
## [constant ERR_INVALID_DATA], changing nothing, for a graph [method CampaignGraph.from_dict]
## refuses or a route that breaks the route invariant (see the class doc).
func restore_map(data: Dictionary) -> Error:
	var graph_data: Variant = data.get(_KEY_GRAPH)
	var read_graph: CampaignGraph = (
			CampaignGraph.from_dict(graph_data as Dictionary) if graph_data is Dictionary else null
	)
	var read_floor: Variant = whole_number(data.get(_KEY_FLOOR))
	var read_node: Variant = whole_number(data.get(_KEY_NODE))
	var route: Variant = data.get(_KEY_VISITED)
	if read_graph == null or read_floor == null or read_node == null or not route is Array:
		return _refuse("map", data)
	var read_route: PackedInt32Array = []
	for entry: Variant in route as Array:
		var node_id: Variant = whole_number(entry)
		if node_id == null:
			return _refuse("map", data)
		read_route.append(node_id as int)
	if not _is_route(read_graph, read_route, read_floor as int, read_node as int):
		return _refuse("map", data)

	graph = read_graph
	visited = read_route
	floor_number = read_floor as int
	node = read_node as int
	return OK


## Takes the run flow [param data] ([method RunFlow.restore]), after [method restore_map]. Returns
## [constant ERR_INVALID_DATA], changing nothing, for data the flow refuses or a stage inside a
## node before any node was entered.
func restore_flow(data: Dictionary) -> Error:
	var read: RunFlow = RunFlow.new()
	if read.restore(data) != OK:
		return ERR_INVALID_DATA
	if not read.is_on_map() and node == CampaignGraph.NO_NODE:
		return _refuse("run flow", data)
	flow = read
	return OK


func _refuse(what: String, data: Dictionary) -> Error:
	push_error("CampaignRunState: the %s data is unusable - %s" % [what, data])
	return ERR_INVALID_DATA


## [param value] as an int when it is one or a whole float (JSON gives every number back as a
## float); null otherwise.
static func whole_number(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if number == floorf(number) and absf(number) <= CampaignFact.MAX_EXACT_JSON_INT:
			return int(number)
	return null


# Whether route climbs graph one floor per node from floor 1, each a child of the one before, to
# floor_reached and last_node.
static func _is_route(
		map: CampaignGraph, route: PackedInt32Array, floor_reached: int, last_node: int
) -> bool:
	if floor_reached != route.size():
		return false
	if route.is_empty():
		return last_node == CampaignGraph.NO_NODE
	var previous: int = CampaignGraph.NO_NODE
	for index: int in route.size():
		var node_id: int = route[index]
		if not map.has_node_id(node_id) or map.floor_of(node_id) != index + 1:
			return false
		if previous != CampaignGraph.NO_NODE and not map.children_of(previous).has(node_id):
			return false
		previous = node_id
	return last_node == previous
