# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     m1_cases.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

extends RefCounted
## The M1 map cases for tests/map/run_all.gd: the greybox map's definition and layout, cover for
## both sides, [MapMarker] nodes read into the layout with stable ids, and a smoke test that opens
## a battle on the map headless. Reports each case through the check callable it is given.
##
## The smoke test runs the real path: a [CombatEncounter] draws the map from a pool of one through
## [MapLoader], opens a session, places fixture enemies on every enemy slot and the leader slot,
## deploys a four-unit army automatically and opens the battle. It fights nothing.

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ENEMY_SLOT: MapLayout.MarkerKind = MapLayout.MarkerKind.ENEMY_SLOT

# Any fixed run seed and combat node: the smoke test compares nothing with golden numbers.
const RUN_SEED: int = 0x5EED_0001
const FLOOR: int = 1
const NODE: int = 1

# Plain's avoid: a tile with more is cover.
const PLAIN_AVOID: int = 5

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	var definition: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	_ok("m1: the definition loads", definition != null)
	if definition == null:
		return
	_test_definition(definition)
	_test_layout(definition)
	_test_cover(definition)
	_test_marker_nodes_stable(definition)
	_test_marker_node_placement(definition)
	_test_marker_nodes_keep_ids()
	_test_battle_opens(definition)


func _test_definition(definition: CombatMapDefinition) -> void:
	_ok("m1: id and scene", definition.id == "m1_greybox" and definition.scene != null)
	_ok("m1: a standard map in the default pool", (
			definition.combat_type == CombatMapDefinition.CombatType.STANDARD
			and definition.pool.is_empty()
	))
	_ok("m1: Rout", definition.objective == CombatMapDefinition.Objective.ROUT)
	_same("m1: turn par", str(definition.turn_par), "5")


func _test_layout(definition: CombatMapDefinition) -> void:
	var layout: MapLayout = MapLoader.load_layout(definition)
	if layout == null:
		_ok("m1 layout: loads", false)
		return
	_ok("m1 layout: no problems", layout.problems.is_empty(), str(layout.problems))
	_ok("m1 layout: 10 × 8", layout.get_rect() == Rect2i(0, 0, 10, 8), str(layout.get_rect()))
	_ok("m1 layout: every tile has terrain", layout.tiles().size() == 80)
	_same(
			"m1 layout: 8 deployment tiles",
			str(layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT).size()),
			"8"
	)
	_ok(
			"m1 layout: the leader slot",
			layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT) == [Vector2i(9, 1)]
	)
	_same(
			"m1 layout: enemy slots from marker nodes, row-major",
			_describe_slots(layout),
			"(6, 1) 2 A; (8, 2) 2 A; (6, 4) 2 B; (7, 6) 2 B"
	)


# Terrain is the only source of avoid, so each side needs a tile better than Plain at hand.
func _test_cover(definition: CombatMapDefinition) -> void:
	var layout: MapLayout = MapLoader.load_layout(definition)
	if layout == null:
		_ok("m1 cover: loads", false)
		return
	var enemy_tiles: Array[Vector2i] = layout.tiles_of(ENEMY_SLOT)
	enemy_tiles.append_array(layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT))
	var uncovered: Array[Vector2i] = []
	for tile: Vector2i in enemy_tiles:
		if not _has_cover_near(layout, tile):
			uncovered.append(tile)
	_ok("m1 cover: next to every enemy start", uncovered.is_empty(), str(uncovered))
	var covered: int = 0
	for tile: Vector2i in layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT):
		if _has_cover_near(layout, tile):
			covered += 1
	_ok("m1 cover: next to the deployment zone", covered >= 4, "%d tiles" % [covered])


func _test_marker_nodes_stable(definition: CombatMapDefinition) -> void:
	var first: MapLayout = MapLoader.load_layout(definition)
	var second: MapLayout = MapLoader.load_layout(definition)
	if first == null or second == null:
		_ok("marker nodes: loads", false)
		return
	_same("marker nodes: the same on two loads", _describe(second), _describe(first))

	var root: Node = definition.scene.instantiate()
	var slots: Node = root.get_node(^"EnemySlots")
	for i: int in slots.get_child_count():
		slots.move_child(slots.get_child(slots.get_child_count() - 1), i)
	var reversed: MapLayout = MapLoader.from_scene(root, definition.id)
	root.free()
	_same(
			"marker nodes: independent of node order",
			_describe(reversed),
			_describe(first)
	)


func _test_marker_node_placement(definition: CombatMapDefinition) -> void:
	var root: Node = definition.scene.instantiate()
	var terrain: TileMapLayer = root.get_node(^"Terrain") as TileMapLayer
	var slots: Node2D = root.get_node(^"EnemySlots") as Node2D
	var tile_size: Vector2 = Vector2(terrain.tile_set.tile_size)

	var corner: MapMarker = _marker_node("Corner", terrain, Vector2i(2, 1))
	corner.position += tile_size * 0.4
	slots.add_child(corner)
	var shared: MapMarker = _marker_node("OnDeployment", terrain, Vector2i(0, 4))
	slots.add_child(shared)
	var off_map: MapMarker = _marker_node("OffMap", terrain, Vector2i(12, 3))
	slots.add_child(off_map)
	var layout: MapLayout = MapLoader.from_scene(root, definition.id)

	_ok(
			"marker nodes: an unsnapped node reads the cell under it",
			layout.tiles_of(ENEMY_SLOT).has(Vector2i(2, 1))
	)
	var on_tile: PackedStringArray = []
	for marker: MapLayout.Marker in layout.markers:
		if marker.tile == Vector2i(0, 4):
			on_tile.append(MapLayout.MarkerKind.find_key(marker.kind) as String)
	_ok(
			"marker nodes: a node and a layer marker on one tile, by kind",
			on_tile == PackedStringArray(["DEPLOYMENT", "ENEMY_SLOT"]),
			str(on_tile)
	)
	_ok(
			"marker nodes: off the map is a problem",
			layout.problems == PackedStringArray(["marker node OffMap off the map at (12, 3)"]),
			str(layout.problems)
	)

	slots.position = tile_size * Vector2(-1.0, 1.0)
	var shifted: MapLayout = MapLoader.from_scene(root, definition.id)
	root.free()
	_ok(
			"marker nodes: a moved parent moves the tile",
			shifted.tiles_of(ENEMY_SLOT).has(Vector2i(5, 2)),
			str(shifted.tiles_of(ENEMY_SLOT))
	)


# Marker nodes join the fixed order without renumbering the object spots and points around them.
func _test_marker_nodes_keep_ids() -> void:
	var plain_root: Node = FIXTURE_SCENE.instantiate()
	var without: MapLayout = MapLoader.from_scene(plain_root, "fixture")
	plain_root.free()
	var root: Node = FIXTURE_SCENE.instantiate()
	var terrain: TileMapLayer = root.get_node(^"Terrain") as TileMapLayer
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(4, 2)]:
		root.add_child(_marker_node("Slot", terrain, tile))
	var with_nodes: MapLayout = MapLoader.from_scene(root, "fixture")
	root.free()
	_same(
			"marker nodes: object and point ids unchanged",
			_describe_ids(with_nodes),
			_describe_ids(without)
	)
	_same(
			"marker nodes: three more markers",
			str(with_nodes.markers.size() - without.markers.size()),
			"3"
	)


func _test_battle_opens(definition: CombatMapDefinition) -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var encounter: CombatEncounter = CombatEncounter.new(
			FLOOR, NODE, PackedInt32Array([0]), ids
	)
	var pool: Array[CombatMapDefinition] = [definition]
	var setup_error: Error = encounter.run_setup(
			pool, CombatEncounter.SetupStreams.new(RUN_SEED, FLOOR, NODE)
	)
	_ok("battle: setup loads the map", (
			setup_error == OK
			and encounter.setup.map == definition
			and encounter.setup.layout.map_id == "m1_greybox"
	), error_string(setup_error))
	if setup_error != OK:
		return
	var rolls: Dictionary[int, RngStream] = {
		0: RngStreams.new(RUN_SEED).stream(
				RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, FLOOR, NODE, 0, -1)
		),
	}
	_ok("battle: a session opens", encounter.open_sessions(rolls))
	var session: CombatSession = encounter.get_session(0)
	if session == null:
		return

	var starts: Array[Vector2i] = session.layout.tiles_of(ENEMY_SLOT)
	starts.append_array(session.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT))
	var placed: int = 0
	for tile: Vector2i in starts:
		var enemy: CombatUnitState = CombatUnitState.new()
		enemy.id = ids.next_enemy_id("Brute")
		enemy.side = ENEMY
		enemy.seat = -1
		enemy.tile = tile
		enemy.unit_type = "Brute"
		enemy.hp = 20
		if session.add_unit(enemy, _bases()):
			placed += 1
	_ok("battle: a fixture enemy in every slot", placed == 5, "%d placed" % [placed])

	var army: Array[CombatUnitState] = []
	var bases: Dictionary[String, Dictionary] = {}
	for unit_type: String in ["Drengr", "Archer", "Hakkapel", "Battle Medic"]:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = ids.next_unit_id(unit_type)
		unit.side = PLAYER
		unit.seat = 0
		unit.unit_type = unit_type
		unit.hp = 20
		army.append(unit)
		bases[unit.id] = _bases()
	var placement: AutoDeploy.Placement = session.deploy(army, bases, army[0].id)
	var deployment: Array[Vector2i] = session.layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT)
	var on_deployment: bool = placement.unplaced.is_empty()
	for unit: CombatUnitState in army:
		on_deployment = on_deployment and deployment.has(session.state.tile_of(unit.id))
	_ok("battle: the army deploys on deployment tiles", on_deployment)

	var batch: CombatSession.FactBatch = session.open_battle()
	_ok("battle: opens", batch.rejected_reason.is_empty(), batch.rejected_reason)
	_ok("battle: turn 1's player phase", (
			session.state.turn == 1 and session.state.phase_side == PLAYER
	), "turn %d" % [session.state.turn])
	_ok("battle: still being fought", not session.is_finished)
	_ok("battle: every unit on the map", (
			session.state.units_of(PLAYER).size() == 4
			and session.state.units_of(ENEMY).size() == 5
	))
	encounter.close()


func _marker_node(node_name: String, terrain: TileMapLayer, tile: Vector2i) -> MapMarker:
	var marker: MapMarker = MapMarker.new()
	marker.name = node_name
	marker.kind = MapMarker.Kind.ENEMY_SLOT
	marker.position = terrain.map_to_local(tile)
	return marker


# Whether tile or a neighbor (grid distance 1) gives more avoid than Plain.
func _has_cover_near(layout: MapLayout, tile: Vector2i) -> bool:
	var near: Array[Vector2i] = [tile]
	for direction: Vector2i in CombatGrid.DIRECTIONS:
		near.append(tile + direction)
	for neighbor: Vector2i in near:
		var terrain: MapLayout.Terrain = layout.terrain_at(neighbor)
		if terrain != null and terrain.bonus.avoid > PLAIN_AVOID:
			return true
	return false


# HP 20, Stance 2 and 5 movement.
func _bases() -> Dictionary:
	return {
		CombatValue.Key.HP: 20.0,
		CombatValue.Key.STANCE_MAX: 2.0,
		CombatValue.Key.MOVEMENT: 5.0,
	}


# One "tile variance group" entry per enemy slot, joined by "; ".
func _describe_slots(layout: MapLayout) -> String:
	var parts: PackedStringArray = []
	for marker: MapLayout.Marker in layout.markers_of(ENEMY_SLOT):
		parts.append("%s %d %s" % [marker.tile, marker.variance_tiles, marker.group_slot])
	return "; ".join(parts)


# Every marker with its ids and parameters, joined by "; ".
func _describe(layout: MapLayout) -> String:
	var parts: PackedStringArray = []
	for marker: MapLayout.Marker in layout.markers:
		parts.append("%s %s %d/%d v%d g%s" % [
			marker.tile,
			MapLayout.MarkerKind.find_key(marker.kind),
			marker.index,
			marker.container_index,
			marker.variance_tiles,
			marker.group_slot,
		])
	return "; ".join(parts)


# The object spots and reinforcement points with their ids, joined by "; ".
func _describe_ids(layout: MapLayout) -> String:
	var parts: PackedStringArray = []
	for marker: MapLayout.Marker in layout.markers:
		if marker.index >= 0 or marker.container_index >= 0:
			parts.append("%s %s %d/%d" % [
				marker.tile,
				MapLayout.ObjectKind.find_key(marker.object_kind),
				marker.index,
				marker.container_index,
			])
	return "; ".join(parts)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
