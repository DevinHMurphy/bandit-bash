# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     check_cases.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

extends RefCounted
## The authoring check cases for tests/map/run_all.gd: the M1 map passes [MapCheck], a good
## hand-built fixture passes, and one bad fixture per [enum MapCheck.Rule] fails that rule alone,
## on the tiles it names. Reports each case through the check callable it is given.
##
## The good fixture is 10 × 8 plain with a river tile at (5, 0), and holds one of everything the
## check looks at: 8 deployment tiles, a reinforcement point, a two-door lever group, a door no
## lever pulls (a lockpick opens it), a passage pair, 3 powder kegs and 2 containers. Each bad
## fixture changes one thing.

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

const OBJECT_SPOT: MapLayout.MarkerKind = MapLayout.MarkerKind.OBJECT_SPOT
const DEPLOYMENT: MapLayout.MarkerKind = MapLayout.MarkerKind.DEPLOYMENT
const DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const LEVER: MapLayout.ObjectKind = MapLayout.ObjectKind.LEVER
const PASSAGE: MapLayout.ObjectKind = MapLayout.ObjectKind.PASSAGE

const ROUT: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
const SURVIVE: CombatMapDefinition.Objective = CombatMapDefinition.Objective.SURVIVE

const WIDTH: int = 10
const HEIGHT: int = 8
const RIVER: Vector2i = Vector2i(5, 0)

# A free plain tile the bad fixtures add their marker on.
const SPARE: Vector2i = Vector2i(7, 1)

var _check: Callable
var _terrains: Dictionary[String, MapLayout.Terrain] = {}


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_m1_passes()
	_test_good_fixture()
	_test_load_problem()
	_test_negative_tile()
	_test_deployment_tiles()
	_test_powder_kegs()
	_test_container_index()
	_test_objective_tile()
	_test_reinforcement_point()
	_test_door_group()
	_test_lever_group()
	_test_passage_pair()


func _test_m1_passes() -> void:
	var definition: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	_ok("check: the M1 definition loads", definition != null)
	if definition == null:
		return
	var layout: MapLayout = MapLoader.load_layout(definition)
	_ok("check: the M1 map loads", layout != null)
	if layout == null:
		return
	var failures: Array[MapCheck.Failure] = MapCheck.check(definition, layout)
	_ok("check: the M1 map passes", failures.is_empty(), MapCheck.describe(failures))


func _test_good_fixture() -> void:
	for objective: CombatMapDefinition.Objective in [ROUT, SURVIVE]:
		var label: String = (CombatMapDefinition.Objective.find_key(objective) as String)
		var failures: Array[MapCheck.Failure] = MapCheck.check(
				_definition(objective), _good_layout(true)
		)
		_ok(
				"check: the good fixture passes as %s" % [label.to_lower()],
				failures.is_empty(),
				MapCheck.describe(failures)
		)


func _test_load_problem() -> void:
	var layout: MapLayout = _good_layout(true)
	layout.problems.append("no terrain \"lava\" at (3, 3)")
	_only("load problem: fails", layout, _definition(), MapCheck.Rule.LOAD_PROBLEM, [null])
	_same(
			"load problem: the loader's text",
			MapCheck.describe(MapCheck.check(_definition(), layout)),
			"LOAD_PROBLEM: no terrain \"lava\" at (3, 3)"
	)


func _test_negative_tile() -> void:
	var layout: MapLayout = _good_layout(false)
	layout.set_terrain(Vector2i(-1, 2), _terrain("plain"))
	layout.index_markers()
	_only(
			"negative tile: a tile",
			layout,
			_definition(),
			MapCheck.Rule.NEGATIVE_TILE,
			[Vector2i(-1, 2)]
	)

	var marked: MapLayout = _good_layout(false)
	marked.set_terrain(Vector2i(3, -1), _terrain("plain"))
	marked.add_marker(MapLayout.MarkerKind.ENEMY_SLOT, Vector2i(3, -1))
	marked.index_markers()
	_only(
			"negative tile: a tile and its marker",
			marked,
			_definition(),
			MapCheck.Rule.NEGATIVE_TILE,
			[Vector2i(3, -1), Vector2i(3, -1)]
	)


func _test_deployment_tiles() -> void:
	var layout: MapLayout = _good_layout(false)
	layout.markers.erase(layout.markers_of(DEPLOYMENT)[0])
	layout.index_markers()
	_only(
			"deployment: 7 tiles fail",
			layout,
			_definition(),
			MapCheck.Rule.DEPLOYMENT_TILES,
			[null]
	)
	_same(
			"deployment: says how many",
			MapCheck.describe(MapCheck.check(_definition(), layout)),
			"DEPLOYMENT_TILES: 7 deployment tiles, 8 needed"
	)


func _test_powder_kegs() -> void:
	var layout: MapLayout = _good_layout(false)
	layout.add_marker(OBJECT_SPOT, Vector2i(6, 6), MapLayout.ObjectKind.POWDER_KEG)
	layout.index_markers()
	_only(
			"kegs: a fourth fails, on its tile",
			layout,
			_definition(),
			MapCheck.Rule.POWDER_KEGS,
			[Vector2i(6, 6)]
	)


func _test_container_index() -> void:
	var repeated: MapLayout = _good_layout(true)
	var containers: Array[MapLayout.Marker] = _containers(repeated)
	containers[1].container_index = containers[0].container_index
	_only(
			"containers: a repeated index",
			repeated,
			_definition(),
			MapCheck.Rule.CONTAINER_INDEX,
			[containers[1].tile]
	)

	var missing: MapLayout = _good_layout(true)
	var unindexed: MapLayout.Marker = _containers(missing)[0]
	unindexed.container_index = -1
	_only(
			"containers: no index",
			missing,
			_definition(),
			MapCheck.Rule.CONTAINER_INDEX,
			[unindexed.tile]
	)


func _test_objective_tile() -> void:
	var needs: Dictionary[CombatMapDefinition.Objective, MapLayout.MarkerKind] = {
		CombatMapDefinition.Objective.SEIZE: MapLayout.MarkerKind.SEIZE,
		CombatMapDefinition.Objective.DEFEND: MapLayout.MarkerKind.DEFEND,
		CombatMapDefinition.Objective.DEFEAT_LEADER: MapLayout.MarkerKind.LEADER_SLOT,
		CombatMapDefinition.Objective.DEFEAT_BOSS: MapLayout.MarkerKind.LEADER_SLOT,
	}
	for objective: CombatMapDefinition.Objective in needs:
		var label: String = (CombatMapDefinition.Objective.find_key(objective) as String)
		label = label.to_lower()
		_only(
				"objective: %s without its tile" % [label],
				_good_layout(true),
				_definition(objective),
				MapCheck.Rule.OBJECTIVE_TILE,
				[null]
		)
		var marked: MapLayout = _good_layout(false)
		marked.add_marker(needs[objective], SPARE)
		marked.index_markers()
		var failures: Array[MapCheck.Failure] = MapCheck.check(_definition(objective), marked)
		_ok(
				"objective: %s with its tile passes" % [label],
				failures.is_empty(),
				MapCheck.describe(failures)
		)
	_only(
			"objective: no definition",
			_good_layout(true),
			null,
			MapCheck.Rule.OBJECTIVE_TILE,
			[null]
	)


func _test_reinforcement_point() -> void:
	var layout: MapLayout = _good_layout(false)
	layout.add_marker(MapLayout.MarkerKind.REINFORCEMENT_POINT, RIVER)
	layout.index_markers()
	_only(
			"reinforcement: a point on a river",
			layout,
			_definition(),
			MapCheck.Rule.REINFORCEMENT_POINT,
			[RIVER]
	)
	_same(
			"reinforcement: names who can't stand there",
			MapCheck.describe(MapCheck.check(_definition(), layout)),
			"REINFORCEMENT_POINT at (5, 0): point 0: DEFAULT, HEAVY, MOUNTED can't stand here"
	)


func _test_door_group() -> void:
	var layout: MapLayout = _good_layout(false)
	_spot(layout, SPARE, DOOR, 5)
	layout.index_markers()
	_only(
			"doors: a group no lever pulls",
			layout,
			_definition(),
			MapCheck.Rule.DOOR_GROUP,
			[SPARE]
	)


func _test_lever_group() -> void:
	var no_group: MapLayout = _good_layout(false)
	_spot(no_group, SPARE, LEVER)
	no_group.index_markers()
	_only("levers: in no group", no_group, _definition(), MapCheck.Rule.LEVER_GROUP, [SPARE])

	var no_door: MapLayout = _good_layout(false)
	_spot(no_door, SPARE, LEVER, 3)
	no_door.index_markers()
	_only(
			"levers: a group with no door",
			no_door,
			_definition(),
			MapCheck.Rule.LEVER_GROUP,
			[SPARE]
	)


func _test_passage_pair() -> void:
	var no_pair: MapLayout = _good_layout(false)
	_spot(no_pair, SPARE, PASSAGE)
	no_pair.index_markers()
	_only(
			"passages: an end in no pair",
			no_pair,
			_definition(),
			MapCheck.Rule.PASSAGE_PAIR,
			[SPARE]
	)

	var one_end: MapLayout = _good_layout(false)
	_spot(one_end, SPARE, PASSAGE, -1, 4)
	one_end.index_markers()
	_only(
			"passages: a pair with one end",
			one_end,
			_definition(),
			MapCheck.Rule.PASSAGE_PAIR,
			[SPARE]
	)

	var three_ends: MapLayout = _good_layout(false)
	_spot(three_ends, SPARE, PASSAGE, -1, 0)
	three_ends.index_markers()
	_only(
			"passages: a pair with three ends",
			three_ends,
			_definition(),
			MapCheck.Rule.PASSAGE_PAIR,
			[Vector2i(2, 0), SPARE, Vector2i(7, 7)]
	)


# The good fixture (see the class doc), indexed when is_indexed; bad fixtures add markers first.
func _good_layout(is_indexed: bool) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "check_fixture"
	for y: int in HEIGHT:
		for x: int in WIDTH:
			var tile: Vector2i = Vector2i(x, y)
			layout.set_terrain(tile, _terrain("river" if tile == RIVER else "plain"))
	for y: int in range(4, 8):
		for x: int in 2:
			layout.add_marker(DEPLOYMENT, Vector2i(x, y))
	layout.add_marker(MapLayout.MarkerKind.REINFORCEMENT_POINT, Vector2i(9, 0))
	_spot(layout, Vector2i(3, 1), LEVER, 0)
	_spot(layout, Vector2i(4, 3), DOOR, 0)
	_spot(layout, Vector2i(4, 4), DOOR, 0)
	_spot(layout, Vector2i(5, 5), DOOR)
	_spot(layout, Vector2i(2, 0), PASSAGE, -1, 0)
	_spot(layout, Vector2i(7, 7), PASSAGE, -1, 0)
	for y: int in range(2, 5):
		_spot(layout, Vector2i(6, y), MapLayout.ObjectKind.POWDER_KEG)
	_spot(layout, Vector2i(8, 5), MapLayout.ObjectKind.CHEST)
	_spot(layout, Vector2i(8, 6), MapLayout.ObjectKind.HOUSE)
	if is_indexed:
		layout.index_markers()
	return layout


func _spot(
		layout: MapLayout,
		tile: Vector2i,
		object_kind: MapLayout.ObjectKind,
		group_id: int = -1,
		pair_id: int = -1
) -> MapLayout.Marker:
	var marker: MapLayout.Marker = layout.add_marker(OBJECT_SPOT, tile, object_kind)
	marker.group_id = group_id
	marker.pair_id = pair_id
	return marker


func _containers(layout: MapLayout) -> Array[MapLayout.Marker]:
	var found: Array[MapLayout.Marker] = []
	for marker: MapLayout.Marker in layout.markers_of(OBJECT_SPOT):
		if MapLayout.CONTAINERS.has(marker.object_kind):
			found.append(marker)
	return found


func _terrain(id: String) -> MapLayout.Terrain:
	if not _terrains.has(id):
		_terrains[id] = MapLayout.Terrain.from_definition(MapLoader.load_terrain(id))
	return _terrains[id]


func _definition(objective: CombatMapDefinition.Objective = ROUT) -> CombatMapDefinition:
	var definition: CombatMapDefinition = CombatMapDefinition.new()
	definition.id = "check_fixture"
	definition.objective = objective
	return definition


# Passes when the check fails layout on rule alone, one failure per entry of tiles, in order: a
# Vector2i is that failure's tile, null a failure about no tile.
func _only(
		case_name: String,
		layout: MapLayout,
		definition: CombatMapDefinition,
		rule: MapCheck.Rule,
		tiles: Array
) -> void:
	var failures: Array[MapCheck.Failure] = MapCheck.check(definition, layout)
	var where: Array = []
	var is_only_rule: bool = true
	for failure: MapCheck.Failure in failures:
		is_only_rule = is_only_rule and failure.rule == rule
		where.append(failure.tile if failure.has_tile else null)
	_ok(
			case_name,
			is_only_rule and where == tiles,
			MapCheck.describe(failures).replace("\n", "; ")
	)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
