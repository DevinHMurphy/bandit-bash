# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_check.gd
# Author:
# Created:  October 28, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name MapCheck
extends RefCounted
## The authoring check: the rules a map must pass to ship, run on its loaded [MapLayout] and its
## [CombatMapDefinition]. The map content tests fail a map with any [Failure].
##
## Each [Failure] names its [enum Rule] and, for a rule about one tile, that tile; the map-wide
## rules (too few deployment tiles, a missing objective tile) name none. Problems the loader
## collected are failures too ([constant Rule.LOAD_PROBLEM]); their text names the tile.[br]
## Pure and static: it reads the layout and changes nothing, on the ids
## [method MapLayout.index_markers] gave it, as the battle sees them. Failures come in [enum Rule]
## order.
##
## @tutorial(Combat map plan, Authoring and loading): docs/plans/2026-10-27-combat-map.md
##
## @todo: TOD-001 - Let the Powder Baron's arena waive the powder keg limit (P05 boss maps).

## One rule of the check. [b]Append only.[/b]
enum Rule {
	## The loader couldn't read a tile or a marker ([member MapLayout.problems]).
	LOAD_PROBLEM = 0,
	## A tile or a marker has a negative coordinate.
	NEGATIVE_TILE = 1,
	## Fewer than [constant MIN_DEPLOYMENT_TILES] deployment tiles.
	DEPLOYMENT_TILES = 2,
	## More than [constant MAX_POWDER_KEGS] powder keg spots; the failure names each spot over it.
	POWDER_KEGS = 3,
	## A container shares its container index with another one, or has none.
	CONTAINER_INDEX = 4,
	## The objective's tile is missing: Seize's seize tile, Defend's defend tile, or the leader
	## slot of Defeat the Leader and Defeat the Boss.
	OBJECTIVE_TILE = 5,
	## A reinforcement point on a tile some movement type can't stand on.
	REINFORCEMENT_POINT = 6,
	## A door in a lever group no lever pulls.
	DOOR_GROUP = 7,
	## A lever in no group, or in a group with no door.
	LEVER_GROUP = 8,
	## A passage end in no pair, or a pair without exactly two ends.
	PASSAGE_PAIR = 9,
	## A map with the darkness ([method DarknessSetup.has_darkness]) has fewer than
	## [constant MIN_SOURCE_CANDIDATES] source candidates, or a candidate with no floodable tile as
	## the battle starts; that failure names the candidate's first tile.
	DARKNESS_SOURCES = 10,
	## A required tile or a lever of a lever door the commander can't reach from the deployment
	## zone with no key, or an area behind a lever door with no lever of its group to get out by
	## ([method _check_reachability]). Names the tile and why.
	REACHABILITY = 11,
}

## The fewest deployment tiles a map may author: the army-size ceiling (game-vision.md, Combat
## maps).
const MIN_DEPLOYMENT_TILES: int = 8

## The most powder kegs a map may author (map-objects.md, Keg chains).
const MAX_POWDER_KEGS: int = 3

## The fewest darkness source candidates a map with the darkness may author (the-darkness.md,
## Values: at least 2), so the active pick varies from run to run.
const MIN_SOURCE_CANDIDATES: int = 2

## The tile the objective needs, per objective that needs one.
const OBJECTIVE_MARKERS: Dictionary[CombatMapDefinition.Objective, MapLayout.MarkerKind] = {
	CombatMapDefinition.Objective.DEFEAT_LEADER: MapLayout.MarkerKind.LEADER_SLOT,
	CombatMapDefinition.Objective.DEFEAT_BOSS: MapLayout.MarkerKind.LEADER_SLOT,
	CombatMapDefinition.Objective.SEIZE: MapLayout.MarkerKind.SEIZE,
	CombatMapDefinition.Objective.DEFEND: MapLayout.MarkerKind.DEFEND,
}

## The movement type [constant Rule.REACHABILITY] walks with: the commander's (Drengr's), since
## every other unit can fall and a lone commander must still be able to finish the map.
const REACH_MOVEMENT: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT

# Marks "no lever group" where a group id is expected.
const _NO_GROUP: int = -1

const _DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const _LEVER: MapLayout.ObjectKind = MapLayout.ObjectKind.LEVER
const _PASSAGE: MapLayout.ObjectKind = MapLayout.ObjectKind.PASSAGE


## Every failure of [param layout], the map of [param definition]; empty when the map passes.
## [param layout] is as [MapLoader] returns it, its markers indexed.
static func check(definition: CombatMapDefinition, layout: MapLayout) -> Array[Failure]:
	var failures: Array[Failure] = []
	for problem: String in layout.problems:
		failures.append(Failure.new(Rule.LOAD_PROBLEM, problem))
	_check_negative_tiles(layout, failures)
	_check_deployment(layout, failures)
	_check_kegs(layout, failures)
	_check_containers(layout, failures)
	_check_objective(definition, layout, failures)
	_check_reinforcement_points(layout, failures)
	_check_lever_groups(layout, failures)
	_check_passages(layout, failures)
	_check_darkness_sources(definition, layout, failures)
	_check_reachability(definition, layout, failures)
	return failures


## [param failures] one per line, for test and log output; empty for none.
static func describe(failures: Array[Failure]) -> String:
	var lines: PackedStringArray = []
	for failure: Failure in failures:
		lines.append(failure.describe())
	return "\n".join(lines)


static func _check_negative_tiles(layout: MapLayout, failures: Array[Failure]) -> void:
	for tile: Vector2i in layout.tiles():
		if tile.x < 0 or tile.y < 0:
			failures.append(Failure.new(Rule.NEGATIVE_TILE, "a tile", tile))
	for marker: MapLayout.Marker in layout.markers:
		if marker.tile.x < 0 or marker.tile.y < 0:
			failures.append(Failure.new(Rule.NEGATIVE_TILE, _name_of(marker), marker.tile))


static func _check_deployment(layout: MapLayout, failures: Array[Failure]) -> void:
	var count: int = layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT).size()
	if count < MIN_DEPLOYMENT_TILES:
		failures.append(Failure.new(
				Rule.DEPLOYMENT_TILES,
				"%d deployment tiles, %d needed" % [count, MIN_DEPLOYMENT_TILES]
		))


static func _check_kegs(layout: MapLayout, failures: Array[Failure]) -> void:
	var count: int = 0
	for marker: MapLayout.Marker in layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT):
		if marker.object_kind != MapLayout.ObjectKind.POWDER_KEG:
			continue
		count += 1
		if count > MAX_POWDER_KEGS:
			failures.append(Failure.new(
					Rule.POWDER_KEGS,
					"powder keg %d, at most %d" % [count, MAX_POWDER_KEGS],
					marker.tile
			))


static func _check_containers(layout: MapLayout, failures: Array[Failure]) -> void:
	var seen: Dictionary[int, bool] = {}
	for marker: MapLayout.Marker in layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT):
		if not MapLayout.CONTAINERS.has(marker.object_kind):
			continue
		var label: String = _name_of(marker)
		if marker.container_index < 0:
			failures.append(Failure.new(
					Rule.CONTAINER_INDEX, "%s has no container index" % [label], marker.tile
			))
		elif seen.has(marker.container_index):
			failures.append(Failure.new(
					Rule.CONTAINER_INDEX,
					"%s repeats container index %d" % [label, marker.container_index],
					marker.tile
			))
		seen[marker.container_index] = true


static func _check_objective(
		definition: CombatMapDefinition, layout: MapLayout, failures: Array[Failure]
) -> void:
	if definition == null:
		failures.append(Failure.new(Rule.OBJECTIVE_TILE, "no map definition to read it from"))
		return
	if not OBJECTIVE_MARKERS.has(definition.objective):
		return
	var kind: MapLayout.MarkerKind = OBJECTIVE_MARKERS[definition.objective]
	if layout.tiles_of(kind).is_empty():
		failures.append(Failure.new(
				Rule.OBJECTIVE_TILE,
				"%s needs a %s marker" % [
					CombatMapDefinition.Objective.find_key(definition.objective),
					MapLayout.MarkerKind.find_key(kind),
				]
		))


# "Standable" means every movement type can stand there, so no arrival is pushed to another tile by
# the point's own terrain (combat map plan, question 22).
static func _check_reinforcement_points(layout: MapLayout, failures: Array[Failure]) -> void:
	var grid: MapGrid = MapGrid.new(layout)
	for marker: MapLayout.Marker in layout.markers_of(MapLayout.MarkerKind.REINFORCEMENT_POINT):
		var blocked: PackedStringArray = []
		for movement_type: CombatGrid.MovementType in CombatGrid.MovementType.values():
			if not grid.can_stand(marker.tile, movement_type):
				blocked.append(CombatGrid.MovementType.find_key(movement_type) as String)
		if not blocked.is_empty():
			failures.append(Failure.new(
					Rule.REINFORCEMENT_POINT,
					"point %d: %s can't stand here" % [marker.index, ", ".join(blocked)],
					marker.tile
			))


# ASSUMPTION: a door may stand in no group (a lockpick opens it), but a door in a group needs a
# lever in it, and every lever needs a group with a door. MP6 may refine what "match up" means.
static func _check_lever_groups(layout: MapLayout, failures: Array[Failure]) -> void:
	var spots: Array[MapLayout.Marker] = layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT)
	var door_groups: Dictionary[int, bool] = {}
	var lever_groups: Dictionary[int, bool] = {}
	for marker: MapLayout.Marker in spots:
		if marker.object_kind == _DOOR and marker.group_id >= 0:
			door_groups[marker.group_id] = true
		elif marker.object_kind == _LEVER and marker.group_id >= 0:
			lever_groups[marker.group_id] = true
	# Doors first, then levers: failures stay in Rule order.
	for marker: MapLayout.Marker in spots:
		if (
				marker.object_kind == _DOOR
				and marker.group_id >= 0
				and not lever_groups.has(marker.group_id)
		):
			failures.append(Failure.new(
					Rule.DOOR_GROUP, "no lever pulls group %d" % [marker.group_id], marker.tile
			))
	for marker: MapLayout.Marker in spots:
		if marker.object_kind != _LEVER:
			continue
		if marker.group_id < 0:
			failures.append(Failure.new(Rule.LEVER_GROUP, "a lever in no group", marker.tile))
		elif not door_groups.has(marker.group_id):
			failures.append(Failure.new(
					Rule.LEVER_GROUP, "group %d has no door" % [marker.group_id], marker.tile
			))


static func _check_passages(layout: MapLayout, failures: Array[Failure]) -> void:
	var ends: Dictionary[int, int] = {}
	for marker: MapLayout.Marker in layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT):
		if marker.object_kind == _PASSAGE and marker.pair_id >= 0:
			ends[marker.pair_id] = ends.get(marker.pair_id, 0) + 1
	for marker: MapLayout.Marker in layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT):
		if marker.object_kind != _PASSAGE:
			continue
		if marker.pair_id < 0:
			failures.append(Failure.new(Rule.PASSAGE_PAIR, "a passage in no pair", marker.tile))
		elif ends[marker.pair_id] != 2:
			failures.append(Failure.new(
					Rule.PASSAGE_PAIR,
					"pair %d has %d ends, 2 needed" % [marker.pair_id, ends[marker.pair_id]],
					marker.tile
			))


# Floodable as the battle starts: doors closed and breakables standing, as DarknessSetup reads it.
static func _check_darkness_sources(
		definition: CombatMapDefinition, layout: MapLayout, failures: Array[Failure]
) -> void:
	if not DarknessSetup.has_darkness(definition):
		return
	var found: Array[DarknessState.Source] = DarknessSetup.candidates(layout)
	if found.size() < MIN_SOURCE_CANDIDATES:
		failures.append(Failure.new(
				Rule.DARKNESS_SOURCES,
				"%d source candidates, %d needed" % [found.size(), MIN_SOURCE_CANDIDATES]
		))
	var state: CombatState = DarknessSetup.start_state(layout)
	for index: int in found.size():
		var tiles: Array[Vector2i] = found[index].tiles
		var is_floodable: bool = false
		for tile: Vector2i in tiles:
			is_floodable = is_floodable or DarknessFlow.is_floodable(state, tile)
		if not is_floodable:
			failures.append(Failure.new(
					Rule.DARKNESS_SOURCES,
					"source candidate %d has no floodable tile" % [index],
					tiles[0]
			))


## Only optional content (shortcuts, loot) may sit behind a door that needs a key
## (map-objects.md, Reachable maps). Walking as [constant REACH_MOVEMENT] from the deployment zone,
## with no key and nothing broken, a lever door opening once a lever of its group is reached and
## passages linking their ends: every required tile ([method _required]) and every lever of a lever
## door is reached; and each area reached only through a lever door holds a lever of its group,
## since either side can pull a lever to shut a unit in.
static func _check_reachability(
		definition: CombatMapDefinition, layout: MapLayout, failures: Array[Failure]
) -> void:
	var walk: ReachWalk = ReachWalk.new(layout)
	# No objective to read, or no zone to walk from: OBJECTIVE_TILE or DEPLOYMENT_TILES says so.
	if definition == null or walk.origins.is_empty():
		return
	var opened: Dictionary[int, bool] = {}
	var reached: Dictionary[Vector2i, bool] = walk.flood(walk.origins, opened)
	for marker: MapLayout.Marker in _required(definition, layout):
		if not walk.is_reached(marker.tile, reached):
			failures.append(Failure.new(
					Rule.REACHABILITY,
					"%s is %s" % [_required_name(marker), walk.why(marker.tile, opened, -1)],
					marker.tile
			))
	for lever: MapLayout.Marker in walk.levers:
		if not reached.has(lever.tile):
			failures.append(Failure.new(
					Rule.REACHABILITY,
					"lever of group %d is %s" % [
						lever.group_id, walk.why(lever.tile, opened, lever.group_id),
					],
					lever.tile
			))
	var groups: Array[int] = []
	groups.assign(opened.keys())
	groups.sort()
	for group_id: int in groups:
		for tile: Vector2i in walk.shut_in(reached, opened, group_id):
			failures.append(Failure.new(
					Rule.REACHABILITY,
					"shut in when group %d's doors close: no lever of the group on this side"
							% [group_id],
					tile
			))


# The markers the objective needs reached, in marker order: Seize and Defend tiles, leader slots
# and reinforcement points on every map, and on Rout every enemy slot. Defeat the Leader or the
# Boss needs only the leader slot; Survive and Defend need no enemy, as ending early is optional.
static func _required(
		definition: CombatMapDefinition, layout: MapLayout
) -> Array[MapLayout.Marker]:
	var kinds: Array[MapLayout.MarkerKind] = [
		MapLayout.MarkerKind.SEIZE,
		MapLayout.MarkerKind.DEFEND,
		MapLayout.MarkerKind.LEADER_SLOT,
		MapLayout.MarkerKind.REINFORCEMENT_POINT,
	]
	if definition.objective == CombatMapDefinition.Objective.ROUT:
		kinds.append(MapLayout.MarkerKind.ENEMY_SLOT)
	var found: Array[MapLayout.Marker] = []
	for marker: MapLayout.Marker in layout.markers:
		if kinds.has(marker.kind):
			found.append(marker)
	return found


# A required marker in failure text, such as "the seize tile" or "point 1"; enemy slots carry no
# index, so the failure's tile tells them apart.
static func _required_name(marker: MapLayout.Marker) -> String:
	match marker.kind:
		MapLayout.MarkerKind.SEIZE:
			return "the seize tile"
		MapLayout.MarkerKind.DEFEND:
			return "the defend tile"
		MapLayout.MarkerKind.LEADER_SLOT:
			return "the leader slot"
		MapLayout.MarkerKind.REINFORCEMENT_POINT:
			return "point %d" % [marker.index]
	return "an enemy slot"


# A marker in failure text: its object kind for an object spot, else its marker kind.
static func _name_of(marker: MapLayout.Marker) -> String:
	if marker.kind == MapLayout.MarkerKind.OBJECT_SPOT:
		return (MapLayout.ObjectKind.find_key(marker.object_kind) as String).to_lower()
	return (MapLayout.MarkerKind.find_key(marker.kind) as String).to_lower()


## One broken rule.
class Failure:
	extends RefCounted

	## The rule broken.
	var rule: Rule = Rule.LOAD_PROBLEM
	## Whether the failure is about one tile, [member tile].
	var has_tile: bool = false
	## The tile it is about; meaningful only when [member has_tile].
	var tile: Vector2i = Vector2i.ZERO
	## What is wrong, for the author.
	var detail: String = ""

	# at: a Vector2i for a failure about one tile, or null for a map-wide one.
	func _init(broken: Rule, what: String, at: Variant = null) -> void:
		rule = broken
		detail = what
		if at is Vector2i:
			has_tile = true
			tile = at

	## One line: the rule, the tile if any, and the detail, such as
	## [code]REINFORCEMENT_POINT at (3, 0): point 0: DEFAULT can't stand here[/code].
	func describe() -> String:
		var rule_name: String = Rule.find_key(rule)
		if has_tile:
			return "%s at %s: %s" % [rule_name, tile, detail]
		return "%s: %s" % [rule_name, detail]


## The walk [constant Rule.REACHABILITY] makes over one map: [constant REACH_MOVEMENT]'s terrain,
## closed doors and standing breakables solid, a passage end linked to its pair's other end. Reads
## the layout only; units and the darkness don't count.
class ReachWalk:
	extends RefCounted

	## The deployment tiles every walk from the zone starts on, in marker order.
	var origins: Array[Vector2i] = []
	## Each lever whose group has a door, in marker order.
	var levers: Array[MapLayout.Marker] = []

	var _grid: MapGrid = null
	# Each door tile's lever group; _NO_GROUP for a key-only door.
	var _doors: Dictionary[Vector2i, int] = {}
	# Each tile a breakable (debris, powder keg) stands on.
	var _breakables: Dictionary[Vector2i, bool] = {}
	# Each passage end's other end, for the pairs with exactly two ends.
	var _passages: Dictionary[Vector2i, Vector2i] = {}

	func _init(layout: MapLayout) -> void:
		_grid = MapGrid.new(layout)
		origins = layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT)
		# Untyped values: typed collections can't nest. Each holds a pair's end tiles.
		var ends: Dictionary[int, Array] = {}
		var spots: Array[MapLayout.Marker] = layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT)
		for marker: MapLayout.Marker in spots:
			if marker.object_kind == _DOOR:
				_doors[marker.tile] = marker.group_id if marker.group_id >= 0 else _NO_GROUP
			elif marker.object_kind == _PASSAGE and marker.pair_id >= 0:
				if not ends.has(marker.pair_id):
					ends[marker.pair_id] = []
				ends[marker.pair_id].append(marker.tile)
			elif MapObjects.BREAKABLE_STATS.has(marker.object_kind):
				_breakables[marker.tile] = true
		for pair_id: int in ends:
			if ends[pair_id].size() == 2:
				_passages[ends[pair_id][0] as Vector2i] = ends[pair_id][1] as Vector2i
				_passages[ends[pair_id][1] as Vector2i] = ends[pair_id][0] as Vector2i
		for marker: MapLayout.Marker in spots:
			if (
					marker.object_kind == _LEVER
					and marker.group_id >= 0
					and _doors.values().has(marker.group_id)
			):
				levers.append(marker)

	## Every tile reached from [param from]. [param opened]: the lever groups whose doors are open;
	## it grows by each group a reached lever opens, except [param closed_group], kept shut.
	## [param extra]: door and breakable tiles counted open.
	func flood(
			from: Array[Vector2i],
			opened: Dictionary[int, bool],
			closed_group: int = _NO_GROUP,
			extra: Dictionary[Vector2i, bool] = {}
	) -> Dictionary[Vector2i, bool]:
		var reached: Dictionary[Vector2i, bool] = _spread(from, opened, closed_group, extra)
		while _pull_reached(reached, opened, closed_group):
			reached = _spread(from, opened, closed_group, extra)
		return reached

	## Whether [param tile] is in [param reached], or, on terrain the commander can't stand on
	## (an enemy on a wall, a point on a river), next to a tile in it: other rules judge the tile.
	func is_reached(tile: Vector2i, reached: Dictionary[Vector2i, bool]) -> bool:
		if reached.has(tile) or _grid.can_stand(tile, REACH_MOVEMENT):
			return reached.has(tile)
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			if reached.has(tile + direction):
				return true
		return false

	## Why the walk from the zone doesn't reach [param tile], with [param opened] the groups it
	## opened: the first of a key-only door, the doors of a group whose levers it can't reach,
	## breakables, or walls. [param own_group]: a lever's group, whose tile must be stood on;
	## [constant _NO_GROUP] for a required tile.
	func why(tile: Vector2i, opened: Dictionary[int, bool], own_group: int) -> String:
		var must_stand: bool = own_group != _NO_GROUP
		var key_doors: Dictionary[Vector2i, bool] = {}
		var group_ids: Array[int] = []
		for door: Vector2i in _sorted(_doors.keys()):
			if _doors[door] == _NO_GROUP:
				key_doors[door] = true
			elif not opened.has(_doors[door]) and not group_ids.has(_doors[door]):
				group_ids.append(_doors[door])
		for door: Vector2i in key_doors:
			if _reaches(tile, must_stand, opened, {door: true}):
				return "behind key-only door at %s" % [door]
		if not key_doors.is_empty() and _reaches(tile, must_stand, opened, key_doors):
			return "behind key-only doors"
		group_ids.sort()
		for group_id: int in group_ids:
			var with_group: Dictionary[int, bool] = opened.duplicate()
			with_group[group_id] = true
			if _reaches(tile, must_stand, with_group, {}):
				if group_id == own_group:
					return "behind its own door (group %d)" % [group_id]
				return "behind the doors of group %d, whose levers can't be reached" % [group_id]
		var every_door: Dictionary[Vector2i, bool] = {}
		for door: Vector2i in _doors:
			every_door[door] = true
		if _reaches(tile, must_stand, opened, every_door):
			return "behind doors no reachable lever opens"
		var everything: Dictionary[Vector2i, bool] = every_door.duplicate()
		for breakable: Vector2i in _breakables:
			everything[breakable] = true
		if _reaches(tile, must_stand, opened, everything):
			return "reached only by breaking debris or a powder keg"
		return "walled off"

	## The first tile, row-major, of each area of [param reached] that only group
	## [param group_id]'s doors lead to and that holds no lever of the group: a unit there is shut
	## in when either side closes them. [param opened]: the groups the walk opened.
	func shut_in(
			reached: Dictionary[Vector2i, bool], opened: Dictionary[int, bool], group_id: int
	) -> Array[Vector2i]:
		var others: Dictionary[int, bool] = opened.duplicate()
		others.erase(group_id)
		var outside: Dictionary[Vector2i, bool] = flood(origins, others.duplicate(), group_id)
		var far: Array[Vector2i] = []
		for tile: Vector2i in reached:
			if not outside.has(tile) and _doors.get(tile, _NO_GROUP) != group_id:
				far.append(tile)
		far.sort_custom(MapLayout.is_before)
		var seen: Dictionary[Vector2i, bool] = {}
		var found: Array[Vector2i] = []
		for tile: Vector2i in far:
			if seen.has(tile):
				continue
			var area: Dictionary[Vector2i, bool] = flood([tile], others.duplicate(), group_id)
			seen.merge(area)
			var has_lever: bool = false
			for lever: MapLayout.Marker in levers:
				has_lever = has_lever or (lever.group_id == group_id and area.has(lever.tile))
			if not has_lever:
				found.append(tile)
		return found

	# Whether the walk from the zone with opened and extra reaches tile (standing on it when
	# must_stand).
	func _reaches(
			tile: Vector2i,
			must_stand: bool,
			opened: Dictionary[int, bool],
			extra: Dictionary[Vector2i, bool]
	) -> bool:
		var reached: Dictionary[Vector2i, bool] = flood(
				origins, opened.duplicate(), _NO_GROUP, extra
		)
		return reached.has(tile) if must_stand else is_reached(tile, reached)

	# Opens the group of each lever in reached not yet open (never closed_group); whether any was.
	func _pull_reached(
			reached: Dictionary[Vector2i, bool], opened: Dictionary[int, bool], closed_group: int
	) -> bool:
		var grew: bool = false
		for lever: MapLayout.Marker in levers:
			var group_id: int = lever.group_id
			if reached.has(lever.tile) and group_id != closed_group and not opened.has(group_id):
				opened[group_id] = true
				grew = true
		return grew

	# Every tile reached from `from` over open tiles, through orthogonal steps and passages.
	func _spread(
			from: Array[Vector2i],
			opened: Dictionary[int, bool],
			closed_group: int,
			extra: Dictionary[Vector2i, bool]
	) -> Dictionary[Vector2i, bool]:
		var reached: Dictionary[Vector2i, bool] = {}
		var frontier: Array[Vector2i] = []
		for tile: Vector2i in from:
			if not reached.has(tile) and _is_open(tile, opened, closed_group, extra):
				reached[tile] = true
				frontier.append(tile)
		while not frontier.is_empty():
			var tile: Vector2i = frontier.pop_back()
			var nexts: Array[Vector2i] = []
			for direction: Vector2i in CombatGrid.DIRECTIONS:
				nexts.append(_grid.step(tile, direction))
			if _passages.has(tile):
				nexts.append(_passages[tile])
			for next: Vector2i in nexts:
				if next == CombatFact.NO_TILE or reached.has(next):
					continue
				if _is_open(next, opened, closed_group, extra):
					reached[next] = true
					frontier.append(next)
		return reached

	# Whether the commander may stand on tile: its terrain allows it, and it holds no breakable
	# and no closed door, unless extra opens it.
	func _is_open(
			tile: Vector2i,
			opened: Dictionary[int, bool],
			closed_group: int,
			extra: Dictionary[Vector2i, bool]
	) -> bool:
		if not _grid.can_stand(tile, REACH_MOVEMENT):
			return false
		if extra.has(tile):
			return true
		if _breakables.has(tile):
			return false
		if _doors.has(tile):
			var group_id: int = _doors[tile]
			return group_id != _NO_GROUP and group_id != closed_group and opened.has(group_id)
		return true

	# tiles, typed and sorted row-major. Untyped parameter: Dictionary.keys() is untyped.
	static func _sorted(tiles: Array) -> Array[Vector2i]:
		var sorted: Array[Vector2i] = []
		sorted.assign(tiles)
		sorted.sort_custom(MapLayout.is_before)
		return sorted
