# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     layout_cases.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## The layout cases for tests/map/run_all.gd: every terrain definition against unit-roster.md's
## table, the fixture map scene against its expected [MapLayout], stable marker ids, and the
## problems the loader collects. Reports each case through the check callable it is given.

const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")

# unit-roster.md's terrain table, transcribed independently of data/terrain/: id, costs
# (Default, Heavy, Mobile, Mounted, Flier; 0 = "—"), avoid, DEF, RES, heal flat, heal percent,
# blocker, slick.
const TABLE: Array[Array] = [
	["plain", [1, 1, 1, 1, 1], 5, 0, 0, 0, 0, 0, false],
	["short_grass", [1, 1, 1, 1, 1], 5, 0, 0, 0, 0, 0, false],
	["road", [1, 1, 1, 1, 1], 0, 0, 0, 0, 0, 0, false],
	["floor", [1, 1, 1, 1, 1], 0, 0, 0, 0, 0, 0, false],
	["bridge", [1, 1, 1, 1, 1], 0, 0, 0, 0, 0, 0, false],
	["broken_wall", [1, 1, 1, 1, 1], 0, 0, 0, 0, 0, 0, false],
	["stairs", [1, 1, 1, 1, 1], 5, 0, 0, 0, 0, 0, false],
	["ruins", [1, 1, 1, 1, 1], 15, 0, 0, 0, 0, 0, false],
	["house", [1, 1, 1, 2, 1], 10, 0, 0, 0, 0, 0, false],
	["forest", [2, 2, 2, 2, 1], 20, 1, 1, 0, 0, 0, false],
	["thicket", [2, 3, 2, 3, 1], 15, 1, 1, 0, 0, 0, false],
	["knoll", [2, 3, 1, 2, 1], 15, 1, 1, 0, 0, 0, false],
	["wooded_knoll", [3, 4, 2, 3, 1], 25, 1, 1, 0, 0, 0, false],
	["pillar", [2, 2, 2, 3, 1], 20, 1, 1, 0, 0, 0, false],
	["camp", [2, 2, 3, 3, 1], 15, 1, 1, 2, 0, 0, false],
	["fort", [2, 2, 2, 2, 2], 20, 2, 2, 0, 20, 0, false],
	["castle_gate", [2, 2, 3, 3, 1], 30, 3, 0, 4, 0, 0, false],
	["throne", [2, 2, 3, 3, 1], 30, 3, 0, 4, 0, 0, false],
	["mountain", [4, 0, 3, 0, 1], 30, 1, 1, 0, 0, 0, false],
	["peak", [0, 0, 4, 0, 1], 40, 2, 2, 0, 0, 0, false],
	["river", [0, 0, 2, 0, 1], 15, 0, 0, 0, 0, 0, false],
	["ocean", [0, 0, 0, 0, 1], 10, 0, 0, 0, 0, 0, false],
	["waterfall", [0, 0, 0, 0, 1], 10, 0, 0, 0, 0, 0, false],
	["wall", [0, 0, 0, 0, 1], 0, 0, 0, 0, 0, 0, false],
	["cracked_wall", [0, 0, 0, 0, 1], 0, 0, 0, 0, 0, 0, false],
	["cliff", [0, 0, 0, 0, 1], 0, 0, 0, 0, 0, 0, false],
	["pit", [0, 0, 0, 0, 1], -5, 0, 0, 0, 0, 0, false],
	["spiked_wall", [0, 0, 0, 0, 0], 0, 0, 0, 0, 0, CombatGrid.Blocker.SPIKED_WALL, false],
	["spilled_oil", [1, 1, 1, 1, 1], 0, 0, 0, 0, 0, 0, true],
]

# The fixture's terrain, row by row (tests/map/fixture_map.tscn).
const FIXTURE_ROWS: Array[String] = [
	"plain plain forest wall river",
	"plain road road mountain river",
	"house plain fort plain plain",
	"plain plain plain plain plain",
]

const DEPLOYMENT: MapLayout.MarkerKind = MapLayout.MarkerKind.DEPLOYMENT
const OBJECT_SPOT: MapLayout.MarkerKind = MapLayout.MarkerKind.OBJECT_SPOT
const POINT: MapLayout.MarkerKind = MapLayout.MarkerKind.REINFORCEMENT_POINT

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_terrain_table()
	_test_fixture_layout()
	_test_fixture_markers()
	_test_stable_ids()
	_test_problems()


func _test_terrain_table() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(MapLoader.TERRAIN_DIR)
	var resources: PackedStringArray = []
	for file: String in files:
		if file.ends_with(".tres"):
			resources.append(file)
	_ok(
			"terrain: one file per table row",
			resources.size() == TABLE.size(),
			"%d files" % [resources.size()]
	)
	for row: Array in TABLE:
		var id: String = row[0]
		var definition: TerrainDefinition = MapLoader.load_terrain(id)
		if definition == null:
			_ok("terrain: %s loads" % [id], false)
			continue
		var cost_row: Array = row[1]
		var costs: PackedInt32Array = PackedInt32Array(cost_row)
		var rules: MapLayout.Terrain = MapLayout.Terrain.from_definition(definition)
		var bonus: CombatGrid.TileBonus = rules.bonus
		var actual: Array = [
				definition.id, definition.costs(), bonus.avoid, bonus.defense, bonus.resistance,
				bonus.heal_flat, bonus.heal_percent, rules.blocker, rules.is_slick,
		]
		var expected: Array = [
				id, costs, row[2], row[3], row[4], row[5], row[6], row[7], row[8],
		]
		_ok("terrain: %s matches the table" % [id], actual == expected, str(actual))
		_ok(
				"terrain: %s has a name" % [id],
				not definition.display_name.is_empty() and rules.costs == costs
		)
	var mountain: TerrainDefinition = MapLoader.load_terrain("mountain")
	_ok(
			"terrain: cost per movement type",
			mountain.cost(CombatGrid.MovementType.DEFAULT) == 4
			and mountain.cost(CombatGrid.MovementType.HEAVY) == TerrainDefinition.IMPASSABLE
			and mountain.cost(CombatGrid.MovementType.FLIER) == 1
	)
	_ok("terrain: an unknown id loads nothing", MapLoader.load_terrain("lava") == null)


func _test_fixture_layout() -> void:
	var layout: MapLayout = _load_fixture()
	_ok("layout: loaded", layout != null)
	if layout == null:
		return
	_ok("layout: map id", layout.map_id == "fixture")
	_ok("layout: no problems", layout.problems.is_empty(), str(layout.problems))
	_ok("layout: 20 tiles", layout.tiles().size() == 20)
	_ok("layout: its rectangle", layout.get_rect() == Rect2i(0, 0, 5, 4), str(layout.get_rect()))
	var ids: PackedStringArray = []
	for row: String in FIXTURE_ROWS:
		ids.append_array(row.split(" "))
	var actual: PackedStringArray = []
	for tile: Vector2i in layout.tiles():
		actual.append(layout.terrain_at(tile).id)
	_ok("layout: terrain row-major", actual == ids, " ".join(actual))
	_ok("layout: each terrain once", layout.terrains.size() == 8)
	_ok(
			"layout: tiles of one terrain share it",
			layout.terrain_at(Vector2i(0, 0)) == layout.terrain_at(Vector2i(4, 3))
	)
	_ok("layout: off the map", not layout.has_tile(Vector2i(5, 0)))
	_ok("layout: no terrain off the map", layout.terrain_at(Vector2i(-1, 0)) == null)
	var fort: MapLayout.Terrain = layout.terrain_at(Vector2i(2, 2))
	_ok(
			"layout: the fort's bonuses",
			fort.bonus.avoid == 20 and fort.bonus.defense == 2 and fort.bonus.heal_percent == 20
	)


func _test_fixture_markers() -> void:
	var layout: MapLayout = _load_fixture()
	if layout == null:
		_ok("markers: loaded", false)
		return
	_ok(
			"markers: deployment tiles row-major",
			layout.tiles_of(DEPLOYMENT) == [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3)]
	)
	_ok("markers: seize", layout.tiles_of(MapLayout.MarkerKind.SEIZE) == [Vector2i(2, 2)])
	_ok(
			"markers: enemy slot",
			layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT) == [Vector2i(3, 2)]
	)
	_same(
			"markers: object spots by index",
			_describe(layout.markers_of(OBJECT_SPOT)),
			"(0, 0) CHEST 0/0; (1, 1) LEVER 1/-1; (2, 1) DOOR 2/-1; (0, 2) HOUSE 3/1; "
			+ "(1, 2) WOODEN_DEBRIS 4/-1"
	)
	_same(
			"markers: reinforcement points by index",
			_describe(layout.markers_of(POINT)),
			"(4, 2) NONE 0/-1; (4, 3) NONE 1/-1"
	)
	var on_lever: PackedStringArray = []
	for marker: MapLayout.Marker in layout.markers:
		if marker.tile == Vector2i(1, 1):
			on_lever.append(MapLayout.MarkerKind.find_key(marker.kind) as String)
	_ok(
			"markers: two on one tile, by kind",
			on_lever == PackedStringArray(["OBJECT_SPOT", "DARKNESS_SOURCE"]),
			str(on_lever)
	)
	_ok("markers: 13 in all", layout.markers.size() == 13, str(layout.markers.size()))


func _test_stable_ids() -> void:
	var first: MapLayout = _load_fixture()
	var second: MapLayout = _load_fixture()
	if first == null or second == null:
		_ok("ids: loaded", false)
		return
	_same("ids: the same on two loads", _describe(second.markers), _describe(first.markers))
	first.index_markers()
	_same(
			"ids: indexing again changes nothing",
			_describe(first.markers),
			_describe(second.markers)
	)

	var forward: MapLayout = MapLayout.new()
	var backward: MapLayout = MapLayout.new()
	var spots: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(2, 1)]
	var kinds: Array[MapLayout.ObjectKind] = [
		MapLayout.ObjectKind.BOOK_SHELF,
		MapLayout.ObjectKind.CHEST,
		MapLayout.ObjectKind.POWDER_KEG,
		MapLayout.ObjectKind.WEAPON_RACK,
	]
	for i: int in spots.size():
		forward.add_marker(OBJECT_SPOT, spots[i], kinds[i])
		var j: int = spots.size() - 1 - i
		backward.add_marker(OBJECT_SPOT, spots[j], kinds[j])
	forward.index_markers()
	backward.index_markers()
	_same(
			"ids: independent of authoring order",
			_describe(backward.markers),
			_describe(forward.markers)
	)
	_same(
			"ids: row-major, containers counted apart",
			_describe(forward.markers),
			"(1, 0) POWDER_KEG 0/-1; (3, 0) BOOK_SHELF 1/0; (0, 1) CHEST 2/1; "
			+ "(2, 1) WEAPON_RACK 3/2"
	)


func _test_problems() -> void:
	var fixture: Node = FIXTURE_SCENE.instantiate()
	var tile_set: TileSet = (fixture.get_node(^"Terrain") as TileMapLayer).tile_set
	var source_id: int = tile_set.get_source_id(0)
	var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
	var atlas: Dictionary[String, Vector2i] = {}
	for i: int in source.get_tiles_count():
		var coords: Vector2i = source.get_tile_id(i)
		var data: TileData = source.get_tile_data(coords, 0)
		var terrain_id: String = data.get_custom_data(MapLoader.TERRAIN_DATA)
		var marker_name: String = data.get_custom_data(MapLoader.MARKER_DATA)
		atlas[terrain_id if not terrain_id.is_empty() else "m:" + marker_name] = coords
	fixture.free()

	var root: Node2D = Node2D.new()
	var terrain: TileMapLayer = TileMapLayer.new()
	terrain.name = MapLoader.TERRAIN_LAYER
	terrain.tile_set = tile_set
	root.add_child(terrain)
	terrain.set_cell(Vector2i(0, 0), source_id, atlas["plain"])
	terrain.set_cell(Vector2i(1, 0), source_id, atlas["lava"])
	terrain.set_cell(Vector2i(2, 0), source_id, atlas["m:deployment"])
	var markers: TileMapLayer = TileMapLayer.new()
	markers.name = "Markers"
	markers.tile_set = tile_set
	root.add_child(markers)
	markers.set_cell(Vector2i(0, 0), source_id, atlas["m:bogus"])
	markers.set_cell(Vector2i(0, 1), source_id, atlas["m:deployment"])
	var layout: MapLayout = MapLoader.from_scene(root, "bad")
	root.free()
	_ok("problems: still loads", layout != null)
	if layout == null:
		return
	_ok("problems: four", layout.problems.size() == 4, str(layout.problems))
	_ok(
			"problems: an unknown marker",
			"unknown marker \"bogus\" at (0, 0) on Markers" in layout.problems
	)
	_ok(
			"problems: an unknown terrain",
			"no terrain \"lava\" at (1, 0)" in layout.problems
	)
	_ok(
			"problems: a tile without a terrain",
			"no terrain \"\" at (2, 0)" in layout.problems
	)
	_ok(
			"problems: a marker off the map",
			"marker \"deployment\" off the map at (0, 1)" in layout.problems
	)
	_ok("problems: unreadable tiles are off the map", layout.tiles() == [Vector2i(0, 0)])
	_ok("problems: no markers", layout.markers.is_empty())

	var bare: Node2D = Node2D.new()
	_ok("problems: no terrain layer, no layout", MapLoader.from_scene(bare, "bare") == null)
	bare.free()


func _load_fixture() -> MapLayout:
	var definition: CombatMapDefinition = CombatMapDefinition.new()
	definition.id = "fixture"
	definition.scene = FIXTURE_SCENE
	return MapLoader.load_layout(definition)


# One "tile KIND index/container" entry per marker, joined by "; ".
func _describe(markers: Array[MapLayout.Marker]) -> String:
	var parts: PackedStringArray = []
	for marker: MapLayout.Marker in markers:
		parts.append(
				"%s %s %d/%d" % [
					marker.tile,
					MapLayout.ObjectKind.find_key(marker.object_kind),
					marker.index,
					marker.container_index,
				]
		)
	return "; ".join(parts)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
