# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_world.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## A test map for the darkness cases: a [MapLayout] from rows of terrain ids, object spots and
## reinforcement points, a [CombatSession] over it with the objects placed
## ([method MapObjects.place]), and helpers to set up the darkness, flood tiles, open and close
## doors, light braziers, break breakables, place units, register the turn loop's hooks, play
## turns and read the fact log.
##
## Test-only. Terrain comes from the real definitions in [code]res://data/terrain/[/code]. The
## engine runs in verify mode. Enemies Wait: no [constant CombatHooks.Hook.ENEMY_COMMANDS].

## The session; its state holds the darkness in [member CombatState.map].
var session: CombatSession = null

var _layout: MapLayout = null


## [param rows]: one string per row, terrain ids separated by spaces. [param spots]:
## [code][tile, MapLayout.ObjectKind][/code] each. [param points]: reinforcement points,
## [code][tile, arrival turns][/code] each.
func _init(rows: Array[String], spots: Array = [], points: Array = []) -> void:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "darkness"
	var cache: Dictionary[String, MapLayout.Terrain] = {}
	for y: int in rows.size():
		var terrain_ids: PackedStringArray = rows[y].split(" ", false)
		for x: int in terrain_ids.size():
			if not cache.has(terrain_ids[x]):
				cache[terrain_ids[x]] = MapLayout.Terrain.from_definition(
						MapLoader.load_terrain(terrain_ids[x])
				)
			layout.set_terrain(Vector2i(x, y), cache[terrain_ids[x]])
	# Untyped: each spot is an array literal.
	for spot: Variant in spots:
		var entry: Array = spot
		layout.add_marker(
				MapLayout.MarkerKind.OBJECT_SPOT, entry[0] as Vector2i, entry[1] as int
		)
	for point: Variant in points:
		var entry: Array = point
		var marker: MapLayout.Marker = layout.add_marker(
				MapLayout.MarkerKind.REINFORCEMENT_POINT, entry[0] as Vector2i
		)
		var turns: Array = entry[1]
		marker.arrival_turns = PackedInt32Array(turns)
	layout.index_markers()
	_layout = layout
	session = CombatSession.new(
			0,
			PackedInt32Array([0]),
			MapGrid.new(layout),
			ForcedRolls.new(PackedInt32Array()),
			InstanceIdAllocator.new()
	)
	session.engine.verify = true
	MapObjects.place(session)


## The session's state.
func state() -> CombatState:
	return session.state


## The session's engine.
func engine() -> EffectEngine:
	return session.engine


## The state's darkness.
func darkness() -> DarknessState:
	return session.state.map.darkness


## Gives the darkness one active source per entry of [param source_tiles] and the drain
## [param drain].
func set_up(source_tiles: Array, drain: Vector2i) -> void:
	# Untyped: each entry is an array literal of tiles.
	for tiles: Variant in source_tiles:
		var source: DarknessState.Source = DarknessState.Source.new()
		source.tiles.assign(tiles as Array)
		darkness().sources.append(source)
	darkness().drain = drain


## The object on [param tile], destroyed or not; null when there is none.
func object_at(tile: Vector2i) -> MapState.ObjectState:
	for object_id: String in state().map.objects:
		if state().map.objects[object_id].tile == tile:
			return state().map.objects[object_id]
	return null


## Opens or closes the door on [param tile] as a lever does: its state and what it blocks.
func set_door(tile: Vector2i, is_open: bool) -> void:
	var door: MapState.ObjectState = object_at(tile)
	door.is_open = is_open
	state().map.set_blocking(tile, MapState.Blocking.NONE if is_open else MapState.Blocking.ALL)


## Lights or douses the brazier on [param tile].
func set_lit(tile: Vector2i, is_lit: bool) -> void:
	object_at(tile).is_lit = is_lit


## Breaks the breakable on [param tile] as the darkness's erosion does. Returns whether it broke.
func erode(tile: Vector2i) -> bool:
	return MapObjects.erode(engine(), state(), object_at(tile).id)


## Places a unit at full HP, [param max_hp] (20 by default). Returns whether it was placed.
func add_unit(
		id: String, side: CombatFact.CombatSide, tile: Vector2i, max_hp: int = 20
) -> bool:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.side = side
	unit.seat = 0 if side == CombatFact.CombatSide.PLAYER else -1
	unit.tile = tile
	unit.hp = max_hp
	return session.add_unit(unit, {
		CombatValue.Key.HP: float(max_hp),
		CombatValue.Key.STANCE_MAX: 2.0,
		CombatValue.Key.MOVEMENT: 5.0,
	})


## Registers darkness damage ([method Darkness.register_damage]), after any [method register].
func register_damage() -> void:
	Darkness.register_damage(session)


## Sets [param tile]'s layer directly, as waves would have.
func flood(tile: Vector2i, layer: WhileLayerCondition.Layer) -> void:
	darkness().layers[tile] = layer


## Registers the darkness step, then, when [param source] is given, draws the points' waves
## through it and registers [Reinforcements], as [CampaignSession] does.
func register(source: Reinforcements.GroupSource = null) -> void:
	Darkness.register(session)
	if source == null:
		return
	var definition: CombatMapDefinition = CombatMapDefinition.new()
	definition.id = "darkness"
	session.setup = CombatEncounter.EncounterSetup.new()
	session.setup.map = definition
	session.setup.layout = _layout
	var ctx: CombatEncounter.SetupContext = CombatEncounter.SetupContext.new(
			session.setup, -1, null, RngStream.new(1), null
	)
	ctx.step = CombatEncounter.SetupStep.REINFORCEMENT_WAVES
	Reinforcements.draw_waves(ctx, source)
	Reinforcements.register(session, source)


## Submits [param command] and resolves it. Returns its batch.
func send(command: Command) -> CombatSession.FactBatch:
	session.submit(command)
	return session.resolve_next()


## Ends seat 0's turn [param turns] times.
func end_turns(turns: int) -> void:
	for i: int in turns:
		send(EndTurnCommand.new(0))


## The facts of [param kinds] in the log, each as "t<turn> <log line>" without its sequence
## prefix, the turn the latest Phase Start's; a [constant CombatFact.Kind.DARKNESS_ADVANCED]
## also ends with "key <source index>". [param from]: the first log index read.
func lines(kinds: Array, from: int = 0) -> Array[String]:
	var found: Array[String] = []
	var turn: int = 0
	var facts: Array[CombatFact] = session.engine.fact_log
	for i: int in facts.size():
		var fact: CombatFact = facts[i]
		if fact.kind == CombatFact.Kind.PHASE_START:
			turn = fact.amount
		if i < from or not kinds.has(fact.kind):
			continue
		var line: String = fact.to_log_line()
		line = line.substr(line.find(" ") + 1)
		if fact.kind == CombatFact.Kind.DARKNESS_ADVANCED:
			line += " key %d" % [fact.key]
		found.append("t%d %s" % [turn, line])
	return found


## Each wave's reach, oldest first, as "8 4 0".
func reaches() -> String:
	var parts: PackedStringArray = []
	for wave: DarknessState.Wave in darkness().waves:
		parts.append(str(wave.reach))
	return " ".join(parts)


## The layers of a row of [param width] tiles at row [param y], as a string such as "1 1 2 0".
func row_layers(y: int, width: int) -> String:
	var parts: PackedStringArray = []
	for x: int in width:
		parts.append(str(darkness().layer_at(Vector2i(x, y))))
	return " ".join(parts)


## [param tiles] as "(x, y)=value" entries, row-major, joined by spaces.
static func describe(tiles: Dictionary[Vector2i, int]) -> String:
	var keys: Array[Vector2i] = []
	keys.assign(tiles.keys())
	keys.sort_custom(MapLayout.is_before)
	var parts: PackedStringArray = []
	for tile: Vector2i in keys:
		parts.append("%s=%d" % [tile, tiles[tile]])
	return " ".join(parts)


## Everything [param on]'s darkness and arrival flag hold, as text: waves (source, reach, tiles
## entered), layers and contacts, each sorted.
static func describe_state(on: CombatState) -> String:
	var darkness: DarknessState = on.map.darkness
	var parts: PackedStringArray = ["arrived %s" % [on.map.has_darkness_arrived]]
	for wave: DarknessState.Wave in darkness.waves:
		var entered: Dictionary[Vector2i, int] = {}
		for tile: Vector2i in wave.entered:
			entered[tile] = 1
		parts.append("wave %d reach %d [%s]" % [wave.source, wave.reach, describe(entered)])
	var layers: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in darkness.layers:
		layers[tile] = darkness.layers[tile]
	parts.append("layers [%s]" % [describe(layers)])
	var ids: Array[String] = []
	ids.assign(darkness.contacts.keys())
	ids.sort()
	for object_id: String in ids:
		parts.append("%s=%d" % [object_id, darkness.contacts[object_id]])
	return "; ".join(parts)


## [param deepened] as "(x, y)>layer@source" entries, in order, joined by spaces.
static func describe_deepened(deepened: Array[DarknessState.Deepening]) -> String:
	var parts: PackedStringArray = []
	for entry: DarknessState.Deepening in deepened:
		parts.append("%s>%d@%d" % [entry.tile, entry.layer, entry.source])
	return " ".join(parts)
