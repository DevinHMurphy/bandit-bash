# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_pool_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## Map pool coverage for tests/campaign/run_all.gd, on the real map rules and pools: every floor
## a Standard, Key or Boss node can stand on, as the map rules place them, has exactly one pool of
## its type, whose maps are all of that combat type and load; nothing else has a pool; and on
## [constant SEED_COUNT] generated maps every combat node, and every Unknown node (which fights on
## the Standard pool), finds a pool with maps. Touches no save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

# Maps generated for the node sweep; each takes a few milliseconds.
const SEED_COUNT: int = 200

# The combat node types and the map combat type each one's pool must hold.
const COMBAT_TYPES: Dictionary[CampaignGraph.NodeType, CombatMapDefinition.CombatType] = {
	CampaignGraph.NodeType.STANDARD: CombatMapDefinition.CombatType.STANDARD,
	CampaignGraph.NodeType.KEY: CombatMapDefinition.CombatType.KEY,
	CampaignGraph.NodeType.BOSS: CombatMapDefinition.CombatType.BOSS,
}

var _report: Callable
var _rules: CampaignMapRules = null
var _pools: CombatMapPools = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_rules = load(RULES_PATH) as CampaignMapRules
	_pools = CombatMapPools.load_default()
	_check("map pools: the map rules and pools load", _rules != null and _pools != null)
	if _rules == null or _pools == null:
		return
	_test_floor_coverage()
	_test_maps_load()
	_test_generated_nodes()


# Each combat type on every floor the rules can place it: one pool, of maps of that combat type.
# Every other node type, on every floor, has none.
func _test_floor_coverage() -> void:
	var problems: PackedStringArray = []
	for type: int in CampaignGraph.NodeType.size():
		var node_type: CampaignGraph.NodeType = type as CampaignGraph.NodeType
		var type_name: String = CampaignGraph.NodeType.find_key(node_type) as String
		for floor_number: int in range(1, _rules.floor_count + 1):
			var covering: int = _covering(node_type, floor_number)
			var is_combat: bool = COMBAT_TYPES.has(node_type)
			if not is_combat:
				if covering > 0:
					problems.append("%s on floor %d has a pool" % [type_name, floor_number])
				continue
			if not _can_stand_on(node_type, floor_number):
				continue
			var pool: CombatMapPool = _pools.pool_for(node_type, floor_number)
			if covering != 1 or pool == null or pool.maps.is_empty():
				problems.append("%s on floor %d: %d pools" % [type_name, floor_number, covering])
				continue
			for map: CombatMapDefinition in pool.maps:
				if map == null or map.combat_type != COMBAT_TYPES[node_type]:
					problems.append("%s on floor %d: %s isn't a %s map" % [
						type_name, floor_number, "a missing map" if map == null else map.id,
						type_name.to_lower(),
					])
	_check("map pools: every floor a combat can stand on has one pool of its own maps", (
			problems.is_empty()
	), ", ".join(problems))


# Every pooled map has a scene that loads into a layout.
func _test_maps_load() -> void:
	var broken: PackedStringArray = []
	var seen: Dictionary[String, bool] = {}
	for pool: CombatMapPool in _pools.pools:
		for map: CombatMapDefinition in pool.maps:
			if map == null or seen.has(map.id):
				continue
			seen[map.id] = true
			if map.scene == null or MapLoader.load_layout(map) == null:
				broken.append(map.id)
	_check("map pools: every pooled map loads (%d maps)" % [seen.size()], (
			not seen.is_empty() and broken.is_empty()
	), ", ".join(broken))


# On generated maps, every combat node finds a pool of its type and every Unknown the Standard
# one, as CampaignRunState.battle_request looks them up.
func _test_generated_nodes() -> void:
	var missing: PackedStringArray = []
	var nodes: int = 0
	for run_seed: int in range(1, SEED_COUNT + 1):
		var stream: RngStream = RngStreams.new(run_seed).stream(
				RngKey.new(RngKey.RngPurpose.MAP_GENERATION)
		)
		var graph: CampaignGraph = CampaignMapGenerator.generate(_rules, stream)
		if graph == null:
			missing.append("seed %d: no map" % [run_seed])
			continue
		for id: int in graph.node_count():
			var type: CampaignGraph.NodeType = graph.type_of(id)
			if type == CampaignGraph.NodeType.UNKNOWN:
				type = CampaignGraph.NodeType.STANDARD
			elif not COMBAT_TYPES.has(type):
				continue
			nodes += 1
			var pool: CombatMapPool = _pools.pool_for(type, graph.floor_of(id))
			if pool == null or pool.maps.is_empty():
				missing.append("seed %d: node %d on floor %d" % [run_seed, id, graph.floor_of(id)])
	_check("map pools: on %d maps, all %d combat and Unknown nodes find maps" % [
		SEED_COUNT, nodes,
	], missing.is_empty(), ", ".join(missing.slice(0, 5)))


# How many pools cover type on floor_number.
func _covering(type: CampaignGraph.NodeType, floor_number: int) -> int:
	var count: int = 0
	for pool: CombatMapPool in _pools.pools:
		if pool != null and pool.covers(type, floor_number):
			count += 1
	return count


# Whether the map rules can put a node of type on floor_number: its fixed row, or a rolled floor
# its weight, earliest floor and banned floors allow.
func _can_stand_on(type: CampaignGraph.NodeType, floor_number: int) -> bool:
	if _rules.fixed_rows.has(floor_number):
		return _rules.fixed_rows[floor_number] == type
	if _rules.weights.get(type, 0) <= 0:
		return false
	if floor_number < _rules.earliest_floor.get(type, 1):
		return false
	var banned: PackedInt32Array = _rules.banned_floors.get(type, PackedInt32Array())
	return not banned.has(floor_number)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
