# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     state_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## [DarknessState]'s cases for tests/darkness/run_all.gd: layers after N creeps from one source and
## from two, each wave entering a tile once, Abyss staying Abyss, the Brazier's cap and a later
## douse (plan question 3), a door closing and opening (question 2), a breakable breaking,
## [method CombatState.darkness_layer] and [WhileLayerCondition] in a forecast equal to execution,
## and a timed full recalculation on the 10 × 8 M1 map, printed as NOTE lines.
##
## Layers are written as one digit per tile of row 0, west to east (0 dry, 1 Dusk, 2 Gloom,
## 3 Abyss); golden values are worked by hand from the flow costs in flow_cases.gd.

const DarknessWorld = preload("res://tests/darkness/darkness_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const DEBRIS: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS
const BRAZIER: MapLayout.ObjectKind = MapLayout.ObjectKind.BRAZIER

const CORRIDOR: Array[String] = ["plain plain plain plain plain"]
const LONG_CORRIDOR: Array[String] = ["plain plain plain plain plain plain plain"]

const WEST: Vector2i = Vector2i(0, 0)
const EAST: Vector2i = Vector2i(4, 0)
const FAR_EAST: Vector2i = Vector2i(6, 0)

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# Timed runs of a full recalculation on M1, and the releases before timing: 3 waves per source.
const TIMED_RUNS: int = 200
const TIMED_RELEASES: int = 3

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_one_source()
	_test_two_sources()
	_test_abyss()
	_test_brazier()
	_test_door()
	_test_breakable()
	_test_forecast()
	_test_m1_timing()


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _test_one_source() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR)
	world.set_up([[WEST]], EAST)
	var darkness: DarknessState = world.darkness()
	_ok("one source: not arrived before the first release", not darkness.has_arrived())
	_ok("one source: dry before the first release", world.row_layers(0, 5) == "0 0 0 0 0")
	_deepened("one source: a release enters its own tile",
			darkness.release(world.state()), "(0, 0)>1@0")
	_ok("one source: arrived at the first release", darkness.has_arrived())
	_layers("one source: released", world, 5, "1 0 0 0 0")
	_deepened("one source: creep 1 enters cost 1 and 2, nearest first",
			darkness.creep(world.state()), "(1, 0)>1@0 (2, 0)>1@0")
	darkness.creep(world.state())
	_layers("one source: after 2 creeps", world, 5, "1 1 1 1 1")
	var later: Array[DarknessState.Deepening] = []
	for i: int in 5:
		later.append_array(darkness.creep(world.state()))
	_ok("one source: a wave enters each tile once", later.is_empty(),
			DarknessWorld.describe_deepened(later))
	_ok("one source: a recalculation on an unchanged map enters nothing",
			darkness.recalculate(world.state()).is_empty())
	_layers("one source: after 7 creeps", world, 5, "1 1 1 1 1")
	_ok("one source: reach grows by the creep speed, 2",
			darkness.waves[0].reach == 7 * DarknessState.CREEP_SPEED
			and DarknessState.CREEP_SPEED == 2,
			"reach %d" % [darkness.waves[0].reach])
	darkness.release(world.state())
	darkness.creep(world.state())
	_layers("one source: a second wave deepens what it reaches", world, 5, "2 2 2 1 1")


func _test_two_sources() -> void:
	var world: DarknessWorld = DarknessWorld.new(LONG_CORRIDOR)
	world.set_up([[WEST], [FAR_EAST]], Vector2i(3, 0))
	var darkness: DarknessState = world.darkness()
	_deepened("two sources: each releases, in source order",
			darkness.release(world.state()), "(0, 0)>1@0 (6, 0)>1@1")
	darkness.creep(world.state())
	_layers("two sources: after 1 creep", world, 7, "1 1 1 0 1 1 1")
	_deepened("two sources: two waves meeting at the drain deepen it twice",
			darkness.creep(world.state()), "(3, 0)>1@0 (3, 0)>2@1")
	_layers("two sources: after 2 creeps", world, 7, "1 1 1 2 1 1 1")
	darkness.release(world.state())
	_layers("two sources: a second release", world, 7, "2 1 1 2 1 1 2")
	_deepened("two sources: creep 3, oldest wave first, uphill across the drain",
			darkness.creep(world.state()),
			"(4, 0)>2@0 (2, 0)>2@1 (1, 0)>2@0 (2, 0)>3@0 (5, 0)>2@1 (4, 0)>3@1")
	_layers("two sources: after 3 creeps", world, 7, "2 2 3 2 3 2 2")


func _test_abyss() -> void:
	var world: DarknessWorld = DarknessWorld.new(["plain plain"])
	world.set_up([[WEST]], Vector2i(1, 0))
	var darkness: DarknessState = world.darkness()
	for i: int in 3:
		darkness.release(world.state())
	_ok("abyss: three waves make Abyss",
			darkness.layer_at(WEST) == WhileLayerCondition.Layer.ABYSS)
	var after: Array[DarknessState.Deepening] = darkness.release(world.state())
	after.append_array(darkness.release(world.state()))
	_ok("abyss: further waves deepen nothing", after.is_empty(),
			DarknessWorld.describe_deepened(after))
	darkness.creep(world.state())
	_layers("abyss: five waves cap both tiles at Abyss", world, 2, "3 3")
	_ok("abyss: the maximum layer is 3", DarknessState.MAX_LAYER == 3)


func _test_brazier() -> void:
	var world: DarknessWorld = DarknessWorld.new(LONG_CORRIDOR, [[FAR_EAST, BRAZIER]])
	world.set_up([[WEST]], FAR_EAST)
	world.set_lit(FAR_EAST, true)
	var darkness: DarknessState = world.darkness()
	_flood(world, 3)
	_layers("brazier: lit, the first wave still makes Dusk", world, 7, "1 1 1 1 1 1 1")
	_flood(world, 3)
	_layers("brazier: lit, tiles within 2 stay Dusk; at 3 they deepen", world, 7, "2 2 2 2 1 1 1")
	world.set_lit(FAR_EAST, false)
	var doused: Array[DarknessState.Deepening] = darkness.recalculate(world.state())
	doused.append_array(darkness.creep(world.state()))
	_ok("brazier: dousing deepens nothing by itself; the capped entries are spent",
			doused.is_empty(), DarknessWorld.describe_deepened(doused))
	_flood(world, 3)
	_layers("brazier: doused, only a later wave deepens them", world, 7, "3 3 3 3 2 2 2")
	world.set_lit(FAR_EAST, true)
	_flood(world, 3)
	_layers("brazier: lit again, deeper tiles never fall", world, 7, "3 3 3 3 2 2 2")
	_ok("brazier: within 2 tiles, at Dusk",
			DarknessState.BRAZIER_RADIUS == 2
			and DarknessState.BRAZIER_CAP == WhileLayerCondition.Layer.DUSK)


func _test_door() -> void:
	var door: Vector2i = Vector2i(2, 0)
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR, [[door, DOOR]])
	world.set_up([[WEST]], EAST)
	world.set_door(door, true)
	var darkness: DarknessState = world.darkness()
	_flood(world, 2)
	_layers("door: open, the first wave crosses it", world, 5, "1 1 1 1 1")
	world.set_door(door, false)
	_ok("door: closing it keeps its layer",
			darkness.layer_at(door) == WhileLayerCondition.Layer.DUSK)
	_ok("door: closing it enters nothing", darkness.recalculate(world.state()).is_empty())
	_flood(world, 2)
	_layers("door: closed, a second wave stops at it", world, 5, "2 2 1 1 1")
	world.set_door(door, true)
	_deepened("door: reopened, the second wave enters what it now reaches, the first nothing",
			darkness.recalculate(world.state()), "(2, 0)>2@0 (3, 0)>2@0 (4, 0)>2@0")


func _test_breakable() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR, [[Vector2i(2, 0), DEBRIS]])
	world.set_up([[WEST]], EAST)
	var darkness: DarknessState = world.darkness()
	_flood(world, 2)
	_layers("breakable: unbroken, it holds the wave back", world, 5, "1 1 0 0 0")
	world.erode(Vector2i(2, 0))
	_deepened("breakable: broken, the wave enters the newly reachable tiles",
			darkness.recalculate(world.state()), "(2, 0)>1@0 (3, 0)>1@0 (4, 0)>1@0")


func _test_forecast() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR)
	world.set_up([[WEST]], EAST)
	world.add_unit("p1", PLAYER, WEST)
	world.add_unit("e1", ENEMY, Vector2i(3, 0))
	world.darkness().release(world.state())
	world.darkness().creep(world.state())
	var sandbox: Sandbox = Sandbox.new(world.engine(), ForecastRolls.new())
	var forecast: CombatState = sandbox.engine.state as CombatState
	if forecast == null:
		_ok("forecast: the sandbox holds a CombatState", false)
		return
	var dusk: WhileLayerCondition = WhileLayerCondition.new()
	for unit_id: String in ["p1", "e1"]:
		_ok("forecast: %s's layer equals execution's" % [unit_id],
				forecast.darkness_layer(unit_id) == world.state().darkness_layer(unit_id))
		_ok("forecast: %s's While on Dusk equals execution's" % [unit_id],
				dusk.test(_context(sandbox.engine, unit_id))
				== dusk.test(_context(world.engine(), unit_id)))
	_ok("forecast: a unit on Dusk reads Dusk",
			world.state().darkness_layer("p1") == WhileLayerCondition.Layer.DUSK)
	_ok("forecast: an id not on the map reads dry",
			world.state().darkness_layer("nobody") == WhileLayerCondition.Layer.DRY)
	forecast.map.darkness.creep(forecast)
	_ok("forecast: a creep in the sandbox leaves the real map dry there",
			world.state().darkness_layer("e1") == WhileLayerCondition.Layer.DRY
			and forecast.darkness_layer("e1") == WhileLayerCondition.Layer.DUSK)
	world.darkness().creep(world.state())
	var real_layers: String = world.row_layers(0, 5)
	var forecast_layers: String = _row(forecast.map.darkness, 5)
	_ok("forecast: the same creep executed gives the same layers",
			real_layers == forecast_layers and dusk.test(_context(world.engine(), "e1")),
			"real %s, forecast %s" % [real_layers, forecast_layers])


func _test_m1_timing() -> void:
	var definition: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	var layout: MapLayout = MapLoader.load_layout(definition) if definition != null else null
	if layout == null:
		_ok("m1: the map loads", false)
		return
	var session: CombatSession = CombatSession.new(
			0,
			PackedInt32Array([0]),
			MapGrid.new(layout),
			ForcedRolls.new(PackedInt32Array()),
			InstanceIdAllocator.new()
	)
	MapObjects.place(session)
	var state: CombatState = session.state
	var floodable: Array[Vector2i] = []
	for tile: Vector2i in layout.tiles():
		if DarknessFlow.is_floodable(state, tile):
			floodable.append(tile)
	var rect: Rect2i = layout.get_rect()
	_ok("m1: 10 × 8", rect.size == Vector2i(10, 8), "%s" % [rect.size])
	# No source markers exist yet, so the timing uses the first and last floodable tiles of the
	# first row as sources and the last floodable tile as the drain: a crossing of the whole map.
	var darkness: DarknessState = state.map.darkness
	var source_a: DarknessState.Source = DarknessState.Source.new()
	source_a.tiles = [floodable[0]]
	var source_b: DarknessState.Source = DarknessState.Source.new()
	for tile: Vector2i in floodable:
		if tile.y == floodable[0].y:
			source_b.tiles = [tile]
	darkness.sources = [source_a, source_b]
	darkness.drain = floodable[floodable.size() - 1]
	for i: int in TIMED_RELEASES:
		darkness.release(state)
		darkness.creep(state)
		darkness.creep(state)
	var heights: Dictionary[Vector2i, int] = DarknessFlow.heights(state, darkness.drain)
	_ok("m1: every floodable tile has a height", heights.size() == floodable.size(),
			"%d of %d" % [heights.size(), floodable.size()])
	var samples: Array[int] = []
	var changed: int = 0
	for i: int in TIMED_RUNS:
		var started: int = Time.get_ticks_usec()
		changed += darkness.recalculate(state).size()
		samples.append(Time.get_ticks_usec() - started)
	_ok("m1: a recalculation on an unchanged map enters nothing", changed == 0)
	samples.sort()
	var median: int = samples[floori(samples.size() / 2.0)]
	var p95: int = samples[mini(samples.size() - 1, floori(samples.size() * 0.95))]
	print("NOTE  m1 full recalculation (heights, 2 sources' flow costs, %d waves, %d floodable"
			% [darkness.waves.size(), floodable.size()]
			+ " tiles), measured over %d runs: median %d us, p95 %d us"
			% [TIMED_RUNS, median, p95])


# Releases a wave, then creeps creeps times.
func _flood(world: DarknessWorld, creeps: int) -> void:
	world.darkness().release(world.state())
	for i: int in creeps:
		world.darkness().creep(world.state())


func _context(engine: EffectEngine, unit_id: String) -> EffectContext:
	var ctx: EffectContext = EffectContext.new()
	ctx.engine = engine
	ctx.subject_id = unit_id
	return ctx


func _row(darkness: DarknessState, width: int) -> String:
	var parts: PackedStringArray = []
	for x: int in width:
		parts.append(str(darkness.layer_at(Vector2i(x, 0))))
	return " ".join(parts)


func _layers(case_name: String, world: DarknessWorld, width: int, expected: String) -> void:
	var found: String = world.row_layers(0, width)
	_ok(case_name, found == expected, "got %s" % [found])


func _deepened(
		case_name: String, deepened: Array[DarknessState.Deepening], expected: String
) -> void:
	var described: String = DarknessWorld.describe_deepened(deepened)
	_ok(case_name, described == expected, "got %s" % [described])
