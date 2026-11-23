# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_run_state.gd
# Author:
# Created:  November 13, 2026
# Modified: November 23, 2026
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
## [method battle_request]; its end pays each seat whose own map was won. Saved as
## [RunSaveSections]' six sections and the [code]events[/code] section.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-001 - Apply recruit grants, unnamed heirloom and rune grants, and a rune with every
## slot full (the discard choice); each is reported and dropped (RN9, P09).

## The key of a seat's combat report in [member SeatRun.pending_offers], from a won combat until
## the run leaves its node: [code]{"grades": CombatGrades.capture(), "xp": [XpAward.capture()],
## "level_ups": [LevelUp.capture()], "stats": {unit_id: BattleStats.capture_unit()}}[/code], the
## units in roster order; [code]stats[/code] covers every seat unit that fought, fallen ones too,
## and is missing from a report saved before it.
const COMBAT_REPORT_KEY: String = "combat"

# capture_map()'s keys. Never change them: saved runs are read by these names.
const _KEY_GRAPH: String = "graph"
const _KEY_VISITED: String = "visited"
const _KEY_FLOOR: String = "floor"
const _KEY_NODE: String = "node"
const _KEY_VOTES: String = "votes"

# The combat report's keys. Never change them: saved runs are read by these names.
const _KEY_GRADES: String = "grades"
const _KEY_XP: String = "xp"
const _KEY_LEVEL_UPS: String = "level_ups"
const _KEY_STATS: String = "stats"

const _PERCENT: float = 100.0

## The run's map. Null only in a state not yet built or restored.
var graph: CampaignGraph = null

## Ids of the nodes entered, one per floor, floor 1 first.
var visited: PackedInt32Array = []

## The floor of [member node]; 0 before the first node is chosen.
var floor_number: int = 0

## The node the run last entered; [constant CampaignGraph.NO_NODE] before the first.
var node: int = CampaignGraph.NO_NODE

## Each seat's co-op route vote, by seat: a node id, set by [RouteVoteCommand] and saved with the
## map. Votes for the next nodes are the open vote ([method open_route_votes]); after the draw they
## stay, on the floor entered, until the next floor's first vote. [b]Empty:[/b] no votes.
var route_votes: Dictionary[int, int] = {}

## The stage within [member node], and the state every seat shares.
var flow: RunFlow = RunFlow.new()

## Each seat's part of the run, by seat.
var seats: Dictionary[int, SeatRun] = {}

## The run's events: those seen, and the one open at a node. Saved as the [code]events[/code]
## section ([EventSaveSection]).
var events: EventRunState = EventRunState.new()

## Every campaign fact recorded this session, in order. Not saved: like a battle's log, it
## starts empty when a run is continued.
var fact_log: Array[CampaignFact] = []

## The co-op swap proposals not yet answered ([ProposeSwapCommand]), in the order made; accepted
## ones move to [member RunFlow.swaps]. Not saved: they live only in the host's memory and are
## lost on a quit, so a continued run starts with none.
var swap_proposals: Array[UnitSwap] = []


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


## The type the node the run is in plays as: an Unknown node's rolled outcome
## ([member RunFlow.unknown], [method UnknownResolution.type_of]), else its type on the map. An
## Unknown not rolled yet, or rolled an event, stays [constant CampaignGraph.NodeType.UNKNOWN].
## The map's own types decide everything else, such as the route rules and the step counts.
func node_type() -> CampaignGraph.NodeType:
	if graph == null:
		return CampaignGraph.NodeType.STANDARD
	var type: CampaignGraph.NodeType = graph.type_of(node)
	if type == CampaignGraph.NodeType.UNKNOWN and not flow.unknown.is_empty():
		return UnknownResolution.type_of(flow.unknown)
	return type


## The nodes the run can enter next, in id order: on the map, the children of [member node], or
## every floor-1 node before the first; empty inside a node. [ChooseNodeCommand] and
## [RouteVoteCommand] accept exactly these.
func next_nodes() -> PackedInt32Array:
	if not is_on_map() or graph == null:
		return PackedInt32Array()
	var found: PackedInt32Array = (
			graph.nodes_on_floor(1) if node == CampaignGraph.NO_NODE
			else graph.children_of(node).duplicate()
	)
	found.sort()
	return found


## The open route vote: each seat's vote in [member route_votes] for one of [method next_nodes],
## by seat. Empty inside a node, and after a draw until the next floor's first vote.
func open_route_votes() -> Dictionary[int, int]:
	var next: PackedInt32Array = next_nodes()
	var open: Dictionary[int, int] = {}
	for seat: int in route_votes:
		if next.has(route_votes[seat]):
			open[seat] = route_votes[seat]
	return open


## Whether the run's Boss is beaten: the run is at the results of a Boss node, which only a battle
## won on a map reaches (in co-op, any one map). The run ends from there
## ([method CampaignService.end_won_run]).
func is_boss_beaten() -> bool:
	return (
			flow.stage == RunFlow.Stage.RESULTS
			and graph != null and graph.has_node_id(node)
			and graph.type_of(node) == CampaignGraph.NodeType.BOSS
	)


## Records [param fact] at the end of [member fact_log], numbering it from 1.
func record(fact: CampaignFact) -> void:
	fact.seq = fact_log.size() + 1
	fact_log.append(fact)


## Checks [param command] against the run as it stands, then resolves it. Returns its batch: the
## facts it recorded, or the reason it was rejected, which records nothing. A seat outside the run
## is rejected before [method CampaignCommand.validate]. A resolved command that took a unit out
## of its army also ends every swap naming it, in the same batch ([method UnitSwap.end_broken]).
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
	UnitSwap.end_broken(self)
	batch.facts = fact_log.slice(first)
	return batch


## Enters [param node_id] on the next floor and locks that floor: the rules of
## [ChooseNodeCommand] and [RouteVoteCommand]'s draw, which check the move first.
func enter_node(node_id: int) -> void:
	visited.append(node_id)
	floor_number = graph.floor_of(node_id)
	node = node_id
	flow.stage = RunFlow.Stage.NODE


## The standard combat nodes the run entered on earlier floors of [member floor_number]'s
## difficulty step ([method EnemySetup.step_of]), read from [member visited], which the run saves:
## a node left in retreat still counts. The node the run is in never counts, so a resume reads the
## same number Begin did.
func standard_combats_in_step() -> int:
	if graph == null:
		return 0
	var step: int = EnemySetup.step_of(floor_number)
	var count: int = 0
	for node_id: int in visited:
		var node_floor: int = graph.floor_of(node_id)
		if (
				node_floor < floor_number
				and EnemySetup.step_of(node_floor) == step
				and graph.type_of(node_id) == CampaignGraph.NodeType.STANDARD
		):
			count += 1
	return count


## The key combat nodes the run entered on earlier floors, read from [member visited], which the
## run saves: the place of this node's mini-boss in the run's order
## ([method EnemySetup.mini_boss_for]). The node the run is in never counts, so a resume reads the
## same number Begin did.
func key_combats_before() -> int:
	if graph == null:
		return 0
	var count: int = 0
	for node_id: int in visited:
		var is_key: bool = graph.type_of(node_id) == CampaignGraph.NodeType.KEY
		if is_key and graph.floor_of(node_id) < floor_number:
			count += 1
	return count


## The battle of the combat node the run is in: floor and node from [member floor_number] and
## [member node], the standard combats before it in its step ([method standard_combats_in_step]),
## the key combats before it ([method key_combats_before]),
## the maps of its pool in [param pools] that [member RunFlow.used_maps] hasn't used
## ([method CombatMapPools.available]), and each seat's living army with its current HP, items,
## heirlooms (once per copy) and runes. Its unit and item instances are the run's own, so the
## battle's write-back reaches them. Each accepted swap's units ([member RunFlow.swaps]) are
## listed last in their partner's army with their items, still owned by their seats
## ([member CampaignSession.Army.visitor_seats]). Content from [param catalog] (null: loaded). An
## Unknown node that became a combat, or whose event chose a surprise combat, fights on the
## Standard pool ([method node_type]). Null, with an error, outside a node or at its results, or
## for a node with no pool or no map.
func battle_request(
		pools: CombatMapPools, catalog: EffectCatalog.Index = null
) -> CampaignSession.BattleRequest:
	if flow.stage != RunFlow.Stage.NODE or graph == null or not graph.has_node_id(node):
		push_error("CampaignRunState: the run isn't inside a node's battle, so none can begin")
		return null
	var pool_type: CampaignGraph.NodeType = (
			CampaignGraph.NodeType.STANDARD if events.is_combat_pending_at(floor_number, node)
			else node_type()
	)
	var pool: CombatMapPool = null if pools == null else pools.pool_for(pool_type, floor_number)
	var maps: Array[CombatMapDefinition] = CombatMapPools.available(pool, flow.used_maps)
	if maps.is_empty():
		push_error("CampaignRunState: node %d on floor %d has no map to fight on (type %s)" % [
			node, floor_number, CampaignGraph.NodeType.find_key(pool_type),
		])
		return null
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = floor_number
	request.node = node
	request.standard_combats_in_step = standard_combats_in_step()
	request.key_combats_before = key_combats_before()
	request.pool = maps
	request.catalog = catalog
	for seat: int in seat_numbers():
		var seat_run: SeatRun = seats[seat]
		var army: CampaignSession.Army = CampaignSession.Army.new()
		army.unit_instances = seat_run.army.duplicate()
		army.item_instances = seat_run.items.duplicate()
		army.heirloom_ids = seat_run.heirloom_ids()
		for slot: SeatRun.RuneSlot in seat_run.rune_slots:
			if not slot.is_empty():
				army.rune_slots.append(SeatRun.RuneSlot.new(slot.instance_id, slot.definition_id))
		request.armies[seat] = army
	for swap: UnitSwap in flow.swaps:
		_lend_swap(request, swap)
	return request


## A copy of this run with [param result] applied, this run unchanged, so the caller swaps it in,
## saves, and keeps this one if the save fails. Each unit's HP, deltas and growth changes; fallen
## units to [member SeatRun.fallen] with their items (a fallen commander stays at critical HP);
## each heirloom copy's campaign lane; each rune cast or discarded gone from its slot; then the
## grants, minted from [param ids]. For the node's own finished battle: the map counts as used,
## each seat's [code]COMBAT_ENDED[/code] records its own map, every swap and proposal ends, each
## seat whose map was won is paid by [param rules] from [param rolls] (see
## [constant COMBAT_REPORT_KEY]), and the run moves to its results: solo on a win, co-op always,
## except a Boss failed on every map, which loses the run. Null for a null result, missing rules
## or rolls, or a failed copy. [param catalog] null: loaded.
func apply_battle(
		result: CampaignSession.BattleResult,
		ids: InstanceIdAllocator,
		rolls: CampaignSession.RewardRolls,
		rules: CombatRewardRules,
		catalog: EffectCatalog.Index = null
) -> CampaignRunState:
	if rolls == null or rules == null:
		push_error("CampaignRunState: a battle's result needs reward rules and rolls")
		return null
	var next: CampaignRunState = _copy()
	if next == null or result == null:
		return null
	for seat: int in next.seat_numbers():
		var seat_run: SeatRun = next.seat_run(seat)
		_apply_units(seat_run, result, rules)
		_apply_heirlooms(seat_run, result)
		if result.runes.has(seat):
			_apply_runes(seat_run, result.runes[seat])
	for grant: CampaignSession.Grant in result.grants:
		_apply_grant(next, grant, ids)
	var is_node_battle: bool = (
			result.floor_number == next.floor_number and result.node == next.node
	)
	if next.flow.stage != RunFlow.Stage.NODE or not is_node_battle:
		return next
	_use_map(next.flow, result.map_id, result.pool_ids)
	if not result.is_finished:
		return next
	for seat: int in next.seat_numbers():
		var ended: CampaignFact = CampaignFact.new(CampaignFact.Kind.COMBAT_ENDED, seat)
		# COMBAT_ENDED's amount is 1 when the seat's own map was won, 0 for a loss; the fact names
		# no field for it.
		ended.amount = 1 if _is_map_won(result, seat) else 0
		next.record(ended)
	# Read before the swaps end: which partner's map each visitor fought on.
	var hosts: Dictionary[String, int] = _visitor_hosts(next.flow)
	UnitSwap.end_all(next, UnitSwap.END_COMBAT_ENDED)
	var contents: EffectCatalog.Index = catalog if catalog != null else EffectCatalog.index()
	for seat: int in next.seat_numbers():
		_reward_seat(next, seat, result, hosts, ids, rolls, rules, contents)
	if _reaches_results(next, result):
		next.flow.stage = RunFlow.Stage.RESULTS
	return next


## The map, the route taken and the route votes as plain JSON, for the [code]campaign_map[/code]
## section; votes are keyed by seat as decimal strings.
func capture_map() -> Dictionary:
	var route: Array[int] = []
	for node_id: int in visited:
		route.append(node_id)
	var votes: Dictionary = {}
	for seat: int in route_votes:
		votes[str(seat)] = route_votes[seat]
	return {
		_KEY_GRAPH: graph.to_dict() if graph != null else {},
		_KEY_VISITED: route,
		_KEY_FLOOR: floor_number,
		_KEY_NODE: node,
		_KEY_VOTES: votes,
	}


## Takes the map [param data], as [method capture_map] wrote it; data with no votes (saved before
## them) has none. Returns [constant ERR_INVALID_DATA], changing nothing, for a graph
## [method CampaignGraph.from_dict] refuses, a route that breaks the route invariant (see the class
## doc), or votes that aren't all choices of one move: the next one, or the last one made.
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
	var read_votes: Dictionary[int, int] = {}
	if not _read_votes(data.get(_KEY_VOTES, {}), read_graph, read_route, read_votes):
		return _refuse("map", data)

	graph = read_graph
	visited = read_route
	floor_number = read_floor as int
	node = read_node as int
	route_votes = read_votes
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
	copied.events = events.copy()
	copied.fact_log = fact_log.duplicate()
	for proposal: UnitSwap in swap_proposals:
		copied.swap_proposals.append(UnitSwap.restore(proposal.capture()))
	return copied


## [param seat_run]'s combat report (see [constant COMBAT_REPORT_KEY]), read with [param rules]
## ([method XpAward.restore]); null when it has none, or its data is unusable (reported).
static func read_combat_report(seat_run: SeatRun, rules: CombatRewardRules) -> CombatReport:
	var data: Variant = seat_run.pending_offers.get(COMBAT_REPORT_KEY, null)
	if data == null:
		return null
	var report: CombatReport = (
			CombatReport.restore(data as Dictionary, rules) if data is Dictionary else null
	)
	if report == null:
		push_error("CampaignRunState: seat %d's combat report is unusable - %s" % [
			seat_run.seat, data,
		])
	return report


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


# Moves swap's two units into each other's armies in request, each last in its partner's roster
# with its items and its owner in visitor_seats. A swap naming a unit its seat's army in request
# doesn't hold is reported and left out whole, so no map is one unit short.
static func _lend_swap(request: CampaignSession.BattleRequest, swap: UnitSwap) -> void:
	var first: CampaignSession.Army = request.armies.get(swap.seat_a, null)
	var second: CampaignSession.Army = request.armies.get(swap.seat_b, null)
	var lent_a: UnitInstance = null if first == null else _army_unit(first, swap.unit_a)
	var lent_b: UnitInstance = null if second == null else _army_unit(second, swap.unit_b)
	if lent_a == null or lent_b == null:
		push_error("CampaignRunState: a swap names a unit not in its army; left out - %s" % [
			swap.capture(),
		])
		return
	_lend(first, lent_a, second, swap.seat_a)
	_lend(second, lent_b, first, swap.seat_b)


# Moves unit and its items from owner's army to host's, last in host's roster, owned by seat.
static func _lend(
		owner: CampaignSession.Army, unit: UnitInstance, host: CampaignSession.Army, seat: int
) -> void:
	owner.unit_instances.erase(unit)
	for item_id: String in unit.item_ids():
		if owner.item_instances.has(item_id):
			host.item_instances[item_id] = owner.item_instances[item_id]
			owner.item_instances.erase(item_id)
	host.unit_instances.append(unit)
	host.visitor_seats[unit.instance_id] = seat


# The unit unit_id among army's unit instances; null when it has none.
static func _army_unit(army: CampaignSession.Army, unit_id: String) -> UnitInstance:
	for unit: UnitInstance in army.unit_instances:
		if unit.instance_id == unit_id:
			return unit
	return null


# Whether seat's own map in result was won; a seat with no map in it has the battle's result.
static func _is_map_won(result: CampaignSession.BattleResult, seat: int) -> bool:
	var outcome: CampaignSession.SeatOutcome = result.seats.get(seat, null)
	return result.is_won if outcome == null else outcome.is_won


# Whether a finished result moves run to its results. Solo: only a win; a loss ends the run. Co-op
# (more than one map): every map has ended, so yes, even with every map failed, as a failed map
# loses only itself; but a Boss no map beat leaves no floor to go on to, so the run is lost.
static func _reaches_results(run: CampaignRunState, result: CampaignSession.BattleResult) -> bool:
	if result.is_won:
		return true
	if result.seats.size() <= 1:
		return false
	if run.graph == null or run.graph.type_of(run.node) != CampaignGraph.NodeType.BOSS:
		return true
	for seat: int in result.seats:
		if result.seats[seat].is_won:
			return true
	return false


# Each accepted swap's visitor in flow, by unit id, with the seat whose map it fought on.
static func _visitor_hosts(flow_state: RunFlow) -> Dictionary[String, int]:
	var hosts: Dictionary[String, int] = {}
	for swap: UnitSwap in flow_state.swaps:
		hosts[swap.unit_a] = swap.seat_b
		hosts[swap.unit_b] = swap.seat_a
	return hosts


# The seat's rewards from a won map of result: grades and gold, XP for each unit still standing on
# any map, their level-ups in roster order (one LEVELED_UP each), the item pick (none after a
# Boss), a Key combat's heirloom from the same stream after it, and the combat report under
# COMBAT_REPORT_KEY, with every seat unit's battle stats. A visitor on a partner's map that failed
# (hosts: visitor id to that map's seat) earns no shared XP. A seat whose map was lost gets nothing.
static func _reward_seat(
		run: CampaignRunState,
		seat: int,
		result: CampaignSession.BattleResult,
		hosts: Dictionary[String, int],
		ids: InstanceIdAllocator,
		rolls: CampaignSession.RewardRolls,
		rules: CombatRewardRules,
		catalog: EffectCatalog.Index
) -> void:
	var outcome: CampaignSession.SeatOutcome = result.seats.get(seat, null)
	var seat_run: SeatRun = run.seat_run(seat)
	if outcome == null or seat_run == null or not outcome.is_won:
		return
	var reward_stream: RngStream = rolls.reward.get(seat, null)
	var level_stream: RngStream = rolls.level_ups.get(seat, null)
	if reward_stream == null or level_stream == null:
		push_error("CampaignRunState: seat %d has no reward streams, so it isn't paid" % [seat])
		return
	var grades: CombatGrades = CombatGrades.grade(outcome, rules)
	seat_run.gold = maxi(seat_run.gold + grades.gold, 0)
	var standing: Array[UnitInstance] = []
	var percents: Dictionary[String, int] = {}
	var unshared: PackedStringArray = []
	for unit: UnitInstance in seat_run.army:
		var unit_outcome: CampaignSession.UnitOutcome = result.units.get(unit.instance_id, null)
		if unit_outcome != null and unit_outcome.seat == seat and not unit_outcome.is_fallen:
			standing.append(unit)
			percents[unit.instance_id] = unit_outcome.xp_percent
			var host: int = hosts.get(unit.instance_id, seat)
			if host != seat and not _is_map_won(result, host):
				unshared.append(unit.instance_id)
	var stats_data: Dictionary = {}
	for unit: UnitInstance in seat_run.army + seat_run.fallen:
		var fought: CampaignSession.UnitOutcome = result.units.get(unit.instance_id, null)
		if fought != null and fought.seat == seat:
			stats_data[unit.instance_id] = result.stats.capture_unit(unit.instance_id)
	var awards: Array[XpAward] = XpAward.award(
			standing, result.tally, outcome, percents, rules, unshared
	)
	var xp_data: Array = []
	var level_data: Array = []
	for award: XpAward in awards:
		xp_data.append(award.capture())
		var unit: UnitInstance = seat_run.unit(award.unit_id)
		var unit_outcome: CampaignSession.UnitOutcome = result.units[award.unit_id]
		for reached: LevelUp in LevelUp.gain_xp(
				unit, award.total, unit_outcome.level_up, level_stream, catalog, rules
		):
			level_data.append(reached.capture())
			var leveled: CampaignFact = CampaignFact.new(
					CampaignFact.Kind.LEVELED_UP, seat, unit.instance_id
			)
			leveled.amount = reached.level
			run.record(leveled)
	var pick: ItemPick = ItemPick.roll(
			reward_stream, outcome.combat_type, seat_run, rules, catalog, ids
	)
	if pick != null:
		pick.store(seat_run)
	if outcome.combat_type == CombatMapDefinition.CombatType.KEY:
		var heirloom: KeyHeirloom = KeyHeirloom.roll(
				reward_stream, seat_run, catalog, run.seat_numbers().size() > 1,
				UniqueClaims.owned_by_teammates(run, seat, catalog)
		)
		if heirloom != null:
			heirloom.store(seat_run)
	seat_run.pending_offers[COMBAT_REPORT_KEY] = {
		_KEY_GRADES: grades.capture(),
		_KEY_XP: xp_data,
		_KEY_LEVEL_UPS: level_data,
		_KEY_STATS: stats_data,
	}


# Each of the seat's units in result, in roster order: its HP, the battle's permanent deltas and
# growth changes, and a fall to the fallen list, its items kept (permadeath). A fallen commander
# instead stays in the army with rules' share of its battle max HP, halves up, at least 1.
static func _apply_units(
		seat_run: SeatRun, result: CampaignSession.BattleResult, rules: CombatRewardRules
) -> void:
	var fell: Array[UnitInstance] = []
	for unit: UnitInstance in seat_run.army + seat_run.fallen:
		var outcome: CampaignSession.UnitOutcome = result.units.get(unit.instance_id, null)
		if outcome == null or outcome.seat != seat_run.seat:
			continue
		var is_commander: bool = seat_run.commander_id == unit.instance_id
		unit.hp = 0 if outcome.is_fallen else outcome.hp
		if outcome.is_fallen and is_commander:
			unit.hp = maxi(1, ValueBreakdown.round_to_int(
					outcome.max_hp * rules.fallen_commander_hp_percent / _PERCENT,
					ValueBreakdown.Rounding.HALF_UP
			))
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
		if outcome.is_fallen and not is_commander and seat_run.army.has(unit):
			fell.append(unit)
	# Units that fall in one battle join the fallen list in roster order; the battle's save keeps
	# no fall order.
	for unit: UnitInstance in fell:
		seat_run.army.erase(unit)
		seat_run.fallen.append(unit)


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


# Empties each of the seat's rune slots whose rune isn't in left (the runes its map still holds):
# a rune cast or discarded in battle is gone from the run. Slots keep their places. Records no
# fact, as HP and falls applied here record none.
static func _apply_runes(seat_run: SeatRun, left: PackedStringArray) -> void:
	for index: int in seat_run.rune_slots.size():
		var slot: SeatRun.RuneSlot = seat_run.rune_slots[index]
		if not slot.is_empty() and not left.has(slot.instance_id):
			seat_run.rune_slots[index] = SeatRun.RuneSlot.new()


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


# Reads data's votes into into, by seat, checked against map and route (already a valid route):
# every vote a node one move could reach, all from one move: the next one (votes still open), or
# the last one made (votes kept after the draw). False, with into partly filled, for any other.
static func _read_votes(
		data: Variant, map: CampaignGraph, route: PackedInt32Array, into: Dictionary[int, int]
) -> bool:
	if not data is Dictionary:
		return false
	var votes: Dictionary = data
	var vote_floor: int = -1
	for key: Variant in votes:
		var node_id: Variant = whole_number(votes[key])
		if (
				not key is String or not (key as String).is_valid_int()
				or (key as String).to_int() < 0
				or node_id == null or not map.has_node_id(node_id as int)
		):
			return false
		var at_floor: int = map.floor_of(node_id as int)
		if vote_floor != -1 and at_floor != vote_floor:
			return false
		vote_floor = at_floor
		into[(key as String).to_int()] = node_id as int
	if into.is_empty():
		return true
	if vote_floor != route.size() + 1 and vote_floor != route.size():
		return false
	var from: int = route[vote_floor - 2] if vote_floor >= 2 else CampaignGraph.NO_NODE
	var reachable: PackedInt32Array = (
			map.nodes_on_floor(1) if from == CampaignGraph.NO_NODE else map.children_of(from)
	)
	for seat: int in into:
		if not reachable.has(into[seat]):
			return false
	return true


## One seat's combat report, as [method read_combat_report] reads it: what Results shows.
class CombatReport:
	extends RefCounted

	## The grades and the gold they paid.
	var grades: CombatGrades = null
	## Each standing unit's XP, in roster order.
	var xp: Array[XpAward] = []
	## Every level-up, in the order reached.
	var level_ups: Array[LevelUp] = []
	## Each seat unit's battle stats by unit id, indexed by [enum BattleStats.Stat]: every unit
	## that fought, fallen ones too, in roster order. Empty for a report saved before stats.
	var stats: Dictionary[String, PackedInt32Array] = {}

	## The report [param data] describes, in the shape
	## [constant CampaignRunState.COMBAT_REPORT_KEY] gives; null for a missing or unusable part.
	## Stats may be missing (an older report); present, they must be usable.
	static func restore(data: Dictionary, rules: CombatRewardRules) -> CombatReport:
		var grade_data: Variant = data.get(_KEY_GRADES)
		var xp_data: Variant = data.get(_KEY_XP)
		var level_data: Variant = data.get(_KEY_LEVEL_UPS)
		var stats_data: Variant = data.get(_KEY_STATS, {})
		if not grade_data is Dictionary or not xp_data is Array or not level_data is Array:
			return null
		if not stats_data is Dictionary:
			return null
		var report: CombatReport = CombatReport.new()
		report.grades = CombatGrades.restore(grade_data as Dictionary)
		if report.grades == null:
			return null
		for entry: Variant in xp_data as Array:
			var award: XpAward = (
					XpAward.restore(entry as Dictionary, rules) if entry is Dictionary else null
			)
			if award == null:
				return null
			report.xp.append(award)
		for entry: Variant in level_data as Array:
			var reached: LevelUp = (
					LevelUp.restore(entry as Dictionary) if entry is Dictionary else null
			)
			if reached == null:
				return null
			report.level_ups.append(reached)
		for unit_id: Variant in stats_data as Dictionary:
			var entry: Variant = (stats_data as Dictionary)[unit_id]
			if not unit_id is String or (unit_id as String).is_empty() or not entry is Dictionary:
				return null
			var values: PackedInt32Array = BattleStats.read_unit(entry as Dictionary)
			if values.is_empty():
				return null
			report.stats[unit_id as String] = values
		return report

	## The Standout's award; null when nobody was.
	func standout() -> XpAward:
		for award: XpAward in xp:
			if award.is_standout:
				return award
		return null
