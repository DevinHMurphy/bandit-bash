# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     grid_cases.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## The grid, state and pathing cases for tests/map/run_all.gd: [MapGrid] from a layout, every
## terrain for every movement type, golden reach per movement type, path checks against units and
## objects, [MapState] blocking and its sandbox copy, the nearest free tile, and the resolvers
## asking [CombatState]. Reports each case through the check callable it is given.

# Preloaded scripts used as types (gdscript.md, Naming): the test map and cases have no class name.
const MapWorld = preload("res://tests/map/map_world.gd")
const LayoutCases = preload("res://tests/map/layout_cases.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const DEFAULT: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT
const HEAVY: CombatGrid.MovementType = CombatGrid.MovementType.HEAVY
const MOBILE: CombatGrid.MovementType = CombatGrid.MovementType.MOBILE
const MOUNTED: CombatGrid.MovementType = CombatGrid.MovementType.MOUNTED
const FLIER: CombatGrid.MovementType = CombatGrid.MovementType.FLIER

# The golden map: forest, mountain, river, wall, thicket and house around a plain start at (0, 0).
const GOLDEN_ROWS: Array[String] = [
	"plain forest mountain plain",
	"plain river wall plain",
	"thicket house plain plain",
]

# Reach from (0, 0) with 5 movement points, worked by hand from unit-roster.md's costs.
const GOLDEN_REACH: Dictionary[CombatGrid.MovementType, String] = {
	DEFAULT: "(0, 0)=0 (1, 0)=2 (0, 1)=1 (0, 2)=3 (1, 2)=4 (2, 2)=5",
	HEAVY: "(0, 0)=0 (1, 0)=2 (0, 1)=1 (0, 2)=4 (1, 2)=5",
	MOBILE: "(0, 0)=0 (1, 0)=2 (2, 0)=5 (0, 1)=1 (1, 1)=3 (0, 2)=3 (1, 2)=4 (2, 2)=5",
	MOUNTED: "(0, 0)=0 (1, 0)=2 (0, 1)=1 (0, 2)=4",
	FLIER: (
			"(0, 0)=0 (1, 0)=1 (2, 0)=2 (3, 0)=3 (0, 1)=1 (1, 1)=2 (2, 1)=3 (3, 1)=4 "
			+ "(0, 2)=2 (1, 2)=3 (2, 2)=4 (3, 2)=5"
	),
}

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_map_grid()
	_test_every_terrain()
	_test_golden_reach()
	_test_units()
	_test_path_checks()
	_test_objects()
	_test_sandbox_copy()
	_test_nearest_free_tile()
	_test_resolvers_ask_the_state()


func _test_map_grid() -> void:
	var world: MapWorld = MapWorld.new(["plain wall spiked_wall", "spilled_oil fort mountain"])
	var grid: MapGrid = world.grid
	_ok("grid: a step on the map", grid.step(Vector2i(0, 0), Vector2i.RIGHT) == Vector2i(1, 0))
	_ok("grid: a step off the map", grid.step(Vector2i(0, 0), Vector2i.UP) == CombatFact.NO_TILE)
	_ok("grid: neighbors on the map", grid.neighbors(Vector2i(0, 0)).size() == 2)
	_ok("grid: off the map is a plain blocker", grid.blocker_at(Vector2i(3, 0)) == 2)
	_ok(
			"grid: a spiked wall",
			grid.blocker_at(Vector2i(2, 0)) == CombatGrid.Blocker.SPIKED_WALL
			and not grid.can_stand(Vector2i(2, 0), FLIER)
	)
	_ok(
			"grid: fliers cross walls, nobody else",
			grid.can_stand(Vector2i(1, 0), FLIER) and not grid.can_stand(Vector2i(1, 0), MOBILE)
			and grid.blocker_at(Vector2i(1, 0)) == CombatGrid.Blocker.NONE
	)
	_ok("grid: oil is slick", grid.is_slick(Vector2i(0, 1)) and not grid.is_slick(Vector2i(0, 0)))
	var fort: CombatGrid.TileBonus = grid.tile_bonus(Vector2i(1, 1))
	_ok(
			"grid: the fort's bonus",
			fort.avoid == 20 and fort.defense == 2 and fort.resistance == 2
			and fort.heal_percent == 20
	)
	var nowhere: CombatGrid.TileBonus = grid.tile_bonus(Vector2i(9, 9))
	_ok("grid: no bonus off the map", nowhere.avoid == 0 and nowhere.heal_flat == 0)
	_ok("grid: the mountain's cost on foot", grid.move_cost(Vector2i(2, 1), DEFAULT) == 4)
	_ok("grid: heavy units can't climb", grid.move_cost(Vector2i(2, 1), HEAVY) == 0)
	_ok("grid: no cost off the map", grid.move_cost(Vector2i(-1, 0), FLIER) == 0)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
	_ok("grid: a path's terrain cost", grid.path_cost(path, DEFAULT) == 7)
	_ok("grid: a path heavy units can't take", grid.path_cost(path, HEAVY) == -1)
	_ok("grid: a single tile costs nothing", grid.path_cost([Vector2i(0, 0)], DEFAULT) == 0)
	_ok("grid: a jump", grid.path_cost([Vector2i(0, 0), Vector2i(1, 1)], FLIER) == -1)


# Every terrain between two plains: reach and a one-step path for every movement type match
# unit-roster.md's costs.
func _test_every_terrain() -> void:
	for row: Array in LayoutCases.TABLE:
		var id: String = row[0]
		var costs: Array = row[1]
		var blocker: int = row[7]
		var mismatches: PackedStringArray = []
		for movement_type: int in CombatGrid.MovementType.values():
			var world: MapWorld = MapWorld.new(["plain %s plain" % [id]])
			var unit_type: CombatGrid.MovementType = movement_type as CombatGrid.MovementType
			world.add_unit("u", PLAYER, Vector2i(0, 0), unit_type, 20)
			var reach: Dictionary[Vector2i, int] = Pathing.reach(world.engine, world.state, "u")
			var cost: int = costs[movement_type]
			var enters: bool = cost > 0 and blocker == CombatGrid.Blocker.NONE
			var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
			var check: CombatGrid.PathCheck = world.state.validate_path(world.engine, "u", path)
			var expected_reach: String = (
					"(0, 0)=0 (1, 0)=%d (2, 0)=%d" % [cost, cost + 1] if enters else "(0, 0)=0"
			)
			var is_right: bool = (
					MapWorld.describe(reach) == expected_reach
					and check.is_legal == enters
					and (not enters or check.cost == cost)
			)
			if not is_right:
				mismatches.append(
						"%s: %s" % [CombatGrid.MovementType.find_key(movement_type), str(reach)]
				)
		_ok(
				"terrain cost: %s for every movement type" % [id],
				mismatches.is_empty(),
				str(mismatches)
		)


func _test_golden_reach() -> void:
	for movement_type: CombatGrid.MovementType in GOLDEN_REACH:
		var world: MapWorld = MapWorld.new(GOLDEN_ROWS)
		world.add_unit("u", PLAYER, Vector2i(0, 0), movement_type, 5)
		var reach: Dictionary[Vector2i, int] = Pathing.reach(world.engine, world.state, "u")
		_same(
				"reach: golden %s" % [CombatGrid.MovementType.find_key(movement_type)],
				MapWorld.describe(reach),
				GOLDEN_REACH[movement_type]
		)
	var spent: MapWorld = MapWorld.new(GOLDEN_ROWS)
	spent.add_unit("u", PLAYER, Vector2i(0, 0), DEFAULT, 5).movement_spent = 3
	_same(
			"reach: cost already spent comes off the budget",
			MapWorld.describe(Pathing.reach(spent.engine, spent.state, "u")),
			"(0, 0)=0 (1, 0)=2 (0, 1)=1"
	)
	_ok("reach: none off the map", Pathing.reach(spent.engine, spent.state, "x").is_empty())


func _test_units() -> void:
	var open: Array[String] = ["plain plain plain", "plain plain plain", "plain plain plain"]
	var ally: MapWorld = MapWorld.new(open)
	ally.add_unit("p1", PLAYER, Vector2i(0, 1), DEFAULT, 2)
	ally.add_unit("p2", PLAYER, Vector2i(1, 1), DEFAULT, 2, 1)
	var through: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
	_ok(
			"units: an ally passes, even another seat's",
			ally.state.validate_path(ally.engine, "p1", through).is_legal
	)
	var ally_reach: Dictionary[Vector2i, int] = Pathing.reach(ally.engine, ally.state, "p1")
	_ok(
			"units: past an ally, never onto it",
			ally_reach.has(Vector2i(2, 1)) and not ally_reach.has(Vector2i(1, 1))
	)
	var onto: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
	_same(
			"units: an occupied destination is rejected",
			ally.state.validate_path(ally.engine, "p1", onto).reason,
			"ends on a taken tile"
	)

	var enemy: MapWorld = MapWorld.new(open)
	enemy.add_unit("p1", PLAYER, Vector2i(0, 1), DEFAULT, 4)
	enemy.add_unit("e1", ENEMY, Vector2i(1, 1))
	_same(
			"units: an enemy blocks",
			enemy.state.validate_path(enemy.engine, "p1", through).reason,
			"blocked at (1, 1)"
	)
	_same(
			"units: the way round an enemy",
			MapWorld.describe(Pathing.reach(enemy.engine, enemy.state, "p1")),
			"(0, 0)=1 (1, 0)=2 (2, 0)=3 (0, 1)=0 (2, 1)=4 (0, 2)=1 (1, 2)=2 (2, 2)=3"
	)
	_same(
			"units: the enemy's side sees the player as solid",
			MapWorld.describe(Pathing.reach(enemy.engine, enemy.state, "e1")),
			"(0, 0)=2 (1, 0)=1 (2, 0)=2 (1, 1)=0 (2, 1)=1 (0, 2)=2 (1, 2)=1 (2, 2)=2"
	)


func _test_path_checks() -> void:
	var world: MapWorld = MapWorld.new(GOLDEN_ROWS)
	var unit: CombatUnitState = world.add_unit("u", PLAYER, Vector2i(0, 0), DEFAULT, 5)
	var state: CombatState = world.state
	var engine: EffectEngine = world.engine
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]
	var check: CombatGrid.PathCheck = state.validate_path(engine, "u", path)
	_ok(
			"path: legal, with tiles moved and cost",
			check.is_legal and check.reason.is_empty() and check.tiles_moved == 3
			and check.cost == 4,
			"%s %d %d" % [check.reason, check.tiles_moved, check.cost]
	)
	path.append(Vector2i(2, 2))
	_ok("path: the whole budget", state.validate_path(engine, "u", path).cost == 5)
	path.append(Vector2i(3, 2))
	_same("path: over budget", state.validate_path(engine, "u", path).reason, "too far")
	unit.movement_spent = 1
	path.pop_back()
	_same(
			"path: cost spent counts against it",
			state.validate_path(engine, "u", path).reason,
			"too far"
	)
	unit.movement_spent = 0
	var stay: CombatGrid.PathCheck = state.validate_path(engine, "u", [Vector2i(0, 0)])
	_ok("path: staying put", stay.is_legal and stay.tiles_moved == 0 and stay.cost == 0)
	var wade: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]
	_same(
			"path: into a river on foot",
			state.validate_path(engine, "u", wade).reason,
			"blocked at (1, 1)"
	)
	_same(
			"path: a jump",
			state.validate_path(engine, "u", [Vector2i(0, 0), Vector2i(0, 2)]).reason,
			"not a walk of single steps"
	)
	_same(
			"path: not from its tile",
			state.validate_path(engine, "u", [Vector2i(0, 1), Vector2i(0, 2)]).reason,
			"doesn't start on its tile"
	)
	_same("path: empty", state.validate_path(engine, "u", []).reason, "empty path")
	_same(
			"path: nobody",
			state.validate_path(engine, "x", [Vector2i(0, 0)]).reason,
			"not on the map"
	)
	_ok("path: budget is MOVEMENT", Pathing.budget_of(engine, state, "u") == 5)
	unit.movement_spent = 7
	_ok("path: budget never below 0", Pathing.budget_of(engine, state, "u") == 0)
	_quiet(world)


func _test_objects() -> void:
	var world: MapWorld = MapWorld.new(["plain plain plain"])
	world.add_unit("foot", PLAYER, Vector2i(0, 0), DEFAULT, 5)
	var state: CombatState = world.state
	var engine: EffectEngine = world.engine
	var door: Vector2i = Vector2i(1, 0)
	var walk: Array[Vector2i] = [Vector2i(0, 0), door, Vector2i(2, 0)]
	state.map.set_blocking(door, MapState.Blocking.ALL)
	_same(
			"door: closed, blocks",
			state.validate_path(engine, "foot", walk).reason,
			"blocked at (1, 0)"
	)
	_ok("door: nobody stands in it", not state.can_stand(door, FLIER))
	_ok("door: a plain blocker", state.blocker_at(door) == CombatGrid.Blocker.PLAIN)
	_ok("door: the grid stays terrain-only", world.grid.blocker_at(door) == 0)
	state.map.set_blocking(door, MapState.Blocking.NONE)
	_ok("door: opened, passes", state.validate_path(engine, "foot", walk).is_legal)
	_ok("door: open, no blocker", state.blocker_at(door) == CombatGrid.Blocker.NONE)

	var flier_world: MapWorld = MapWorld.new(["plain plain plain"])
	flier_world.add_unit("flier", PLAYER, Vector2i(0, 0), FLIER, 5)
	var fliers: CombatState = flier_world.state
	fliers.map.set_blocking(door, MapState.Blocking.ALL)
	_same(
			"door: blocks fliers too",
			fliers.validate_path(flier_world.engine, "flier", walk).reason,
			"blocked at (1, 0)"
	)
	fliers.map.set_blocking(door, MapState.Blocking.ALL_BUT_FLIERS)
	_ok(
			"debris: a flier crosses it",
			fliers.validate_path(flier_world.engine, "flier", walk).is_legal
			and fliers.can_stand(door, FLIER)
	)
	state.map.set_blocking(door, MapState.Blocking.ALL_BUT_FLIERS)
	_same(
			"debris: blocks a unit on foot",
			state.validate_path(engine, "foot", walk).reason,
			"blocked at (1, 0)"
	)
	_ok("debris: blocking is kept", state.map.blocking_at(door) == 2)
	state.map.set_blocking(door, MapState.Blocking.NONE)
	_ok(
			"debris: broken, the terrain passes again",
			state.validate_path(engine, "foot", walk).is_legal
	)
	_ok("debris: broken, nothing kept", state.map.blocking_at(door) == MapState.Blocking.NONE)
	_quiet(world)


func _test_sandbox_copy() -> void:
	var world: MapWorld = MapWorld.new(["plain plain plain"])
	world.add_unit("foot", PLAYER, Vector2i(0, 0), DEFAULT, 5)
	var door: Vector2i = Vector2i(1, 0)
	world.state.map.set_blocking(door, MapState.Blocking.ALL)
	var copy: CombatState = world.state.copy_for_sandbox()
	_ok("sandbox: the copy has the door", copy.map.blocks(door, DEFAULT))
	_ok("sandbox: its own map state", copy.map != world.state.map)
	_ok("sandbox: the same shared grid", copy.grid == world.grid)
	copy.map.set_blocking(door, MapState.Blocking.NONE)
	_ok("sandbox: opening a door there", not copy.map.blocks(door, DEFAULT))
	_ok("sandbox: leaves the real door shut", world.state.map.blocks(door, DEFAULT))
	var walk: Array[Vector2i] = [Vector2i(0, 0), door, Vector2i(2, 0)]
	_ok("sandbox: the copy walks through", copy.validate_path(world.engine, "foot", walk).is_legal)
	_ok(
			"sandbox: the real map doesn't",
			not world.state.validate_path(world.engine, "foot", walk).is_legal
	)


func _test_nearest_free_tile() -> void:
	var world: MapWorld = MapWorld.new(
			["plain plain plain plain", "plain plain forest plain", "plain plain plain plain"]
	)
	var state: CombatState = world.state
	var origin: Vector2i = Vector2i(1, 1)
	_ok(
			"nearest: a free point is itself",
			Pathing.nearest_free_tile(state, origin, DEFAULT) == origin
	)
	world.add_unit("e1", ENEMY, origin)
	_ok(
			"nearest: the cheapest, ties in direction order (right is forest)",
			Pathing.nearest_free_tile(state, origin, DEFAULT) == Vector2i(1, 2)
	)
	_ok(
			"nearest: a flier pays 1 in the forest",
			Pathing.nearest_free_tile(state, origin, FLIER) == Vector2i(2, 1)
	)
	world.add_unit("p1", PLAYER, Vector2i(1, 2))
	world.add_unit("p2", PLAYER, Vector2i(0, 1))
	world.add_unit("p3", PLAYER, Vector2i(1, 0))
	_ok(
			"nearest: the forest when every plain neighbor is taken",
			Pathing.nearest_free_tile(state, origin, DEFAULT) == Vector2i(2, 1)
	)
	world.add_unit("p4", PLAYER, Vector2i(2, 1), FLIER)
	_ok(
			"nearest: past units of either side",
			Pathing.nearest_free_tile(state, origin, DEFAULT) == Vector2i(2, 2)
	)
	state.map.set_blocking(Vector2i(2, 2), MapState.Blocking.ALL)
	_ok(
			"nearest: never into an object",
			Pathing.nearest_free_tile(state, origin, DEFAULT) == Vector2i(0, 2)
	)
	var single: MapWorld = MapWorld.new(["plain"])
	single.add_unit("e1", ENEMY, Vector2i(0, 0))
	_ok(
			"nearest: none at all",
			Pathing.nearest_free_tile(single.state, Vector2i(0, 0), DEFAULT) == CombatFact.NO_TILE
	)


func _test_resolvers_ask_the_state() -> void:
	var world: MapWorld = MapWorld.new(["plain plain plain plain"])
	world.add_unit("shover", PLAYER, Vector2i(0, 0))
	world.add_unit("target", ENEMY, Vector2i(1, 0))
	world.state.map.set_blocking(Vector2i(2, 0), MapState.Blocking.ALL_BUT_FLIERS)
	var path: ShoveResolver.Path = ShoveResolver.trace(
			world.engine, world.state, "shover", "target"
	)
	_ok(
			"shove: stops at an object",
			path.stop == ShoveResolver.Stop.BLOCKED and path.tiles_moved == 0
	)

	var recall: MapWorld = MapWorld.new(["plain plain river"])
	recall.add_unit("foot", PLAYER, Vector2i(0, 0))
	recall.add_unit("flier", PLAYER, Vector2i(2, 0), FLIER)
	recall.state.rune_slots[0] = PackedStringArray(["rune:1"])
	var reason: String = RuneResolver.recall(
			recall.engine, recall.state, 0, "rune:1", "foot", "flier"
	)
	_same("recall: terrain still counts", reason, "a unit can't stand on the other's tile")
	recall.state.move_unit("flier", Vector2i(1, 0))
	recall.state.map.set_blocking(Vector2i(1, 0), MapState.Blocking.ALL_BUT_FLIERS)
	reason = RuneResolver.recall(recall.engine, recall.state, 0, "rune:1", "foot", "flier")
	_same("recall: so do objects", reason, "a unit can't stand on the other's tile")
	recall.state.map.set_blocking(Vector2i(1, 0), MapState.Blocking.NONE)
	reason = RuneResolver.recall(recall.engine, recall.state, 0, "rune:1", "foot", "flier")
	_ok("recall: with nothing in the way", reason.is_empty(), reason)


# Every scenario ends with no engine diagnostics.
func _quiet(world: MapWorld) -> void:
	_ok("diagnostics: none", world.engine.diagnostics.is_empty(), str(world.engine.diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
