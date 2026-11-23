# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_state.gd
# Author:
# Created:  November 4, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name DarknessState
extends RefCounted
## The darkness on one map: its active sources, the drain, its waves, each tile's layer and each
## breakable's contact count (the-darkness.md, Waves and creep).
##
## Held by [member MapState.darkness] and copied with it for a sandbox, so a forecast reads real
## layers ([method CombatState.darkness_layer]) and never changes the real map. Plain data.[br]
## [b]Operations:[/b] [method release], [method creep] and [method recalculate] let waves enter
## tiles: a wave enters each tile within its reach ([method DarknessFlow.flow_costs]) once, ever,
## deepening it a layer up to [constant MAX_LAYER], or [constant BRAZIER_CAP] near a lit Brazier;
## an entry that can't deepen is still spent. Flow is derived afresh each time, so a break or door
## needs only [method recalculate]; layers never fall. Each returns what deepened and reports what
## was entered, for [Darkness] to record. [DarknessSetup] places the sources and drain.[br]
## [b]Saves and mirrors:[/b] [method capture] and [method restore] carry it as plain JSON for the
## snapshot and the [DarknessSaveSection]; a mirror follows its facts ([method CombatState.follow]).
##
## @tutorial(The darkness): docs/design/the-darkness.md
## @tutorial(The darkness plan): docs/plans/2026-11-03-the-darkness.md
## @tutorial(Save system design): docs/design/save-system.md

## How far every wave's reach grows per [method creep], in flow cost (the-darkness.md, Values:
## creep speed 2: two tiles downhill, one level, under one uphill).
const CREEP_SPEED: int = 2

## The deepest layer: Abyss stays Abyss (the-darkness.md, Values: maximum layer 3).
const MAX_LAYER: WhileLayerCondition.Layer = WhileLayerCondition.Layer.ABYSS

## How near a lit Brazier holds tiles, in tiles of grid distance (the-darkness.md, Torches: within
## 2 tiles; combat map plan question 12: grid distance).
const BRAZIER_RADIUS: int = 2

## The deepest layer a wave may make a tile near a lit Brazier (the-darkness.md, Torches: never
## past Dusk).
const BRAZIER_CAP: WhileLayerCondition.Layer = WhileLayerCondition.Layer.DUSK

## [member first_release] on a map whose darkness never comes: before setup, and on a map with no
## darkness ([method DarknessSetup.has_darkness]). The lowest int, which no first release takes
## (turn par is at least 1 and an arrival offset is a few turns), so it is never mistaken for one;
## a JSON number holds it exactly.
const NO_RELEASE: int = -9223372036854775807 - 1

## The active sources; a wave's [member Wave.source] indexes this. Empty before setup chooses
## them, and on a map with no darkness.
var sources: Array[Source] = []

## The turn whose darkness step releases the first wave, which is arrival: turn par − 1 plus the
## map's Short Wick offset, set at battle start ([method DarknessSetup.place]). Below 1 when that
## falls before turn 1. [constant NO_RELEASE] when the darkness never comes.
var first_release: int = NO_RELEASE

## Where the darkness flows toward, which sets every tile's height; [constant CombatFact.NO_TILE]
## for none, when every step is level.
var drain: Vector2i = CombatFact.NO_TILE

## Every wave released, oldest first, then by source index.
var waves: Array[Wave] = []

## Each flooded tile's layer; a dry tile is absent. Changed only by the operations here (and a
## restore), never lowered.
var layers: Dictionary[Vector2i, WhileLayerCondition.Layer] = {}

## Turns of contact with the darkness each breakable has had, by object id; absent for none.
var contacts: Dictionary[String, int] = {}


## The layer of [param tile]; [constant WhileLayerCondition.Layer.DRY] when dry or off the map.
func layer_at(tile: Vector2i) -> WhileLayerCondition.Layer:
	return layers.get(tile, WhileLayerCondition.Layer.DRY)


## Whether the darkness has arrived: arrival is the first release, so any wave means it has.
func has_arrived() -> bool:
	return not waves.is_empty()


## Releases a new wave from every active source, in source index order, each entering that
## source's own floodable tiles (reach 0). Returns the tiles that deepened.
## [param entered]: gains every tile a wave entered, deepened or not, in entry order.
func release(state: CombatState, entered: Array[Entry] = []) -> Array[Deepening]:
	var released: Array[Wave] = []
	for source_index: int in sources.size():
		var wave: Wave = Wave.new()
		wave.source = source_index
		waves.append(wave)
		released.append(wave)
	return _enter(state, released, entered)


## Grows every wave's reach by [constant CREEP_SPEED], then each, oldest first, enters the tiles
## now within its reach. Returns the tiles that deepened.
## [param entered]: gains every tile a wave entered, deepened or not, in entry order.
func creep(state: CombatState, entered: Array[Entry] = []) -> Array[Deepening]:
	for wave: Wave in waves:
		wave.reach += CREEP_SPEED
	return _enter(state, waves, entered)


## Derives the flow again after a breakable broke or a door opened or closed, and every wave
## enters the tiles now within its reach that it hasn't entered. Reaches don't grow. Returns the
## tiles that deepened.
## [param entered]: gains every tile a wave entered, deepened or not, in entry order.
func recalculate(state: CombatState, entered: Array[Entry] = []) -> Array[Deepening]:
	return _enter(state, waves, entered)


## A copy sharing nothing mutable.
func copy() -> DarknessState:
	var state_copy: DarknessState = DarknessState.new()
	for source: Source in sources:
		state_copy.sources.append(source.copy())
	state_copy.first_release = first_release
	state_copy.drain = drain
	for wave: Wave in waves:
		state_copy.waves.append(wave.copy())
	state_copy.layers = layers.duplicate()
	state_copy.contacts = contacts.duplicate()
	return state_copy


## This state as plain JSON values: [code]sources[/code] (each its tiles), [code]drain[/code]
## ([code]""[/code] for none), [code]first_release[/code], [code]waves[/code] (source index, reach,
## tiles entered), [code]layers[/code] by tile, [code]contacts[/code] by object id and
## [code]arrived[/code] ([method has_arrived]). Tiles are [code]"x,y"[/code] strings, layers their
## [enum WhileLayerCondition.Layer] names. Entered tiles and layers are written row-major and
## contacts by id, so equal states write equal text; nothing reads them in order.
func capture() -> Dictionary:
	var source_list: Array = []
	for source: Source in sources:
		source_list.append(_tile_texts(source.tiles))
	var wave_list: Array = []
	for wave: Wave in waves:
		var entered: Array[Vector2i] = []
		entered.assign(wave.entered.keys())
		entered.sort_custom(MapLayout.is_before)
		wave_list.append({
			"source": wave.source,
			"reach": wave.reach,
			"entered": _tile_texts(entered),
		})
	var flooded: Array[Vector2i] = []
	flooded.assign(layers.keys())
	flooded.sort_custom(MapLayout.is_before)
	var by_tile: Dictionary = {}
	for tile: Vector2i in flooded:
		by_tile[_tile_text(tile)] = WhileLayerCondition.Layer.find_key(layers[tile]) as String
	var object_ids: Array[String] = []
	object_ids.assign(contacts.keys())
	object_ids.sort()
	var by_object: Dictionary = {}
	for object_id: String in object_ids:
		by_object[object_id] = contacts[object_id]
	return {
		"sources": source_list,
		"drain": "" if drain == CombatFact.NO_TILE else _tile_text(drain),
		"first_release": first_release,
		"waves": wave_list,
		"layers": by_tile,
		"contacts": by_object,
		"arrived": has_arrived(),
	}


## Replaces everything [method capture] holds with [param data], also after a trip through JSON.
## Returns [constant OK], or [constant ERR_INVALID_DATA], changing nothing, when a key is missing
## or malformed, a wave names no source or enters a tile twice, a layer is DRY or unknown, a
## contact count is below 1, or [code]arrived[/code] disagrees with the waves.
func restore(data: Dictionary) -> Error:
	var source_data: Variant = data.get("sources", null)
	var drain_data: Variant = data.get("drain", null)
	var release: Variant = _release_from(data.get("first_release", null))
	var wave_data: Variant = data.get("waves", null)
	var layer_data: Variant = data.get("layers", null)
	var contact_data: Variant = data.get("contacts", null)
	var arrived: Variant = data.get("arrived", null)
	if (
			not source_data is Array
			or not drain_data is String
			or release == null
			or not wave_data is Array
			or not layer_data is Dictionary
			or not contact_data is Dictionary
			or not arrived is bool
	):
		return ERR_INVALID_DATA
	# Untyped: the parts come from JSON and are checked entry by entry.
	var restored_sources: Array[Source] = []
	for entry: Variant in source_data:
		var tiles: Array[Vector2i] = _tiles_from(entry)
		if not entry is Array or tiles.size() != (entry as Array).size():
			return ERR_INVALID_DATA
		var source: Source = Source.new()
		source.tiles = tiles
		restored_sources.append(source)
	var restored_drain: Vector2i = CombatFact.NO_TILE
	if not (drain_data as String).is_empty():
		restored_drain = _tile_from(drain_data)
		if restored_drain == CombatFact.NO_TILE:
			return ERR_INVALID_DATA
	var restored_waves: Array[Wave] = []
	for entry: Variant in wave_data:
		var wave: Wave = _wave_from(entry, restored_sources.size())
		if wave == null:
			return ERR_INVALID_DATA
		restored_waves.append(wave)
	if (arrived as bool) == restored_waves.is_empty():
		return ERR_INVALID_DATA
	var restored_layers: Dictionary[Vector2i, WhileLayerCondition.Layer] = {}
	for key: Variant in layer_data:
		var tile: Vector2i = _tile_from(key)
		var layer_name: Variant = (layer_data as Dictionary)[key]
		if (
				tile == CombatFact.NO_TILE
				or not layer_name is String
				or not WhileLayerCondition.Layer.has(layer_name)
				or layer_name == "DRY"
		):
			return ERR_INVALID_DATA
		var layer_value: int = WhileLayerCondition.Layer[layer_name]
		restored_layers[tile] = layer_value as WhileLayerCondition.Layer
	var restored_contacts: Dictionary[String, int] = {}
	for key: Variant in contact_data:
		var count: Variant = _whole((contact_data as Dictionary)[key])
		if not key is String or (key as String).is_empty() or count == null or (count as int) < 1:
			return ERR_INVALID_DATA
		restored_contacts[key as String] = count

	sources = restored_sources
	drain = restored_drain
	first_release = release
	waves = restored_waves
	layers = restored_layers
	contacts = restored_contacts
	return OK


# Lets each of entering, in order, enter its unentered tiles within reach, in flow order (by flow
# cost, then row-major), adding each entry to entered.
func _enter(state: CombatState, entering: Array[Wave], entered: Array[Entry]) -> Array[Deepening]:
	var deepened: Array[Deepening] = []
	if entering.is_empty():
		return deepened
	var tile_heights: Dictionary[Vector2i, int] = DarknessFlow.heights(state, drain)
	var lit: Array[Vector2i] = _lit_braziers(state)
	# Each element is the Dictionary[Vector2i, int] of one source, or empty until first needed.
	var costs_by_source: Array[Dictionary] = []
	var order_by_source: Array[Array] = []
	costs_by_source.resize(sources.size())
	order_by_source.resize(sources.size())
	for wave: Wave in entering:
		if wave.source < 0 or wave.source >= sources.size():
			continue
		if order_by_source[wave.source].is_empty():
			var computed: Dictionary[Vector2i, int] = DarknessFlow.flow_costs(
					state, sources[wave.source].tiles, tile_heights
			)
			costs_by_source[wave.source] = computed
			order_by_source[wave.source] = _flow_order(computed)
		var costs: Dictionary[Vector2i, int] = costs_by_source[wave.source]
		var wave_index: int = waves.find(wave)
		for tile: Vector2i in order_by_source[wave.source]:
			if costs[tile] > wave.reach:
				break
			if wave.entered.has(tile):
				continue
			wave.entered[tile] = true
			entered.append(Entry.new(wave_index, tile))
			var cap: WhileLayerCondition.Layer = (
					BRAZIER_CAP if _is_held(state, lit, tile) else MAX_LAYER
			)
			var current: WhileLayerCondition.Layer = layer_at(tile)
			if current >= cap:
				continue
			var deeper: int = current + 1
			layers[tile] = deeper as WhileLayerCondition.Layer
			deepened.append(Deepening.new(tile, layers[tile], wave.source))
	return deepened


# The tiles of a lit Brazier still on the map.
func _lit_braziers(state: CombatState) -> Array[Vector2i]:
	var lit: Array[Vector2i] = []
	for brazier: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.BRAZIER):
		if brazier.is_lit and not brazier.is_destroyed:
			lit.append(brazier.tile)
	return lit


# Whether tile is within BRAZIER_RADIUS of any of lit.
func _is_held(state: CombatState, lit: Array[Vector2i], tile: Vector2i) -> bool:
	for brazier_tile: Vector2i in lit:
		if state.grid.distance(brazier_tile, tile) <= BRAZIER_RADIUS:
			return true
	return false


# The keys of costs by cost, ties row-major, so waves enter (and callers record) in the order the
# darkness reaches them.
# A wave's entries within one step go nearest first, then row-major, which also orders the
# darkness step's facts.
static func _flow_order(costs: Dictionary[Vector2i, int]) -> Array[Vector2i]:
	var order: Array[Vector2i] = []
	order.assign(costs.keys())
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if costs[a] != costs[b]:
			return costs[a] < costs[b]
		return MapLayout.is_before(a, b)
	)
	return order


# A tile as capture() writes it: "x,y".
static func _tile_text(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


static func _tile_texts(tiles: Array[Vector2i]) -> Array:
	var texts: Array = []
	for tile: Vector2i in tiles:
		texts.append(_tile_text(tile))
	return texts


# A tile from _tile_text(); NO_TILE when value isn't one.
static func _tile_from(value: Variant) -> Vector2i:
	if not value is String:
		return CombatFact.NO_TILE
	var parts: PackedStringArray = (value as String).split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return CombatFact.NO_TILE
	return Vector2i(parts[0].to_int(), parts[1].to_int())


# The tiles of value, an Array of _tile_text() strings; those that aren't tiles are left out, so
# a caller compares sizes to refuse them.
static func _tiles_from(value: Variant) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not value is Array:
		return tiles
	for entry: Variant in value:
		var tile: Vector2i = _tile_from(entry)
		if tile != CombatFact.NO_TILE:
			tiles.append(tile)
	return tiles


# A wave from capture(); null when malformed, when its source isn't below source_count, or when it
# enters a tile twice.
static func _wave_from(value: Variant, source_count: int) -> Wave:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	var source: Variant = _whole(data.get("source", null))
	var reach: Variant = _whole(data.get("reach", null))
	var entered_data: Variant = data.get("entered", null)
	var entered: Array[Vector2i] = _tiles_from(entered_data)
	if (
			source == null
			or (source as int) < 0
			or (source as int) >= source_count
			or reach == null
			or (reach as int) < 0
			or not entered_data is Array
			or entered.size() != (entered_data as Array).size()
	):
		return null
	var wave: Wave = Wave.new()
	wave.source = source
	wave.reach = reach
	for tile: Vector2i in entered:
		if wave.entered.has(tile):
			return null
		wave.entered[tile] = true
	return wave


# first_release from capture(), also after JSON: a whole number, or NO_RELEASE, which JSON holds
# exactly though it is beyond 2^53. Null when it is neither.
static func _release_from(value: Variant) -> Variant:
	if value is float and (value as float) == float(NO_RELEASE):
		return NO_RELEASE
	return _whole(value)


# value as an int when it is one, or a whole float within JSON's exact range; null otherwise.
# NOTE: The same rule as MapState._whole and CombatState._whole; keep them in step.
static func _whole(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var number: float = value
	if number != floorf(number) or absf(number) > CombatFact.MAX_EXACT_JSON_INT:
		return null
	return int(number)


## One active source: the tiles of one source candidate.
class Source:
	extends RefCounted

	## Its tiles; those not floodable are skipped, so a wave starts on the rest.
	var tiles: Array[Vector2i] = []

	## A copy sharing nothing mutable.
	func copy() -> Source:
		var source_copy: Source = Source.new()
		source_copy.tiles = tiles.duplicate()
		return source_copy


## One wave: the source that released it, how far it reaches and the tiles it has entered.
class Wave:
	extends RefCounted

	## The index in [member DarknessState.sources] of the source that released it.
	var source: int = -1
	## The flow cost it reaches: 0 at release, growing by the creep speed each creep.
	var reach: int = 0
	## Every tile it has entered, which it never enters again, even once its flow cost changes.
	var entered: Dictionary[Vector2i, bool] = {}

	## A copy sharing nothing mutable.
	func copy() -> Wave:
		var wave_copy: Wave = Wave.new()
		wave_copy.source = source
		wave_copy.reach = reach
		wave_copy.entered = entered.duplicate()
		return wave_copy


## One tile a wave deepened: its new layer and the source that released the wave.
class Deepening:
	extends RefCounted

	## The tile.
	var tile: Vector2i = CombatFact.NO_TILE
	## Its layer after the wave entered.
	var layer: WhileLayerCondition.Layer = WhileLayerCondition.Layer.DRY
	## The index in [member DarknessState.sources] of the wave's source.
	var source: int = -1

	func _init(
			deepened_tile: Vector2i, new_layer: WhileLayerCondition.Layer, source_index: int
	) -> void:
		tile = deepened_tile
		layer = new_layer
		source = source_index


## One tile a wave entered, deepened or not: the wave's index in [member DarknessState.waves].
class Entry:
	extends RefCounted

	## The index in [member DarknessState.waves] of the wave that entered it.
	var wave: int = -1
	## The tile.
	var tile: Vector2i = CombatFact.NO_TILE

	func _init(wave_index: int, entered_tile: Vector2i) -> void:
		wave = wave_index
		tile = entered_tile
