# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     full_run_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## A whole seeded solo run for tests/ui/campaign/run_all.gd, from the new run to the Boss's end,
## through the real SaveService and CampaignService ([code]full_run_pilot.gd[/code] plays it):
## played straight, it completes on a route through every kind of node; every battle draws a map
## of its node's pool and a pack of its kind at its step's count, all placed, no map or mini-boss
## repeating before its pool is used; Results shows the run's seed, once. Played again with a quit
## and Continue at every stop (on the map, mid-battle, at each combat's results, inside each other
## node), it ends the same, and after every node, of each kind, the whole run (its sections,
## events, streams and id counter) equals the straight play's. Battles are won by recording their
## end, not played. Writes save files, so it runs only with a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Pilot = preload("res://tests/ui/campaign/full_run_pilot.gd")

const RESULTS_SCENE: String = "res://ui/screens/results_screen.tscn"

# A seed whose richest route passes every kind of node, the Unknown playing as an event.
const RUN_SEED: int = 0x51A7E

# Units a drawn pack fields at steps 1, 2 and 3, a key pack's escorts likewise, with its mini-boss
# on top (game-vision.md, Run structure and Campaign nodes).
const STEP_SIZES: Array[int] = [3, 4, 5]

# Every kind of map node a run can enter.
const KINDS: Array[CampaignGraph.NodeType] = [
	CampaignGraph.NodeType.STANDARD,
	CampaignGraph.NodeType.KEY,
	CampaignGraph.NodeType.BOSS,
	CampaignGraph.NodeType.TREASURE,
	CampaignGraph.NodeType.CAMP,
	CampaignGraph.NodeType.ARMORY,
	CampaignGraph.NodeType.GUILDHALL,
	CampaignGraph.NodeType.UNKNOWN,
]

var _check: Callable
var _root: Window = null


func _init(check: Callable, tree_root: Window) -> void:
	_check = check
	_root = tree_root


func run() -> void:
	var straight: Pilot = Pilot.new(_root, false)
	var is_done: bool = straight.play(RUN_SEED, RESULTS_SCENE)
	_check.call("full run: a seeded solo run plays from its start to the Boss's end", (
			is_done
	), str(straight.errors))
	if not is_done:
		return
	_test_route(straight)
	_test_battles(straight)
	_check.call("full run: Results shows the run's seed (RunSeed.format), and takes the run once", (
			straight.results_seed_text == "Seed %s" % [RunSeed.format(RUN_SEED)]
			and not straight.is_record_left
	), straight.results_seed_text)

	var quitting: Pilot = Pilot.new(_root, true)
	var is_resumed: bool = quitting.play(RUN_SEED, RESULTS_SCENE)
	_check.call("full run: with a quit and Continue at every stop, it plays to the same end", (
			is_resumed
			and quitting.route == straight.route
			and quitting.nodes.size() == straight.nodes.size()
			and quitting.results_seed_text == straight.results_seed_text
	), str(quitting.errors))
	if is_resumed:
		_test_resumes(straight, quitting)
	print("NOTE  full run: %d ms straight, %d ms with %d quits" % [
		straight.elapsed_msec, quitting.elapsed_msec, _total(quitting.quit_in),
	])


# The planned route: one node per floor, every kind of node on it.
func _test_route(straight: Pilot) -> void:
	var kinds: Dictionary[String, bool] = {}
	for entry: Dictionary in straight.nodes:
		kinds[entry["type"] as String] = true
	var missing: PackedStringArray = []
	for kind: CampaignGraph.NodeType in KINDS:
		var kind_name: String = CampaignGraph.NodeType.find_key(kind) as String
		if not kinds.has(kind_name):
			missing.append(kind_name)
	_check.call("full run: the route enters 18 nodes, one per floor, every kind among them", (
			straight.nodes.size() == Pilot.MAX_NODES and missing.is_empty()
	), "missing %s" % [missing])


# Each battle's map and pack, as its setup drew them.
func _test_battles(straight: Pilot) -> void:
	var pools: CombatMapPools = CombatMapPools.load_default()
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var wrong_maps: PackedStringArray = []
	var wrong_packs: PackedStringArray = []
	var repeats: PackedStringArray = []
	# Every map fought so far: the run counts used maps across all its pools.
	var used: PackedStringArray = []
	var mini_bosses: PackedStringArray = []
	var kinds: Dictionary[String, bool] = {}
	for battle: Dictionary in straight.battles:
		var floor_number: int = battle["floor"]
		var type_name: String = battle["type"]
		var type: CampaignGraph.NodeType = (
				CampaignGraph.NodeType.get(type_name, 0) as int
		) as CampaignGraph.NodeType
		var where: String = "floor %d %s" % [floor_number, type_name]
		kinds[type_name] = true
		var pool: CombatMapPool = pools.pool_for(type, floor_number)
		var map_id: String = battle["map"]
		if pool == null or not pool.map_ids().has(map_id):
			wrong_maps.append("%s: %s" % [where, map_id])
		elif used.has(map_id) and not _is_used_up(pool, used):
			repeats.append("%s: %s" % [where, map_id])
		used.append(map_id)
		var problem: String = _pack_problem(battle, type, catalog, pool)
		if not problem.is_empty():
			wrong_packs.append("%s: %s" % [where, problem])
		var mini_boss: String = battle["mini_boss"]
		if not mini_boss.is_empty():
			if mini_bosses.has(mini_boss):
				repeats.append("%s: mini-boss %s" % [where, mini_boss])
			mini_bosses.append(mini_boss)
	_check.call("full run: Standard, Key and Boss battles were all fought", (
			kinds.has("STANDARD") and kinds.has("KEY") and kinds.has("BOSS")
	), str(kinds.keys()))
	_check.call("full run: every battle draws a real map of its node's pool", (
			wrong_maps.is_empty()
	), ", ".join(wrong_maps))
	_check.call("full run: every battle's pack is its kind's, at its step's count, all placed", (
			wrong_packs.is_empty()
	), ", ".join(wrong_packs))
	_check.call("full run: no map repeats before its pool is used, no mini-boss twice", (
			repeats.is_empty()
	), ", ".join(repeats))


# After every node the quitting play's run equals the straight play's, checked per kind of node.
func _test_resumes(straight: Pilot, quitting: Pilot) -> void:
	var differs: Dictionary[String, PackedStringArray] = {}
	for index: int in mini(straight.nodes.size(), quitting.nodes.size()):
		var entry: Dictionary = straight.nodes[index]
		var kind: String = entry["type"]
		var problems: PackedStringArray = differs.get(kind, PackedStringArray())
		if entry["snapshot"] != quitting.nodes[index]["snapshot"]:
			problems.append("floor %d" % [entry["floor"]])
		differs[kind] = problems
	for kind: CampaignGraph.NodeType in KINDS:
		var kind_name: String = CampaignGraph.NodeType.find_key(kind) as String
		var problems: PackedStringArray = differs.get(kind_name, PackedStringArray())
		_check.call(
				"full run: quits inside %s nodes resume to the uninterrupted run" % [
					kind_name.to_lower(),
				],
				quitting.quit_in.get(kind_name, 0) > 0 and differs.has(kind_name)
				and problems.is_empty(),
				"%d quits; differs on %s" % [quitting.quit_in.get(kind_name, 0), problems]
		)


# Why battle's pack isn't the one a node of type draws at its floor's step, or "" when it is. A
# scripted map's is its fixed pack.
func _pack_problem(
		battle: Dictionary,
		type: CampaignGraph.NodeType,
		catalog: EffectCatalog.Index,
		pool: CombatMapPool
) -> String:
	var pack: PackDefinition = catalog.pack(battle["pack"] as String)
	if pack == null:
		return "no pack drawn"
	if (battle["unplaced"] as int) > 0:
		return "%d units unplaced" % [battle["unplaced"]]
	var size: int = STEP_SIZES[EnemySetup.step_of(battle["floor"] as int) - 1]
	var units: int = battle["units"]
	match type:
		CampaignGraph.NodeType.KEY:
			if pack.pool != PackDefinition.Pool.KEY or (battle["mini_boss"] as String).is_empty():
				return "%s isn't a key pack" % [pack.id]
			if units != size + 1:
				return "%d units, not %d escorts and the mini-boss" % [units, size]
		CampaignGraph.NodeType.BOSS:
			var fixed: String = _fixed_pack(pool, battle["map"] as String)
			if fixed.is_empty() or pack.id != fixed:
				return "%s isn't the boss map's pack %s" % [pack.id, fixed]
		_:
			if pack.pool != PackDefinition.Pool.BASIC and pack.pool != PackDefinition.Pool.HARD:
				return "%s isn't a standard pack" % [pack.id]
			if units != size:
				return "%d units, not %d" % [units, size]
	return ""


# Whether every map of pool is in used, so its pool may refill and repeat one.
static func _is_used_up(pool: CombatMapPool, used: PackedStringArray) -> bool:
	for map_id: String in pool.map_ids():
		if not used.has(map_id):
			return false
	return true


# The fixed pack of the map map_id in pool; "" for none.
static func _fixed_pack(pool: CombatMapPool, map_id: String) -> String:
	if pool == null:
		return ""
	for map: CombatMapDefinition in pool.maps:
		if map != null and map.id == map_id:
			return map.fixed_pack_id
	return ""


static func _total(counts: Dictionary[String, int]) -> int:
	var total: int = 0
	for key: String in counts:
		total += counts[key]
	return total
