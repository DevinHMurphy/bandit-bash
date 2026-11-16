# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     gen_maps.gd
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================

extends SceneTree
## Builds the M2 map set's greybox maps (combat map plan, MP10): for each map in [method _maps],
## its scene from ASCII terrain and marker grids plus its [MapMarker] nodes, and its
## [CombatMapDefinition] with each assumption written above its value; then runs [MapCheck].[br]
## [b]Rebuilding:[/b] an existing scene and definition are updated in place, so node and resource
## ids stay and unchanged data writes the same bytes. The tile layers and the listed marker nodes
## are rewritten; marker nodes the data doesn't list are removed; other nodes are kept.[br]
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tools/gen_maps.gd[/code], optionally
## followed by [code]-- <map id> ...[/code] to build only those. Prints one line per map; exits
## with code 1 when a map fails to build or fails the check. Authoring tooling: nothing in the
## game loads it.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md

const TILE_SET_PATH: String = "res://maps/greybox_tile_set.tres"
const STANDARD_FOLDER: String = "res://maps/standard"
const KEY_FOLDER: String = "res://maps/key"

## The terrain id of each character in a map's terrain rows.
const TERRAIN_CHARS: Dictionary[String, String] = {
	".": "plain", ",": "short_grass", "=": "road", "F": "forest", "T": "thicket",
	"M": "mountain", "K": "knoll", "Q": "wooded_knoll", "W": "wall", "~": "river",
	"B": "bridge", "H": "house", "R": "ruins", "_": "floor", "O": "fort", "S": "stairs",
	"P": "pillar", "C": "cliff", "G": "castle_gate", "A": "camp", "Y": "throne",
}

## The marker name ([constant MapLoader.MARKERS], [constant MapLoader.OBJECTS]) of each character
## in a map's marker rows; "." is no marker.
const MARKER_CHARS: Dictionary[String, String] = {
	"d": "deployment", "h": "house", "c": "chest", "w": "wooden_debris", "s": "stone_debris",
	"k": "powder_keg", "b": "brazier", "f": "food_shelf", "o": "book_shelf", "r": "weapon_rack",
	"L": "leader_slot", "Z": "seize", "X": "defend",
}

## The parent node of each kind of marker node, in the order they are added to a new scene.
const GROUPS: Dictionary[MapMarker.Kind, String] = {
	MapMarker.Kind.ENEMY_SLOT: "EnemySlots",
	MapMarker.Kind.DOOR: "Objects",
	MapMarker.Kind.LEVER: "Objects",
	MapMarker.Kind.PASSAGE: "Objects",
	MapMarker.Kind.REINFORCEMENT_POINT: "ReinforcementPoints",
	MapMarker.Kind.DARKNESS_SOURCE: "DarknessSources",
}

## Each parent of [constant GROUPS] once.
const GROUP_NAMES: PackedStringArray = [
	"EnemySlots", "Objects", "ReinforcementPoints", "DarknessSources",
]

## The marker layer's name in a map scene; [MapLoader] reads every tile layer but the terrain.
const MARKER_LAYER: StringName = &"Markers"

## The name stem of each kind of marker node, numbered from 1 in the order the data lists them.
const NAME_STEMS: Dictionary[MapMarker.Kind, String] = {
	MapMarker.Kind.ENEMY_SLOT: "EnemySlot",
	MapMarker.Kind.DOOR: "Door",
	MapMarker.Kind.LEVER: "Lever",
	MapMarker.Kind.PASSAGE: "Passage",
	MapMarker.Kind.REINFORCEMENT_POINT: "Point",
	MapMarker.Kind.DARKNESS_SOURCE: "DarknessSource",
}

# ASSUMPTION: every enemy slot's position variance is 2 tiles, as the M1 map's; setup doesn't
# read it yet (P05).
const SLOT_VARIANCE: int = 2

const ROUT: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
const LEADER: CombatMapDefinition.Objective = CombatMapDefinition.Objective.DEFEAT_LEADER
const BOSS: CombatMapDefinition.Objective = CombatMapDefinition.Objective.DEFEAT_BOSS
const SEIZE: CombatMapDefinition.Objective = CombatMapDefinition.Objective.SEIZE
const SURVIVE: CombatMapDefinition.Objective = CombatMapDefinition.Objective.SURVIVE
const DEFEND: CombatMapDefinition.Objective = CombatMapDefinition.Objective.DEFEND

const ROUT_PAR_NOTE: PackedStringArray = [
	"ASSUMPTION: turn par 5, as M1's (the middle of game-vision.md's standard target, 4-6), until",
	"playtesting measures a clean clear (par = its turns + 1).",
]
const LEADER_PAR_NOTE: PackedStringArray = [
	"ASSUMPTION: turn par 4, the low end of game-vision.md's standard target (4-6), since "
			+ "Defeat the",
	"Leader is for very short fights, until playtesting measures a clean clear "
			+ "(par = its turns + 1).",
]
const HOLD_PAR_NOTE: PackedStringArray = [
	"ASSUMPTION: turn par 5, below survive_turns, so only an early end (no enemy left and every",
	"reinforcement point closed) earns the speed bonus; waiting it out still wins.",
]
const HOLD_TURNS_NOTE: PackedStringArray = [
	"ASSUMPTION: 6 turns, a first value (Godot_FE's Survive maps used 7-8 on larger maps), until",
	"playtesting sets it.",
]

var _terrain_atlas: Dictionary[String, Vector2i] = {}
var _marker_atlas: Dictionary[String, Vector2i] = {}


func _init() -> void:
	var tile_set: TileSet = load(TILE_SET_PATH) as TileSet
	if tile_set == null or not _read_atlas(tile_set):
		push_error("gen_maps: no greybox tile set atlas - %s" % [TILE_SET_PATH])
		quit(1)
		return
	var only: PackedStringArray = OS.get_cmdline_user_args()
	var failed: int = 0
	for spec: MapSpec in _maps():
		if only.is_empty() or only.has(spec.id):
			if not _build(tile_set, spec):
				failed += 1
	quit(1 if failed > 0 else 0)


# Fills the atlas lookups from the tile set's custom data; false when it has no atlas source.
func _read_atlas(tile_set: TileSet) -> bool:
	var source: TileSetAtlasSource = tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		return false
	for index: int in source.get_tiles_count():
		var coords: Vector2i = source.get_tile_id(index)
		var data: TileData = source.get_tile_data(coords, 0)
		var terrain_id: Variant = data.get_custom_data(MapLoader.TERRAIN_DATA)
		var marker_name: Variant = data.get_custom_data(MapLoader.MARKER_DATA)
		if terrain_id is String and not (terrain_id as String).is_empty():
			_terrain_atlas[terrain_id as String] = coords
		if marker_name is String and not (marker_name as String).is_empty():
			_marker_atlas[marker_name as String] = coords
	return true


# Builds or updates one map's scene and definition and checks it; false on any failure.
func _build(tile_set: TileSet, spec: MapSpec) -> bool:
	var scene_path: String = "%s/%s.tscn" % [spec.folder, spec.id]
	var definition_path: String = "%s/%s.tres" % [spec.folder, spec.id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(spec.folder))
	# Loaded before the scene is saved: the resources it references keep their ids in this file.
	var definition: CombatMapDefinition = null
	if ResourceLoader.exists(definition_path):
		definition = load(definition_path) as CombatMapDefinition
	var root: Node2D = _scene_root(scene_path, spec)
	if root == null:
		return false
	var problems: PackedStringArray = []
	var terrain: TileMapLayer = _layer(root, MapLoader.TERRAIN_LAYER, tile_set)
	_paint(terrain, spec.terrain, TERRAIN_CHARS, _terrain_atlas, false, problems)
	var markers: TileMapLayer = _layer(root, MARKER_LAYER, tile_set)
	_paint(markers, spec.markers, MARKER_CHARS, _marker_atlas, true, problems)
	_place_marker_nodes(root, terrain, spec)
	var scene: PackedScene = PackedScene.new()
	var error: Error = scene.pack(root)
	root.free()
	if error == OK:
		error = ResourceSaver.save(scene, scene_path)
	if error != OK or not problems.is_empty():
		push_error("gen_maps: %s not built - %s %s" % [spec.id, error_string(error), problems])
		return false
	if definition == null:
		definition = CombatMapDefinition.new()
		definition.scene = ResourceLoader.load(
				scene_path, "", ResourceLoader.CACHE_MODE_REPLACE
		) as PackedScene
	definition.id = spec.id
	definition.combat_type = spec.combat_type
	definition.objective = spec.objective
	definition.turn_par = spec.turn_par
	definition.survive_turns = spec.survive_turns
	error = ResourceSaver.save(definition, definition_path)
	if error == OK:
		error = _write_notes(definition_path, spec.notes)
	if error != OK:
		push_error("gen_maps: %s definition not saved - %s" % [spec.id, error_string(error)])
		return false
	return _check(definition, scene_path)


# The map's scene root: the saved scene's, so its nodes keep their ids, or a new one.
func _scene_root(scene_path: String, spec: MapSpec) -> Node2D:
	var root: Node2D = null
	if ResourceLoader.exists(scene_path):
		var saved: PackedScene = load(scene_path) as PackedScene
		if saved != null:
			root = saved.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		if root == null:
			push_error("gen_maps: %s can't be opened - %s" % [spec.id, scene_path])
			return null
	else:
		root = Node2D.new()
	root.name = spec.node_name
	return root


# The tile layer layer_name under root, created when missing, with every cell cleared.
func _layer(root: Node2D, layer_name: StringName, tile_set: TileSet) -> TileMapLayer:
	var layer: TileMapLayer = root.get_node_or_null(NodePath(layer_name)) as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = layer_name
		root.add_child(layer)
		layer.owner = root
	layer.tile_set = tile_set
	layer.clear()
	return layer


# Paints rows onto layer in row-major order, one tile per character of chars; with skip_blank,
# "." and " " paint nothing. An unknown character is a problem.
func _paint(
		layer: TileMapLayer,
		rows: PackedStringArray,
		chars: Dictionary[String, String],
		atlas: Dictionary[String, Vector2i],
		skip_blank: bool,
		problems: PackedStringArray
) -> void:
	for y: int in rows.size():
		for x: int in rows[y].length():
			var character: String = rows[y][x]
			if skip_blank and (character == "." or character == " "):
				continue
			if not chars.has(character) or not atlas.has(chars[character]):
				problems.append("unknown \"%s\" at (%d, %d) on %s" % [character, x, y, layer.name])
				continue
			layer.set_cell(Vector2i(x, y), 0, atlas[chars[character]])


# Adds, updates and removes the marker nodes so the scene holds exactly spec's, in its order.
func _place_marker_nodes(root: Node2D, terrain: TileMapLayer, spec: MapSpec) -> void:
	var wanted: Dictionary[String, PackedStringArray] = {}
	for node_spec: MarkerSpec in spec.nodes:
		var group_name: String = GROUPS[node_spec.kind]
		var group: Node2D = root.get_node_or_null(NodePath(group_name)) as Node2D
		if group == null:
			group = Node2D.new()
			group.name = group_name
			root.add_child(group)
			group.owner = root
		var marker: MapMarker = group.get_node_or_null(NodePath(node_spec.node_name)) as MapMarker
		if marker == null:
			marker = MapMarker.new()
			marker.name = node_spec.node_name
			group.add_child(marker)
			marker.owner = root
		node_spec.apply(marker, terrain)
		if not wanted.has(group_name):
			wanted[group_name] = PackedStringArray()
		wanted[group_name].append(node_spec.node_name)
	for group_name: String in GROUP_NAMES:
		var group: Node = root.get_node_or_null(NodePath(group_name))
		if group == null:
			continue
		var kept: PackedStringArray = []
		if wanted.has(group_name):
			kept = wanted[group_name]
		for child: Node in group.get_children():
			if child is MapMarker and not kept.has(String(child.name)):
				group.remove_child(child)
				child.free()
		if group.get_child_count() == 0:
			root.remove_child(group)
			group.free()


# Writes each note's lines, as "; " comments, above the line that sets its property.
func _write_notes(path: String, notes: Dictionary[String, PackedStringArray]) -> Error:
	if notes.is_empty():
		return OK
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return FileAccess.get_open_error()
	var lines: PackedStringArray = text.split("\n")
	var written: PackedStringArray = []
	for line: String in lines:
		for property: String in notes:
			if line.begins_with(property + " = "):
				for note: String in notes[property]:
					written.append("; " + note)
		written.append(line)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(written))
	file.close()
	return OK


# Runs MapCheck on the saved map, read fresh from disk, and prints the map's line.
func _check(definition: CombatMapDefinition, scene_path: String) -> bool:
	var fresh: CombatMapDefinition = definition.duplicate() as CombatMapDefinition
	fresh.scene = ResourceLoader.load(
			scene_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var layout: MapLayout = MapLoader.load_layout(fresh)
	if layout == null:
		push_error("gen_maps: %s doesn't load" % [definition.id])
		return false
	var failures: Array[MapCheck.Failure] = MapCheck.check(fresh, layout)
	print("%s: %s, %d enemy slots, %d deployment tiles, check %s" % [
		definition.id,
		layout.get_rect().size,
		layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT).size(),
		layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT).size(),
		"PASS" if failures.is_empty() else "FAIL\n" + MapCheck.describe(failures),
	])
	return failures.is_empty()


# Every map of the set, standard maps first.
func _maps() -> Array[MapSpec]:
	var maps: Array[MapSpec] = []
	maps.append_array(_standard_maps())
	maps.append_array(_key_maps())
	return maps


func _standard_maps() -> Array[MapSpec]:
	var crossroads: MapSpec = MapSpec.standard("crossroads", "Crossroads", ROUT, 5, ROUT_PAR_NOTE)
	crossroads.terrain = PackedStringArray([
		"F.T..=.F.T",
		".....=.H..",
		"T.F..=...F",
		"==========",
		"..T..=..F.",
		".H...=....",
		"..F..=.T..",
		"T....=....",
	])
	crossroads.markers = PackedStringArray([
		"..........",
		".......h..",
		"..........",
		"........w.",
		"..........",
		".h...w....",
		"dddd......",
		"dddd......",
	])
	crossroads.slots([[1, 0, "A"], [6, 0, "A"], [2, 1, "A"], [8, 1, "B"], [1, 2, "B"],
			[8, 2, ""], [7, 4, ""]])
	crossroads.sources([[5, 7, 0], [9, 6, 1], [9, 7, 1], [0, 3, 2]])

	var river_ford: MapSpec = MapSpec.standard("river_ford", "RiverFord", ROUT, 5, ROUT_PAR_NOTE)
	river_ford.terrain = PackedStringArray([
		"F.T.....FF",
		"..F..F....",
		".T.....T..",
		"~~B~~~~B~~",
		"~~B~~~~B~~",
		"..T....F..",
		".F..,....T",
		"....T.....",
	])
	river_ford.markers = PackedStringArray([
		".........c",
		"..........",
		"......k.k.",
		"..........",
		"..........",
		"..........",
		"...dddd...",
		"...dddd...",
	])
	river_ford.slots([[2, 0, "A"], [8, 0, "A"], [0, 1, "A"], [5, 1, "B"], [9, 1, "B"],
			[1, 2, ""], [7, 2, ""]])
	river_ford.sources([[0, 7, 0], [0, 6, 0], [9, 7, 1], [9, 6, 1]])

	var old_mill: MapSpec = MapSpec.standard("old_mill", "OldMill", ROUT, 5, ROUT_PAR_NOTE)
	old_mill.terrain = PackedStringArray([
		"..F...T..F",
		"TWWWW.....",
		".W__W..F..",
		".W__W.WW.W",
		".WW_W.....",
		"...=...T..",
		".T.=..F...",
		"...=......",
	])
	old_mill.markers = PackedStringArray([
		"..........",
		"..........",
		"..f.......",
		"........s.",
		"..........",
		"..........",
		"....dddd..",
		"....dddd..",
	])
	old_mill.slots([[0, 0, "A"], [3, 0, "A"], [7, 0, "A"], [9, 1, "B"], [0, 2, "B"],
			[6, 2, ""], [8, 2, ""]])
	old_mill.door(Vector2i(3, 4), 0)
	old_mill.lever(Vector2i(5, 1), 0)
	old_mill.sources([[3, 7, 0], [0, 5, 1], [0, 6, 1], [9, 7, 2]])

	var chapel: MapSpec = MapSpec.standard("ruined_chapel", "RuinedChapel", ROUT, 5, ROUT_PAR_NOTE)
	chapel.terrain = PackedStringArray([
		"RR_P__P_RR",
		"R________R",
		"._P_RR_P_.",
		"...R..R...",
		".,......,.",
		"..F.RR.F..",
		"...T..T...",
		".F......F.",
	])
	chapel.markers = PackedStringArray([
		".....o....",
		"....b.....",
		"..........",
		"..........",
		"......b...",
		"..........",
		"...dddd...",
		"...dddd...",
	])
	chapel.slots([[1, 0, "A"], [7, 0, "A"], [2, 1, "A"], [5, 1, "B"], [8, 1, "B"],
			[0, 2, ""], [9, 2, ""]])
	chapel.sources([[0, 6, 0], [0, 7, 0], [9, 6, 1], [9, 7, 1]])

	var camp: MapSpec = MapSpec.standard("bandit_camp", "BanditCamp", LEADER, 4, LEADER_PAR_NOTE)
	camp.terrain = PackedStringArray([
		"T..WOW..T",
		"...W.W...",
		".F.....F.",
		"...T.T...",
		".,.....,.",
		"..F...F..",
		".........",
	])
	camp.markers = PackedStringArray([
		"..k.L.r..",
		".........",
		".........",
		".........",
		".........",
		"..dddd...",
		"..dddd...",
	])
	camp.slots([[1, 0, "A"], [7, 0, "A"], [4, 1, "A"], [1, 2, "B"], [7, 2, "B"],
			[3, 3, ""], [5, 3, ""]])
	camp.sources([[0, 5, 0], [0, 6, 0], [8, 5, 1], [8, 6, 1]])

	var post: MapSpec = MapSpec.standard("watch_post", "WatchPost", LEADER, 4, LEADER_PAR_NOTE)
	post.terrain = PackedStringArray([
		".T.WOW.T.",
		".K.W_W.K.",
		"F..W_W..F",
		".........",
		".T.F..FT.",
		".H.......",
		"....T....",
	])
	post.markers = PackedStringArray([
		"....L....",
		".........",
		".........",
		".........",
		".........",
		".h.dddd..",
		"...dddd..",
	])
	post.slots([[1, 0, "A"], [7, 0, "A"], [2, 1, "A"], [6, 1, "B"], [0, 2, "B"],
			[8, 2, ""], [1, 4, ""]])
	post.door(Vector2i(4, 2), 0)
	post.lever(Vector2i(7, 3), 0)
	post.sources([[0, 5, 0], [0, 6, 0], [8, 5, 1], [8, 6, 1]])
	return [crossroads, river_ford, old_mill, chapel, camp, post]


# Every key map leaves the leader slot ("L") for its mini-boss (P05 EN8).
func _key_maps() -> Array[MapSpec]:
	var hall: MapSpec = MapSpec.key("hall", "Hall", BOSS, 8, PackedStringArray([
		"ASSUMPTION: turn par 8, inside game-vision.md's key target (7-10), until playtesting",
		"measures a clean clear (par = its turns + 1).",
	]))
	hall.terrain = PackedStringArray([
		"W__W_PYP_W.F",
		"W__W_____W..",
		"W__W_P_P_WT.",
		"WW_W______..",
		"...._____W..",
		"...._____WF.",
		".T...==.....",
		"..F......T..",
		"....T..T....",
		"F..........F",
	])
	hall.markers = PackedStringArray([
		".c....L.....",
		"............",
		"............",
		"............",
		"....b...b...",
		"............",
		"............",
		"............",
		"....dddd....",
		"....dddd....",
	])
	hall.slots([[4, 0, "A"], [8, 0, "A"], [6, 1, "A"], [10, 1, "B"], [5, 3, "B"],
			[7, 3, ""], [10, 5, ""]])
	hall.door(Vector2i(2, 3), -1)
	hall.passage(Vector2i(0, 6), 0)
	hall.passage(Vector2i(11, 1), 0)
	hall.point(Vector2i(11, 3), [3])
	hall.sources([[0, 8, 0], [11, 8, 1], [0, 4, 2], [0, 5, 2]])

	var gatehouse: MapSpec = MapSpec.key("gatehouse", "Gatehouse", SEIZE, 7, PackedStringArray([
		"ASSUMPTION: turn par 7, the low end of game-vision.md's key target (7-10), until",
		"playtesting measures a clean clear (par = its turns + 1).",
	]))
	gatehouse.terrain = PackedStringArray([
		".F..__G__.F.",
		"...._____...",
		"WWWWW__WWW.W",
		"..T......T..",
		".,...==...,.",
		"F....==....F",
		"...T.==.T...",
		".....==.....",
		".F..T==T..F.",
		".....==.....",
	])
	gatehouse.markers = PackedStringArray([
		".....LZ.....",
		"............",
		"..........s.",
		"............",
		"............",
		"............",
		"............",
		"............",
		"....dddd....",
		"....dddd....",
	])
	gatehouse.slots([[1, 0, "A"], [9, 0, "A"], [6, 1, "A"], [10, 1, "B"], [2, 3, "B"],
			[9, 3, ""], [11, 4, ""]])
	gatehouse.door(Vector2i(5, 2), 0, Vector2i(2, 1))
	gatehouse.lever(Vector2i(3, 4), 0)
	gatehouse.lever(Vector2i(8, 1), 0)
	gatehouse.point(Vector2i(11, 0), [3])
	gatehouse.sources([[0, 9, 0], [11, 9, 1], [0, 6, 2], [0, 7, 2]])

	var hilltop: MapSpec = MapSpec.key("hilltop", "Hilltop", SURVIVE, 5, HOLD_PAR_NOTE)
	hilltop.hold_for(6, HOLD_TURNS_NOTE)
	hilltop.terrain = PackedStringArray([
		".F..T..T..F.",
		"............",
		"T..K....K..T",
		"............",
		"..MM....MM..",
		"..M......M..",
		".H..OQQO..H.",
		"............",
		".....,,.....",
		"F..........F",
	])
	hilltop.markers = PackedStringArray([
		"......L.....",
		"............",
		"............",
		"...k....k...",
		"............",
		"............",
		".h........h.",
		"....dddd....",
		"....dddd....",
		"............",
	])
	hilltop.slots([[1, 0, "A"], [10, 0, "A"], [4, 1, "A"], [8, 1, "B"], [0, 2, "B"],
			[3, 2, ""], [11, 2, ""]])
	hilltop.point(Vector2i(0, 4), [2])
	hilltop.point(Vector2i(11, 4), [4])

	var village: MapSpec = MapSpec.key("village", "Village", DEFEND, 5, HOLD_PAR_NOTE)
	village.hold_for(6, HOLD_TURNS_NOTE)
	village.terrain = PackedStringArray([
		"F..T.==.T..F",
		".....==.....",
		".T...==...T.",
		"============",
		"..H..==..H..",
		".....==.....",
		".F...HH...F.",
		".....==.....",
		"...T.==.T...",
		".....==.....",
	])
	village.markers = PackedStringArray([
		"....L.......",
		"............",
		".....ww.....",
		"............",
		"..h......h..",
		"............",
		".....Xh.....",
		"....dddd....",
		"....dddd....",
		"............",
	])
	village.slots([[0, 0, "A"], [3, 0, "A"], [11, 0, "A"], [3, 1, "B"], [8, 1, "B"],
			[1, 2, ""], [10, 2, ""]])
	village.point(Vector2i(0, 5), [2])
	village.point(Vector2i(11, 5), [4])
	return [hall, gatehouse, hilltop, village]


## One map's data: what [method _build] writes.
class MapSpec:
	extends RefCounted

	## The definition's id and the files' base name.
	var id: String = ""
	## The scene root's name.
	var node_name: String = ""
	## Where the scene and definition go.
	var folder: String = ""
	var combat_type: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.STANDARD
	var objective: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
	var turn_par: int = 0
	## [b]0:[/b] not a Survive or Defend map.
	var survive_turns: int = 0
	## One string per row, one character per tile ([constant TERRAIN_CHARS]).
	var terrain: PackedStringArray = []
	## One string per row, one character per tile ([constant MARKER_CHARS]).
	var markers: PackedStringArray = []
	## The marker nodes, in the order each kind is numbered.
	var nodes: Array[MarkerSpec] = []
	## Comment lines written above a definition property, by property name.
	var notes: Dictionary[String, PackedStringArray] = {}

	## A standard map in maps/standard.
	static func standard(
			map_id: String,
			root_name: String,
			goal: CombatMapDefinition.Objective,
			par: int,
			par_note: PackedStringArray
	) -> MapSpec:
		var spec: MapSpec = MapSpec.new()
		spec.id = map_id
		spec.node_name = root_name
		spec.folder = STANDARD_FOLDER
		spec.objective = goal
		spec.turn_par = par
		spec.notes["turn_par"] = par_note
		return spec

	## A key map in maps/key.
	static func key(
			map_id: String,
			root_name: String,
			goal: CombatMapDefinition.Objective,
			par: int,
			par_note: PackedStringArray
	) -> MapSpec:
		var spec: MapSpec = MapSpec.standard(map_id, root_name, goal, par, par_note)
		spec.folder = KEY_FOLDER
		spec.combat_type = CombatMapDefinition.CombatType.KEY
		return spec

	## Survive and Defend: the turns to hold, with its note.
	func hold_for(turns: int, note: PackedStringArray) -> void:
		survive_turns = turns
		notes["survive_turns"] = note

	## Enemy slots from [code][x, y, group slot][/code] entries, numbered in this order.
	func slots(entries: Array[Array]) -> void:
		for entry: Array in entries:
			var tile: Vector2i = Vector2i(entry[0] as int, entry[1] as int)
			var node_spec: MarkerSpec = _add(MapMarker.Kind.ENEMY_SLOT, tile)
			node_spec.group_slot = entry[2] as String
			node_spec.variance = SLOT_VARIANCE

	## Darkness source tiles from [code][x, y, candidate][/code] entries; tiles with the same
	## candidate form one source.
	func sources(entries: Array[Array]) -> void:
		for entry: Array in entries:
			var tile: Vector2i = Vector2i(entry[0] as int, entry[1] as int)
			_add(MapMarker.Kind.DARKNESS_SOURCE, tile).group_id = entry[2] as int

	func door(tile: Vector2i, lever_group: int, size: Vector2i = Vector2i.ONE) -> void:
		var node_spec: MarkerSpec = _add(MapMarker.Kind.DOOR, tile)
		node_spec.group_id = lever_group
		node_spec.door_size = size

	func lever(tile: Vector2i, lever_group: int) -> void:
		_add(MapMarker.Kind.LEVER, tile).group_id = lever_group

	func passage(tile: Vector2i, pair: int) -> void:
		_add(MapMarker.Kind.PASSAGE, tile).pair_id = pair

	func point(tile: Vector2i, turns: Array[int]) -> void:
		_add(MapMarker.Kind.REINFORCEMENT_POINT, tile).arrival_turns = turns

	func _add(kind: MapMarker.Kind, tile: Vector2i) -> MarkerSpec:
		var count: int = 1
		for node_spec: MarkerSpec in nodes:
			if node_spec.kind == kind:
				count += 1
		var added: MarkerSpec = MarkerSpec.new()
		added.kind = kind
		added.tile = tile
		added.node_name = "%s%d" % [NAME_STEMS[kind], count]
		nodes.append(added)
		return added


## One [MapMarker] node's data; each kind reads only its own fields, as [MapMarker] does.
class MarkerSpec:
	extends RefCounted

	var kind: MapMarker.Kind = MapMarker.Kind.ENEMY_SLOT
	var node_name: String = ""
	var tile: Vector2i = Vector2i.ZERO
	var variance: int = 0
	var group_slot: String = ""
	var group_id: int = -1
	var pair_id: int = -1
	var door_size: Vector2i = Vector2i.ONE
	var arrival_turns: Array[int] = []

	## Sets [param marker]'s exports and puts it on [member tile] of [param terrain].
	func apply(marker: MapMarker, terrain: TileMapLayer) -> void:
		marker.position = terrain.map_to_local(tile)
		marker.kind = kind
		marker.variance_tiles = variance
		marker.group_slot = group_slot
		marker.group_id = group_id
		marker.pair_id = pair_id
		marker.door_size = door_size
		marker.arrival_turns.assign(arrival_turns)
