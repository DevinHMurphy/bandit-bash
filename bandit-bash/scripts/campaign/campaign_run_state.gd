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
## command arrives (the first arrival wins; a rejection changes nothing), and a battle's end, which
## [method apply_battle] applies to a copy so a failed save changes nothing; each records
## [CampaignFact]s. [b]Route invariant:[/b] [member visited] holds one node per floor from floor 1
## to [member floor_number], each a child of the one before, [member node] its last
## ([constant CampaignGraph.NO_NODE] before the first). A combat node's battle comes from
## [method battle_request]. Saved as [RunSaveSections]' six sections.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-001 - Apply recruit grants, unnamed heirloom and rune grants, and a rune with every
## slot full (the discard choice); each is reported and dropped (RN9, P09).

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


## The battle of the combat node the run is in: floor and node from [member floor_number] and
## [member node], the maps of its pool in [param pools] that [member RunFlow.used_maps] hasn't used
## ([method CombatMapPools.available]), and each seat's living army with its current HP, items and
## heirlooms, a repeated heirloom once per copy. The army's unit and item instances are the run's
## own, so the battle's write-back reaches them. Content from [param catalog] (null: the loaded
## one). Returns null, with an error, outside a node, or for a node with no pool or no map.
func battle_request(
		pools: CombatMapPools, catalog: EffectCatalog.Index = null
) -> CampaignSession.BattleRequest:
	if is_on_map() or graph == null or not graph.has_node_id(node):
		push_error("CampaignRunState: the run isn't inside a node, so no battle can begin")
		return null
	var pool: CombatMapPool = (
			null if pools == null else pools.pool_for(graph.type_of(node), floor_number)
	)
	var maps: Array[CombatMapDefinition] = CombatMapPools.available(pool, flow.used_maps)
	if maps.is_empty():
		push_error("CampaignRunState: node %d on floor %d has no map to fight on (type %s)" % [
			node, floor_number, CampaignGraph.NodeType.find_key(graph.type_of(node)),
		])
		return null
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = floor_number
	request.node = node
	request.pool = maps
	request.catalog = catalog
	for seat: int in seat_numbers():
		var seat_run: SeatRun = seats[seat]
		var army: CampaignSession.Army = CampaignSession.Army.new()
		army.unit_instances = seat_run.army.duplicate()
		army.item_instances = seat_run.items.duplicate()
		army.heirloom_ids = seat_run.heirloom_ids()
		request.armies[seat] = army
	return request


## A copy of this run with [param result] applied; this run is left unchanged, so the caller
## swaps the copy in, saves, and keeps this one if the save fails. Each unit's HP, permanent
## deltas and growth changes; fallen units to [member SeatRun.fallen] with their items; each
## heirloom copy's campaign lane; the grants (gold, a named heirloom, a named rune into an empty
## slot, minted from [param ids]). For the node's own battle: the map counts as used and, once
## won, the run leaves the node for the map. Returns null for a null result or a copy that failed.
func apply_battle(
		result: CampaignSession.BattleResult, ids: InstanceIdAllocator
) -> CampaignRunState:
	var next: CampaignRunState = _copy()
	if next == null or result == null:
		return null
	for seat: int in next.seat_numbers():
		var seat_run: SeatRun = next.seat_run(seat)
		_apply_units(seat_run, result)
		_apply_heirlooms(seat_run, result)
	for grant: CampaignSession.Grant in result.grants:
		_apply_grant(next, grant, ids)
	var is_node_battle: bool = (
			result.floor_number == next.floor_number and result.node == next.node
	)
	if next.is_on_map() or not is_node_battle:
		return next
	_use_map(next.flow, result.map_id, result.pool_ids)
	if not result.is_finished:
		return next
	for seat: int in next.seat_numbers():
		var ended: CampaignFact = CampaignFact.new(CampaignFact.Kind.COMBAT_ENDED, seat)
		# ASSUMPTION: COMBAT_ENDED's amount is 1 for a win, 0 for a loss; the fact names no field.
		ended.amount = 1 if result.is_won else 0
		next.record(ended)
	if result.is_won:
		next.flow.stage = RunFlow.Stage.MAP
		var left: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_LEFT)
		left.amount = next.node
		next.record(left)
	return next


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


# A copy through each part's own capture and restore, so it shares no instance with this run; the
# fact log goes on from this one's. Null when a part refuses (never for a run that saves).
func _copy() -> CampaignRunState:
	var copied: CampaignRunState = CampaignRunState.new()
	if copied.restore_map(capture_map()) != OK or copied.restore_flow(flow.capture()) != OK:
		return null
	for seat: int in seat_numbers():
		var source: SeatRun = seats[seat]
		var seat_run: SeatRun = SeatRun.new(seat)
		if (
				seat_run.restore_roster(source.capture_roster()) != OK
				or seat_run.restore_heirlooms(source.capture_heirlooms()) != OK
				or seat_run.restore_runes(source.capture_runes()) != OK
				or seat_run.restore_economy(source.capture_economy()) != OK
		):
			return null
		copied.seats[seat] = seat_run
	copied.fact_log = fact_log.duplicate()
	return copied


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


# A grant from battle on run, for its seat: gold added, a named heirloom or curse as a new copy, a
# named rune into the first empty slot. The rest is reported and dropped.
static func _apply_grant(
		run: CampaignRunState, grant: CampaignSession.Grant, ids: InstanceIdAllocator
) -> void:
	var holder: SeatRun = run.seat_run(grant.seat)
	if holder == null:
		push_warning("CampaignRunState: a grant for seat %d, not in the run - %s" % [
			grant.seat, grant.describe(),
		])
		return
	match grant.grant:
		CampaignGrant.Grant.GOLD:
			holder.gold = maxi(holder.gold + grant.amount, 0)
			return
		CampaignGrant.Grant.HEIRLOOM:
			if not grant.definition_id.is_empty():
				holder.add_heirloom(grant.definition_id)
				var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, grant.seat)
				gained.definition_id = grant.definition_id
				gained.source_effect_id = grant.source_effect_id
				run.record(gained)
				return
		CampaignGrant.Grant.RUNE:
			var slot: int = _empty_rune_slot(holder)
			if not grant.definition_id.is_empty() and slot >= 0 and ids != null:
				var rune_id: String = ids.next_rune_id(grant.definition_id)
				holder.rune_slots[slot] = SeatRun.RuneSlot.new(rune_id, grant.definition_id)
				var gained: CampaignFact = CampaignFact.new(
						CampaignFact.Kind.GAINED, grant.seat, rune_id
				)
				gained.definition_id = grant.definition_id
				gained.source_effect_id = grant.source_effect_id
				run.record(gained)
				return
	# TODO(TOD-001): recruits (RN9), unnamed grants (no pick rule yet) and a rune with every slot
	# full (the player discards one, on a screen) aren't applied.
	push_warning("CampaignRunState: seat %d's grant isn't applied yet - %s" % [
		grant.seat, grant.describe(),
	])


# Counts map_id as used in flow. A map already used means its pool refilled for this battle, so
# the pool's maps (pool_ids) are forgotten first: no map repeats until its pool is used up.
static func _use_map(flow_state: RunFlow, map_id: String, pool_ids: PackedStringArray) -> void:
	if map_id.is_empty():
		return
	if flow_state.used_maps.has(map_id):
		var kept: PackedStringArray = []
		for used: String in flow_state.used_maps:
			if not pool_ids.has(used):
				kept.append(used)
		flow_state.used_maps = kept
	flow_state.used_maps.append(map_id)


# Each of the seat's units in result, in roster order: its HP, the battle's permanent deltas and
# growth changes, and a fall to the fallen list, its items kept (permadeath).
static func _apply_units(seat_run: SeatRun, result: CampaignSession.BattleResult) -> void:
	var fell: Array[UnitInstance] = []
	for unit: UnitInstance in seat_run.army + seat_run.fallen:
		var outcome: CampaignSession.UnitOutcome = result.units.get(unit.instance_id, null)
		if outcome == null or outcome.seat != seat_run.seat:
			continue
		unit.hp = 0 if outcome.is_fallen else outcome.hp
		for delta: ItemInstance.StatDelta in outcome.stat_deltas:
			unit.stat_deltas.append(ItemInstance.StatDelta.new(
					delta.key, delta.amount, delta.source_id, delta.label
			))
		var growth: Dictionary = result.growth_changes.get(unit.instance_id, {})
		for stat: Variant in growth:
			# A growth change from battle carries no source: its delta's source and label are empty.
			unit.growth_deltas.append(ItemInstance.StatDelta.new(
					stat as int, float(growth[stat] as int), "", ""
			))
		if outcome.is_fallen and seat_run.army.has(unit):
			fell.append(unit)
	# ASSUMPTION: units that fall in one battle join the fallen list in roster order; the battle's
	# save keeps no fall order.
	for unit: UnitInstance in fell:
		seat_run.army.erase(unit)
		seat_run.fallen.append(unit)
		# ASSUMPTION: a fallen commander leaves the army like any unit, clearing the commander, so
		# the roster stays valid; solo's run ends at once, and co-op's return is P11's.
		if seat_run.commander_id == unit.instance_id:
			seat_run.commander_id = ""


# Each of the seat's heirloom copies in result gets its campaign lane: the k-th copy of an id is
# the seat's k-th entry of that id.
static func _apply_heirlooms(seat_run: SeatRun, result: CampaignSession.BattleResult) -> void:
	for lane: CampaignSession.HeirloomLane in result.heirlooms:
		if lane.seat != seat_run.seat:
			continue
		var seen: int = 0
		for owned: SeatRun.OwnedHeirloom in seat_run.heirlooms:
			if owned.heirloom_id != lane.heirloom_id:
				continue
			if seen == lane.copy:
				owned.counters = lane.counters.duplicate()
				owned.charges = lane.charges.duplicate()
				break
			seen += 1


# The index of the seat's first empty rune slot; -1 when every slot holds a rune.
static func _empty_rune_slot(seat_run: SeatRun) -> int:
	for index: int in seat_run.rune_slots.size():
		if seat_run.rune_slots[index].is_empty():
			return index
	return -1


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
