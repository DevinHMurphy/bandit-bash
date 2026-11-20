# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_bridge_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The run's runes through a real battle, for tests/campaign/run_all.gd (BUG-014): runes bought at
## a Guildhall are in the next battle's request, in [member CombatState.rune_slots] with their
## effects (so the rune bar lists them), and castable; after one is cast and one discarded, the
## battle's result reports the rune left and the run keeps only it, in its own slot. A run with no
## result entry for a seat keeps its runes. Touches no save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 4242

# Gold a staged seat holds, enough for both runes. Units: gold.
const RICH: int = 1000

# A rune given to the third slot so one can be cast, one discarded and one kept.
const KEPT_RUNE: String = "aegis"

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _pools: CombatMapPools = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_pools = CombatMapPools.load_default()
	_check("rune bridge: the catalog and map pools load", _catalog != null and _pools != null)
	if _catalog == null or _pools == null:
		return
	_test_bought_runes_reach_battle()
	_test_no_entry_keeps_runes()


func _test_bought_runes_reach_battle() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var run_state: CampaignRunState = session.run
	_check("rune bridge: the map has a Guildhall route", Fixture.enter(
			run_state, CampaignGraph.NodeType.GUILDHALL
	))
	session.submit(OpenGuildhallCommand.for_session(session, _catalog))
	var seat_run: SeatRun = run_state.seat_run(0)
	seat_run.gold = RICH
	var stock: GuildhallStock = GuildhallStock.pending(run_state)
	for index: int in stock.indexes_of(GuildhallStock.CATEGORY_RUNE):
		var command: GuildhallPurchaseCommand = GuildhallPurchaseCommand.new(0, index)
		command.catalog = _catalog
		session.submit(command)
	seat_run.rune_slots[2] = SeatRun.RuneSlot.new(session.ids.next_rune_id(KEPT_RUNE), KEPT_RUNE)
	var bought: PackedStringArray = []
	for slot: SeatRun.RuneSlot in seat_run.rune_slots:
		bought.append(slot.instance_id)
	session.submit(LeaveNodeCommand.new(0))
	_walk_to_combat(run_state)
	var request: CampaignSession.BattleRequest = run_state.battle_request(_pools, _catalog)
	_check("rune bridge: a Standard combat's request is built", request != null)
	if request == null:
		return
	var carried: PackedStringArray = []
	for slot: SeatRun.RuneSlot in request.armies[0].rune_slots:
		carried.append(slot.instance_id)
	_check("rune bridge: the battle request carries the run's runes in slot order", (
			carried == bought and not bought.has("")
	), "%s vs %s" % [carried, bought])
	var battle: CombatEncounter = session.begin_battle(request)
	_check("rune bridge: the battle begins", battle != null)
	if battle == null:
		return
	var map: CombatSession = battle.get_session(0)
	var slots: PackedStringArray = map.state.rune_slots.get(0, PackedStringArray())
	var held: Array[TurnInputModel.HeldRune] = TurnInputModel.held_runes(map, 0)
	var on_bar: bool = slots == bought and held.size() == bought.size()
	for index: int in held.size():
		on_bar = (
				on_bar and held[index].rune_id == bought[index]
				and held[index].definition_id == seat_run.rune_slots[index].definition_id
		)
	_check("rune bridge: a rune bought at the Guildhall is on the battle's rune bar", (
			on_bar
	), str(slots))
	var cast_id: String = _cast_any(map, PackedStringArray([bought[0], bought[1]]))
	var discard_id: String = bought[1] if cast_id == bought[0] else bought[0]
	map.engine.begin_step()
	var discarded: String = RuneResolver.discard(map.engine, map.state, 0, discard_id)
	_check("rune bridge: one rune is cast and another discarded in battle", (
			not cast_id.is_empty() and discarded.is_empty()
	), "cast %s; discard: %s" % [cast_id, discarded])
	var result: CampaignSession.BattleResult = session.collect_battle()
	var left: PackedStringArray = result.runes.get(0, PackedStringArray())
	_check("rune bridge: the result reports only the rune left", (
			left == PackedStringArray([bought[2]])
	), str(result.runes))
	var next: CampaignRunState = run_state.apply_battle(
			result, session.ids, session.reward_rolls(result), CombatRewardRules.load_default(),
			_catalog
	)
	session.end_battle()
	var after: SeatRun = next.seat_run(0)
	_check("rune bridge: the cast and discarded runes are gone from the run; the kept one stays", (
			after.rune_slots[0].is_empty() and after.rune_slots[1].is_empty()
			and after.rune_slots[2].instance_id == bought[2]
	), str(after.capture_runes()))
	session.close()


func _test_no_entry_keeps_runes() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var run_state: CampaignRunState = session.run
	run_state.seat_run(0).rune_slots[0] = SeatRun.RuneSlot.new(
			session.ids.next_rune_id(KEPT_RUNE), KEPT_RUNE
	)
	run_state.enter_node(run_state.graph.nodes_on_floor(1)[0])
	var result: CampaignSession.BattleResult = CampaignSession.BattleResult.new()
	result.floor_number = run_state.floor_number
	result.node = run_state.node
	var next: CampaignRunState = run_state.apply_battle(
			result, session.ids, session.reward_rolls(result), CombatRewardRules.load_default(),
			_catalog
	)
	_check("rune bridge: a result naming no seat's runes leaves them as they are", (
			next != null and not next.seat_run(0).rune_slots[0].is_empty()
	))


# Casts the first of rune_ids that some unit on map can take as a unit rune; its id, or empty when
# none could be cast.
func _cast_any(map: CombatSession, rune_ids: PackedStringArray) -> String:
	for rune_id: String in rune_ids:
		var rune: RuneDefinition = RuneResolver.definition_of(map.engine, rune_id)
		if rune == null or rune.target_kind != ContentIds.RUNE_UNIT:
			continue
		var units: PackedStringArray = map.state.units_of(CombatFact.CombatSide.PLAYER)
		units.append_array(map.state.units_of(CombatFact.CombatSide.ENEMY))
		for unit_id: String in units:
			if not RuneResolver.target_reason(map.state, rune, unit_id).is_empty():
				continue
			map.engine.begin_step()
			var refused: String = RuneResolver.cast(
					map.engine, map.state, 0, RuneResolver.effect_of(map.engine, rune_id), unit_id
			)
			if refused.is_empty():
				return rune_id
	return ""


# Walks run_state from its node down the map to the nearest Standard combat node, entering each
# node on the way as choosing it would, so the route stays one the run's checks accept.
func _walk_to_combat(run_state: CampaignRunState) -> void:
	var graph: CampaignGraph = run_state.graph
	var routes: Array[PackedInt32Array] = [PackedInt32Array()]
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_front()
		var from: int = run_state.node if route.is_empty() else route[route.size() - 1]
		var children: PackedInt32Array = graph.children_of(from).duplicate()
		children.sort()
		for child: int in children:
			var longer: PackedInt32Array = route.duplicate()
			longer.append(child)
			if graph.type_of(child) == CampaignGraph.NodeType.STANDARD:
				for node_id: int in longer:
					run_state.enter_node(node_id)
				return
			routes.append(longer)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
