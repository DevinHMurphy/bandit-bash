# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_set_cases.gd
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================

extends RefCounted
## The M2 map set's cases for tests/map_set/run_all.gd (combat map plan, MP10 row): each map loads
## and passes [MapCheck], fits its combat type's size, has a turn par, cover for both sides and
## enough enemy slots; the real pools cover every combat node and floor with no empty pool; a seeded
## run draws the same maps twice, never repeating one before its pool is used up. Reports each case
## through the check callable it is given.[br]
## [b]Enough enemy slots:[/b] the largest pack the map's steps can draw on the real catalog, plus
## [constant HUNTED_SLOTS] free for two Hunted copies (enemy-packs.md, What this means for maps).
## Setup fills slots in [MapLayout] order, so only the count matters.
##
## @tutorial(Enemy packs): docs/design/enemy-packs.md

const M1Cases = preload("res://tests/map/m1_cases.gd")

## The standard maps of the set, each [code]res://maps/standard/<id>.tres[/code].
const STANDARD_MAPS: Array[String] = [
	"crossroads", "river_ford", "old_mill", "ruined_chapel", "bandit_camp", "watch_post",
]

## The Defeat the Leader maps, kept out of every pool until P05 EN7 fills the leader slot: before
## that, nothing appears there and the objective can't be won.
const LEADER_MAPS: Array[String] = ["bandit_camp", "watch_post"]

## Free enemy slots a map keeps beyond its largest pack: two Hunted copies (P05 question 40).
const HUNTED_SLOTS: int = 2

## Standard map size bounds, in tiles (game-vision.md, Combat maps: about 8×6 to 10×8).
const STANDARD_MIN_SIZE: Vector2i = Vector2i(8, 6)
const STANDARD_MAX_SIZE: Vector2i = Vector2i(10, 8)

## Deployment tiles with cover at hand, as the M1 map's cover case asks.
const COVERED_DEPLOYMENT: int = 4

## The run's combat floors (game-vision.md, Run structure): standard combats on 1-17, key combats
## from floor 6, the boss on 18.
const LAST_STANDARD_FLOOR: int = 17
const FIRST_KEY_FLOOR: int = 6
const BOSS_FLOOR: int = 18

# Any fixed run seed and node: the draw cases compare two runs, never golden maps.
const RUN_SEED: int = 0x3A9_0010
const NODE: int = 1

const STANDARD: CampaignGraph.NodeType = CampaignGraph.NodeType.STANDARD
const KEY: CampaignGraph.NodeType = CampaignGraph.NodeType.KEY
const BOSS: CampaignGraph.NodeType = CampaignGraph.NodeType.BOSS

var _check: Callable
var _pools: CombatMapPools = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	var needed: int = _largest_standard_pack(EffectCatalog.index()) + HUNTED_SLOTS
	for map_id: String in STANDARD_MAPS:
		_test_standard_map(map_id, needed)
	_pools = CombatMapPools.load_default()
	_ok("pools: load", _pools != null)
	if _pools == null:
		return
	_test_pool_coverage()
	_test_standard_pools()
	_test_seeded_draws()


func _test_standard_map(map_id: String, needed_slots: int) -> void:
	var label: String = "map %s" % [map_id]
	var path: String = "res://maps/standard/%s.tres" % [map_id]
	var definition: CombatMapDefinition = load(path) as CombatMapDefinition
	_ok("%s: the definition loads" % [label], definition != null, path)
	if definition == null:
		return
	_ok("%s: its id, scene and combat type" % [label], (
			definition.id == map_id
			and definition.scene != null
			and definition.combat_type == CombatMapDefinition.CombatType.STANDARD
	))
	var objective: CombatMapDefinition.Objective = (
			CombatMapDefinition.Objective.DEFEAT_LEADER if LEADER_MAPS.has(map_id)
			else CombatMapDefinition.Objective.ROUT
	)
	_ok("%s: %s, with a turn par" % [label, CombatMapDefinition.Objective.find_key(objective)], (
			definition.objective == objective and definition.turn_par > 0
	), "objective %d, par %d" % [definition.objective, definition.turn_par])
	var layout: MapLayout = MapLoader.load_layout(definition)
	if layout == null:
		_ok("%s: loads" % [label], false)
		return
	var failures: Array[MapCheck.Failure] = MapCheck.check(definition, layout)
	_ok("%s: passes the map check" % [label], failures.is_empty(), MapCheck.describe(failures))
	var rect: Rect2i = layout.get_rect()
	_ok("%s: a full rectangle of standard size" % [label], (
			rect.position == Vector2i.ZERO
			and rect.size.x >= STANDARD_MIN_SIZE.x and rect.size.x <= STANDARD_MAX_SIZE.x
			and rect.size.y >= STANDARD_MIN_SIZE.y and rect.size.y <= STANDARD_MAX_SIZE.y
			and layout.tiles().size() == rect.get_area()
	), str(rect))
	var slots: int = layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT).size()
	_ok("%s: enough enemy slots for every step, Hunted included" % [label], (
			slots >= needed_slots
	), "%d slots, %d needed" % [slots, needed_slots])
	var leader_slots: int = layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT).size()
	_ok("%s: one leader slot when the objective needs it, none otherwise" % [label], (
			leader_slots == (1 if objective == CombatMapDefinition.Objective.DEFEAT_LEADER else 0)
	), "%d leader slots" % [leader_slots])
	_test_cover(label, layout)


# Terrain is the only source of avoid, so each side needs cover at hand (game-vision.md, Combat
# maps), judged as the M1 map's cover case judges it.
func _test_cover(label: String, layout: MapLayout) -> void:
	var starts: Array[Vector2i] = layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	starts.append_array(layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT))
	var uncovered: Array[Vector2i] = []
	for tile: Vector2i in starts:
		if not M1Cases.has_cover_near(layout, tile):
			uncovered.append(tile)
	_ok("%s: cover next to every enemy start" % [label], uncovered.is_empty(), str(uncovered))
	var covered: int = 0
	for tile: Vector2i in layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT):
		if M1Cases.has_cover_near(layout, tile):
			covered += 1
	_ok("%s: cover next to the deployment zone" % [label], (
			covered >= COVERED_DEPLOYMENT
	), "%d tiles" % [covered])


func _test_pool_coverage() -> void:
	var empty: PackedStringArray = []
	for floor_number: int in range(1, LAST_STANDARD_FLOOR + 1):
		_note_empty(empty, STANDARD, floor_number)
		if floor_number >= FIRST_KEY_FLOOR:
			_note_empty(empty, KEY, floor_number)
	_note_empty(empty, BOSS, BOSS_FLOOR)
	_ok("pools: no combat node on any floor has an empty pool", empty.is_empty(), str(empty))


func _test_standard_pools() -> void:
	var expected: PackedStringArray = []
	for map_id: String in STANDARD_MAPS:
		if not LEADER_MAPS.has(map_id):
			expected.append(map_id)
	var wrong: PackedStringArray = []
	for floor_number: int in range(1, LAST_STANDARD_FLOOR + 1):
		var pool: CombatMapPool = _pools.pool_for(STANDARD, floor_number)
		var ids: PackedStringArray = PackedStringArray() if pool == null else pool.map_ids()
		if ids != expected:
			wrong.append("floor %d: %s" % [floor_number, ids])
	_ok("pools: every standard floor draws the set's Rout maps, not M1 or a Leader map", (
			wrong.is_empty()
	), "; ".join(wrong))


# A run whose every floor up to 17 is a standard combat, the most draws one run can make.
func _test_seeded_draws() -> void:
	var first: PackedStringArray = _draws(RUN_SEED)
	var second: PackedStringArray = _draws(RUN_SEED)
	_ok("draws: a seeded run draws the same maps twice", (
			first.size() == LAST_STANDARD_FLOOR and first == second
	), "%s / %s" % [first, second])
	var repeats: PackedStringArray = []
	var since_refill: PackedStringArray = []
	for index: int in first.size():
		var pool: CombatMapPool = _pools.pool_for(STANDARD, index + 1)
		var map_id: String = first[index]
		if since_refill.has(map_id):
			for pool_id: String in pool.map_ids():
				if not since_refill.has(pool_id):
					repeats.append("floor %d: %s before %s" % [index + 1, map_id, pool_id])
			since_refill.clear()
		since_refill.append(map_id)
	_ok("draws: no map repeats before its pool is used up", repeats.is_empty(), str(repeats))


# The map each floor's standard combat draws, through CombatEncounter's step 1 on the pool's
# unused maps (CombatMapPools.available), counting each draw as used as CampaignRunState does: a
# map drawn again means its pool refilled, so the pool's maps are forgotten first.
func _draws(run_seed: int) -> PackedStringArray:
	var drawn: PackedStringArray = []
	var used: PackedStringArray = []
	for floor_number: int in range(1, LAST_STANDARD_FLOOR + 1):
		var pool: CombatMapPool = _pools.pool_for(STANDARD, floor_number)
		var offered: Array[CombatMapDefinition] = CombatMapPools.available(pool, used)
		var encounter: CombatEncounter = CombatEncounter.new(
				floor_number, NODE, PackedInt32Array([0]), InstanceIdAllocator.new()
		)
		var error: Error = encounter.run_setup(
				offered, CombatEncounter.SetupStreams.new(run_seed, floor_number, NODE)
		)
		if error != OK:
			drawn.append("error %s" % [error_string(error)])
			encounter.close()
			continue
		var map_id: String = encounter.setup.map.id
		encounter.close()
		if used.has(map_id):
			var kept: PackedStringArray = []
			for used_id: String in used:
				if not pool.map_ids().has(used_id):
					kept.append(used_id)
			used = kept
		used.append(map_id)
		drawn.append(map_id)
	return drawn


func _note_empty(empty: PackedStringArray, type: CampaignGraph.NodeType, floor_number: int) -> void:
	var pool: CombatMapPool = _pools.pool_for(type, floor_number)
	if pool == null or pool.map_ids().is_empty():
		empty.append("%s floor %d" % [CampaignGraph.NodeType.find_key(type), floor_number])


# The most units any basic or hard pack fields at any step: a standard map serves every step.
func _largest_standard_pack(catalog: EffectCatalog.Index) -> int:
	var largest: int = 0
	for path: String in catalog.paths:
		var pack: PackDefinition = catalog.at_path(path) as PackDefinition
		if pack == null:
			continue
		if pack.pool != PackDefinition.Pool.BASIC and pack.pool != PackDefinition.Pool.HARD:
			continue
		for step: int in range(1, PackDefinition.STEPS + 1):
			largest = maxi(largest, pack.units(step).size())
	_ok("packs: the real catalog's largest standard pack", largest > 0, str(largest))
	return largest


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
