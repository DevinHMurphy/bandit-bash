# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_state.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name DarknessState
extends RefCounted
## The darkness on one map: its active sources, the drain, its waves, each tile's layer and each
## breakable's contact count (the-darkness.md, Waves and creep).
##
## Held by [MapState] as [member MapState.darkness] and copied with it for a sandbox, so a
## forecast reads real layers through [method CombatState.darkness_layer] and never changes the
## real map. Plain data with ids and tiles only.[br]
## [b]Operations:[/b] [method release], [method creep] and [method recalculate] let waves enter
## tiles. A wave enters each tile whose flow cost ([method DarknessFlow.flow_costs]) is within its
## reach once, ever, deepening it one layer up to [constant MAX_LAYER], or up to
## [constant BRAZIER_CAP] within [constant BRAZIER_RADIUS] of a lit Brazier; an entry that can't
## deepen a tile is still spent (plan question 3). Heights and flow costs are derived afresh for
## each operation, so a break or a door change only needs [method recalculate] (plan question 2);
## a tile that stops being floodable keeps its layer. Layers never fall.[br]
## [DarknessSetup] chooses the sources, the drain and [member first_release]. Scheduling waves,
## erosion, damage and facts belong to the callers; each operation returns what deepened, in
## order, for them to record.
##
## @tutorial(The darkness): docs/design/the-darkness.md
## @tutorial(The darkness plan): docs/plans/2026-11-03-the-darkness.md

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
## darkness ([method DarknessSetup.has_darkness]).
const NO_RELEASE: int = -1

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
func release(state: CombatState) -> Array[Deepening]:
	var released: Array[Wave] = []
	for source_index: int in sources.size():
		var wave: Wave = Wave.new()
		wave.source = source_index
		waves.append(wave)
		released.append(wave)
	return _enter(state, released)


## Grows every wave's reach by [constant CREEP_SPEED], then each, oldest first, enters the tiles
## now within its reach. Returns the tiles that deepened.
func creep(state: CombatState) -> Array[Deepening]:
	for wave: Wave in waves:
		wave.reach += CREEP_SPEED
	return _enter(state, waves)


## Derives the flow again after a breakable broke or a door opened or closed, and every wave
## enters the tiles now within its reach that it hasn't entered. Reaches don't grow. Returns the
## tiles that deepened.
func recalculate(state: CombatState) -> Array[Deepening]:
	return _enter(state, waves)


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


# Lets each of entering, in order, enter its unentered tiles within reach, in flow order (by flow
# cost, then row-major).
func _enter(state: CombatState, entering: Array[Wave]) -> Array[Deepening]:
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
		for tile: Vector2i in order_by_source[wave.source]:
			if costs[tile] > wave.reach:
				break
			if wave.entered.has(tile):
				continue
			wave.entered[tile] = true
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
# ASSUMPTION: the-darkness.md doesn't order a wave's entries within one step; nearest first, then
# row-major, also orders the darkness step's facts.
static func _flow_order(costs: Dictionary[Vector2i, int]) -> Array[Vector2i]:
	var order: Array[Vector2i] = []
	order.assign(costs.keys())
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if costs[a] != costs[b]:
			return costs[a] < costs[b]
		return MapLayout.is_before(a, b)
	)
	return order


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
