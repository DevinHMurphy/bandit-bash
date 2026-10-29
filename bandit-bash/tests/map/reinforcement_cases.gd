# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reinforcement_cases.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

extends RefCounted
## Reinforcement cases for tests/map/run_all.gd: the point [MapMarker] kind and its arrival turns,
## setup step 5's draw, warnings at the right player Phase Starts with the preview the phase before,
## arrival on a free and on an occupied point, a closed point never sending, closing only at Phase
## End and only while the point can send, no arrivals once the darkness has arrived, Rout cancelling
## pending waves, Survive ending early once its points are closed, and a sandbox copy.
##
## Each battle case runs a real [CombatSession] on a small plain map, its waves drawn by
## [method Reinforcements.draw_waves] through a fixture [Reinforcements.GroupSource] (P05's groups
## don't exist yet) and its hooks added by [method Reinforcements.register]. Enemies Wait, so no
## case depends on a roll. Log lines are compared without their sequence prefix.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const WAIT: UnitTurnCommand.Action = UnitTurnCommand.Action.WAIT
const POINT: MapLayout.MarkerKind = MapLayout.MarkerKind.REINFORCEMENT_POINT
const ROUT: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
const SURVIVE: CombatMapDefinition.Objective = CombatMapDefinition.Objective.SURVIVE

const PLAIN_ROWS: Array[String] = [
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
]

const TILE_SET: TileSet = preload("res://maps/greybox_tile_set.tres")

# Preloaded script used as a type (gdscript.md, Naming): its defeat fixture command.
const ObjectiveCases = preload("res://tests/map/objective_cases.gd")

# The setup stream's seed; the draw case compares two draws, never golden numbers.
const SEED: int = 20261029

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_marker()
	_test_draw()
	_test_warnings()
	_test_arrival_on_free_point()
	_test_arrival_on_occupied_point()
	_test_no_room()
	_test_closed_point()
	_test_closing_needs_phase_end()
	_test_closing_needs_a_live_point()
	_test_darkness()
	_test_rout_cancels()
	_test_survive_closed_points()
	_test_sandbox()


# A point node carries its arrival turns into the layout; ids stay row-major; MapCheck's
# standable-tile rule still reads a node point.
func _test_marker() -> void:
	var root: Node2D = Node2D.new()
	var terrain: TileMapLayer = TileMapLayer.new()
	terrain.name = MapLoader.TERRAIN_LAYER
	terrain.tile_set = TILE_SET
	root.add_child(terrain)
	var plain: Vector2i = _atlas_of(MapLoader.TERRAIN_DATA, "plain")
	var river: Vector2i = _atlas_of(MapLoader.TERRAIN_DATA, "river")
	for y: int in 4:
		for x: int in 6:
			var atlas: Vector2i = river if Vector2i(x, y) == Vector2i(0, 3) else plain
			terrain.set_cell(Vector2i(x, y), 0, atlas)
	root.add_child(_point_node(terrain, Vector2i(1, 2), [2]))
	root.add_child(_point_node(terrain, Vector2i(4, 0), [3, 1]))
	root.add_child(_point_node(terrain, Vector2i(0, 3), []))
	var layout: MapLayout = MapLoader.from_scene(root, "points")
	root.free()
	var parts: PackedStringArray = []
	for marker: MapLayout.Marker in layout.markers_of(POINT):
		parts.append("%s %d %s" % [marker.tile, marker.index, marker.arrival_turns])
	_same("marker: turns as authored, ids row-major", "; ".join(parts), (
			"(4, 0) 0 [3, 1]; (1, 2) 1 [2]; (0, 3) 2 []"
	))
	var failures: PackedStringArray = []
	for failure: MapCheck.Failure in MapCheck.check(CombatMapDefinition.new(), layout):
		if failure.rule == MapCheck.Rule.REINFORCEMENT_POINT:
			failures.append(failure.describe())
	_same("marker: a node point off a standable tile fails the check", "; ".join(failures), (
			"REINFORCEMENT_POINT at (0, 3): point 2: DEFAULT, HEAVY, MOUNTED can't stand here"
	))


# Step 5: a group per arrival turn, turns ascending, an empty group no wave, every wave keeps
# "turn"; the same stream draws the same waves.
func _test_draw() -> void:
	var source: FixtureGroups = FixtureGroups.new({1: ["Bandit"], 3: ["Archer", "Brute"]})
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [3, 2, 1]], [Vector2i(0, 3), [2]]], source
	)
	var drawn: Dictionary = world.session.setup.shared[Objectives.WAVES_KEY]
	var parts: PackedStringArray = []
	for point_key: String in drawn:
		# Untyped: setup results are plain data.
		for wave: Variant in drawn[point_key]:
			var entry: Dictionary = wave
			var types: PackedStringArray = []
			var group: Array = entry[Reinforcements.GROUP_KEY]
			for unit: Variant in group:
				var unit_type: String = (unit as Dictionary)[Reinforcements.UNIT_TYPE_KEY]
				types.append(unit_type)
			parts.append("%s: turn %d %s" % [
				point_key, entry[Reinforcements.TURN_KEY], ", ".join(types),
			])
	# (0, 3) comes first in row-major order, so the point at (5, 3) is point 1.
	_same("draw: turns ascending, an empty group sends no wave", "; ".join(parts), (
			"1: turn 1 Bandit; 1: turn 3 Archer, Brute"
	))
	var again: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [3, 2, 1]], [Vector2i(0, 3), [2]]], source
	)
	_same(
			"draw: the same stream draws the same waves",
			str(again.session.setup.shared),
			str(world.session.setup.shared)
	)
	_ok("draw: two waves loaded at the point", (
			Reinforcements.waves_left(world.state(), 1) == 2
			and Reinforcements.waves_left(world.state(), 0) == 0
	))


# Every player Phase Start warns of each open point's next wave; the phase right before it arrives
# also previews its unit types.
func _test_warnings() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [2, 4]]],
			FixtureGroups.new({2: ["Bandit", "Bandit", "Archer"], 4: ["Brute"]})
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	var seen: Array[String] = []
	world.session.open_battle()
	for turn: int in 5:
		seen.append_array(world.warnings_this_phase())
		world.send(EndTurnCommand.new(0))
	_same_lines("warnings: each player Phase Start, the preview the phase before", seen, [
		"turn 1: REINFORCEMENT_INCOMING point:0 amount 2 tile (5, 3)",
		"turn 2: REINFORCEMENT_INCOMING point:0 amount 1 tile (5, 3) types Bandit, Bandit, Archer",
		"turn 3: REINFORCEMENT_INCOMING point:0 amount 2 tile (5, 3)",
		"turn 4: REINFORCEMENT_INCOMING point:0 amount 1 tile (5, 3) types Brute",
	])
	_ok("warnings: both waves arrived", world.count(CombatFact.Kind.REINFORCEMENT_ARRIVED) == 2)
	_quiet(world)


# A wave arrives after its turn's enemy phase: the first unit on the free point, the next on the
# nearest free tile, each with Block 0 and full Stance, then REINFORCEMENT_ARRIVED.
func _test_arrival_on_free_point() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [1]]], FixtureGroups.new({1: ["Bandit", "Archer"]})
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.session.open_battle()
	var start: int = world.log_size()
	world.send(EndTurnCommand.new(0))
	var arrived: Array[String] = world.lines_of(start, [
		CombatFact.Kind.UNIT_SPAWNED, CombatFact.Kind.REINFORCEMENT_ARRIVED,
	])
	_same_lines("arrival: on the point, then the nearest free tile", arrived, [
		"UNIT_SPAWNED enemy:%d tile (5, 3)" % [world.first_enemy_value()],
		"UNIT_SPAWNED enemy:%d tile (4, 3)" % [world.first_enemy_value() + 1],
		"REINFORCEMENT_ARRIVED point:0 amount 2 tile (5, 3)",
	])
	_ok("arrival: after the enemy Phase End, before the next player Phase Start", (
			world.index_of(CombatFact.Kind.PHASE_END, ENEMY)
			< world.index_of(CombatFact.Kind.REINFORCEMENT_ARRIVED)
			and world.index_of(CombatFact.Kind.REINFORCEMENT_ARRIVED)
			< world.last_player_phase_start()
	))
	_ok("arrival: Block 0 and full Stance", world.all_spawned_fresh())
	_ok("arrival: the point has no wave left", not Reinforcements.is_open(world.state(), 0))
	_quiet(world)


# An occupied point, boxed in by units of either side, still lands the whole wave on the nearest
# free tiles.
func _test_arrival_on_occupied_point() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [1]]], FixtureGroups.new({1: ["Bandit", "Bandit", "Bandit"]})
	)
	world.add_unit("p1", PLAYER, Vector2i(4, 3))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.add_unit("e2", ENEMY, Vector2i(5, 2))
	world.session.open_battle()
	# p1 leaves at the player Phase End only if it moves; it stays, so the point is boxed in.
	world.send(UnitTurnCommand.new(0, "p1", WAIT, ""))
	var taken: Array[Vector2i] = [Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 2)]
	var start: int = world.log_size()
	world.send(EndTurnCommand.new(0))
	var tiles: Array[Vector2i] = world.spawned_tiles(start)
	var is_spread: bool = tiles.size() == 3
	for tile: Vector2i in tiles:
		is_spread = is_spread and not taken.has(tile) and tiles.count(tile) == 1
	_ok("occupied: every unit on its own free tile", is_spread, str(tiles))
	_ok("occupied: nearest first", (
			tiles.size() == 3 and _distance(tiles[0], Vector2i(5, 3)) == 2
	), str(tiles))
	_same_lines("occupied: the wave completes", world.lines_of(start, [
		CombatFact.Kind.REINFORCEMENT_ARRIVED,
	]), ["REINFORCEMENT_ARRIVED point:0 amount 3 tile (5, 3)"])
	_ok("occupied: no wave left", Reinforcements.waves_left(world.state(), 0) == 0)
	_quiet(world)


# With no free tile anywhere, the unit is lost and the wave still completes.
func _test_no_room() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(1, 0), [1]]], FixtureGroups.new({1: ["Bandit"]}), ["plain plain"]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(1, 0))
	world.session.open_battle()
	var start: int = world.log_size()
	world.send(EndTurnCommand.new(0))
	_same_lines("no room: nothing placed, the wave arrives empty", world.lines_of(start, [
		CombatFact.Kind.UNIT_SPAWNED, CombatFact.Kind.REINFORCEMENT_ARRIVED,
	]), ["REINFORCEMENT_ARRIVED point:0 tile (1, 0)"])
	_same(
			"no room: reported",
			str(world.session.engine.diagnostics),
			str(["Reinforcements: no free tile for Bandit at point:0 (Reinforcement Point)"])
	)


# A player unit ending its turn on an open point closes it for good: one fact, no warning and no
# arrival afterwards.
func _test_closed_point() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(1, 0), [2]]], FixtureGroups.new({2: ["Bandit"]})
	)
	world.add_unit("p1", PLAYER, Vector2i(1, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	var start: int = world.log_size()
	for turn: int in 3:
		world.send(EndTurnCommand.new(0))
	_same_lines("closed: closed at the first player Phase End", world.lines_of(start, [
		CombatFact.Kind.OBJECT_STATE_CHANGED,
		CombatFact.Kind.REINFORCEMENT_INCOMING,
		CombatFact.Kind.REINFORCEMENT_ARRIVED,
	]), ["OBJECT_STATE_CHANGED point:0 -> p1 change %d tile (1, 0)" % [
		MapObjects.Change.POINT_CLOSED,
	]])
	_ok("closed: never sends", (
			world.count(CombatFact.Kind.UNIT_SPAWNED) == 2
			and Reinforcements.waves_left(world.state(), 0) == 0
			and world.state().map.points[0].is_closed
	))
	_quiet(world)


# A unit's action on the point doesn't close it; its side's Phase End does. An enemy's Phase End
# on the point closes nothing.
func _test_closing_needs_phase_end() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(1, 0), [3]], [Vector2i(5, 3), [3]]], FixtureGroups.new({3: ["Bandit"]})
	)
	world.add_unit("p1", PLAYER, Vector2i(1, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	world.send(UnitTurnCommand.new(0, "p1", WAIT, ""))
	_ok("phase end: not closed by the action", Reinforcements.is_open(world.state(), 0))
	world.send(EndTurnCommand.new(0))
	_ok("phase end: closed by the player Phase End", (
			not Reinforcements.is_open(world.state(), 0)
	))
	_ok("phase end: an enemy on a point closes nothing", Reinforcements.is_open(world.state(), 1))
	_quiet(world)


# Only a point that can still send can be closed: not one with no waves, nor one the darkness
# stopped.
func _test_closing_needs_a_live_point() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(1, 0), [2]], [Vector2i(3, 0), [2]]], FixtureGroups.new({})
	)
	world.add_unit("p1", PLAYER, Vector2i(1, 0))
	world.session.open_battle()
	world.send(EndTurnCommand.new(0))
	_ok("live point: no waves, no closing", (
			world.count(CombatFact.Kind.OBJECT_STATE_CHANGED) == 0
			and not world.state().map.points[0].is_closed
	))

	var dark: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(1, 0), [2]]], FixtureGroups.new({2: ["Bandit"]})
	)
	dark.add_unit("p1", PLAYER, Vector2i(1, 0))
	dark.state().map.has_darkness_arrived = true
	dark.session.open_battle()
	dark.send(EndTurnCommand.new(0))
	_ok("live point: the darkness stopped it, no closing", (
			dark.count(CombatFact.Kind.OBJECT_STATE_CHANGED) == 0
	))


# Once the darkness query says it has arrived, no point warns or sends again.
func _test_darkness() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [2, 3]]], FixtureGroups.new({2: ["Bandit"], 3: ["Brute"]})
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.session.open_battle()
	_ok("darkness: a warning before it arrives", (
			world.count(CombatFact.Kind.REINFORCEMENT_INCOMING) == 1
	))
	world.state().map.has_darkness_arrived = true
	_ok("darkness: the query answers", Reinforcements.has_darkness_arrived(world.state()))
	var start: int = world.log_size()
	for turn: int in 3:
		world.send(EndTurnCommand.new(0))
	_same_lines("darkness: no warning and no arrival", world.lines_of(start, [
		CombatFact.Kind.REINFORCEMENT_INCOMING,
		CombatFact.Kind.REINFORCEMENT_ARRIVED,
		CombatFact.Kind.UNIT_SPAWNED,
	]), [])
	_ok("darkness: no wave left", Reinforcements.waves_left(world.state(), 0) == 0)
	_quiet(world)


# Rout's win cancels the waves still to come.
func _test_rout_cancels() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [2]]], FixtureGroups.new({2: ["Bandit"]}), PLAIN_ROWS, ROUT
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.session.open_battle()
	_ok("rout: a wave to come", Objectives.waves_left(world.session, 0) == 1)
	var defeated: Array[String] = ["e1"]
	world.send(ObjectiveCases.DefeatFixture.new(defeated, "p1"))
	_ok("rout: won", world.session.is_won)
	_ok("rout: the waves are cancelled", (
			world.state().map.are_waves_cancelled
			and Objectives.waves_left(world.session, 0) == 0
			and world.count(CombatFact.Kind.REINFORCEMENT_ARRIVED) == 0
	))
	_quiet(world)


# Survive ends early in the step a player closes the last open point with no enemy left.
func _test_survive_closed_points() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(1, 0), [5]]], FixtureGroups.new({5: ["Bandit"]}), PLAIN_ROWS, SURVIVE, 9
	)
	world.add_unit("p1", PLAYER, Vector2i(1, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.session.open_battle()
	var defeated: Array[String] = ["e1"]
	world.send(ObjectiveCases.DefeatFixture.new(defeated, "p1"))
	_ok("survive: an open point keeps it going", not world.session.is_finished)
	world.send(EndTurnCommand.new(0))
	var ended: CombatFact = world.last_of(CombatFact.Kind.COMBAT_ENDED)
	_ok("survive: closing the point ends it at that Phase End", (
			world.session.is_won and ended != null and ended.amount == 1 and ended.key == 9
			and world.count(CombatFact.Kind.PHASE_START) == 1
	), "" if ended == null else ended.to_log_line())
	_quiet(world)


# A sandbox copy of the map state shares no point or wave with the real one.
func _test_sandbox() -> void:
	var world: ReinforcementWorld = ReinforcementWorld.new(
			[[Vector2i(5, 3), [2]]], FixtureGroups.new({2: ["Bandit"]})
	)
	var copy: MapState = world.state().map.copy()
	copy.points[0].is_closed = true
	copy.points[0].sent = 1
	copy.points[0].waves[0][Reinforcements.TURN_KEY] = 9
	copy.has_darkness_arrived = true
	var real: MapState.PointState = world.state().map.points[0]
	var real_turn: int = real.waves[0][Reinforcements.TURN_KEY]
	_ok("sandbox: the real points are unchanged", (
			not real.is_closed and real.sent == 0
			and real_turn == 2
			and not world.state().map.has_darkness_arrived
	))


func _point_node(terrain: TileMapLayer, tile: Vector2i, turns: Array[int]) -> MapMarker:
	var node: MapMarker = MapMarker.new()
	node.kind = MapMarker.Kind.REINFORCEMENT_POINT
	node.arrival_turns = turns
	node.position = terrain.map_to_local(tile)
	return node


func _atlas_of(data_name: String, value: String) -> Vector2i:
	var source: TileSetAtlasSource = TILE_SET.get_source(0) as TileSetAtlasSource
	for i: int in source.get_tiles_count():
		var coords: Vector2i = source.get_tile_id(i)
		if source.get_tile_data(coords, 0).get_custom_data(data_name) == value:
			return coords
	return Vector2i(-1, -1)


func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _quiet(world: ReinforcementWorld) -> void:
	var diagnostics: PackedStringArray = world.session.engine.diagnostics
	_ok("diagnostics: none", diagnostics.is_empty(), str(diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])


func _same_lines(case_name: String, actual: Array[String], expected: Array[String]) -> void:
	_check.call(case_name, actual == expected, "got\n      " + "\n      ".join(actual))


## Fixture groups: the unit types of each turn's wave, the same at every point, plus one draw
## from the stream per unit so the draw depends on it.
class FixtureGroups:
	extends Reinforcements.GroupSource

	var _types_by_turn: Dictionary = {}

	# [param types_by_turn]: arrival turn to an Array of unit type names; no entry draws no wave.
	func _init(types_by_turn: Dictionary) -> void:
		_types_by_turn = types_by_turn

	func draw_group(stream: RngStream, _point: MapLayout.Marker, turn: int) -> Array[Dictionary]:
		var group: Array[Dictionary] = []
		var types: Array = _types_by_turn.get(turn, [])
		# Untyped: the fixture's lists are array literals.
		for unit_type: Variant in types:
			group.append({
				# A plain String from the fixture's literal.
				Reinforcements.UNIT_TYPE_KEY: unit_type,
				"roll": stream.pick_index(100),
			})
		return group

	func build(
			_session: CombatSession, entry: Dictionary, unit_id: String
	) -> Reinforcements.Recruit:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = unit_id
		unit.side = CombatFact.CombatSide.ENEMY
		unit.seat = -1
		unit.unit_type = entry.get(Reinforcements.UNIT_TYPE_KEY, "")
		unit.hp = 20
		var recruit: Reinforcements.Recruit = Reinforcements.Recruit.new()
		recruit.unit = unit
		recruit.bases = {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
		}
		return recruit


## A session on a small map with reinforcement points, its waves drawn through a fixture source and
## its reinforcement hooks registered; [Objectives] too when a case names an objective.
class ReinforcementWorld:
	extends RefCounted

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = null

	# The allocator's next value before any arrival, so a case can name the arrivals' ids.
	var _first_enemy_value: int = 0

	# [param points]: [tile, arrival turns] each. [param objective]: registers Objectives with it
	# unless -1.
	func _init(
			points: Array,
			source: Reinforcements.GroupSource,
			rows: Array[String] = PLAIN_ROWS,
			objective: int = -1,
			survive_turns: int = 0
	) -> void:
		var layout: MapLayout = MapLayout.new()
		layout.map_id = "reinforcements"
		var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
				MapLoader.load_terrain("plain")
		)
		for y: int in rows.size():
			for x: int in rows[y].split(" ", false).size():
				layout.set_terrain(Vector2i(x, y), plain)
		# Untyped: each point is an array literal.
		for point: Variant in points:
			var entry: Array = point
			var marker: MapLayout.Marker = layout.add_marker(POINT, entry[0] as Vector2i)
			var turns: Array = entry[1]
			marker.arrival_turns = PackedInt32Array(turns)
		layout.index_markers()
		var definition: CombatMapDefinition = CombatMapDefinition.new()
		definition.id = "reinforcements"
		if objective >= 0:
			definition.objective = objective as CombatMapDefinition.Objective
		definition.survive_turns = survive_turns
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(SEED))
		session = CombatSession.new(0, PackedInt32Array([0]), MapGrid.new(layout), rolls, ids)
		session.engine.verify = true
		session.setup = CombatEncounter.EncounterSetup.new()
		session.setup.map = definition
		session.setup.layout = layout
		var ctx: CombatEncounter.SetupContext = CombatEncounter.SetupContext.new(
				session.setup, -1, null, RngStream.new(SEED), null
		)
		ctx.step = CombatEncounter.SetupStep.REINFORCEMENT_WAVES
		Reinforcements.draw_waves(ctx, source)
		if objective >= 0:
			Objectives.register(session)
		Reinforcements.register(session, source)
		_first_enemy_value = ids.get_next_value()

	func state() -> CombatState:
		return session.state

	# Places a unit: HP 20, Stance 2, 5 movement. Player units are seat 0's.
	func add_unit(id: String, side: CombatFact.CombatSide, tile: Vector2i) -> void:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = 0 if side == CombatFact.CombatSide.PLAYER else -1
		unit.tile = tile
		unit.hp = 20
		session.add_unit(unit, {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
		})

	func send(command: Command) -> CombatSession.FactBatch:
		session.submit(command)
		return session.resolve_next()

	func log_size() -> int:
		return session.engine.fact_log.size()

	func first_enemy_value() -> int:
		return _first_enemy_value

	# The REINFORCEMENT_INCOMING lines since the latest player Phase Start, each prefixed with its
	# turn.
	func warnings_this_phase() -> Array[String]:
		var found: Array[String] = []
		for i: int in range(last_player_phase_start(), log_size()):
			var fact: CombatFact = session.engine.fact_log[i]
			if fact.kind == CombatFact.Kind.REINFORCEMENT_INCOMING:
				found.append("turn %d: %s" % [state().turn, _bare(fact)])
		return found

	# Lines of the given kinds from [param start], without their "sN#M " prefix.
	func lines_of(start: int, kinds: Array) -> Array[String]:
		var found: Array[String] = []
		for i: int in range(start, log_size()):
			var fact: CombatFact = session.engine.fact_log[i]
			if kinds.has(fact.kind):
				found.append(_bare(fact))
		return found

	func count(kind: CombatFact.Kind) -> int:
		var found: int = 0
		for fact: CombatFact in session.engine.fact_log:
			if fact.kind == kind:
				found += 1
		return found

	func last_of(kind: CombatFact.Kind) -> CombatFact:
		for i: int in range(log_size() - 1, -1, -1):
			if session.engine.fact_log[i].kind == kind:
				return session.engine.fact_log[i]
		return null

	# The index of the first fact of [param kind] (and [param side], when given); -1 for none.
	func index_of(
			kind: CombatFact.Kind, side: CombatFact.CombatSide = CombatFact.CombatSide.NONE
	) -> int:
		for i: int in log_size():
			var fact: CombatFact = session.engine.fact_log[i]
			if fact.kind == kind and (side == CombatFact.CombatSide.NONE or fact.side == side):
				return i
		return -1

	func last_player_phase_start() -> int:
		for i: int in range(log_size() - 1, -1, -1):
			var fact: CombatFact = session.engine.fact_log[i]
			if fact.kind == CombatFact.Kind.PHASE_START and fact.side == PLAYER:
				return i
		return -1

	# The tiles of the units spawned since [param start], in order.
	func spawned_tiles(start: int) -> Array[Vector2i]:
		var tiles: Array[Vector2i] = []
		for i: int in range(start, log_size()):
			var fact: CombatFact = session.engine.fact_log[i]
			if fact.kind == CombatFact.Kind.UNIT_SPAWNED:
				tiles.append(fact.tile)
		return tiles

	# Whether every enemy that arrived has Block 0 and its full Stance (2).
	func all_spawned_fresh() -> bool:
		var any: bool = false
		for fact: CombatFact in session.engine.fact_log:
			if fact.kind != CombatFact.Kind.UNIT_SPAWNED or state().side_of(fact.actor_id) != ENEMY:
				continue
			var unit: CombatUnitState = state().unit(fact.actor_id)
			any = true
			if unit.block != 0 or unit.stance != 2:
				return false
		return any

	func _bare(fact: CombatFact) -> String:
		var line: String = fact.to_log_line()
		return line.substr(line.find(" ") + 1)
