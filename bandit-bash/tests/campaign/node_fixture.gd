# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     node_fixture.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Shared setup for the Treasure and Camp cases (treasure_cases.gd, camp_cases.gd): real runs from
## the real catalog and map rules, solo or two-seat, put inside a node of a wanted type on a route
## the run's own checks accept; a run through JSON, as a quit and Continue gives it back; and the
## fact kinds a run recorded. Static; never instanced.

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const MERCENARY: String = "mercenary"


## A new run on [param run_seed] with no starting offer: solo, or [param seat_count] seats.
static func session(run_seed: int, seat_count: int = 1) -> CampaignSession:
	var seats: PackedInt32Array = []
	var factions: Dictionary[int, String] = {}
	for seat: int in seat_count:
		seats.append(seat)
		factions[seat] = MERCENARY
	var mode: CampaignData.Mode = (
			CampaignData.Mode.SOLO if seat_count == 1 else CampaignData.Mode.MULTIPLAYER
	)
	var made: CampaignSession = CampaignSession.new(mode, run_seed, seats)
	var start: RunStart = RunStart.build(
			load(RULES_PATH) as CampaignMapRules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			EffectCatalog.index(),
			factions,
			made.ids
	)
	made.run = start.run
	return made


## Puts [param run] inside the first node of [param type] reached from floor 1 (depth first, in id
## order), on a route of one node per floor, as choosing each would. Returns false, changing
## nothing, when the map has none.
static func enter(run: CampaignRunState, type: CampaignGraph.NodeType) -> bool:
	var route: PackedInt32Array = route_to(run.graph, type)
	if route.is_empty():
		return false
	run.visited = route
	run.floor_number = route.size()
	run.node = route[route.size() - 1]
	run.flow.stage = RunFlow.Stage.NODE
	return true


## The first route from floor 1 to a node of [param type] (see [method enter]); empty for none.
static func route_to(graph: CampaignGraph, type: CampaignGraph.NodeType) -> PackedInt32Array:
	var routes: Array[PackedInt32Array] = []
	var starts: PackedInt32Array = graph.nodes_on_floor(1)
	for index: int in range(starts.size() - 1, -1, -1):
		routes.append(PackedInt32Array([starts[index]]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_back()
		var last: int = route[route.size() - 1]
		if graph.type_of(last) == type:
			return route
		var children: PackedInt32Array = graph.children_of(last).duplicate()
		children.sort()
		for index: int in range(children.size() - 1, -1, -1):
			var longer: PackedInt32Array = route.duplicate()
			longer.append(children[index])
			routes.append(longer)
	return PackedInt32Array()


## [param run] as a quit and Continue gives it back: every section through JSON; null when one
## is refused.
static func through_json(run: CampaignRunState) -> CampaignRunState:
	var copied: CampaignRunState = CampaignRunState.new()
	if (
			copied.restore_map(json(run.capture_map())) != OK
			or copied.restore_flow(json(run.flow.capture())) != OK
	):
		return null
	for seat: int in run.seat_numbers():
		var source: SeatRun = run.seat_run(seat)
		var seat_run: SeatRun = SeatRun.new(seat)
		if (
				seat_run.restore_roster(json(source.capture_roster())) != OK
				or seat_run.restore_heirlooms(json(source.capture_heirlooms())) != OK
				or seat_run.restore_runes(json(source.capture_runes())) != OK
				or seat_run.restore_economy(json(source.capture_economy())) != OK
		):
			return null
		copied.seats[seat] = seat_run
	return copied


## [param data] after a trip through JSON.
static func json(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	return parsed if parsed is Dictionary else {}


## The kinds of [param batch]'s facts, in order.
static func kinds(batch: CampaignBatch) -> Array[CampaignFact.Kind]:
	var found: Array[CampaignFact.Kind] = []
	for fact: CampaignFact in batch.facts:
		found.append(fact.kind)
	return found


## Whether [param seat_run]'s roster invariant holds: a restore of its capture accepts it.
static func is_whole(seat_run: SeatRun) -> bool:
	return SeatRun.new(seat_run.seat).restore_roster(seat_run.capture_roster()) == OK


## A new item of [param definition_id] in [param seat_run]'s convoy, its id from [param ids].
static func add_to_convoy(
		seat_run: SeatRun, definition_id: String, ids: InstanceIdAllocator
) -> String:
	var item_id: String = ids.next_item_id(definition_id)
	seat_run.items[item_id] = ItemInstance.new(item_id, definition_id)
	seat_run.convoy.append(item_id)
	return item_id
