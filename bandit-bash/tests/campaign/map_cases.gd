# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_cases.gd
# Author:
# Created:  November 12, 2026
# Modified: November 12, 2026
# ==============================================================================

extends RefCounted
## Campaign map cases for tests/campaign/run_all.gd: the shipped rules match game-vision.md, every
## hard rule holds on [constant SEED_COUNT] seeds, the same seed gives the same map whatever the
## global generator does, [CampaignGraph]'s save data round-trips (through JSON too) and rejects
## bad data, the generator refuses unusable rules, and map_checks.gd catches broken maps.
## The 10,000-seed check and the target miss rates are in tests/bench/campaign_map_bench.gd.

# A preloaded script used as a type (gdscript.md, Naming): the checks have no class name.
const MapChecks = preload("res://tests/campaign/map_checks.gd")

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

## Seeds checked against every hard rule.
const SEED_COUNT: int = 300

# A run seed for the single-map cases (the RNG plan's example, 3F9A-12C0-77E1-A).
const RUN_SEED: int = 0x3F9A12C077E1A

# Short names for the node types, so the expected tables fit on a line.
const STANDARD: CampaignGraph.NodeType = CampaignGraph.NodeType.STANDARD
const KEY: CampaignGraph.NodeType = CampaignGraph.NodeType.KEY
const BOSS: CampaignGraph.NodeType = CampaignGraph.NodeType.BOSS
const ARMORY: CampaignGraph.NodeType = CampaignGraph.NodeType.ARMORY
const GUILDHALL: CampaignGraph.NodeType = CampaignGraph.NodeType.GUILDHALL
const UNKNOWN: CampaignGraph.NodeType = CampaignGraph.NodeType.UNKNOWN
const CAMP: CampaignGraph.NodeType = CampaignGraph.NodeType.CAMP
const TREASURE: CampaignGraph.NodeType = CampaignGraph.NodeType.TREASURE

var _report: Callable
var _rules: CampaignMapRules = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_rules = load(RULES_PATH) as CampaignMapRules
	_check("rules: the .tres loads", _rules != null)
	if _rules == null:
		return
	_test_rules_match_vision()
	_test_hard_rules_hold()
	_test_same_seed_same_map()
	_test_round_trip()
	_test_bad_data_rejected()
	_test_unusable_rules_refused()
	_test_checks_catch_breaks()


## The map stream of run seed [param run_seed], as the run's registry would make it.
static func map_stream(run_seed: int) -> RngStream:
	return RngStream.new(
			RngKey.derive_seed(run_seed, RngKey.RngPurpose.MAP_GENERATION, -1, -1, -1, -1)
	)


# Values from game-vision.md (Run structure: Node placement, Campaign map) and Godot_FE's grid.
func _test_rules_match_vision() -> void:
	var problems: PackedStringArray = _rules.validate()
	_check("rules: validate() finds nothing", problems.is_empty(), "; ".join(problems))
	_check("rules: 18 floors x 7 columns, 6 walks", (
			_rules.floor_count == 18 and _rules.column_count == 7 and _rules.path_count == 6
	))
	_check("rules: weights 4/2/1/1/2/1/1", _rules.weights == {
		STANDARD: 4, UNKNOWN: 2, ARMORY: 1, GUILDHALL: 1, CAMP: 2, TREASURE: 1, KEY: 1,
	}, str(_rules.weights))
	_check("rules: fixed rows 1, 6, 9, 12, 17, 18", _rules.fixed_rows == {
		1: STANDARD, 6: KEY, 9: TREASURE, 12: KEY, 17: CAMP, 18: BOSS,
	}, str(_rules.fixed_rows))
	var camp_banned: PackedInt32Array = _rules.banned_floors.get(CAMP, PackedInt32Array())
	_check("rules: floor limits", (
			_rules.earliest_floor == {CAMP: 6, KEY: 6, ARMORY: 3, GUILDHALL: 3}
			and _rules.banned_floors.size() == 1
			and camp_banned == PackedInt32Array([16])
	), "%s %s" % [_rules.earliest_floor, _rules.banned_floors])
	var groups: Array[PackedInt32Array] = [
		PackedInt32Array([KEY]),
		PackedInt32Array([ARMORY, GUILDHALL]),
		PackedInt32Array([CAMP]),
	]
	# Compared as text: comparing two typed arrays gives an untyped result here.
	_check("rules: Key, shops, Camp never repeat", str(_rules.no_repeat_groups) == str(groups))
	_check("rules: caps Key 4, Camp 5", _rules.path_caps == {KEY: 4, CAMP: 5})
	_check("rules: targets Armory 1, Guildhall 1, Treasure 2, Camp 2", _rules.path_targets == {
		ARMORY: 1, GUILDHALL: 1, TREASURE: 2, CAMP: 2,
	}, str(_rules.path_targets))


func _test_hard_rules_hold() -> void:
	var broken: int = 0
	var first: String = ""
	for run_seed: int in range(1, SEED_COUNT + 1):
		var graph: CampaignGraph = CampaignMapGenerator.generate(_rules, map_stream(run_seed))
		var problems: PackedStringArray = MapChecks.violations(graph, _rules)
		if not problems.is_empty():
			broken += 1
			if first.is_empty():
				first = "seed %d: %s" % [run_seed, problems[0]]
	_check("generate: %d seeds keep every hard rule" % [SEED_COUNT], broken == 0, (
			"%d broken; %s" % [broken, first]
	))


# The global generator is reseeded between the two maps, so a draw from it would show.
func _test_same_seed_same_map() -> void:
	seed(1)
	var first: CampaignGraph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	seed(2)
	randi()
	var second: CampaignGraph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	_check("generate: same seed, same map", first.to_dict() == second.to_dict())
	var other: CampaignGraph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED + 1))
	_check("generate: another seed, another map", first.to_dict() != other.to_dict())


func _test_round_trip() -> void:
	var graph: CampaignGraph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	var data: Dictionary = graph.to_dict()
	var copy: CampaignGraph = CampaignGraph.from_dict(data)
	_check("graph: from_dict(to_dict()) is the same map", (
			copy != null and copy.to_dict() == data
	))

	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var parsed_data: Dictionary = parsed if parsed is Dictionary else {}
	var from_json: CampaignGraph = CampaignGraph.from_dict(parsed_data)
	_check("graph: survives a JSON round trip", (
			from_json != null and from_json.to_dict() == data
	))
	if from_json == null:
		return
	var same_links: bool = from_json.node_count() == graph.node_count()
	for id: int in graph.node_count():
		same_links = (
				same_links
				and from_json.parents_of(id) == graph.parents_of(id)
				and from_json.type_of(id) == graph.type_of(id)
		)
	_check("graph: parents and types rebuilt from the data", same_links)


func _test_bad_data_rejected() -> void:
	var good: Dictionary = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED)).to_dict()
	var cases: Dictionary[String, Dictionary] = {}

	var no_nodes: Dictionary = good.duplicate(true)
	no_nodes.erase("nodes")
	cases["no node list"] = no_nodes

	var bad_type: Dictionary = good.duplicate(true)
	bad_type["nodes"][0]["type"] = 99
	cases["an unknown type"] = bad_type

	var fraction: Dictionary = good.duplicate(true)
	fraction["nodes"][0]["column"] = 1.5
	cases["a column that isn't whole"] = fraction

	var outside: Dictionary = good.duplicate(true)
	outside["nodes"][0]["floor"] = 0
	cases["a floor below 1"] = outside

	var shared_cell: Dictionary = good.duplicate(true)
	shared_cell["nodes"][1]["floor"] = shared_cell["nodes"][0]["floor"]
	shared_cell["nodes"][1]["column"] = shared_cell["nodes"][0]["column"]
	cases["two nodes in one cell"] = shared_cell

	var skip: Dictionary = good.duplicate(true)
	var last: int = (skip["nodes"] as Array).size() - 1
	skip["nodes"][0]["children"] = [last]
	cases["an edge skipping floors"] = skip

	var missing: Dictionary = good.duplicate(true)
	missing["nodes"][0]["children"] = [9999]
	cases["a child that doesn't exist"] = missing

	for case_name: String in cases:
		_check("graph: rejects %s" % [case_name], CampaignGraph.from_dict(cases[case_name]) == null)


func _test_unusable_rules_refused() -> void:
	_check("generate: refuses missing rules (error expected)", (
			CampaignMapGenerator.generate(null, map_stream(RUN_SEED)) == null
	))
	var no_boss: CampaignMapRules = _rules.duplicate() as CampaignMapRules
	var rows: Dictionary[int, CampaignGraph.NodeType] = no_boss.fixed_rows.duplicate()
	rows.erase(no_boss.floor_count)
	no_boss.fixed_rows = rows
	_check("generate: refuses rules with no boss row (error expected)", (
			CampaignMapGenerator.generate(no_boss, map_stream(RUN_SEED)) == null
	))
	var nothing_rolls: CampaignMapRules = _rules.duplicate() as CampaignMapRules
	var weights: Dictionary[CampaignGraph.NodeType, int] = {}
	nothing_rolls.weights = weights
	_check("generate: refuses rules that leave a node no type (error expected)", (
			CampaignMapGenerator.generate(nothing_rolls, map_stream(RUN_SEED)) == null
	))


# Each break is made on a valid map, and the checks must name it.
func _test_checks_catch_breaks() -> void:
	var graph: CampaignGraph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	var key_id: int = graph.nodes_on_floor(6)[0]
	graph.set_node_type(key_id, STANDARD)
	_check("checks: catch a broken fixed row", _has(MapChecks.violations(graph, _rules), "fixed"))

	graph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	graph.set_node_type(graph.children_of(key_id)[0], KEY)
	_check("checks: catch a Key after a Key", _has(MapChecks.violations(graph, _rules), "repeats"))

	graph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	graph.set_node_type(graph.nodes_on_floor(2)[0], ARMORY)
	_check("checks: catch a shop on floor 2", _has(MapChecks.violations(graph, _rules), "earliest"))

	graph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	graph.set_node_type(graph.nodes_on_floor(16)[0], CAMP)
	_check("checks: catch a Camp on floor 16", _has(MapChecks.violations(graph, _rules), "banned"))

	graph = CampaignMapGenerator.generate(_rules, map_stream(RUN_SEED))
	for floor_number: int in [8, 10, 14]:
		for id: int in graph.nodes_on_floor(floor_number):
			graph.set_node_type(id, KEY)
	_check("checks: catch a fifth Key on a route", _has(MapChecks.violations(graph, _rules), "cap"))

	var twins: CampaignGraph = _graph_with_two_children()
	_check("checks: catch two children of one type", (
			_has(MapChecks.violations(twins, _rules), "two children")
	))


# A valid map with a node on a rolled floor whose two children are given one type. Seeds are
# tried in order until a map has such a node; the check case fails if none does.
func _graph_with_two_children() -> CampaignGraph:
	for run_seed: int in range(1, SEED_COUNT + 1):
		var graph: CampaignGraph = CampaignMapGenerator.generate(_rules, map_stream(run_seed))
		for id: int in graph.nodes_on_floor(3):
			var children: PackedInt32Array = graph.children_of(id)
			if children.size() >= 2:
				graph.set_node_type(children[0], UNKNOWN)
				graph.set_node_type(children[1], UNKNOWN)
				return graph
	return null


func _has(problems: PackedStringArray, word: String) -> bool:
	for problem: String in problems:
		if problem.contains(word):
			return true
	return false


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
