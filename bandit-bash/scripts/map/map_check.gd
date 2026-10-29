# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_check.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
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

## One rule of the check. [b]Append only[/b]: P06 adds the darkness-source rule.
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
}

## The fewest deployment tiles a map may author: the army-size ceiling (game-vision.md, Combat
## maps).
const MIN_DEPLOYMENT_TILES: int = 8

## The most powder kegs a map may author (map-objects.md, Keg chains).
const MAX_POWDER_KEGS: int = 3

## The tile the objective needs, per objective that needs one.
const OBJECTIVE_MARKERS: Dictionary[CombatMapDefinition.Objective, MapLayout.MarkerKind] = {
	CombatMapDefinition.Objective.DEFEAT_LEADER: MapLayout.MarkerKind.LEADER_SLOT,
	CombatMapDefinition.Objective.DEFEAT_BOSS: MapLayout.MarkerKind.LEADER_SLOT,
	CombatMapDefinition.Objective.SEIZE: MapLayout.MarkerKind.SEIZE,
	CombatMapDefinition.Objective.DEFEND: MapLayout.MarkerKind.DEFEND,
}

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


# ASSUMPTION: "standable" means every movement type can stand there, so no arrival is pushed to
# another tile by the point's own terrain.
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
