# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_state_cases.gd
# Author:
# Created:  November 13, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## Run state cases for tests/campaign/run_all.gd, on two seats: a new run's map, armies, gold,
## heirlooms, runes and economy ([RunStart]); the same seed gives the same run; the campaign
## commands (the route by votes, a seat's own choice refused, rejections change nothing); a run
## saves through its six sections ([RunSaveSections], driven by a [SaveSectionRegistry] and a JSON
## round trip) and reloads identically, with a Hit delta, a curse held twice, a convoy item, a
## fallen unit's items and the route votes; a section from a newer build or at version 0 stops the
## load, and a map from before the votes loads with none; bad, partial and empty run data; the
## standard combats a step has seen, read from the saved route. Touches no save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

# Any fixed run seeds: the cases compare runs with each other, never with golden numbers.
const RUN_SEED: int = 0x3F9A12C077E1A
const OTHER_SEED: int = 0x123456789ABCD

const SEATS: PackedInt32Array = [0, 1]

# The Mercenary (game-vision.md, Run structure: the faction table).
const MERCENARY: String = "mercenary"
const MERCENARY_TYPES: PackedStringArray = ["drengr", "hakkapel", "archer", "battle_medic"]
const MERCENARY_GOLD: int = 100
const COMMANDER_HEIRLOOM: String = "iron_heart"

# Content ids the save sections carry without looking them up (no curse or rune exists yet).
const CURSE_ID: String = "test_curse"
const RUNE_ID: String = "test_rune"

const CAMPAIGN: SaveSection.Block = SaveSection.Block.CAMPAIGN

var _report: Callable
var _rules: CampaignMapRules = null
var _catalog: EffectCatalog.Index = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_rules = load(RULES_PATH) as CampaignMapRules
	_catalog = EffectCatalog.index()
	_check("run state: the map rules and the catalog load", _rules != null and _catalog != null)
	if _rules == null or _catalog == null:
		return
	_test_new_run()
	_test_same_seed_same_run()
	_test_commands()
	_test_save_and_reload()
	_test_newer_and_zero_versions_refused()
	_test_bad_data_refused()
	_test_partial_and_empty_runs()
	_test_standard_combats_in_step()
	_test_key_combats_before()


## A session on [param run_seed] for [constant SEATS] with a new run built as
## [code]CampaignService[/code] builds it: the map from the session's MAP_GENERATION stream, every
## seat a Mercenary.
func new_session(run_seed: int) -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, run_seed, SEATS
	)
	var factions: Dictionary[int, String] = {}
	for seat: int in SEATS:
		factions[seat] = MERCENARY
	var start: RunStart = RunStart.build(
			_rules,
			session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog,
			factions,
			session.ids
	)
	session.run = start.run
	return session


## Every part of [param run] as one JSON text, seats in order: equal texts are equal runs.
static func run_text(run: CampaignRunState) -> String:
	var parts: Array = [run.capture_map(), run.flow.capture()]
	for seat: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat)
		parts.append_array([
			seat_run.capture_roster(),
			seat_run.capture_heirlooms(),
			seat_run.capture_runes(),
			seat_run.capture_economy(),
		])
	return JSON.stringify(parts)


# A one-column route: floors 1, 2, 4, 5, 7, 8 and 9 standard, 3 a Camp, 6 a Key combat. The count
# reads only earlier floors of the node's own step, and only Standard nodes; it is the same after
# the map's save round trip, and the battle request carries it.
func _test_standard_combats_in_step() -> void:
	var standard: CampaignGraph.NodeType = CampaignGraph.NodeType.STANDARD
	var types: Array[CampaignGraph.NodeType] = [
		standard, standard, CampaignGraph.NodeType.CAMP, standard, standard,
		CampaignGraph.NodeType.KEY, standard, standard, standard,
	]
	var graph: CampaignGraph = CampaignGraph.new(18, 1)
	for index: int in types.size():
		graph.add_node(index + 1, 0, types[index])
		if index > 0:
			graph.link(index - 1, index)
	# Floor reached to the count expected there.
	var expected: Dictionary[int, int] = {1: 0, 2: 1, 3: 2, 4: 2, 5: 3, 6: 0, 7: 0, 9: 2}
	var counts: Dictionary[int, int] = {}
	var reloaded: Dictionary[int, int] = {}
	for floor_reached: int in expected:
		var run: CampaignRunState = CampaignRunState.new()
		run.graph = graph
		for node_id: int in floor_reached:
			run.enter_node(node_id)
		counts[floor_reached] = run.standard_combats_in_step()
		var copy: CampaignRunState = CampaignRunState.new()
		var data: Variant = JSON.parse_string(JSON.stringify(run.capture_map()))
		var restored: bool = data is Dictionary and copy.restore_map(data as Dictionary) == OK
		reloaded[floor_reached] = copy.standard_combats_in_step() if restored else -1
	_check("standard combats in step: earlier Standard floors of the same step", (
			counts == expected
	), str(counts))
	_check("standard combats in step: the same after the map's save round trip", (
			reloaded == expected
	), str(reloaded))
	var pools: CombatMapPools = load("res://data/campaign/combat_map_pools.tres") as CombatMapPools
	var at_four: CampaignRunState = CampaignRunState.new()
	at_four.graph = graph
	for node_id: int in 4:
		at_four.enter_node(node_id)
	var request: CampaignSession.BattleRequest = at_four.battle_request(pools, _catalog)
	_check("standard combats in step: the battle request carries the count", (
			request != null and request.standard_combats_in_step == 2
	))


# A one-column route with Key combats on floors 3 and 6: the count reads only earlier floors, so
# the key node the run is in never counts; it is the same after the map's save round trip, and the
# battle request carries it.
func _test_key_combats_before() -> void:
	var standard: CampaignGraph.NodeType = CampaignGraph.NodeType.STANDARD
	var key: CampaignGraph.NodeType = CampaignGraph.NodeType.KEY
	var types: Array[CampaignGraph.NodeType] = [
		standard, standard, key, standard, standard, key, standard,
	]
	var graph: CampaignGraph = CampaignGraph.new(18, 1)
	for index: int in types.size():
		graph.add_node(index + 1, 0, types[index])
		if index > 0:
			graph.link(index - 1, index)
	# Floor reached to the count expected there.
	var expected: Dictionary[int, int] = {1: 0, 3: 0, 4: 1, 6: 1, 7: 2}
	var counts: Dictionary[int, int] = {}
	var reloaded: Dictionary[int, int] = {}
	for floor_reached: int in expected:
		var run: CampaignRunState = CampaignRunState.new()
		run.graph = graph
		for node_id: int in floor_reached:
			run.enter_node(node_id)
		counts[floor_reached] = run.key_combats_before()
		var copy: CampaignRunState = CampaignRunState.new()
		var data: Variant = JSON.parse_string(JSON.stringify(run.capture_map()))
		var restored: bool = data is Dictionary and copy.restore_map(data as Dictionary) == OK
		reloaded[floor_reached] = copy.key_combats_before() if restored else -1
	_check("key combats before: the Key nodes on earlier floors", counts == expected, str(counts))
	_check("key combats before: the same after the map's save round trip", (
			reloaded == expected
	), str(reloaded))
	var pools: CombatMapPools = load("res://data/campaign/combat_map_pools.tres") as CombatMapPools
	var at_seven: CampaignRunState = CampaignRunState.new()
	at_seven.graph = graph
	for node_id: int in 7:
		at_seven.enter_node(node_id)
	var request: CampaignSession.BattleRequest = at_seven.battle_request(pools, _catalog)
	_check("key combats before: the battle request carries the count", (
			request != null and request.key_combats_before == 2
	))


func _test_new_run() -> void:
	var session: CampaignSession = new_session(RUN_SEED)
	var run: CampaignRunState = session.run
	_check("new run: built, on the map, before floor 1", (
			run != null
			and run.graph != null
			and run.is_on_map()
			and run.floor_number == 0
			and run.node == CampaignGraph.NO_NODE
			and run.visited.is_empty()
			and run.seat_numbers() == SEATS
	))
	if run == null:
		return
	_check("new run: the map has every floor", (
			run.graph.get_floor_count() == _rules.floor_count
			and not run.graph.nodes_on_floor(1).is_empty()
	))
	_check("new run: the shared state starts empty", (
			run.flow.unknown_odds.is_empty()
			and run.flow.used_maps.is_empty()
			and run.flow.shop_stock.is_empty()
	))
	var seen_ids: Dictionary[String, bool] = {}
	for seat: int in SEATS:
		var seat_run: SeatRun = run.seat_run(seat)
		var types: PackedStringArray = []
		var whole: bool = true
		for unit: UnitInstance in seat_run.army:
			types.append(unit.unit_type_id)
			whole = whole and not seen_ids.has(unit.instance_id) and unit.level == 1
			seen_ids[unit.instance_id] = true
			for item_id: String in unit.item_ids():
				whole = whole and seat_run.items.has(item_id)
		_check("new run seat %d: the Mercenary's army, commander first" % [seat], (
				seat_run.faction_id == MERCENARY
				and types == MERCENARY_TYPES
				and seat_run.commander_id == seat_run.army[0].instance_id
				and whole
				and seat_run.convoy.is_empty()
				and seat_run.fallen.is_empty()
		), "%s" % [types])
		var empty_slots: int = 0
		for slot: SeatRun.RuneSlot in seat_run.rune_slots:
			empty_slots += 1 if slot.is_empty() else 0
		_check("new run seat %d: 100 gold, Iron Heart, 3 empty rune slots, offset -5" % [seat], (
				seat_run.gold == MERCENARY_GOLD
				and seat_run.heirloom_ids() == PackedStringArray([COMMANDER_HEIRLOOM])
				and empty_slots == SeatRun.RUNE_SLOT_COUNT
				and seat_run.rune_slots.size() == SeatRun.RUNE_SLOT_COUNT
				and seat_run.rare_offset == SeatRun.RARE_OFFSET_START
				and seat_run.rare_offset == -5
				and seat_run.pending_offers.is_empty()
		), "%d gold, %s" % [seat_run.gold, seat_run.heirloom_ids()])
	var started: PackedStringArray = []
	for fact: CampaignFact in run.fact_log:
		started.append("%s %d %s %d" % [
			CampaignFact.Kind.find_key(fact.kind), fact.seat, fact.definition_id, fact.seq,
		])
	_check("new run: RUN_STARTED once per seat, in seat order", started == PackedStringArray([
		"RUN_STARTED 0 mercenary 1", "RUN_STARTED 1 mercenary 2",
	]), str(started))


func _test_same_seed_same_run() -> void:
	var first: String = run_text(new_session(RUN_SEED).run)
	var again: String = run_text(new_session(RUN_SEED).run)
	var other: CampaignSession = new_session(OTHER_SEED)
	_check("same seed: the same new run, map and ids included", first == again)
	_check("other seed: another map", (
			JSON.stringify(other.run.graph.to_dict())
			!= JSON.stringify(new_session(RUN_SEED).run.graph.to_dict())
	))


func _test_commands() -> void:
	var session: CampaignSession = new_session(RUN_SEED)
	var run: CampaignRunState = session.run
	var resolved: Array[CampaignBatch] = []
	var rejections: Array[String] = []
	session.campaign_batch_resolved.connect(func(batch: CampaignBatch) -> void:
		resolved.append(batch)
	)
	session.command_rejected.connect(func(seat: int, arrival: int, reason: String) -> void:
		rejections.append("%d #%d %s" % [seat, arrival, reason])
	)
	var first_floor: PackedInt32Array = run.graph.nodes_on_floor(1)
	var start_node: int = first_floor[0]

	var before: String = run_text(run)
	var leave_early: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	var too_far: CampaignBatch = session.submit(
			ChooseNodeCommand.new(0, run.graph.nodes_on_floor(2)[0])
	)
	var no_node: CampaignBatch = session.submit(ChooseNodeCommand.new(0, 9999))
	var stranger: CampaignBatch = session.submit(ChooseNodeCommand.new(5, start_node))
	var own_choice: CampaignBatch = session.submit(ChooseNodeCommand.new(1, start_node))
	_check("commands: rejections change nothing and record nothing", (
			leave_early.is_rejected()
			and too_far.is_rejected()
			and no_node.is_rejected()
			and stranger.is_rejected()
			and own_choice.is_rejected()
			and run_text(run) == before
			and run.fact_log.size() == SEATS.size()
			and rejections.size() == 5
	), "%s" % [rejections])
	_check("commands: in co-op a seat's own choice is refused, with a reason", (
			own_choice.rejected_reason == "the team votes on its route in co-op"
	), own_choice.rejected_reason)

	var voted: CampaignBatch = session.submit(RouteVoteCommand.for_session(session, 1, start_node))
	var chosen: CampaignBatch = session.submit(
			RouteVoteCommand.for_session(session, 0, start_node)
	)
	var late: CampaignBatch = session.submit(
			RouteVoteCommand.for_session(session, 0, first_floor[first_floor.size() - 1])
	)
	_check("commands: the votes for a node on floor 1 lock the floor and enter the node", (
			not voted.is_rejected()
			and not chosen.is_rejected()
			and chosen.facts.size() == 2
			and chosen.facts[0].kind == CampaignFact.Kind.ROUTE_VOTED
			and chosen.facts[0].seat == 0
			and chosen.facts[1].kind == CampaignFact.Kind.NODE_CHOSEN
			and chosen.facts[1].seat == CampaignFact.NO_SEAT
			and chosen.facts[1].amount == start_node
			and run.floor_number == 1
			and run.node == start_node
			and run.visited == PackedInt32Array([start_node])
			and run.flow.stage == RunFlow.Stage.NODE
	), "%s / %s" % [voted.rejected_reason, chosen.rejected_reason])
	_check("commands: once the votes drew, a later vote is rejected", (
			late.is_rejected() and run.node == start_node and late.arrival > chosen.arrival
	), late.rejected_reason)

	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	var children: PackedInt32Array = run.graph.children_of(start_node)
	var stray: int = _node_not_child(run.graph, start_node, 2)
	var off_route: CampaignBatch = session.submit(RouteVoteCommand.for_session(session, 0, stray))
	var back: CampaignBatch = session.submit(RouteVoteCommand.for_session(session, 0, start_node))
	session.submit(RouteVoteCommand.for_session(session, 0, children[0]))
	var next: CampaignBatch = session.submit(RouteVoteCommand.for_session(session, 1, children[0]))
	_check("commands: leaving returns to the map; the route only follows children", (
			not left.is_rejected()
			and left.facts[0].kind == CampaignFact.Kind.NODE_LEFT
			and left.facts[0].amount == start_node
			and off_route.is_rejected()
			and back.is_rejected()
			and not next.is_rejected()
			and run.visited == PackedInt32Array([start_node, children[0]])
			and run.floor_number == 2
	), "%s / %s" % [off_route.rejected_reason, next.rejected_reason])
	var seqs: Array[int] = []
	for fact: CampaignFact in run.fact_log:
		seqs.append(fact.seq)
	_check("commands: facts are numbered in order, every batch announced", (
			seqs == [1, 2, 3, 4, 5, 6, 7, 8, 9] and resolved.size() == 13
	), "%s, %d batches" % [seqs, resolved.size()])

	session.close()
	var closed: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check(
			"commands: a closed run rejects everything",
			closed.is_rejected(),
			closed.rejected_reason
	)


# The full round trip: a run with something in every part, captured through a registry, through
# JSON as on disk, restored into new sections and attached to a new session.
func _test_save_and_reload() -> void:
	var session: CampaignSession = new_session(RUN_SEED)
	var run: CampaignRunState = session.run
	_fill_every_part(session)
	var sections: RunSaveSections = RunSaveSections.new()
	var attached: Error = sections.attach(session)
	var saved: Dictionary = _save(sections, run.seat_numbers())

	var loaded_sections: RunSaveSections = RunSaveSections.new()
	var restored: Error = _load(loaded_sections, saved)
	var reloaded: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, SEATS
	)
	var reattached: Error = loaded_sections.attach(reloaded)
	_check("save: an attached run with nothing held reports so and reads the session", (
			attached == ERR_DOES_NOT_EXIST
	), error_string(attached))
	var expected_versions: String = (
			"campaign_map 2, run_flow 1; economy 2, heirlooms 2, roster 1, runes 1"
	)
	_check("save: every section is at its version in the campaign block, the map, economy and "
			+ "heirlooms at 2", (
			_versions(saved) == expected_versions
	), _versions(saved))
	_check("save: the run reloads identically, part by part", (
			restored == OK
			and reattached == OK
			and reloaded.run != null
			and run_text(reloaded.run) == run_text(run)
	), "%s, %s" % [error_string(restored), error_string(reattached)])
	if reloaded.run == null:
		return
	var seat_zero: SeatRun = reloaded.run.seat_run(0)
	var seat_one: SeatRun = reloaded.run.seat_run(1)
	var unit: UnitInstance = seat_zero.army[1]
	var hit: ItemInstance.StatDelta = (
			unit.stat_deltas[0] if not unit.stat_deltas.is_empty() else null
	)
	_check("save: the permanent Hit delta comes back as a Hit delta", (
			hit != null
			and hit.key == CombatValue.Key.HIT
			and is_equal_approx(hit.amount, 5.0)
			and unit.stats(_catalog).get_int(CombatValue.Key.HIT)
					== run.seat_run(0).army[1].stats(_catalog).get_int(CombatValue.Key.HIT)
	))
	_check("save: the curse held twice is two copies, each with its own counters", (
			seat_one.heirloom_ids() == PackedStringArray([COMMANDER_HEIRLOOM, CURSE_ID, CURSE_ID])
			and (seat_one.heirlooms[1].counters.get("bleed", 0) as int) == 2
			and seat_one.heirlooms[2].counters.is_empty()
	), str(seat_one.heirloom_ids()))
	var fallen: UnitInstance = seat_one.fallen[0] if not seat_one.fallen.is_empty() else null
	_check("save: the route votes kept after their draw come back", (
			reloaded.run.route_votes == run.route_votes
			and run.route_votes.size() == SEATS.size()
	), str(reloaded.run.route_votes))
	_check("save: the convoy item and the fallen unit's items are kept", (
			seat_zero.convoy.size() == 1
			and seat_zero.items.has(seat_zero.convoy[0])
			and fallen != null
			and not fallen.item_ids().is_empty()
			and seat_one.items.has(fallen.weapon_id)
			and seat_one.unit(fallen.instance_id) == fallen
	))
	_check("save: a reloaded run takes commands like the first", (
			not reloaded.submit(LeaveNodeCommand.new(0)).is_rejected()
			and reloaded.run.is_on_map()
	))

	# Saving the reloaded run writes the same data again.
	var resaved: Dictionary = _save(loaded_sections, reloaded.run.seat_numbers())
	_check("save: saving the reloaded run writes what it loaded", (
			JSON.stringify(resaved) == JSON.stringify(_with_flow_stage(saved, "map"))
	))


func _test_newer_and_zero_versions_refused() -> void:
	var session: CampaignSession = new_session(RUN_SEED)
	var sections: RunSaveSections = RunSaveSections.new()
	sections.attach(session)
	var saved: Dictionary = _save(sections, SEATS)
	print("    (errors about a newer section version, then version 0, follow)")
	var cases: Dictionary[String, Array] = {
		"campaign_map newer": [_with_version(saved, "campaign_map", -1, 3), ERR_FILE_UNRECOGNIZED],
		"run_flow at 0": [_with_version(saved, "run_flow", -1, 0), ERR_INVALID_DATA],
		"roster newer": [_with_version(saved, "roster", 1, 2), ERR_FILE_UNRECOGNIZED],
		"economy at 0": [_with_version(saved, "economy", 0, 0), ERR_INVALID_DATA],
		"economy newer": [_with_version(saved, "economy", 0, 3), ERR_FILE_UNRECOGNIZED],
	}
	for case_name: String in cases:
		var fresh: RunSaveSections = RunSaveSections.new()
		var err: Error = _load(fresh, cases[case_name][0] as Dictionary)
		var target: CampaignSession = CampaignSession.new(
				CampaignData.Mode.MULTIPLAYER, RUN_SEED, SEATS
		)
		var attached: Error = fresh.attach(target)
		var expected: Error = cases[case_name][1]
		_check("versions: %s stops the load and holds no run" % [case_name], (
				err == expected
				and target.run == null
				and attached == ERR_DOES_NOT_EXIST
		), "%s, %s" % [error_string(err), error_string(attached)])

	# economy version 1 (a combat report without stats) migrates as it is.
	var old_economy: Dictionary = _with_version(saved, "economy", 0, 1)
	var migrated: RunSaveSections = RunSaveSections.new()
	var loaded: Error = _load(migrated, old_economy)
	var into: CampaignSession = CampaignSession.new(CampaignData.Mode.MULTIPLAYER, RUN_SEED, SEATS)
	var built: Error = migrated.attach(into)
	_check("versions: economy at version 1 loads, and saves again at version 2", (
			loaded == OK
			and built == OK
			and JSON.stringify(_save(migrated, into.run.seat_numbers())) == JSON.stringify(saved)
			and ((saved["players"] as Array)[0]["sections"]["economy"]["version"] as int) == 2
	), "%s, %s" % [error_string(loaded), error_string(built)])

	# campaign_map version 1 (no votes key) loads as a map with no votes, and saves again at 2.
	var voting: CampaignSession = new_session(RUN_SEED)
	voting.submit(RouteVoteCommand.for_session(voting, 0, voting.run.next_nodes()[0]))
	var with_votes: Dictionary = _save_of(voting)
	var old_map: Dictionary = _with_version(with_votes, "campaign_map", -1, 1)
	(old_map["sections"]["campaign_map"]["data"] as Dictionary).erase("votes")
	var map_loaded: RunSaveSections = RunSaveSections.new()
	var map_err: Error = _load(map_loaded, old_map)
	var map_into: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, SEATS
	)
	var map_built: Error = map_loaded.attach(map_into)
	var resaved: Dictionary = (
			_save(map_loaded, SEATS)["sections"]["campaign_map"] if map_built == OK else {}
	)
	_check("versions: campaign_map at version 1 loads with no votes, and saves again at 2", (
			map_err == OK
			and map_built == OK
			and map_into.run.route_votes.is_empty()
			and ItemInstance.read_int(resaved.get("version"), 0) == 2
			and JSON.stringify(resaved["data"]["votes"]) == "{}"
			and voting.run.route_votes.size() == 1
	), "%s, %s" % [error_string(map_err), error_string(map_built)])


func _test_bad_data_refused() -> void:
	var session: CampaignSession = new_session(RUN_SEED)
	_fill_every_part(session)
	var run: CampaignRunState = session.run
	var map: Dictionary = run.capture_map()
	var roster: Dictionary = run.seat_run(0).capture_roster()
	var first_unit: Dictionary = (roster["army"] as Array)[0]
	var second_unit: Dictionary = (roster["army"] as Array)[1]
	print("    (errors about unusable run data follow)")

	var broken_route: Dictionary = map.duplicate(true)
	broken_route["visited"] = [run.graph.nodes_on_floor(2)[0]]
	broken_route["floor"] = 1
	broken_route["node"] = run.graph.nodes_on_floor(2)[0]
	var twice: Dictionary = roster.duplicate(true)
	((twice["army"] as Array)[1] as Dictionary)["weapon_id"] = first_unit["weapon_id"]
	var stray_item: Dictionary = roster.duplicate(true)
	(stray_item["items"] as Dictionary)["item:9999"] = {
		"instance_id": "item:9999", "definition_id": "simple_bow",
	}
	var lost_item: Dictionary = roster.duplicate(true)
	(lost_item["convoy"] as Array).append("item:9999")
	var outsider: Dictionary = roster.duplicate(true)
	outsider["commander_id"] = "unit:9999"
	var duplicate_unit: Dictionary = roster.duplicate(true)
	(duplicate_unit["fallen"] as Array).append(second_unit.duplicate(true))
	var no_faction: Dictionary = roster.duplicate(true)
	no_faction["faction_id"] = ""
	var entered: int = run.node
	var child: int = run.graph.children_of(entered)[0]
	var stray: int = _node_not_child(run.graph, entered, 2)
	var far: int = run.graph.nodes_on_floor(3)[0]

	var cases: Dictionary[String, Error] = {
		"a route that skips a floor": CampaignRunState.new().restore_map(broken_route),
		"votes on two floors": _restore_votes(map, {"0": entered, "1": child}),
		"a vote two floors ahead": _restore_votes(map, {"0": far}),
		"a vote the route can't reach": _restore_votes(
				map, {"0": stray if stray != CampaignGraph.NO_NODE else 9999}
		),
		"a vote for a node the map lacks": _restore_votes(map, {"0": 9999}),
		"a vote by no seat": _restore_votes(map, {"-1": child}),
		"a vote keyed by a name": _restore_votes(map, {"host": child}),
		"a vote for a name": _restore_votes(map, {"0": str(child)}),
		"votes that aren't a dictionary": _restore_votes(map, [child]),
		"a stage inside a node before any node": CampaignRunState.new().restore_flow(
				{"stage": "node", "unknown_odds": {}, "used_maps": [], "shop_stock": {}}
		),
		"an unknown stage": RunFlow.new().restore(
				{"stage": "camp", "unknown_odds": {}, "used_maps": [], "shop_stock": {}}
		),
		"an item in two slots": SeatRun.new().restore_roster(twice),
		"an item held by nobody": SeatRun.new().restore_roster(stray_item),
		"a convoy item that doesn't exist": SeatRun.new().restore_roster(lost_item),
		"a commander outside the army": SeatRun.new().restore_roster(outsider),
		"a unit both living and fallen": SeatRun.new().restore_roster(duplicate_unit),
		"no faction": SeatRun.new().restore_roster(no_faction),
		"an heirloom without an id": SeatRun.new().restore_heirlooms(
				{"entries": [{"heirloom_id": ""}]}
		),
		"two rune slots": SeatRun.new().restore_runes({"slots": [{}, {}]}),
		"one rune in two slots": SeatRun.new().restore_runes({"slots": [
			{"instance_id": "rune:1", "definition_id": RUNE_ID},
			{"instance_id": "rune:1", "definition_id": RUNE_ID},
			{},
		]}),
		"negative gold": SeatRun.new().restore_economy(
				{"gold": -1, "rare_offset": -5, "pending_offers": {}}
		),
		"a rare offset past +40": SeatRun.new().restore_economy(
				{"gold": 0, "rare_offset": 41, "pending_offers": {}}
		),
		"a rare offset below -5": SeatRun.new().restore_economy(
				{"gold": 0, "rare_offset": -6, "pending_offers": {}}
		),
		"fractional gold": SeatRun.new().restore_economy(
				{"gold": 10.5, "rare_offset": -5, "pending_offers": {}}
		),
	}
	for case_name: String in cases:
		_check("bad data: %s is refused" % [case_name], cases[case_name] == ERR_INVALID_DATA)
	_check("bad data: open votes for the next floor and votes kept after a draw both load", (
			_restore_votes(map, {"0": child, "1": child}) == OK
			and _restore_votes(map, {"0": entered}) == OK
	))

	var flow_alone: Dictionary = _save_of(session)
	flow_alone["sections"]["campaign_map"] = {"version": 1, "data": {}}
	var sections: RunSaveSections = RunSaveSections.new()
	_check("bad data: a run flow with no map stops the load", (
			_load(sections, flow_alone) == ERR_INVALID_DATA
	))


func _test_partial_and_empty_runs() -> void:
	var session: CampaignSession = new_session(RUN_SEED)
	var saved: Dictionary = _save_of(session)
	var players: Array = saved["players"]
	var seat_one: Dictionary = players[1]
	(seat_one["sections"] as Dictionary).erase("economy")
	var partial: RunSaveSections = RunSaveSections.new()
	var restored: Error = _load(partial, saved)
	var target: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, SEATS
	)
	print("    (an error about a run missing a part follows)")
	var attached: Error = partial.attach(target)
	var rewritten: Dictionary = _save(partial, SEATS)
	var kept_map: Dictionary = (rewritten["sections"] as Dictionary)["campaign_map"]
	_check("partial: a save missing a seat's part attaches no run and keeps its data", (
			restored == OK
			and attached == ERR_INVALID_DATA
			and target.run == null
			and JSON.stringify(kept_map["data"])
					== JSON.stringify(saved["sections"]["campaign_map"]["data"])
	), "%s, %s" % [error_string(restored), error_string(attached)])

	var empty: RunSaveSections = RunSaveSections.new()
	var first_save: Dictionary = _save(empty, SEATS)
	var reloaded: RunSaveSections = RunSaveSections.new()
	var empty_restored: Error = _load(reloaded, first_save)
	var fresh: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	_check("empty: a first save holds {} in every part, and reloads as no run", (
			JSON.stringify(first_save["sections"]["run_flow"]["data"]) == "{}"
			and JSON.stringify(first_save["players"][0]["sections"]["roster"]["data"]) == "{}"
			and empty_restored == OK
			and reloaded.attach(fresh) == ERR_DOES_NOT_EXIST
			and fresh.run == null
	), error_string(empty_restored))


# A Hit delta on seat 0's second unit, a convoy item for seat 0, a curse held twice (one copy
# with a counter) and a fallen unit for seat 1, a rune, gold, the offset, pending offers, the
# shared state and one node chosen by both seats' votes, which stay after their draw.
func _fill_every_part(session: CampaignSession) -> void:
	var run: CampaignRunState = session.run
	var seat_zero: SeatRun = run.seat_run(0)
	seat_zero.army[1].stat_deltas.append(
			ItemInstance.StatDelta.new(CombatValue.Key.HIT, 5.0, "hit_booster", "Hit Booster")
	)
	seat_zero.army[1].xp = 40
	seat_zero.army[1].hp = 7
	var spare: ItemInstance = ItemInstance.new(session.ids.next_item_id("Simple Bow"), "simple_bow")
	seat_zero.items[spare.instance_id] = spare
	seat_zero.convoy.append(spare.instance_id)
	seat_zero.rune_slots[1] = SeatRun.RuneSlot.new(session.ids.next_rune_id("Rune"), RUNE_ID)
	seat_zero.gold = 75
	seat_zero.rare_offset = 3
	seat_zero.pending_offers = {"item_pick": {"kind": "weapon", "offers": ["simple_bow"]}}

	var seat_one: SeatRun = run.seat_run(1)
	seat_one.add_heirloom(CURSE_ID).counters["bleed"] = 2
	seat_one.add_heirloom(CURSE_ID)
	var lost: UnitInstance = seat_one.army.pop_back()
	seat_one.fallen.append(lost)

	run.flow.unknown_odds = {"standard": 20, "shop": 6}
	run.flow.used_maps = PackedStringArray(["m1_greybox"])
	run.flow.shop_stock = {"7": {"weapons": ["simple_bow"]}}
	for seat: int in SEATS:
		session.submit(RouteVoteCommand.for_session(session, seat, run.graph.nodes_on_floor(1)[0]))


# The campaign block's sections and each seat's, as a registry writes them, after a JSON trip.
func _save(sections: RunSaveSections, seats: PackedInt32Array) -> Dictionary:
	var registry: SaveSectionRegistry = _registry(sections)
	var players: Array[CampaignData.PlayerRun] = _players(seats)
	var block: Dictionary = registry.capture(CAMPAIGN, {})
	registry.capture_players(players)
	var player_entries: Array = []
	for player: CampaignData.PlayerRun in players:
		player_entries.append(player.to_dict())
	var parsed: Variant = JSON.parse_string(
			JSON.stringify({"sections": block, "players": player_entries})
	)
	return parsed as Dictionary if parsed is Dictionary else {}


# A session's run saved through fresh sections.
func _save_of(session: CampaignSession) -> Dictionary:
	var sections: RunSaveSections = RunSaveSections.new()
	sections.attach(session)
	return _save(sections, session.run.seat_numbers())


# Restores saved into sections as SaveService loads a file: the campaign block, then its players;
# a failed load resets both, as SaveService's does.
func _load(sections: RunSaveSections, saved: Dictionary) -> Error:
	var registry: SaveSectionRegistry = _registry(sections)
	var players: Array[CampaignData.PlayerRun] = []
	for entry: Variant in saved.get("players", []) as Array:
		players.append(CampaignData.PlayerRun.from_dict(entry))
	var err: Error = registry.restore(CAMPAIGN, saved.get("sections", {}) as Dictionary)
	if err == OK:
		err = registry.restore_players(players)
	if err != OK:
		registry.reset(CAMPAIGN)
		registry.clear_players()
	return err


func _registry(sections: RunSaveSections) -> SaveSectionRegistry:
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	registry.register(CAMPAIGN, sections.map)
	registry.register(CAMPAIGN, sections.flow)
	for section: RunSaveSections.SeatSection in sections.seat_sections:
		registry.register_player(section)
	return registry


func _players(seats: PackedInt32Array) -> Array[CampaignData.PlayerRun]:
	var players: Array[CampaignData.PlayerRun] = []
	for seat: int in seats:
		var player: CampaignData.PlayerRun = CampaignData.PlayerRun.new()
		player.seat = seat
		players.append(player)
	return players


# "key version, ..." for the campaign block, then for seat 0, keys sorted (JSON.stringify sorts
# them, so the saved order isn't the registration order).
func _versions(saved: Dictionary) -> String:
	var shared: PackedStringArray = []
	var block: Dictionary = saved.get("sections", {})
	for key: String in block:
		shared.append("%s %d" % [key, ItemInstance.read_int(block[key]["version"])])
	var per_seat: PackedStringArray = []
	var seat_sections: Dictionary = (saved["players"] as Array)[0]["sections"]
	for key: String in seat_sections:
		per_seat.append("%s %d" % [key, ItemInstance.read_int(seat_sections[key]["version"])])
	shared.sort()
	per_seat.sort()
	return "%s; %s" % [", ".join(shared), ", ".join(per_seat)]


# A copy of saved with one section's version set: a campaign section when seat is -1.
func _with_version(saved: Dictionary, key: String, seat: int, version: int) -> Dictionary:
	var copy: Dictionary = saved.duplicate(true)
	var holder: Dictionary = (
			copy["sections"] if seat < 0 else (copy["players"] as Array)[seat]["sections"]
	)
	holder[key]["version"] = version
	return copy


func _with_flow_stage(saved: Dictionary, stage: String) -> Dictionary:
	var copy: Dictionary = saved.duplicate(true)
	copy["sections"]["run_flow"]["data"]["stage"] = stage
	return copy


# What a new run state's restore_map() returns for map with its votes replaced by votes.
func _restore_votes(map: Dictionary, votes: Variant) -> Error:
	var changed: Dictionary = map.duplicate(true)
	changed["votes"] = votes
	return CampaignRunState.new().restore_map(changed)


# A node on floor_number that from_id doesn't lead to; NO_NODE when it leads to them all.
func _node_not_child(graph: CampaignGraph, from_id: int, floor_number: int) -> int:
	for node_id: int in graph.nodes_on_floor(floor_number):
		if not graph.children_of(from_id).has(node_id):
			return node_id
	return CampaignGraph.NO_NODE


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
