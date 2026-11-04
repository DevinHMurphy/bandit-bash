# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     flow_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## [DarknessFlow]'s cases for tests/darkness/run_all.gd: which tiles are floodable (walls, doors,
## breakables, units, off the map), and golden heights and flow costs on fixture maps (a corridor
## both ways, a side room behind walls, a closed and an opened door, a breakable before and after
## it breaks, tiles with no height, a source of two tiles, no drain).
##
## Golden values are worked by hand from the-darkness.md's rules: height is the 4-directional
## walking distance to the drain; steps cost 1 downhill, 2 level (or either tile without height),
## 3 uphill.

const DarknessWorld = preload("res://tests/darkness/darkness_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const DEBRIS: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS

# 5 × 1 of plain; the drain is its east end in most cases.
const CORRIDOR: Array[String] = ["plain plain plain plain plain"]

# The corridor with a one-tile side room two deep below its middle, walled on both sides.
const SIDE_ROOM: Array[String] = [
	"plain plain plain plain plain",
	"wall wall plain wall wall",
	"wall wall plain wall wall",
]

const WEST: Vector2i = Vector2i(0, 0)
const EAST: Vector2i = Vector2i(4, 0)

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_floodable()
	_test_corridor()
	_test_side_room()
	_test_door()
	_test_breakable()
	_test_no_height()
	_test_step_cost()


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _test_floodable() -> void:
	var world: DarknessWorld = DarknessWorld.new(
			["plain plain plain wall plain"], [[Vector2i(1, 0), DOOR], [Vector2i(2, 0), DEBRIS]]
	)
	var state: CombatState = world.state()
	_ok("floodable: plain ground", DarknessFlow.is_floodable(state, WEST))
	_ok("floodable: a wall blocks (fliers stand on it)",
			not DarknessFlow.is_floodable(state, Vector2i(3, 0)))
	_ok("floodable: off the map blocks", not DarknessFlow.is_floodable(state, Vector2i(5, 0)))
	_ok("floodable: a closed door blocks", not DarknessFlow.is_floodable(state, Vector2i(1, 0)))
	world.set_door(Vector2i(1, 0), true)
	_ok("floodable: an open door is floor", DarknessFlow.is_floodable(state, Vector2i(1, 0)))
	_ok("floodable: an unbroken breakable blocks",
			not DarknessFlow.is_floodable(state, Vector2i(2, 0)))
	_ok("floodable: the breakable breaks", world.erode(Vector2i(2, 0)))
	_ok("floodable: a broken breakable is floor", DarknessFlow.is_floodable(state, Vector2i(2, 0)))
	_ok("floodable: a unit never blocks",
			world.add_unit("p1", PLAYER, WEST) and DarknessFlow.is_floodable(state, WEST))


func _test_corridor() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR)
	world.add_unit("p1", PLAYER, Vector2i(2, 0))
	var heights: Dictionary[Vector2i, int] = DarknessFlow.heights(world.state(), EAST)
	_expect("corridor: heights fall toward the drain, a unit changing nothing", heights,
			"(0, 0)=4 (1, 0)=3 (2, 0)=2 (3, 0)=1 (4, 0)=0")
	_expect("corridor: downhill from the far end costs 1 a step",
			DarknessFlow.flow_costs(world.state(), [WEST], heights),
			"(0, 0)=0 (1, 0)=1 (2, 0)=2 (3, 0)=3 (4, 0)=4")
	_expect("corridor: uphill from the drain costs 3 a step",
			DarknessFlow.flow_costs(world.state(), [EAST], heights),
			"(0, 0)=12 (1, 0)=9 (2, 0)=6 (3, 0)=3 (4, 0)=0")
	_expect("corridor: a source of two tiles takes the cheaper of them",
			DarknessFlow.flow_costs(world.state(), [WEST, EAST], heights),
			"(0, 0)=0 (1, 0)=1 (2, 0)=2 (3, 0)=3 (4, 0)=0")


func _test_side_room() -> void:
	var world: DarknessWorld = DarknessWorld.new(SIDE_ROOM)
	var heights: Dictionary[Vector2i, int] = DarknessFlow.heights(world.state(), EAST)
	_expect("side room: walls have no height, the room climbs away from the drain", heights,
			"(0, 0)=4 (1, 0)=3 (2, 0)=2 (3, 0)=1 (4, 0)=0 (2, 1)=3 (2, 2)=4")
	_expect("side room: the main path is cheap, the room uphill and dearer",
			DarknessFlow.flow_costs(world.state(), [WEST], heights),
			"(0, 0)=0 (1, 0)=1 (2, 0)=2 (3, 0)=3 (4, 0)=4 (2, 1)=5 (2, 2)=8")
	_expect("side room: a wall as a source tile is skipped",
			DarknessFlow.flow_costs(world.state(), [Vector2i(0, 1), WEST], heights),
			"(0, 0)=0 (1, 0)=1 (2, 0)=2 (3, 0)=3 (4, 0)=4 (2, 1)=5 (2, 2)=8")
	var wall_drain: Dictionary[Vector2i, int] = DarknessFlow.heights(world.state(), Vector2i(0, 1))
	_ok("side room: a drain on a wall gives no heights", wall_drain.is_empty())


func _test_door() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR, [[Vector2i(3, 0), DOOR]])
	var heights: Dictionary[Vector2i, int] = DarknessFlow.heights(world.state(), EAST)
	_expect("closed door: only the drain's side has heights", heights, "(4, 0)=0")
	_expect("closed door: flow stops at it, level 2 a step without heights",
			DarknessFlow.flow_costs(world.state(), [WEST], heights),
			"(0, 0)=0 (1, 0)=2 (2, 0)=4")
	world.set_door(Vector2i(3, 0), true)
	heights = DarknessFlow.heights(world.state(), EAST)
	_expect("opened door: heights run through it", heights,
			"(0, 0)=4 (1, 0)=3 (2, 0)=2 (3, 0)=1 (4, 0)=0")
	_expect("opened door: flow runs downhill through it",
			DarknessFlow.flow_costs(world.state(), [WEST], heights),
			"(0, 0)=0 (1, 0)=1 (2, 0)=2 (3, 0)=3 (4, 0)=4")


func _test_breakable() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR, [[Vector2i(2, 0), DEBRIS]])
	var heights: Dictionary[Vector2i, int] = DarknessFlow.heights(world.state(), EAST)
	_expect("breakable: unbroken, it walls off the drain", heights, "(3, 0)=1 (4, 0)=0")
	_expect("breakable: unbroken, flow stops at it",
			DarknessFlow.flow_costs(world.state(), [WEST], heights), "(0, 0)=0 (1, 0)=2")
	world.erode(Vector2i(2, 0))
	heights = DarknessFlow.heights(world.state(), EAST)
	_expect("breakable: broken, heights run through it", heights,
			"(0, 0)=4 (1, 0)=3 (2, 0)=2 (3, 0)=1 (4, 0)=0")
	_expect("breakable: broken, flow runs through it",
			DarknessFlow.flow_costs(world.state(), [WEST], heights),
			"(0, 0)=0 (1, 0)=1 (2, 0)=2 (3, 0)=3 (4, 0)=4")


func _test_no_height() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR)
	var none: Dictionary[Vector2i, int] = DarknessFlow.heights(world.state(), CombatFact.NO_TILE)
	_ok("no drain: no heights", none.is_empty())
	_expect("no drain: every step is level",
			DarknessFlow.flow_costs(world.state(), [WEST], none),
			"(0, 0)=0 (1, 0)=2 (2, 0)=4 (3, 0)=6 (4, 0)=8")
	var walled: DarknessWorld = DarknessWorld.new(["plain plain wall plain plain"])
	var heights: Dictionary[Vector2i, int] = DarknessFlow.heights(walled.state(), EAST)
	_expect("no height: a pocket the drain can't reach has none", heights, "(3, 0)=1 (4, 0)=0")
	_expect("no height: flow inside the pocket is level",
			DarknessFlow.flow_costs(walled.state(), [WEST], heights), "(0, 0)=0 (1, 0)=2")


func _test_step_cost() -> void:
	var heights: Dictionary[Vector2i, int] = {WEST: 2, Vector2i(1, 0): 1, Vector2i(0, 1): 2}
	_ok("step: downhill is 1",
			DarknessFlow.step_cost(heights, WEST, Vector2i(1, 0)) == DarknessFlow.STEP_DOWNHILL)
	_ok("step: uphill is 3",
			DarknessFlow.step_cost(heights, Vector2i(1, 0), WEST) == DarknessFlow.STEP_UPHILL)
	_ok("step: the same height is level, 2",
			DarknessFlow.step_cost(heights, WEST, Vector2i(0, 1)) == DarknessFlow.STEP_LEVEL)
	_ok("step: into a tile without height is level",
			DarknessFlow.step_cost(heights, WEST, Vector2i(9, 9)) == DarknessFlow.STEP_LEVEL)
	_ok("step: out of a tile without height is level",
			DarknessFlow.step_cost(heights, Vector2i(9, 9), WEST) == DarknessFlow.STEP_LEVEL)
	_ok("step: the values are the-darkness.md's 1 / 2 / 3",
			DarknessFlow.STEP_DOWNHILL == 1
			and DarknessFlow.STEP_LEVEL == 2
			and DarknessFlow.STEP_UPHILL == 3)


func _expect(case_name: String, found: Dictionary[Vector2i, int], expected: String) -> void:
	var described: String = DarknessWorld.describe(found)
	_ok(case_name, described == expected, "got %s" % [described])
