# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_battle_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## Co-op unit swaps in battle for tests/campaign/run_all.gd, on real 2- and 4-seat runs, real maps
## and the real catalog: the battle request listing each visitor last in its partner's army with
## its items, still its seat's; the visitor deployed by role on the partner's map, every map
## keeping its unit count; its owner controlling it there and ending its turn, the map's player
## phase waiting for both; the opening swap window by each seat's own setting, where the visitor's
## owner moves it onto a free deployment tile and nothing else; the swap kept across a non-combat
## node and applied to a surprise combat; the swap and the open proposals ending when the combat
## ends, the visitor's HP back on its owner's roster; and a map that received a sent unit losing
## its speed bonus (BUG-037).

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 0x0C05
const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
# The visitor's HP when its battle ends, below any unit's maximum.
const HURT_HP: int = 3
# Any event id: a surprise combat needs an event open at the node.
const SURPRISE_EVENT: String = "test_surprise"

var _report: Callable
var _pools: CombatMapPools = null
var _catalog: EffectCatalog.Index = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_pools = CombatMapPools.load_default()
	_catalog = EffectCatalog.index()
	_test_request(2)
	_test_request(4)
	_test_deployment(2)
	_test_deployment(4)
	_test_control(2)
	_test_control(4)
	_test_opening_window(2)
	_test_opening_window(4)
	_test_after_non_combat_node()
	_test_surprise_combat()
	_test_lapses_at_combat_end()
	_test_received_map_loses_speed_bonus()


# Seat 0 swaps with seat 1 (and, with four seats, seat 2 with seat 3): each visitor is last in
# its partner's army with its items, owned by its seat; its own army no longer lists it.
func _test_request(seat_count: int) -> void:
	var made: CampaignSession = _swapped(seat_count)
	var run: CampaignRunState = made.run
	var request: CampaignSession.BattleRequest = _enter_combat(made)
	var label: String = "request %d seats" % [seat_count]
	if request == null:
		_check("%s: the run's combat node has a request" % [label], false)
		return
	var problems: PackedStringArray = []
	for swap: UnitSwap in run.flow.swaps:
		for side: Array in [
			[swap.seat_a, swap.unit_a, swap.seat_b], [swap.seat_b, swap.unit_b, swap.seat_a],
		]:
			var owner: int = side[0]
			var unit_id: String = side[1]
			var host: CampaignSession.Army = request.armies[side[2] as int]
			var home: CampaignSession.Army = request.armies[owner]
			var listed: PackedStringArray = _ids_of(host)
			var unit: UnitInstance = run.seat_run(owner).unit(unit_id)
			if listed[listed.size() - 1] != unit_id or _ids_of(home).has(unit_id):
				problems.append("%s isn't last in seat %d's army only" % [unit_id, side[2]])
			if host.visitor_seats.get(unit_id, -1) != owner or host.owner_of(unit_id, -1) != owner:
				problems.append("%s isn't owned by seat %d" % [unit_id, owner])
			for item_id: String in unit.item_ids():
				if not host.item_instances.has(item_id) or home.item_instances.has(item_id):
					problems.append("%s's item %s didn't travel" % [unit_id, item_id])
	for seat: int in run.seat_numbers():
		if request.armies[seat].unit_instances.size() != run.seat_run(seat).army.size():
			problems.append("seat %d's army changed size" % [seat])
	_check("%s: each visitor is last in its partner's army, with its items, still its seat's" % [
		label,
	], problems.is_empty() and run.flow.swaps.size() * 2 == seat_count, str(problems))
	made.close()


# The battle begins with each visitor on its partner's map, on a deployment tile, placed with
# that map's army at deployment, owned by its seat; no map is a unit short.
func _test_deployment(seat_count: int) -> void:
	var made: CampaignSession = _swapped(seat_count)
	var run: CampaignRunState = made.run
	var request: CampaignSession.BattleRequest = _enter_combat(made)
	var battle: CombatEncounter = null if request == null else made.begin_battle(request)
	var label: String = "deployment %d seats" % [seat_count]
	if battle == null:
		_check("%s: the battle begins" % [label], false)
		made.close()
		return
	var problems: PackedStringArray = []
	for swap: UnitSwap in run.flow.swaps:
		for side: Array in [
			[swap.seat_a, swap.unit_a, swap.seat_b], [swap.seat_b, swap.unit_b, swap.seat_a],
		]:
			var unit_id: String = side[1]
			var host: CombatSession = battle.session_of_seat(side[2] as int)
			var home: CombatSession = battle.session_of_seat(side[0] as int)
			var deployment: Array[Vector2i] = host.layout.tiles_of(
					MapLayout.MarkerKind.DEPLOYMENT
			)
			if (
					not host.state.has_unit(unit_id)
					or home.state.has_unit(unit_id)
					or battle.session_of_unit(unit_id) != host
					or host.state.seat_of(unit_id) != (side[0] as int)
					or not deployment.has(host.state.tile_of(unit_id))
					or not _spawned_at_deployment(host, unit_id)
			):
				problems.append("%s isn't deployed on seat %d's map" % [unit_id, side[2]])
	for seat: int in run.seat_numbers():
		var map: CombatSession = battle.session_of_seat(seat)
		if map.state.units_of(PLAYER).size() != run.seat_run(seat).army.size():
			problems.append("seat %d's map has %d units" % [
				seat, map.state.units_of(PLAYER).size(),
			])
		if map.commander_ids.get(seat, "") != run.seat_run(seat).commander_id:
			problems.append("seat %d's commander isn't its own" % [seat])
	_check("%s: each visitor deploys by role with its partner's army, owned by its seat" % [
		label,
	], problems.is_empty(), str(problems))
	made.close()


# With the opening swap off, the visitor's owner moves it (a Wait) on the partner's map, the map's
# own seat can't, and the map's player phase waits until both seats end their turn there.
func _test_control(seat_count: int) -> void:
	var made: CampaignSession = _swapped(seat_count)
	var run: CampaignRunState = made.run
	var request: CampaignSession.BattleRequest = _enter_combat(made)
	var label: String = "control %d seats" % [seat_count]
	if request == null:
		_check("%s: the battle begins" % [label], false)
		return
	for seat: int in seat_count:
		request.opening_swap[seat] = false
	var battle: CombatEncounter = made.begin_battle(request)
	var swap: UnitSwap = run.flow.swaps[0]
	var host: CombatSession = battle.session_of_seat(1)
	var host_id: int = host.session_id
	var visitor: String = swap.unit_a
	var by_host: String = _reason(battle, UnitTurnCommand.new(1, visitor), host_id)
	var by_owner: String = _reason(battle, UnitTurnCommand.new(0, visitor), host_id)
	var turn: int = host.state.turn
	var host_ended: String = _reason(battle, EndTurnCommand.new(1), host_id)
	var waiting: PackedInt32Array = PhaseRunner.seats_to_end(host)
	var still_player: bool = (
			host.state.phase_side == PLAYER and not host.state.is_phase_ended
			and host.state.turn == turn
	)
	var owner_ended: String = _reason(battle, EndTurnCommand.new(0), host_id)
	_check("%s: the visitor's seat acts for it on its partner's map, not the map's" % [label], (
			not by_host.is_empty() and by_owner.is_empty()
	), "%s / %s" % [by_host, by_owner])
	_check("%s: the map's player phase waits for the visitor's seat to end its turn" % [label], (
			host_ended.is_empty()
			and waiting == PackedInt32Array([0])
			and still_player
			and owner_ended.is_empty()
			and (host.is_finished or host.state.turn == turn + 1)
	), "%s / %s, waiting %s, turn %d" % [host_ended, owner_ended, waiting, host.state.turn])
	made.close()


# With both settings on, the partner's map waits for both seats' Start; the visitor's owner moves
# it onto a free deployment tile, the map's own seat can't move a unit so, and no seat swaps a
# visitor with a host unit. With seat 0's setting off, each map waits for seat 1 only: its own map,
# and seat 0's map, where seat 1's visitor stands.
func _test_opening_window(seat_count: int) -> void:
	var made: CampaignSession = _swapped(seat_count)
	var run: CampaignRunState = made.run
	var request: CampaignSession.BattleRequest = _enter_combat(made)
	var label: String = "window %d seats" % [seat_count]
	if request == null:
		_check("%s: the battle begins" % [label], false)
		return
	var battle: CombatEncounter = made.begin_battle(request)
	var swap: UnitSwap = run.flow.swaps[0]
	var host: CombatSession = battle.session_of_seat(1)
	var host_id: int = host.session_id
	var visitor: String = swap.unit_a
	var own_unit: String = _own_unit_on(host, 1)
	var free: Vector2i = _free_deployment_tile(host)
	var both_wait: bool = host.state.seats_to_start == PackedInt32Array([0, 1])
	var trade: String = _reason(battle, _opening(0, visitor, own_unit, []), host_id)
	var host_move: String = _reason(battle, _opening(1, own_unit, "", [free]), host_id)
	var moved: String = _reason(battle, _opening(0, visitor, "", [free]), host_id)
	var on_free: bool = host.state.tile_of(visitor) == free
	var own_tile: Vector2i = host.state.tile_of(own_unit)
	var taken: String = _reason(battle, _opening(0, visitor, "", [own_tile]), host_id)
	var started: String = _reason(battle, StartCommand.new(0), host_id)
	_check("%s: both seats' Start is awaited on the visitor's map" % [label], both_wait)
	_check("%s: the visitor's owner moves it onto a free deployment tile" % [label], (
			moved.is_empty() and on_free and started.is_empty()
	), "%s / %s" % [moved, started])
	_check("%s: no trade with a host unit, no host move, no move onto a taken tile" % [label], (
			trade == "not two of the seat's units"
			and host_move == "not two of the seat's units"
			and taken == "the tile is taken"
	), "%s / %s / %s" % [trade, host_move, taken])
	made.close()

	var off: CampaignSession = _swapped(seat_count)
	var off_request: CampaignSession.BattleRequest = _enter_combat(off)
	off_request.opening_swap = {0: false}
	var off_battle: CombatEncounter = off.begin_battle(off_request)
	_check("%s: seat 0's setting off, only seat 1 waits on its map and as a visitor" % [label], (
			off_battle != null
			and off_battle.session_of_seat(1).state.seats_to_start == PackedInt32Array([1])
			and off_battle.session_of_seat(0).state.seats_to_start == PackedInt32Array([1])
	))
	off.close()


# Accepted on the map, the swap stays through a node with no combat and applies at the next
# combat node.
func _test_after_non_combat_node() -> void:
	var made: CampaignSession = _swapped(2)
	var run: CampaignRunState = made.run
	var route: PackedInt32Array = _shop_then_combat(run)
	if route.is_empty():
		_check("non-combat node: the map has a shop before a combat", false)
		return
	_put_on_map_at(run, route.slice(0, route.size() - 2))
	var shop: CampaignBatch = Fixture.choose(made, route[route.size() - 2])
	var left: CampaignBatch = made.submit(LeaveNodeCommand.new(0))
	var kept: bool = run.flow.swaps.size() == 1
	Fixture.choose(made, route[route.size() - 1])
	var request: CampaignSession.BattleRequest = run.battle_request(_pools, _catalog)
	_check("non-combat node: the swap is kept through a shop and applies at the next combat", (
			not shop.is_rejected() and not left.is_rejected() and kept
			and request != null
			and request.armies[1].visitor_seats.has(run.flow.swaps[0].unit_a)
	), "%s / %s" % [shop.rejected_reason, left.rejected_reason])
	made.close()


# A surprise combat at an event node is the next combat too.
func _test_surprise_combat() -> void:
	var made: CampaignSession = _swapped(2)
	var run: CampaignRunState = made.run
	var route: PackedInt32Array = Fixture.route_to(run.graph, CampaignGraph.NodeType.UNKNOWN)
	if route.is_empty():
		_check("surprise: the map has an Unknown node", false)
		return
	_put_on_map_at(run, route.slice(0, route.size() - 1))
	Fixture.choose(made, route[route.size() - 1])
	run.events.event_id = SURPRISE_EVENT
	run.events.floor_number = run.floor_number
	run.events.node = run.node
	run.events.is_combat_pending = true
	var request: CampaignSession.BattleRequest = run.battle_request(_pools, _catalog)
	var battle: CombatEncounter = null if request == null else made.begin_battle(request)
	var visitor: String = run.flow.swaps[0].unit_a
	_check("surprise: the visitor fights a surprise combat on its partner's map", (
			battle != null
			and battle.session_of_seat(1).state.has_unit(visitor)
			and battle.session_of_seat(1).state.seat_of(visitor) == 0
	))
	made.close()


# The combat ends: the swap and an open proposal end (combat_ended), the visitor's HP is back on
# its owner's roster, and the next combat's request lists no visitor.
func _test_lapses_at_combat_end() -> void:
	var made: CampaignSession = _swapped(4)
	var run: CampaignRunState = made.run
	made.submit(ProposeSwapCommand.new(
			1, _unit_of(run, 1, 1), 3, _unit_of(run, 3, 1)
	))
	var request: CampaignSession.BattleRequest = _enter_combat(made)
	var battle: CombatEncounter = null if request == null else made.begin_battle(request)
	if battle == null:
		_check("lapse: the battle begins", false)
		made.close()
		return
	var swap: UnitSwap = run.flow.swaps[0]
	var saved_mid_battle: bool = (run.flow.capture()["swaps"] as Array).size() == 2
	battle.session_of_seat(swap.seat_b).state.unit(swap.unit_a).hp = HURT_HP
	for session: CombatSession in battle.get_sessions():
		var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
		ended.side = PLAYER
		session.engine.record(ended)
	var result: CampaignSession.BattleResult = made.collect_battle()
	var next: CampaignRunState = run.apply_battle(
			result, made.ids, made.reward_rolls(result), CombatRewardRules.load_default(), _catalog
	)
	made.end_battle()
	var endings: PackedStringArray = []
	var first: int = run.fact_log.size()
	for fact: CampaignFact in next.fact_log.slice(first):
		if fact.kind == CampaignFact.Kind.SWAP_ENDED:
			endings.append(fact.definition_id)
	_check("lapse: the swap is saved until the combat ends", saved_mid_battle)
	_check("lapse: the swaps and the open proposal end when the combat ends", (
			next != null
			and next.flow.swaps.is_empty()
			and next.swap_proposals.is_empty()
			and endings == PackedStringArray([
				UnitSwap.END_COMBAT_ENDED, UnitSwap.END_COMBAT_ENDED, UnitSwap.END_COMBAT_ENDED,
			])
	), str(endings))
	_check("lapse: the visitor's HP is back on its owner's roster", (
			next != null
			and next.seat_run(swap.seat_a).unit(swap.unit_a) != null
			and next.seat_run(swap.seat_a).unit(swap.unit_a).hp == HURT_HP
			and result.units[swap.unit_a].seat == swap.seat_a
	))
	made.close()


# Seat 0 wins and sends a unit to seat 1's map, where it lands; seat 1 then wins on turn 1. Its
# outcome says it received units, so it isn't under par, while seat 0's own map still is.
func _test_received_map_loses_speed_bonus() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var request: CampaignSession.BattleRequest = _enter_combat(made)
	if request == null:
		_check("received: the battle begins", false)
		return
	request.opening_swap = {0: false, 1: false}
	var battle: CombatEncounter = made.begin_battle(request)
	var winner: CombatSession = battle.session_of_seat(0)
	var target: CombatSession = battle.session_of_seat(1)
	_end(winner)
	var sent: String = _own_unit_on(winner, 0)
	var commander: String = target.commander_ids.get(1, "")
	var aim: Vector2i = target.state.tile_of(commander)
	var reason: String = battle.send_unit(sent, winner.session_id, target.session_id, aim)
	var landed: PackedStringArray = battle.deliver_arrivals(target.session_id)
	_end(target)
	var result: CampaignSession.BattleResult = made.collect_battle()
	var received: CampaignSession.SeatOutcome = result.seats[1]
	var own: CampaignSession.SeatOutcome = result.seats[0]
	_check("received: the map a sent unit landed on loses its speed bonus (BUG-037)", (
			reason.is_empty()
			and landed == PackedStringArray([sent])
			and received.has_received_units
			and not own.has_received_units
			and not CombatGrades.is_under_par_for(received)
			and CombatGrades.is_under_par_for(own) == (own.turn_par > 0 and own.turn < own.turn_par)
			and received.turn_par == own.turn_par
	), "%s, landed %s, par %d turn %d" % [reason, landed, own.turn_par, own.turn])
	made.close()


# A new run of seat_count seats on the map with seat 0's first unit swapped for seat 1's, and with
# four seats seat 2's for seat 3's too.
func _swapped(seat_count: int) -> CampaignSession:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var run: CampaignRunState = made.run
	for one: int in range(0, seat_count - 1, 2):
		var other: int = one + 1
		var mine: String = _unit_of(run, one)
		var theirs: String = _unit_of(run, other)
		made.submit(ProposeSwapCommand.new(one, mine, other, theirs))
		made.submit(AnswerSwapCommand.new(other, one, true, mine, theirs))
	return made


# Moves made's run into its first floor-1 Standard combat node and returns its battle request;
# null when floor 1 has none.
func _enter_combat(made: CampaignSession) -> CampaignSession.BattleRequest:
	var run: CampaignRunState = made.run
	for node: int in run.next_nodes():
		if run.graph.type_of(node) == CampaignGraph.NodeType.STANDARD:
			Fixture.choose(made, node)
			return run.battle_request(_pools, _catalog)
	return null


# The first route from floor 1 that enters an Armory or Guildhall and then a Standard combat;
# empty for none.
func _shop_then_combat(run: CampaignRunState) -> PackedInt32Array:
	for type: CampaignGraph.NodeType in [
		CampaignGraph.NodeType.ARMORY, CampaignGraph.NodeType.GUILDHALL,
	]:
		var to_shop: PackedInt32Array = Fixture.route_to(run.graph, type)
		if to_shop.is_empty():
			continue
		var children: PackedInt32Array = run.graph.children_of(to_shop[to_shop.size() - 1])
		for child: int in children:
			if run.graph.type_of(child) == CampaignGraph.NodeType.STANDARD:
				var route: PackedInt32Array = to_shop.duplicate()
				route.append(child)
				return route
	return PackedInt32Array()


# Puts run on the map after route (the nodes entered, floor 1 first), as leaving its last does.
func _put_on_map_at(run: CampaignRunState, route: PackedInt32Array) -> void:
	run.visited = route
	run.floor_number = route.size()
	run.node = CampaignGraph.NO_NODE if route.is_empty() else route[route.size() - 1]
	run.flow.stage = RunFlow.Stage.MAP


# The index-th living unit of seat's army that isn't its commander; empty when there is none.
func _unit_of(run: CampaignRunState, seat: int, index: int = 0) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	var found: int = 0
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == seat_run.commander_id:
			continue
		if found == index:
			return unit.instance_id
		found += 1
	return ""


func _ids_of(army: CampaignSession.Army) -> PackedStringArray:
	var ids: PackedStringArray = []
	for unit: UnitInstance in army.unit_instances:
		ids.append(unit.instance_id)
	return ids


# A player unit of seat on map that isn't its commander.
func _own_unit_on(map: CombatSession, seat: int) -> String:
	for unit_id: String in map.state.units_of(PLAYER):
		if map.state.seat_of(unit_id) == seat and map.commander_ids.get(seat, "") != unit_id:
			return unit_id
	return ""


# A deployment tile of map no unit stands on; NO_TILE when none is free.
func _free_deployment_tile(map: CombatSession) -> Vector2i:
	for tile: Vector2i in map.layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT):
		if map.state.occupant_at(tile).is_empty():
			return tile
	return CombatFact.NO_TILE


# Whether map's fact log records unit_id's UNIT_SPAWNED before its first Phase Start: deployed
# with the army, not arrived later.
func _spawned_at_deployment(map: CombatSession, unit_id: String) -> bool:
	for fact: CombatFact in map.engine.fact_log:
		if fact.kind == CombatFact.Kind.PHASE_START:
			return false
		if fact.kind == CombatFact.Kind.UNIT_SPAWNED and fact.actor_id == unit_id:
			return true
	return false


func _opening(
		seat: int, unit_id: String, target_id: String, walk: Array[Vector2i]
) -> UnitTurnCommand:
	return UnitTurnCommand.new(
			seat, unit_id, UnitTurnCommand.Action.OPENING_SWAP, target_id, walk
	)


# Submits command to session_id through the encounter; why it was refused, or empty.
func _reason(battle: CombatEncounter, command: Command, session_id: int) -> String:
	var arrival: int = battle.submit(command, session_id)
	for batch: CombatSession.FactBatch in battle.resolve_queued():
		if batch.arrival == arrival and batch.is_rejected():
			return batch.rejected_reason
	return ""


# Ends map's combat as a player win.
func _end(map: CombatSession) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	map.engine.record(ended)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
