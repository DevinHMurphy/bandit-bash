# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_setup.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name DarknessSetup
extends RefCounted
## Setup step 3: which darkness source candidates are active and where the darkness drains, drawn
## once for every map; and the darkness each map starts the battle with.
##
## [method draw] runs on [constant CombatEncounter.SetupStep.DARKNESS_SOURCES] for a map with a
## turn par and a drained objective ([method has_darkness]). It picks [method active_count]
## candidates ([method candidates]) with the shared [code]ENCOUNTER_SETUP[/code] stream, then finds
## the drain ([method drain_for]); a Rout tie draws from the same stream, after the pick. Plain
## data goes under [constant DARKNESS_KEY] in [member CombatEncounter.EncounterSetup.shared]. A
## forced choice (as many candidates as it needs, one tied tile) draws nothing.[br]
## [method place] gives each map's [DarknessState] those sources and that drain, and its
## [member DarknessState.first_release] with Short Wick read then, once the army's effects are
## registered. The setup result is never saved: a battle restarted from Begin draws it again.[br]
## Floodable tiles are read on the map as the battle starts ([method start_state]): doors closed,
## breakables standing, no units. Pure rules code: it draws only from the stream handed to it.
##
## @tutorial(The darkness): docs/design/the-darkness.md
## @tutorial(The darkness plan): docs/plans/2026-11-03-the-darkness.md

## The key of the drawn darkness in [member CombatEncounter.EncounterSetup.shared]: a Dictionary
## with [constant SOURCES_KEY] and, when the map has a drain, [constant DRAIN_KEY]. Absent on a map
## with no darkness.
const DARKNESS_KEY: String = "darkness"

## The active sources in source index order: one Array of [code][x, y][/code] tiles each, in
## [MapLayout] order.
const SOURCES_KEY: String = "sources"

## The drain's tile as [code][x, y][/code]; absent when the map has none.
const DRAIN_KEY: String = "drain"

## Active sources per combat type (the-darkness.md, Values: standard 1; key and boss 2).
const ACTIVE_SOURCES: Dictionary[CombatMapDefinition.CombatType, int] = {
	CombatMapDefinition.CombatType.STANDARD: 1,
	CombatMapDefinition.CombatType.KEY: 2,
	CombatMapDefinition.CombatType.BOSS: 2,
}

## The objectives whose maps already end on a turn count, so they get no darkness
## (the-darkness.md, The drain).
const UNDRAINED: Array[CombatMapDefinition.Objective] = [
	CombatMapDefinition.Objective.SURVIVE,
	CombatMapDefinition.Objective.DEFEND,
]


## Setup step 3: draws the active sources and the drain of the map [param ctx] set up, with its
## shared stream. Writes nothing for a map with no darkness or no candidate. Registered unbound.
static func draw(ctx: CombatEncounter.SetupContext) -> void:
	var definition: CombatMapDefinition = ctx.setup.map
	var layout: MapLayout = ctx.setup.layout
	if layout == null or not has_darkness(definition):
		return
	var found: Array[DarknessState.Source] = candidates(layout)
	if found.is_empty():
		return
	var remaining: Array[int] = []
	for index: int in found.size():
		remaining.append(index)
	var picked: Array[int] = []
	for _drawn: int in mini(active_count(definition.combat_type), found.size()):
		var pick: int = 0 if remaining.size() == 1 else ctx.stream.pick_index(remaining.size())
		picked.append(remaining.pop_at(pick))
	# Source index order follows candidate order, whichever was drawn first.
	picked.sort()
	var sources: Array[DarknessState.Source] = []
	var written: Array = []
	for index: int in picked:
		sources.append(found[index])
		written.append(_tiles_to_data(found[index].tiles))
	var drawn: Dictionary = {SOURCES_KEY: written}
	var drain: Vector2i = drain_for(definition, layout, sources, ctx.stream)
	if drain != CombatFact.NO_TILE:
		drawn[DRAIN_KEY] = [drain.x, drain.y]
	ctx.setup.shared[DARKNESS_KEY] = drawn


## Gives [param session]'s darkness the sources and drain setup drew ([method draw]) and its
## [member DarknessState.first_release]: turn par − 1 plus [method arrival_offset]. Call once per
## session after the army's effects are registered, so Short Wick counts. Leaves the darkness
## empty on a map with no darkness.
static func place(session: CombatSession) -> void:
	if session.setup == null or session.setup.map == null:
		return
	var drawn: Variant = session.setup.shared.get(DARKNESS_KEY, null)
	if not drawn is Dictionary:
		return
	var result: Dictionary = drawn
	var darkness: DarknessState = session.state.map.darkness
	var written: Variant = result.get(SOURCES_KEY, [])
	if written is Array:
		# Untyped: setup results are plain data.
		for entry: Variant in written:
			var source: DarknessState.Source = DarknessState.Source.new()
			source.tiles = _tiles_from_data(entry)
			darkness.sources.append(source)
	var drain: Array[Vector2i] = _tiles_from_data([result.get(DRAIN_KEY, null)])
	darkness.drain = CombatFact.NO_TILE if drain.is_empty() else drain[0]
	darkness.first_release = session.setup.map.turn_par - 1 + arrival_offset(session)


## Whether the map of [param definition] gets the darkness: it has a turn par and an objective
## with a drain (not Survive or Defend).
static func has_darkness(definition: CombatMapDefinition) -> bool:
	return (
			definition != null
			and definition.turn_par > 0
			and not UNDRAINED.has(definition.objective)
	)


## How many candidates a map of [param combat_type] activates ([constant ACTIVE_SOURCES]).
static func active_count(combat_type: CombatMapDefinition.CombatType) -> int:
	return ACTIVE_SOURCES.get(combat_type, 1)


## The source candidates of [param layout], in the order their first marker comes in
## [MapLayout] order: [constant MapLayout.MarkerKind.DARKNESS_SOURCE] markers sharing a
## [member MapLayout.Marker.group_id] of 0 or more form one candidate; a marker in no group (-1),
## such as a plain marker tile, is a candidate of its own. Each candidate's tiles are distinct and
## in [MapLayout] order.
static func candidates(layout: MapLayout) -> Array[DarknessState.Source]:
	var found: Array[DarknessState.Source] = []
	var of_group: Dictionary[int, DarknessState.Source] = {}
	for marker: MapLayout.Marker in layout.markers_of(MapLayout.MarkerKind.DARKNESS_SOURCE):
		var source: DarknessState.Source = of_group.get(marker.group_id, null)
		if source == null:
			source = DarknessState.Source.new()
			found.append(source)
			if marker.group_id >= 0:
				of_group[marker.group_id] = source
		if not source.tiles.has(marker.tile):
			source.tiles.append(marker.tile)
	return found


## The drain of [param definition]'s map with the active [param sources] (the-darkness.md, The
## drain): for Rout, the floodable tile farthest by walking distance
## ([method DarknessFlow.heights]) from every source tile, a tie drawn from [param stream]; for
## Defeat the Leader and Defeat the Boss, the first leader slot; for Seize, the first seize tile.
## [constant CombatFact.NO_TILE] when there is none, so every step is level.
static func drain_for(
		definition: CombatMapDefinition,
		layout: MapLayout,
		sources: Array[DarknessState.Source],
		stream: RngStream
) -> Vector2i:
	match definition.objective:
		CombatMapDefinition.Objective.ROUT:
			return _rout_drain(layout, sources, stream)
		CombatMapDefinition.Objective.DEFEAT_LEADER, CombatMapDefinition.Objective.DEFEAT_BOSS:
			# The leader's, mini-boss's or boss's starting tile: Objectives marks the enemy placed
			# on a leader slot as the one to defeat.
			return _first_tile(layout, MapLayout.MarkerKind.LEADER_SLOT)
		CombatMapDefinition.Objective.SEIZE:
			return _first_tile(layout, MapLayout.MarkerKind.SEIZE)
	return CombatFact.NO_TILE


## The map of [param layout] as a battle starts, for reading floodable tiles before a session
## exists: every object spot placed ([method MapObjects.place_objects]), so doors are closed and
## breakables stand, and no unit. A throwaway: nothing in it reaches the battle.
static func start_state(layout: MapLayout) -> CombatState:
	var state: CombatState = CombatState.new(MapGrid.new(layout))
	var engine: EffectEngine = EffectEngine.new(state, ForcedRolls.new(PackedInt32Array()))
	# NOTE: a fresh allocator, so the objects' ids are minted outside the run's.
	MapObjects.place_objects(engine, state, layout, InstanceIdAllocator.new())
	return state


## [constant CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET] for [param session]'s map, in turns (Short
## Wick: −1). 0 for a map with no seat.
static func arrival_offset(session: CombatSession) -> int:
	if session.seats.is_empty():
		return 0
	var offset: int = 0
	var is_first: bool = true
	for seat: int in session.seats:
		var sheet: StatSheet = session.engine.stats(InstanceIdAllocator.seat_subject_id(seat))
		var seat_offset: int = sheet.get_int(CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET)
		# ASSUMPTION: a map shared by several seats (P11) takes the earliest arrival, so one
		# player's Short Wick still applies; MVP maps have one seat each.
		offset = seat_offset if is_first else mini(offset, seat_offset)
		is_first = false
	return offset


# Rout's drain: the floodable tiles farthest from every source tile, row-major, one drawn when
# several tie. NO_TILE when no source tile is floodable.
static func _rout_drain(
		layout: MapLayout, sources: Array[DarknessState.Source], stream: RngStream
) -> Vector2i:
	var state: CombatState = start_state(layout)
	var nearest: Dictionary[Vector2i, int] = {}
	for source: DarknessState.Source in sources:
		for tile: Vector2i in source.tiles:
			# Walking distance from one source tile: its heights with that tile as the drain.
			var from_tile: Dictionary[Vector2i, int] = DarknessFlow.heights(state, tile)
			for reached: Vector2i in from_tile:
				if not nearest.has(reached) or from_tile[reached] < nearest[reached]:
					nearest[reached] = from_tile[reached]
	var farthest: Array[Vector2i] = []
	var distance: int = -1
	for tile: Vector2i in layout.tiles():
		if not nearest.has(tile) or nearest[tile] < distance:
			continue
		if nearest[tile] > distance:
			distance = nearest[tile]
			farthest.clear()
		farthest.append(tile)
	if farthest.is_empty():
		return CombatFact.NO_TILE
	if farthest.size() == 1:
		return farthest[0]
	return farthest[stream.pick_index(farthest.size())]


# The first tile marked kind in MapLayout order; NO_TILE when none is.
static func _first_tile(layout: MapLayout, kind: MapLayout.MarkerKind) -> Vector2i:
	var tiles: Array[Vector2i] = layout.tiles_of(kind)
	# ASSUMPTION: a map with several leader slots or seize tiles drains to the first;
	# the-darkness.md names one tile per objective.
	return CombatFact.NO_TILE if tiles.is_empty() else tiles[0]


# tiles as plain data: an Array of [x, y].
static func _tiles_to_data(tiles: Array[Vector2i]) -> Array:
	var written: Array = []
	for tile: Vector2i in tiles:
		written.append([tile.x, tile.y])
	return written


# The tiles of entries, an Array of [x, y] from _tiles_to_data(), ints or floats after a JSON
# round trip; anything else is skipped.
static func _tiles_from_data(entries: Variant) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not entries is Array:
		return tiles
	# Untyped: setup results are plain data.
	for entry: Variant in entries:
		if not entry is Array or (entry as Array).size() != 2:
			continue
		var parts: Array = entry
		var is_number_pair: bool = (
				(parts[0] is int or parts[0] is float) and (parts[1] is int or parts[1] is float)
		)
		if not is_number_pair:
			continue
		var x: float = parts[0]
		var y: float = parts[1]
		tiles.append(Vector2i(roundi(x), roundi(y)))
	return tiles
