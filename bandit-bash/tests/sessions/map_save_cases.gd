# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_save_cases.gd
# Author:
# Created:  November 3, 2026
# Modified: November 3, 2026
# ==============================================================================

extends RefCounted
## Cases for the map save (combat map plan MP8): [MapState] capture and restore, the
## [CombatMapSection] pair through a [SaveSectionRegistry], Save & Quit mid-phase then resume with
## broken, opened, lit and exploded objects, a closed point, waves left and waiting wave units, a
## mirror following object and reinforcement facts hash for hash, and a dump replayed through them.
##
## Run by [code]tests/sessions/run_all.gd[/code] on its first frame, after the save cases, whose
## [code]Registry[/code] it reuses. Every save goes through JSON, as a file would. Several cases
## feed in bad data on purpose, so errors from them are expected.

# Preloaded scripts used as types (gdscript.md, Naming): fixtures of other case files.
const WireCases = preload("res://tests/sessions/wire_cases.gd")
const SaveCases = preload("res://tests/sessions/save_cases.gd")
const ObjectiveCases = preload("res://tests/map/objective_cases.gd")

const TILE_SET: TileSet = preload("res://maps/greybox_tile_set.tres")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const COMBAT: SaveSection.Block = SaveSection.Block.COMBAT
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const USE: UnitTurnCommand.Action = UnitTurnCommand.Action.USE_OBJECT
const WAIT: UnitTurnCommand.Action = UnitTurnCommand.Action.WAIT

# Any fixed run seed and node: these cases compare runs with each other, never golden numbers.
const RUN_SEED: int = 0x3F9A12C077E1A
const FLOOR: int = 2
const NODE: int = 5

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_map_state_round_trip()
	_test_map_state_refusals()
	_test_save_and_resume_same_map()
	_test_mirror_follows_objects_and_points()
	_test_dump_replays_objects_and_points()
	_test_section_versions_and_pairing()


func _test_map_state_round_trip() -> void:
	var host: Outpost = Outpost.new()
	host.play_first_turn()
	var map: MapState = host.session.state.map
	var text: String = JSON.stringify(map.capture())
	var back: MapState = MapState.new()
	var restored: Error = back.restore(WireCases.Kit.through_json(map.capture()) as Dictionary)
	var keg_tile: Vector2i = Outpost.KEGS[0]
	_check.call("map state: every part survives JSON, numbers as ints", (
			restored == OK
			and JSON.stringify(back.capture()) == text
			and back.points[1].waiting.size() == 1
			and back.contents.size() == map.contents.size()
			and back.found.size() == 1
	), "%s; %s" % [error_string(restored), JSON.stringify(back.capture())])
	_check.call("map state: blocking is rebuilt from the objects", (
			back.blocking_at(keg_tile) == MapState.Blocking.NONE
			and back.blocking_at(Outpost.DEBRIS) == MapState.Blocking.NONE
			and map.blocking_at(keg_tile) == MapState.Blocking.NONE
	))
	var fresh: Outpost = Outpost.new()
	var intact: MapState = MapState.new()
	intact.restore(WireCases.Kit.through_json(fresh.session.state.map.capture()) as Dictionary)
	_check.call("map state: an unbroken keg blocks all but fliers after a restore", (
			intact.blocking_at(keg_tile) == MapState.Blocking.ALL_BUT_FLIERS
			and intact.blocks(keg_tile, CombatGrid.MovementType.DEFAULT)
			and not intact.blocks(keg_tile, CombatGrid.MovementType.FLIER)
	))


func _test_map_state_refusals() -> void:
	var host: Outpost = Outpost.new()
	host.play_first_turn()
	var good: Dictionary = WireCases.Kit.through_json(host.session.state.map.capture())
	var no_entities: Dictionary = good.duplicate(true)
	no_entities.erase("entities")
	var repeated: Dictionary = good.duplicate(true)
	var objects: Array = (repeated["entities"] as Dictionary)["objects"]
	objects.append((objects[0] as Dictionary).duplicate(true))
	var bad_tile: Dictionary = good.duplicate(true)
	var first: Dictionary = ((bad_tile["entities"] as Dictionary)["objects"] as Array)[0]
	first["tile"] = [1.5, 0]
	var overdue: Dictionary = good.duplicate(true)
	var point: Dictionary = ((overdue["combat_map"] as Dictionary)["points"] as Array)[1]
	point["sent"] = 9
	var kind: Dictionary = good.duplicate(true)
	var second: Dictionary = ((kind["entities"] as Dictionary)["objects"] as Array)[1]
	second["kind"] = "CATAPULT"
	var results: Array[Error] = []
	var target: MapState = host.session.state.map.copy()
	var before: String = JSON.stringify(target.capture())
	for data: Dictionary in [no_entities, repeated, bad_tile, overdue, kind]:
		results.append(target.restore(data))
	_check.call("map state: a missing part, a repeat, a bad tile, waves overdue, a kind refused", (
			results == [
				ERR_INVALID_DATA, ERR_INVALID_DATA, ERR_INVALID_DATA, ERR_INVALID_DATA,
				ERR_INVALID_DATA,
			]
			and JSON.stringify(target.capture()) == before
	), str(results))


# Save & Quit mid-phase on turn 2 after every kind of object change and a wave that overflowed,
# then resume into a battle rebuilt as Begin set it up: the same map, then the same facts.
func _test_save_and_resume_same_map() -> void:
	var host: Outpost = Outpost.new()
	host.play_first_turn()
	host.act(UnitTurnCommand.new(0, host.lighter, WAIT, ""))
	var saved: Dictionary = host.save()
	var saved_at: int = host.session.last_seq()
	var saved_map: String = JSON.stringify(host.session.snapshot()["map"])

	var resumed: Outpost = Outpost.new(saved)
	var map: MapState = resumed.session.state.map
	var waiting: Array[Dictionary] = map.points[1].waiting
	_check.call("resume: the map loads into the rebuilt battle", (
			resumed.load_error == OK
			and JSON.stringify(resumed.session.snapshot()["map"]) == saved_map
			and resumed.session.state_hash() == host.session.state_hash()
	), "%s; %s" % [error_string(resumed.load_error), JSON.stringify(map.capture())])
	_check.call("resume: broken, opened, lit and exploded objects, with the loot", (
			map.objects_at(Outpost.DEBRIS).is_empty()
			and not resumed.session.state.has_unit(host.object_at(Outpost.DEBRIS))
			and map.object(host.object_at(Outpost.CHEST)).is_used
			and (map.found.get(0, []) as Array).size() == 1
			and map.object(host.object_at(Outpost.BRAZIER)).is_lit
			and host.kegs_destroyed() == 3
			and resumed.kegs_destroyed() == 3
			and resumed.session.state.unit(host.opener).pouch_item_id.is_empty()
	))
	_check.call("resume: a closed point, a wave left with its group, a unit waiting", (
			map.points[0].is_closed
			and map.points[1].sent == 1
			and map.points[1].waves.size() == 2
			and Reinforcements.waves_left(resumed.session.state, 1) == 2
			and waiting.size() == 1
			and waiting[0].get(Reinforcements.UNIT_TYPE_KEY, "") == "Bandit"
	), JSON.stringify(map.capture()["combat_map"]))
	_check.call("resume: Survive's count goes on", (
			Objectives.turns_early(resumed.session) == Objectives.turns_early(host.session)
			and Objectives.turns_early(host.session) == Outpost.SURVIVE_TURNS - 1
			and not resumed.session.is_finished
	))

	for field: Outpost in [host, resumed]:
		field.free_pocket(2)
		field.act(EndTurnCommand.new(0))
		field.act(UnitTurnCommand.new(0, field.breaker, WAIT, ""))
	var host_facts: Array = host.facts_after(saved_at)
	var resumed_facts: Array = resumed.facts_after(saved_at)
	_check.call("resume: playing on gives the same facts, the waiting unit's arrival included", (
			not host_facts.is_empty()
			and JSON.stringify(resumed_facts) == JSON.stringify(host_facts)
			and host.rejected == 0
			and resumed.rejected == 0
			and host.session.state.map.points[1].waiting.is_empty()
			and resumed.session.state_hash() == host.session.state_hash()
			and JSON.stringify(resumed.session.snapshot()["map"])
			== JSON.stringify(host.session.snapshot()["map"])
	), "%d and %d facts" % [host_facts.size(), resumed_facts.size()])


# A mirror loaded once at battle start follows every object and reinforcement fact, hash for hash
# after every batch; it follows the points' closing and waves sent, but not their waiting units.
func _test_mirror_follows_objects_and_points() -> void:
	var host: Outpost = Outpost.new()
	var mirror: CombatSession = host.bare_session()
	var loaded: Error = mirror.load_snapshot(
			WireCases.Kit.through_json(host.session.snapshot()) as Dictionary
	)
	var sent: int = host.batches.size()
	host.play_first_turn()
	host.free_pocket(2)
	host.act(EndTurnCommand.new(0))
	var results: Array[Error] = []
	for batch: CombatSession.FactBatch in host.batches.slice(sent):
		results.append(mirror.apply_batch(WireCases.Kit.batch_through_json(batch)))
	var host_map: Dictionary = host.session.state.map.capture()
	var mirror_map: Dictionary = mirror.state.map.capture()
	_check.call("mirror: hash for hash through objects, kegs, closing and arrivals", (
			loaded == OK
			and results.size() >= 7
			and results.count(OK) == results.size()
			and mirror.state_hash() == host.session.state_hash()
	), "%s, %s" % [error_string(loaded), results])
	_check.call("mirror: the map objects, the loot and the Pouch match the host's", (
			JSON.stringify(mirror_map["entities"]) == JSON.stringify(host_map["entities"])
			and mirror.state.unit(host.opener).pouch_item_id.is_empty()
			and mirror.state.map.blocking_at(Outpost.KEGS[0]) == MapState.Blocking.NONE
	))
	_check.call("mirror: points closed and waves sent as on the host", (
			mirror.state.map.points[0].is_closed
			and mirror.state.map.points[1].sent == host.session.state.map.points[1].sent
			and mirror.state.map.points[1].sent == 1
	))


# A dump taken after a checkpoint replays the object changes and the overflowing wave, waiting unit
# and all, since the replay resolves the commands again.
func _test_dump_replays_objects_and_points() -> void:
	var host: Outpost = Outpost.new()
	host.session.mark_checkpoint()
	host.play_first_turn()
	var path: String = host.session.debug_dump()
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(path) if not path.is_empty() else ""
	)
	var dump: Dictionary = parsed if parsed is Dictionary else {}
	var again: Outpost = Outpost.new()
	var loaded: Error = again.session.load_snapshot(dump.get("snapshot", {}) as Dictionary)
	for wire: Variant in dump.get("commands", []):
		again.session.submit(Command.from_wire(wire as Array))
	again.session.resolve_queued()
	_check.call("dump: replays the map's objects and points, the waiting unit included", (
			loaded == OK
			and dump.get("complete", false) == true
			and again.session.state_hash() == host.session.state_hash()
			and JSON.stringify(again.session.snapshot()["map"])
			== JSON.stringify(host.session.snapshot()["map"])
			and again.session.state.map.points[1].waiting.size() == 1
	), error_string(loaded))
	if not path.is_empty():
		DirAccess.remove_absolute(path)


func _test_section_versions_and_pairing() -> void:
	var host: Outpost = Outpost.new()
	host.play_first_turn()
	var saved: Dictionary = host.save()
	var map_entry: Dictionary = saved["combat_map"]
	var map_data: Dictionary = map_entry["data"]
	var first_map: Dictionary = (map_data["sessions"] as Array)[0]
	_check.call("section: both keys at version 1, with the map id and its active spots", (
			WireCases.Kit.as_int(map_entry["version"]) == 1
			and WireCases.Kit.as_int((saved["entities"] as Dictionary)["version"]) == 1
			and first_map["map_id"] == Outpost.MAP_ID
			and (first_map["object_spots"] as Array).size() == 6
			and not JSON.stringify(saved["entities"]).contains("\"hp\"")
	), JSON.stringify(first_map))

	var newer_map: Dictionary = saved.duplicate(true)
	(newer_map["combat_map"] as Dictionary)["version"] = 2
	var newer_entities: Dictionary = saved.duplicate(true)
	(newer_entities["entities"] as Dictionary)["version"] = 2
	var zero_map: Dictionary = saved.duplicate(true)
	(zero_map["combat_map"] as Dictionary)["version"] = 0
	var zero_entities: Dictionary = saved.duplicate(true)
	(zero_entities["entities"] as Dictionary)["version"] = 0
	var broken: Dictionary = saved.duplicate(true)
	var broken_map: Dictionary = (
			((broken["combat_map"] as Dictionary)["data"] as Dictionary)["sessions"] as Array
	)[0]
	broken_map["object_spots"] = [0.5]
	var broken_objects: Dictionary = saved.duplicate(true)
	var objects_part: Dictionary = (
			((broken_objects["entities"] as Dictionary)["data"] as Dictionary)["sessions"] as Array
	)[0]
	objects_part["objects"] = "none"
	print("    (errors about refused map sections follow)")
	var results: Array[Error] = []
	var holding: Array[bool] = []
	for sections: Dictionary in [
		newer_map, newer_entities, zero_map, zero_entities, broken, broken_objects,
	]:
		var registry: SaveCases.Registry = SaveCases.Registry.new()
		results.append(registry.sections.restore(COMBAT, sections))
		holding.append(registry.combat_map.is_holding())
	_check.call("section: each refuses a newer version, version 0 and malformed data", (
			results == [
				ERR_FILE_UNRECOGNIZED, ERR_FILE_UNRECOGNIZED, ERR_INVALID_DATA, ERR_INVALID_DATA,
				ERR_INVALID_DATA, ERR_INVALID_DATA,
			]
			and not holding.has(true)
	), str(results))

	var battle: CombatEncounter = Outpost.new().battle
	var loads: Array[Error] = []
	for missing: Array in [["combat_map"], ["entities"], ["combat_map", "entities"]]:
		var partial: Dictionary = saved.duplicate(true)
		for key: Variant in missing:
			partial.erase(key)
		var registry: SaveCases.Registry = SaveCases.Registry.new()
		registry.sections.restore(COMBAT, partial)
		loads.append(registry.combat_map.load_into(battle))
	_check.call("section: one or both missing holds no maps, which restarts from Begin", (
			loads == [ERR_UNCONFIGURED, ERR_UNCONFIGURED, ERR_UNCONFIGURED]
	), str(loads))

	var full: SaveCases.Registry = SaveCases.Registry.new()
	full.sections.restore(COMBAT, saved)
	var recaptured: Dictionary = WireCases.Kit.through_json(
			full.sections.capture(COMBAT, {})
	) as Dictionary
	_check.call("section: held data is saved again unchanged before it is loaded", (
			full.combat_map.is_holding()
			and JSON.stringify(recaptured["combat_map"]) == JSON.stringify(saved["combat_map"])
			and JSON.stringify(recaptured["entities"]) == JSON.stringify(saved["entities"])
	))
	var other: Outpost = Outpost.new({}, "outpost_b")
	print("    (an error about another map follows)")
	_check.call("section: a battle on another map is refused, holding on", (
			full.combat_map.load_into(other.battle) == ERR_INVALID_DATA
			and full.combat_map.is_holding()
	))

	var half: Outpost = Outpost.new()
	var maps_only: SaveCases.Registry = SaveCases.Registry.new()
	maps_only.sections.restore(COMBAT, saved)
	maps_only.combat_state.reset()
	maps_only.combat_state.effects.reset()
	var map_loaded: Error = maps_only.combat_map.load_into(half.battle)
	print("    (an error about a map that disagrees with its units follows)")
	var units_kept: Error = half.battle.load_snapshot(half.battle.snapshot())
	_check.call("session: a map from another moment than its units is refused", (
			map_loaded == OK
			and units_kept == ERR_INVALID_DATA
	), "%s, %s" % [error_string(map_loaded), error_string(units_kept)])


# One map with every object kind MP8 saves, built in code and run through a real encounter: setup
# draws the waves and rolls the chest, objects and points are placed, then six player units (Begin
# places them by hand, as no prep screen or army is needed) and turn 1 opens. Survive for
# SURVIVE_TURNS turns. Built the same way every time, ids included.
#   y0  A . . K K # . B        A: point closed by a unit, turn 3. B: walled pocket point,
#   y1  . R . K . # . .           turns 1 (five units) and 4 (one). K: kegs. #: walls.
#   y2  . . . . . # # #        R: the archer. D: debris; X: its breaker. C: chest (the
#   y3  . X D . . . . .           opener stands on it). Z: brazier; L: its lighter.
#   y4  . . . C L Z . .
class Outpost:
	extends RefCounted

	const MAP_ID: String = "outpost"
	const SURVIVE_TURNS: int = 6
	const ROWS: Array[String] = [
		"plain plain plain plain plain wall plain plain",
		"plain plain plain plain plain wall plain plain",
		"plain plain plain plain plain wall wall wall",
		"plain plain plain plain plain plain plain plain",
		"plain plain plain plain plain plain plain plain",
	]
	const POINT_A: Vector2i = Vector2i(0, 0)
	const POINT_B: Vector2i = Vector2i(7, 0)
	const KEGS: Array[Vector2i] = [Vector2i(3, 1), Vector2i(3, 0), Vector2i(4, 0)]
	const DEBRIS: Vector2i = Vector2i(2, 3)
	const CHEST: Vector2i = Vector2i(3, 4)
	const BRAZIER: Vector2i = Vector2i(5, 4)

	var run: CampaignSession = null
	var battle: CombatEncounter = null
	var session: CombatSession = null
	var layout: MapLayout = null
	var batches: Array[CombatSession.FactBatch] = []
	var rejected: int = 0
	var breaker: String = ""
	var archer: String = ""
	var opener: String = ""
	var lighter: String = ""
	var closer: String = ""
	var key_id: String = ""
	## The result of loading a save, for a resumed battle; OK otherwise.
	var load_error: Error = OK

	var _sections: SaveCases.Registry = null

	## [param saved]: the COMBAT block sections to load once the battle is rebuilt, as a resume
	## does. [param map_id]: the map definition's id.
	func _init(saved: Dictionary = {}, map_id: String = MAP_ID) -> void:
		run = CampaignSession.new(CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0]))
		_sections = SaveCases.Registry.new()
		if saved.is_empty():
			_sections.attach(run)
		else:
			load_error = _sections.sections.restore(COMBAT, saved)
			_sections.rng.attach(run)
			_sections.combat_state.attach(run)
			_sections.combat_map.attach(run)
		var source: Groups = Groups.new()
		var definition: CombatMapDefinition = CombatMapDefinition.new()
		definition.id = map_id
		definition.scene = Outpost.scene()
		definition.objective = CombatMapDefinition.Objective.SURVIVE
		definition.survive_turns = SURVIVE_TURNS
		battle = CombatEncounter.new(FLOOR, NODE, PackedInt32Array([0]), run.ids)
		battle.run_seed = RUN_SEED
		battle.add_setup_step(
				CombatEncounter.SetupStep.REINFORCEMENT_WAVES,
				Reinforcements.draw_waves.bind(source)
		)
		battle.add_setup_step(
				CombatEncounter.SetupStep.CONTAINER_CONTENTS, MapObjects.roll_contents
		)
		var pool: Array[CombatMapDefinition] = [definition]
		battle.run_setup(pool, CombatEncounter.SetupStreams.new(RUN_SEED, FLOOR, NODE))
		var rolls: Dictionary[int, RngStream] = {
			0: run.rng.stream(RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, FLOOR, NODE, 0, -1)),
		}
		battle.open_sessions(rolls)
		run.encounter = battle
		session = battle.get_session(0)
		layout = session.layout
		session.batch_resolved.connect(_on_batch_resolved)
		MapObjects.place(session)
		Reinforcements.register(session, source)
		breaker = _unit("Breaker", Vector2i(1, 3), "breaker")
		archer = _unit("Archer", Vector2i(1, 1), "bow")
		opener = _unit("Opener", CHEST, "sword")
		lighter = _unit("Lighter", Vector2i(4, 4), "sword")
		closer = _unit("Closer", POINT_A, "sword")
		_unit("Reserve", Vector2i(0, 4), "sword")
		key_id = _give_key(opener)
		session.flush("deployment")
		session.open_battle()
		if saved.is_empty():
			return
		# The maps first, then the battle, whose reload carries them (CombatMapSection).
		if load_error == OK:
			load_error = _sections.combat_map.load_into(battle)
		if load_error == OK:
			load_error = _sections.combat_state.load_into(battle)
		# The resume flow sets the battle's id counter again once the battle is rebuilt.
		run.ids.restore((saved["instance_ids"] as Dictionary)["data"] as Dictionary)

	## Turn 1: the debris broken, the chest opened with the key (its last use), the brazier lit,
	## the first keg shot (the other two explode with it), a unit waiting on point A; then the end
	## of the turn: point A closes, and point B's five arrive in a pocket of four, one waiting.
	func play_first_turn() -> void:
		act(UnitTurnCommand.new(0, breaker, ATTACK, object_at(DEBRIS)))
		var open_chest: UnitTurnCommand = UnitTurnCommand.new(0, opener, USE, object_at(CHEST))
		open_chest.item_id = key_id
		act(open_chest)
		act(UnitTurnCommand.new(0, lighter, USE, object_at(BRAZIER)))
		act(UnitTurnCommand.new(0, archer, ATTACK, object_at(KEGS[0])))
		act(UnitTurnCommand.new(0, closer, WAIT, ""))
		act(EndTurnCommand.new(0))

	## Defeats [param count] of the units in point B's pocket, nearest the walls first, so the
	## waiting unit finds room.
	func free_pocket(count: int) -> void:
		var freed: Array[String] = []
		for tile: Vector2i in [Vector2i(6, 1), Vector2i(7, 1), Vector2i(6, 0)]:
			var occupant: String = session.state.occupant_at(tile)
			if not occupant.is_empty() and freed.size() < count:
				freed.append(occupant)
		act(ObjectiveCases.DefeatFixture.new(freed, breaker))

	func act(command: Command) -> void:
		session.submit(command)
		session.resolve_queued()

	## The COMBAT block's sections now, through a registry and JSON, as a combat file holds them.
	func save() -> Dictionary:
		return WireCases.Kit.through_json(_sections.sections.capture(COMBAT, {})) as Dictionary

	## The id of the object on [param tile], destroyed or not; empty for none.
	func object_at(tile: Vector2i) -> String:
		for object_id: String in session.state.map.objects:
			if session.state.map.objects[object_id].tile == tile:
				return object_id
		return ""

	## How many powder kegs are destroyed.
	func kegs_destroyed() -> int:
		var count: int = 0
		for keg: MapState.ObjectState in session.state.map.objects_of(
				MapLayout.ObjectKind.POWDER_KEG
		):
			count += 1 if keg.is_destroyed else 0
		return count

	## A session on this map with nothing on it: a client's mirror before its snapshot.
	func bare_session() -> CombatSession:
		return CombatSession.new(
				0,
				PackedInt32Array([0]),
				MapGrid.new(layout),
				LiveRolls.new(RngStream.new(0)),
				InstanceIdAllocator.new()
		)

	## Every fact after [param seq], as wire arrays.
	func facts_after(seq: int) -> Array:
		var wires: Array = []
		for fact: CombatFact in session.engine.fact_log:
			if fact.seq > seq:
				wires.append(fact.to_wire())
		return wires

	## The map scene, built in code: a Terrain layer from [constant ROWS], a marker layer with the
	## objects, and a [MapMarker] node per reinforcement point.
	static func scene() -> PackedScene:
		var root: Node2D = Node2D.new()
		var terrain: TileMapLayer = TileMapLayer.new()
		terrain.name = MapLoader.TERRAIN_LAYER
		terrain.tile_set = TILE_SET
		root.add_child(terrain)
		for y: int in ROWS.size():
			var terrain_ids: PackedStringArray = ROWS[y].split(" ", false)
			for x: int in terrain_ids.size():
				terrain.set_cell(
						Vector2i(x, y), 0, Outpost.atlas_of(MapLoader.TERRAIN_DATA, terrain_ids[x])
				)
		var markers: TileMapLayer = TileMapLayer.new()
		markers.name = &"Markers"
		markers.tile_set = TILE_SET
		root.add_child(markers)
		var spots: Dictionary[Vector2i, String] = {
			DEBRIS: "wooden_debris", CHEST: "chest", BRAZIER: "brazier",
		}
		for keg: Vector2i in KEGS:
			spots[keg] = "powder_keg"
		for tile: Vector2i in spots:
			markers.set_cell(tile, 0, Outpost.atlas_of(MapLoader.MARKER_DATA, spots[tile]))
		var points: Dictionary[Vector2i, Array] = {POINT_A: [3], POINT_B: [1, 4]}
		for tile: Vector2i in points:
			var node: MapMarker = MapMarker.new()
			node.kind = MapMarker.Kind.REINFORCEMENT_POINT
			var turns: Array[int] = []
			turns.assign(points[tile])
			node.arrival_turns = turns
			node.position = terrain.map_to_local(tile)
			root.add_child(node)
		for child: Node in root.get_children():
			child.owner = root
		var packed: PackedScene = PackedScene.new()
		packed.pack(root)
		root.free()
		return packed

	## The greybox tile whose custom data [param data_name] is [param value].
	static func atlas_of(data_name: String, value: String) -> Vector2i:
		var atlas: TileSetAtlasSource = TILE_SET.get_source(0) as TileSetAtlasSource
		for i: int in atlas.get_tiles_count():
			var coords: Vector2i = atlas.get_tile_id(i)
			if atlas.get_tile_data(coords, 0).get_custom_data(data_name) == value:
				return coords
		return Vector2i(-1, -1)

	# A player unit of seat 0 on tile holding a preset weapon: "breaker" breaks debris in one
	# attack.
	func _unit(unit_type: String, tile: Vector2i, preset: String) -> String:
		var weapon_id: String = run.ids.next_item_id(preset.capitalize())
		var weapon: CombatState.WeaponStats = WireCases.Kit.weapon(
				weapon_id, "sword" if preset == "breaker" else preset
		)
		if preset == "breaker":
			weapon.damage = 40
		session.state.add_weapon(weapon)
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = run.ids.next_unit_id(unit_type)
		unit.seat = 0
		unit.unit_type = unit_type
		unit.hp = 20
		unit.tile = tile
		unit.equipped_weapon_id = weapon_id
		session.add_unit(unit, WireCases.Kit.bases(20.0))
		return unit.id

	# A key with one use in unit_id's Pouch, as the loadout would make it. Returns its item id.
	func _give_key(unit_id: String) -> String:
		var item_id: String = run.ids.next_item_id("Key")
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = MapObjects.KEY_EFFECT_ID
		definition.charges = 1
		definition.charge_lane = EffectTerms.Lane.CAMPAIGN
		session.engine.register(EffectInstance.new(
				run.ids.next_effect_id("Key"),
				definition,
				EffectOwner.for_item(item_id, unit_id, 0, PLAYER),
				Modifier.SourceKind.POUCH_ITEM
		))
		session.state.unit(unit_id).pouch_item_id = item_id
		return item_id

	func _on_batch_resolved(batch: CombatSession.FactBatch) -> void:
		batches.append(batch)
		rejected += 1 if batch.is_rejected() else 0


# The waves of each point by its tile, the same every draw: point A sends one Bandit on turn 3,
# point B five on turn 1 and a Brute on turn 4. Units have 20 HP, Stance 2 and 5 movement.
class Groups:
	extends Reinforcements.GroupSource

	const TYPES: Dictionary[Vector2i, Dictionary] = {
		Vector2i(0, 0): {3: ["Bandit"]},
		Vector2i(7, 0): {1: ["Bandit", "Bandit", "Bandit", "Bandit", "Bandit"], 4: ["Brute"]},
	}

	func draw_group(stream: RngStream, point: MapLayout.Marker, turn: int) -> Array[Dictionary]:
		var group: Array[Dictionary] = []
		var by_turn: Dictionary = TYPES.get(point.tile, {})
		# Untyped: the fixture's lists are array literals.
		for unit_type: Variant in by_turn.get(turn, []):
			group.append({Reinforcements.UNIT_TYPE_KEY: unit_type, "roll": stream.pick_index(100)})
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
		recruit.bases = WireCases.Kit.bases(20.0)
		return recruit
