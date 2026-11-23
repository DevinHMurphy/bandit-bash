# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness.gd
# Author:
# Created:  November 4, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name Darkness
extends RefCounted
## The darkness phase at the end of every turn, arrival, and the queries the board reads
## (the-darkness.md; ui-lift.md, Darkness phase).
##
## [b]The darkness phase[/b], after the enemy Phase End and before the player Phase Start, is
## [method hurt] then [method step], each its own step on
## [constant CombatHooks.Hook.AFTER_ENEMY_PHASE], so a battle the damage ends sees no creep; it has
## no Phase Start or End. Damage is not an attack: only the Darkness damage taken window.
## [method advance]: creep, release when due (the first is arrival), then erosion. [b]Facts:[/b]
## per unit hurt, [constant CombatFact.Kind.DARKNESS_DAMAGE_TAKEN] then its defeat; per tile
## deepened, [constant CombatFact.Kind.DARKNESS_ADVANCED] (a release's flagged one first), then
## [constant CombatFact.Kind.DARKNESS_WAVE_SPREAD] for what waves entered; erosion as
## [constant CombatFact.Kind.OBJECT_STATE_CHANGED]. Pure static rules code; it never awaits.
##
## @tutorial(The darkness): docs/design/the-darkness.md
## @tutorial(The darkness plan): docs/plans/2026-11-03-the-darkness.md

## Darkness damage by layer, in percent of max HP (the-darkness.md, Values: Dusk 10%, Gloom 25%,
## Abyss 50%; the damage model itself is a first pass, to playtest).
const LAYER_DAMAGE_PERCENT: Dictionary[WhileLayerCondition.Layer, int] = {
	WhileLayerCondition.Layer.DUSK: 10,
	WhileLayerCondition.Layer.GLOOM: 25,
	WhileLayerCondition.Layer.ABYSS: 50,
}

## The least darkness damage a unit on a flooded tile takes, after rounding down (the-darkness.md,
## Values: all damage is rounded down, with a minimum of 1).
const MINIMUM_DAMAGE: int = 1

## Turns between one wave and the next (the-darkness.md, Values: every 2 turns).
const WAVE_INTERVAL: int = 2

## Turns of contact that break an authored breakable (the-darkness.md, Values: breakable contact
## limit 3). A thrown keg's lit fuse has its own, [constant MapObjects.LIT_CONTACT_LIMIT].
const CONTACT_LIMIT: int = 3

## The earliest turn whose darkness step may release the first wave: the darkness can't arrive
## before the player has played a turn (darkness plan question 12 d).
const EARLIEST_RELEASE: int = 1

# The order hurt takes the sides in: the turn's own order, player then enemy.
const _HURT_ORDER: Array[CombatFact.CombatSide] = [
	CombatFact.CombatSide.PLAYER,
	CombatFact.CombatSide.ENEMY,
]


## Puts the darkness phase on [param session]'s [constant CombatHooks.Hook.AFTER_ENEMY_PHASE],
## [method hurt] then [method step], and a [constant CombatHooks.Hook.TERRAIN_HEALING_ALLOWED]
## check that stops terrain healing on a flooded tile (the-darkness.md, Terrain). Call once per
## session, before [method Reinforcements.register], so the phase runs before arrivals.
static func register(session: CombatSession) -> void:
	session.hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, Darkness.hurt)
	session.hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, Darkness.step)
	session.hooks.add(CombatHooks.Hook.TERRAIN_HEALING_ALLOWED, _allows_terrain_healing)


## [constant CombatHooks.Hook.AFTER_ENEMY_PHASE]: the darkness phase's damage on [param session].
## Every unit on a flooded tile, player units then enemies, each side in placement order, takes
## its darkness damage at its tile's layer now, before the creep. The battle's end is checked
## after all of it, so a commander and the last enemy falling together is a loss.
static func hurt(session: CombatSession) -> void:
	var state: CombatState = session.state
	for side: CombatFact.CombatSide in _HURT_ORDER:
		for unit_id: String in state.units_of(side):
			if not state.has_unit(unit_id):
				continue
			var layer: WhileLayerCondition.Layer = state.map.darkness.layer_at(
					state.tile_of(unit_id)
			)
			if layer != WhileLayerCondition.Layer.DRY:
				_deal(session.engine, state, unit_id, layer)


## [constant CombatHooks.Hook.AFTER_ENEMY_PHASE]: the darkness step on [param session]
## ([method advance]), at the end of turn [member CombatState.turn], after [method hurt].
static func step(session: CombatSession) -> void:
	advance(session.engine, session.state)


## The darkness step at the end of turn [member CombatState.turn] of [param state]: creep, the
## release when due, then erosion, recording every change through [param engine]. Does nothing on
## a map with no active source. The caller drains the engine.
static func advance(engine: EffectEngine, state: CombatState) -> void:
	var darkness: DarknessState = state.map.darkness
	if darkness.sources.is_empty():
		return
	var entered: Array[DarknessState.Entry] = []
	_record(engine, darkness.creep(state, entered))
	_record_spread(engine, darkness, entered, true)
	if is_release_due(darkness, state.turn):
		_release(engine, state)
	_erode(engine, state)


## The turn whose darkness step releases the first wave: [member DarknessState.first_release],
## and never before [constant EARLIEST_RELEASE]. [constant DarknessState.NO_RELEASE] when the map
## has no active source or no first release.
static func release_turn(darkness: DarknessState) -> int:
	if darkness.sources.is_empty() or darkness.first_release == DarknessState.NO_RELEASE:
		return DarknessState.NO_RELEASE
	return maxi(darkness.first_release, EARLIEST_RELEASE)


## Whether the darkness step at the end of [param turn] releases a wave: at [method release_turn]
## and every [constant WAVE_INTERVAL] turns after it.
static func is_release_due(darkness: DarknessState, turn: int) -> bool:
	var first: int = release_turn(darkness)
	if first == DarknessState.NO_RELEASE or turn < first:
		return false
	# The interval counts from the turn the first wave was released, so a first release held back
	# to turn 1 is followed at turn 3, not turn 2.
	return (turn - first) % WAVE_INTERVAL == 0


## Lets every wave on [param state]'s map enter the tiles now within its reach, after a breakable
## broke or a door opened or closed ([method DarknessState.recalculate]), recording one
## [constant CombatFact.Kind.DARKNESS_ADVANCED] per tile deepened, then one
## [constant CombatFact.Kind.DARKNESS_WAVE_SPREAD] per tile entered. A closed door keeps its layer.
static func recalculate(engine: EffectEngine, state: CombatState) -> void:
	var darkness: DarknessState = state.map.darkness
	var entered: Array[DarknessState.Entry] = []
	_record(engine, darkness.recalculate(state, entered))
	_record_spread(engine, darkness, entered, false)


## The HP [param unit_id] would lose in this turn's darkness phase standing on [param tile]: its
## damage for the tile's layer now, with every "that darkness damage" effect, at most its HP now,
## as [constant CombatFact.Kind.DARKNESS_DAMAGE_TAKEN] would record. 0 on a dry tile or off the
## map. Changes nothing (a sandbox when an effect answers it). What happens before the phase (a
## heal, a hit, a shove, a break) isn't foreseen.
## [param tile]: a tile the unit could end its move on, free or its own.
static func damage_at(engine: EffectEngine, unit_id: String, tile: Vector2i) -> int:
	var state: CombatState = engine.state as CombatState
	if state == null or not state.has_unit(unit_id):
		return 0
	var layer: WhileLayerCondition.Layer = state.map.darkness.layer_at(tile)
	if layer == WhileLayerCondition.Layer.DRY:
		return 0
	if not _is_answered(engine, unit_id):
		return mini(_amount(engine, unit_id, layer, EffectContext.new()), state.get_hp(unit_id))
	var sandbox: Sandbox = Sandbox.new(engine, ForecastRolls.new())
	var copy: CombatState = sandbox.engine.state as CombatState
	if copy.tile_of(unit_id) != tile:
		copy.move_unit(unit_id, tile)
	return _deal(sandbox.engine, copy, unit_id, layer)


## The tiles the darkness step at the end of this turn would deepen on [param engine]'s map, each
## to the layer it would reach, if nothing else changed first: [method advance] on a sandbox,
## erosion's breaks included. Before turn 1's Phase Start, turn 1's step. Empty with no active
## source. Changes nothing.
static func next_deepening(engine: EffectEngine) -> Dictionary[Vector2i, WhileLayerCondition.Layer]:
	var deepening: Dictionary[Vector2i, WhileLayerCondition.Layer] = {}
	var state: CombatState = engine.state as CombatState
	if state == null or state.map.darkness.sources.is_empty():
		return deepening
	var sandbox: Sandbox = Sandbox.new(engine, ForecastRolls.new())
	var copy: CombatState = sandbox.engine.state as CombatState
	copy.turn = maxi(copy.turn, 1)
	var facts: Array[CombatFact] = sandbox.engine.fact_log
	var from: int = facts.size()
	sandbox.engine.begin_step()
	advance(sandbox.engine, copy)
	sandbox.engine.drain()
	for i: int in range(from, facts.size()):
		var fact: CombatFact = facts[i]
		if fact.kind == CombatFact.Kind.DARKNESS_ADVANCED and fact.tile != CombatFact.NO_TILE:
			deepening[fact.tile] = fact.amount as WhileLayerCondition.Layer
	return deepening


## Each active source's counter on [param state]'s map, by source index: the turns until its next
## wave, this turn included (1: at the end of this turn), counted as
## [constant CombatFact.Kind.REINFORCEMENT_INCOMING] counts. Before arrival it counts to arrival,
## then to the next wave. Every source releases together, so the counters are equal. Before turn
## 1's Phase Start, counted from turn 1. Empty when the darkness never comes.
static func source_counters(state: CombatState) -> PackedInt32Array:
	var counters: PackedInt32Array = []
	var darkness: DarknessState = state.map.darkness
	var first: int = release_turn(darkness)
	if first == DarknessState.NO_RELEASE:
		return counters
	var turn: int = maxi(state.turn, 1)
	var next: int = first
	if turn > first:
		next = turn + posmod(first - turn, WAVE_INTERVAL)
	for _source: int in darkness.sources.size():
		counters.append(next - turn + 1)
	return counters

# One DARKNESS_ADVANCED per entry of deepened, in order.
static func _record(engine: EffectEngine, deepened: Array[DarknessState.Deepening]) -> void:
	for entry: DarknessState.Deepening in deepened:
		var fact: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_ADVANCED)
		fact.tile = entry.tile
		fact.amount = entry.layer
		fact.key = entry.source
		engine.record(fact)


# One DARKNESS_WAVE_SPREAD per entry of entered, in order, and on a creep one with no tile for
# each wave that entered nothing, since its reach still grew. Each fact sits among its wave's, as
# DarknessState._enter lets the waves enter one by one in index order.
static func _record_spread(
		engine: EffectEngine,
		darkness: DarknessState,
		entered: Array[DarknessState.Entry],
		is_creep: bool
) -> void:
	var next: int = 0
	for wave_index: int in darkness.waves.size():
		var reach: int = darkness.waves[wave_index].reach
		var from: int = next
		while next < entered.size() and entered[next].wave == wave_index:
			_record_wave(engine, wave_index, reach, entered[next].tile)
			next += 1
		if is_creep and next == from:
			_record_wave(engine, wave_index, reach, CombatFact.NO_TILE)


# One DARKNESS_WAVE_SPREAD: the wave at wave_index, its reach now, the tile it entered or NO_TILE.
static func _record_wave(
		engine: EffectEngine, wave_index: int, reach: int, tile: Vector2i
) -> void:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_WAVE_SPREAD)
	fact.key = wave_index
	fact.amount = reach
	fact.tile = tile
	engine.record(fact)


# Every active source releases a wave; the first release is arrival. Each wave's release fact
# comes before the tiles it deepened, by source index; the tiles the new waves entered follow all
# of them.
static func _release(engine: EffectEngine, state: CombatState) -> void:
	var darkness: DarknessState = state.map.darkness
	var is_arrival: bool = not darkness.has_arrived()
	var entered: Array[DarknessState.Entry] = []
	var deepened: Array[DarknessState.Deepening] = darkness.release(state, entered)
	if is_arrival:
		state.map.has_darkness_arrived = true
	var flags: int = CombatFact.Flag.DARKNESS_RELEASED
	if is_arrival:
		flags |= CombatFact.Flag.DARKNESS_ARRIVED
	for source_index: int in darkness.sources.size():
		var released: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_ADVANCED)
		released.key = source_index
		released.flags = flags
		engine.record(released)
		var own: Array[DarknessState.Deepening] = []
		for entry: DarknessState.Deepening in deepened:
			if entry.source == source_index:
				own.append(entry)
		_record(engine, own)
	_record_spread(engine, darkness, entered, false)


# Each standing breakable next to a flooded tile, in spot order, gains a turn of contact; one at
# its limit (MapObjects.contact_limit) erodes and breaks, which lets the darkness flow through
# (MapObjects.broken). A thrown keg also touches through its own tile, if it landed on a flooded
# one.
static func _erode(engine: EffectEngine, state: CombatState) -> void:
	var darkness: DarknessState = state.map.darkness
	# Contact is read once, before any break this step, so a lane a break opens erodes the
	# breakables beyond it from the next step.
	var touching: Array[MapState.ObjectState] = []
	for placed: MapState.ObjectState in _breakables(state):
		var is_under: bool = (
				placed.is_thrown
				and darkness.layer_at(placed.tile) != WhileLayerCondition.Layer.DRY
		)
		if is_under or _is_touching(state, placed.tile):
			touching.append(placed)
	for placed: MapState.ObjectState in touching:
		# A keg's blast earlier this step may have broken it.
		if placed.is_destroyed:
			continue
		var count: int = darkness.contacts.get(placed.id, 0) + 1
		var limit: int = MapObjects.contact_limit(placed)
		darkness.contacts[placed.id] = count
		var contact: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_STATE_CHANGED, placed.id)
		contact.tile = placed.tile
		contact.amount = count
		contact.key = MapObjects.Change.ERODED if count >= limit else MapObjects.Change.CONTACTED
		engine.record(contact)
		if count >= limit:
			MapObjects.erode(engine, state, placed.id)


# Every standing breakable on state's map, in spot order.
static func _breakables(state: CombatState) -> Array[MapState.ObjectState]:
	var found: Array[MapState.ObjectState] = []
	var by_index: Dictionary[int, MapState.ObjectState] = {}
	for object_id: String in state.map.objects:
		var placed: MapState.ObjectState = state.map.objects[object_id]
		if MapObjects.BREAKABLE_STATS.has(placed.kind) and not placed.is_destroyed:
			by_index[placed.index] = placed
	var indexes: Array[int] = []
	indexes.assign(by_index.keys())
	indexes.sort()
	for index: int in indexes:
		found.append(by_index[index])
	return found


# Whether a 4-adjacent neighbor of tile is flooded.
static func _is_touching(state: CombatState, tile: Vector2i) -> bool:
	for next: Vector2i in state.grid.neighbors(tile):
		if state.map.darkness.layer_at(next) != WhileLayerCondition.Layer.DRY:
			return true
	return false


# TERRAIN_HEALING_ALLOWED: no terrain heal for a unit on a flooded tile.
static func _allows_terrain_healing(session: CombatSession, unit_id: String) -> bool:
	return session.state.darkness_layer(unit_id) == WhileLayerCondition.Layer.DRY


# Deals unit_id its darkness damage for layer through engine: the Darkness damage taken window,
# the HP lost, its fact, then its defeat at 0 HP, by no unit. Returns the HP lost.
static func _deal(
		engine: EffectEngine, state: CombatState, unit_id: String, layer: WhileLayerCondition.Layer
) -> int:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_DAMAGE_TAKEN, unit_id)
	fact.source = CombatFact.Source.DARKNESS
	var ctx: EffectContext = EffectContext.new()
	engine.open_window(fact, ctx)
	var hp: int = state.get_hp(unit_id)
	var lost: int = mini(_amount(engine, unit_id, layer, ctx), hp)
	state.set_hp(unit_id, hp - lost)
	# The amount is the HP lost, overkill dropped, as DAMAGE_TAKEN's amount is what got through
	# and as the board reads it.
	fact.amount = lost
	fact.hp_amount = lost
	engine.record(fact, ctx)
	if state.get_hp(unit_id) == 0:
		state.defeat(engine, unit_id, "")
	return lost


# unit_id's darkness damage for layer before HP caps it: the layer's share of max HP, exact through
# ctx's window (its "that darkness damage" amount changes, then its Multipliers changes, as Lantern
# Oil's ×0.5), rounded down once, at least MINIMUM_DAMAGE.
static func _amount(
		engine: EffectEngine,
		unit_id: String,
		layer: WhileLayerCondition.Layer,
		ctx: EffectContext
) -> int:
	var max_hp: int = engine.stats(unit_id).get_int(CombatValue.Key.HP)
	var percent: int = LAYER_DAMAGE_PERCENT.get(layer, 0)
	var shaped: float = ctx.shaped_amount(max_hp * percent / 100.0).total
	var multipliers: float = ValueBreakdown.compute(
			DamageStage.Key.MULTIPLIERS, 1.0, "", ctx.that_modifiers(DamageStage.Key.MULTIPLIERS)
	).total
	var rounded: int = ValueBreakdown.round_to_int(
			shaped * multipliers, ValueBreakdown.Rounding.FLOOR
	)
	return maxi(rounded, MINIMUM_DAMAGE)


# Whether an effect on engine would answer darkness damage to unit_id: a waking Darkness damage
# taken effect whose scope holds it. Without one, damage_at needs no sandbox.
static func _is_answered(engine: EffectEngine, unit_id: String) -> bool:
	for instance: EffectInstance in engine.get_instances():
		var definition: EffectDefinition = instance.definition
		if definition == null or definition.trigger != EffectTerms.Trigger.DARKNESS_DAMAGE_TAKEN:
			continue
		var holds: bool = engine.in_scope(instance.owner, unit_id, definition.scope)
		if holds and not engine.is_dormant(instance):
			return true
	return false
