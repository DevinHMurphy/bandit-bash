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
## The M2 map set's cases for the map_set/standard suite (combat map plan, MP10 row): each map loads
## and passes [MapCheck], fits its combat type's size, has its objective and turn par, cover for
## both sides, enough enemy slots and its leader slot; the real pools cover every combat node and
## floor with no empty pool; a seeded run draws the same maps twice, never repeating one before its
## pool is used up. Reports each case through the check callable it is given.[br]
## [b]Enough enemy slots:[/b] the largest pack the map's steps can draw on the real catalog (a key
## map's escorts; its mini-boss takes the leader slot), plus [constant HUNTED_SLOTS] free for two
## Hunted copies (enemy-packs.md, What this means for maps). Setup fills slots in [MapLayout]
## order, so only the count matters.
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

## The key maps of the set, each [code]res://maps/key/<id>.tres[/code], with its objective.
const KEY_MAPS: Dictionary[String, CombatMapDefinition.Objective] = {
	"hall": CombatMapDefinition.Objective.DEFEAT_BOSS,
	"gatehouse": CombatMapDefinition.Objective.SEIZE,
	"hilltop": CombatMapDefinition.Objective.SURVIVE,
	"village": CombatMapDefinition.Objective.DEFEND,
}

## The Defeat the mini-boss map, kept out of the key pools until P05 EN8 places the mini-boss on
## its leader slot, for the same reason as [constant LEADER_MAPS].
const MINI_BOSS_MAPS: Array[String] = ["hall"]

## Free enemy slots a map keeps beyond its largest pack: two Hunted copies (P05 question 40).
const HUNTED_SLOTS: int = 2

## Standard map size bounds, in tiles (game-vision.md, Combat maps: about 8×6 to 10×8).
const STANDARD_MIN_SIZE: Vector2i = Vector2i(8, 6)
const STANDARD_MAX_SIZE: Vector2i = Vector2i(10, 8)

## Key map size, in tiles: game-vision.md's "about 12×10", which every key map of the set uses.
const KEY_SIZE: Vector2i = Vector2i(12, 10)

## Deployment tiles with cover at hand, as the M1 map's cover case asks.
const COVERED_DEPLOYMENT: int = 4

## The run's combat floors (game-vision.md, Run structure): standard combats on 1-17, key combats
## from floor 6 (steps 2 and 3), the boss on 18.
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
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var standard_needed: int = _largest_pack(
			catalog, [PackDefinition.Pool.BASIC, PackDefinition.Pool.HARD], 1
	) + HUNTED_SLOTS
	var key_needed: int = _largest_pack(catalog, [PackDefinition.Pool.KEY], 2) + HUNTED_SLOTS
	for map_id: String in STANDARD_MAPS:
		var objective: CombatMapDefinition.Objective = (
				CombatMapDefinition.Objective.DEFEAT_LEADER if LEADER_MAPS.has(map_id)
				else CombatMapDefinition.Objective.ROUT
		)
		_test_map("res://maps/standard/%s.tres" % [map_id], map_id, objective, standard_needed)
	for map_id: String in KEY_MAPS:
		_test_map("res://maps/key/%s.tres" % [map_id], map_id, KEY_MAPS[map_id], key_needed)
	_pools = CombatMapPools.load_default()
	_ok("pools: load", _pools != null)
	if _pools == null:
		return
	_test_pool_coverage()
	_test_pool_maps()
	_test_seeded_draws(STANDARD, 1)
	_test_seeded_draws(KEY, FIRST_KEY_FLOOR)


func _test_map(
		path: String,
		map_id: String,
		objective: CombatMapDefinition.Objective,
		needed_slots: int
) -> void:
	var label: String = "map %s" % [map_id]
	var definition: CombatMapDefinition = load(path) as CombatMapDefinition
	_ok("%s: the definition loads" % [label], definition != null, path)
	if definition == null:
		return
	var is_key: bool = KEY_MAPS.has(map_id)
	var combat_type: CombatMapDefinition.CombatType = (
			CombatMapDefinition.CombatType.KEY if is_key
			else CombatMapDefinition.CombatType.STANDARD
	)
	_ok("%s: its id, scene and combat type" % [label], (
			definition.id == map_id
			and definition.scene != null
			and definition.combat_type == combat_type
	))
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
	var min_size: Vector2i = KEY_SIZE if is_key else STANDARD_MIN_SIZE
	var max_size: Vector2i = KEY_SIZE if is_key else STANDARD_MAX_SIZE
	_ok("%s: a full rectangle of its combat type's size" % [label], (
			rect.position == Vector2i.ZERO
			and rect.size.x >= min_size.x and rect.size.x <= max_size.x
			and rect.size.y >= min_size.y and rect.size.y <= max_size.y
			and layout.tiles().size() == rect.get_area()
	), str(rect))
	var slots: int = layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT).size()
	_ok("%s: enough enemy slots for every step, Hunted included" % [label], (
			slots >= needed_slots
	), "%d slots, %d needed" % [slots, needed_slots])
	var has_leader: bool = is_key or objective == CombatMapDefinition.Objective.DEFEAT_LEADER
	var leader_slots: int = layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT).size()
	_ok("%s: one leader slot when a leader or mini-boss needs it, none otherwise" % [label], (
			leader_slots == (1 if has_leader else 0)
	), "%d leader slots" % [leader_slots])
	if objective == CombatMapDefinition.Objective.SURVIVE or (
			objective == CombatMapDefinition.Objective.DEFEND
	):
		_test_hold(label, definition, layout)
	_test_cover(label, layout)


# Survive and Defend end on a turn count; par below it rewards only an early end, which needs
# reinforcement points to close (game-vision.md, Combat maps).
func _test_hold(label: String, definition: CombatMapDefinition, layout: MapLayout) -> void:
	var points: int = layout.tiles_of(MapLayout.MarkerKind.REINFORCEMENT_POINT).size()
	_ok("%s: holds for its turns, par below them, with reinforcement points" % [label], (
			definition.survive_turns > definition.turn_par and points > 0
	), "%d turns, par %d, %d points" % [
		definition.survive_turns, definition.turn_par, points,
	])


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


func _test_pool_maps() -> void:
	var standard: PackedStringArray = []
	for map_id: String in STANDARD_MAPS:
		if not LEADER_MAPS.has(map_id):
			standard.append(map_id)
	var key: PackedStringArray = []
	for map_id: String in KEY_MAPS:
		if not MINI_BOSS_MAPS.has(map_id):
			key.append(map_id)
	var wrong: PackedStringArray = []
	for floor_number: int in range(1, LAST_STANDARD_FLOOR + 1):
		_note_wrong(wrong, STANDARD, floor_number, standard)
		if floor_number >= FIRST_KEY_FLOOR:
			_note_wrong(wrong, KEY, floor_number, key)
	_ok("pools: every floor draws the set's maps, not M1, a Leader or a mini-boss map", (
			wrong.is_empty()
	), "; ".join(wrong))


# A run whose every floor from first_floor to 17 is a combat of type, the most draws one run can
# make.
func _test_seeded_draws(type: CampaignGraph.NodeType, first_floor: int) -> void:
	var label: String = (CampaignGraph.NodeType.find_key(type) as String).to_lower()
	var first: PackedStringArray = _draws(type, first_floor, RUN_SEED)
	var second: PackedStringArray = _draws(type, first_floor, RUN_SEED)
	_ok("draws %s: a seeded run draws the same maps twice" % [label], (
			first.size() == LAST_STANDARD_FLOOR - first_floor + 1 and first == second
	), "%s / %s" % [first, second])
	var repeats: PackedStringArray = []
	var since_refill: PackedStringArray = []
	for index: int in first.size():
		var floor_number: int = first_floor + index
		var pool: CombatMapPool = _pools.pool_for(type, floor_number)
		var map_id: String = first[index]
		if since_refill.has(map_id):
			for pool_id: String in pool.map_ids():
				if not since_refill.has(pool_id):
					repeats.append("floor %d: %s before %s" % [floor_number, map_id, pool_id])
			since_refill.clear()
		since_refill.append(map_id)
	_ok("draws %s: no map repeats before its pool is used up" % [label], (
			repeats.is_empty()
	), str(repeats))


# The map each floor's combat of type draws, through CombatEncounter's step 1 on the pool's unused
# maps (CombatMapPools.available), counting each draw as used as CampaignRunState does: a map
# drawn again means its pool refilled, so the pool's maps are forgotten first.
func _draws(
		type: CampaignGraph.NodeType, first_floor: int, run_seed: int
) -> PackedStringArray:
	var drawn: PackedStringArray = []
	var used: PackedStringArray = []
	for floor_number: int in range(first_floor, LAST_STANDARD_FLOOR + 1):
		var pool: CombatMapPool = _pools.pool_for(type, floor_number)
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


func _note_wrong(
		wrong: PackedStringArray,
		type: CampaignGraph.NodeType,
		floor_number: int,
		expected: PackedStringArray
) -> void:
	var pool: CombatMapPool = _pools.pool_for(type, floor_number)
	var ids: PackedStringArray = PackedStringArray() if pool == null else pool.map_ids()
	if ids != expected:
		wrong.append("%s floor %d: %s" % [
			CampaignGraph.NodeType.find_key(type), floor_number, ids,
		])


# The most units any pack of pools fields at any step from first_step up: a standard map serves
# every step, a key map steps 2 and 3.
func _largest_pack(
		catalog: EffectCatalog.Index, pools: Array[PackDefinition.Pool], first_step: int
) -> int:
	var largest: int = 0
	for path: String in catalog.paths:
		var pack: PackDefinition = catalog.at_path(path) as PackDefinition
		if pack == null or not pools.has(pack.pool):
			continue
		for step: int in range(first_step, PackDefinition.STEPS + 1):
			largest = maxi(largest, pack.units(step).size())
	_ok("packs: the real catalog's largest pack from step %d" % [first_step], (
			largest > 0
	), str(largest))
	return largest


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
