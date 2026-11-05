# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name Darkness
extends RefCounted
## The darkness step at the end of every turn, arrival, darkness damage, and the queries the board
## reads (the-darkness.md, The darkness step, Layers and damage; darkness plan, DK3 and DK4).
##
## [method register] puts [method step] first on [constant CombatHooks.Hook.AFTER_ENEMY_PHASE],
## before [method Reinforcements.arrive], and stops terrain healing on a flooded tile.
## [method advance], in order: [b]creep[/b], [b]release[/b] when a wave is due
## ([method is_release_due]), then [b]erosion[/b]: each standing breakable 4-adjacent to a flooded
## tile gains a turn of contact, and at [constant CONTACT_LIMIT] breaks through
## [method MapObjects.erode]. The first release is arrival ([member MapState.has_darkness_arrived]).
## A break or door change lets the darkness flow anew through [method recalculate].[br]
## [b]Damage[/b] ([method register_damage]): at each side's Phase End, each of its units on a
## flooded tile takes [constant LAYER_DAMAGE_PERCENT] of its max HP, rounded down, at least
## [constant MINIMUM_DAMAGE]. Not an attack: no damage stages, Block or Stance loss; only the
## Darkness damage taken window, whose "that darkness damage" changes apply.[br]
## [b]Facts[/b], in order: one [constant CombatFact.Kind.DARKNESS_ADVANCED] per tile deepened;
## per released wave, one with [constant CombatFact.Flag.DARKNESS_RELEASED] (and
## [constant CombatFact.Flag.DARKNESS_ARRIVED] at the first release) before its own tiles;
## erosion as [constant CombatFact.Kind.OBJECT_STATE_CHANGED]
## ([constant MapObjects.Change.CONTACTED] or [constant MapObjects.Change.ERODED]); one
## [constant CombatFact.Kind.DARKNESS_DAMAGE_TAKEN] per unit hurt, then its defeat at 0 HP.
## Payloads are on the kinds.[br]
## [b]Queries[/b] for the board: [method damage_at], [method next_deepening],
## [method source_counters]. Pure, static rules code: it reads and changes only the engine and
## state it is handed, so it runs unchanged on a sandbox or a stand-in session, and never awaits.
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

## Turns of contact that break a breakable (the-darkness.md, Values: breakable contact limit 3).
const CONTACT_LIMIT: int = 3

## The earliest turn whose darkness step may release the first wave: the darkness can't arrive
## before the player has played a turn (darkness plan question 12 d).
const EARLIEST_RELEASE: int = 1


## Puts [method step] on [param session]'s [constant CombatHooks.Hook.AFTER_ENEMY_PHASE], and a
## [constant CombatHooks.Hook.TERRAIN_HEALING_ALLOWED] check that stops terrain healing on a
## flooded tile (the-darkness.md, Terrain). Call once per session, before
## [method Reinforcements.register], so the darkness step runs first.
static func register(session: CombatSession) -> void:
	session.hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, Darkness.step)
	session.hooks.add(CombatHooks.Hook.TERRAIN_HEALING_ALLOWED, _allows_terrain_healing)


## Puts darkness damage on [param session]'s [constant CombatHooks.Hook.PHASE_END_EFFECTS]: at each
## side's Phase End, after its Phase End and Unit Turn End effects, each of its units on a flooded
## tile takes its darkness damage, in placement order. Call once per session, after
## [method Reinforcements.register], so a unit ending its turn on an open point closes it before
## the darkness hurts it (darkness plan question 5).
static func register_damage(session: CombatSession) -> void:
	session.hooks.add(CombatHooks.Hook.PHASE_END_EFFECTS, _hurt_side)


## [constant CombatHooks.Hook.AFTER_ENEMY_PHASE]: the darkness step on [param session]
## ([method advance]), at the end of turn [member CombatState.turn].
static func step(session: CombatSession) -> void:
	advance(session.engine, session.state)


## The darkness step at the end of turn [member CombatState.turn] of [param state]: creep, the
## release when due, then erosion, recording every change through [param engine]. Does nothing on
## a map with no active source. The caller drains the engine.
static func advance(engine: EffectEngine, state: CombatState) -> void:
	var darkness: DarknessState = state.map.darkness
	if darkness.sources.is_empty():
		return
	_record(engine, darkness.creep(state))
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
	# ASSUMPTION: the interval counts from the turn the first wave was released, so a first release
	# held back to turn 1 (question 12 d) is followed at turn 3, not turn 2.
	return (turn - first) % WAVE_INTERVAL == 0


## Lets every wave on [param state]'s map enter the tiles now within its reach, after a breakable
## broke or a door opened or closed ([method DarknessState.recalculate]), recording one
## [constant CombatFact.Kind.DARKNESS_ADVANCED] per tile deepened. A closed door keeps its layer.
static func recalculate(engine: EffectEngine, state: CombatState) -> void:
	_record(engine, state.map.darkness.recalculate(state))


## The HP [param unit_id] would lose to the darkness by ending its side's phase on [param tile]
## now: its darkness damage for that tile's layer, with every "that darkness damage" effect that
## would answer it, at most its HP, as its [constant CombatFact.Kind.DARKNESS_DAMAGE_TAKEN] would
## record. 0 on a dry tile or for a unit off [param engine]'s map. Changes nothing: with no
## effect answering darkness damage it reads the stat sheet only, else it deals the damage on a
## sandbox with the unit moved there. Phase End effects that would land first (a heal) aren't
## foreseen; the intents preview runs them.
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


# Every active source releases a wave; the first release is arrival. Each wave's release fact
# comes before the tiles it entered, by source index.
static func _release(engine: EffectEngine, state: CombatState) -> void:
	var darkness: DarknessState = state.map.darkness
	var is_arrival: bool = not darkness.has_arrived()
	var deepened: Array[DarknessState.Deepening] = darkness.release(state)
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


# Each standing breakable next to a flooded tile, in spot order, gains a turn of contact; one at
# the limit erodes and breaks, which lets the darkness flow through (MapObjects.broken).
static func _erode(engine: EffectEngine, state: CombatState) -> void:
	var darkness: DarknessState = state.map.darkness
	# ASSUMPTION: contact is read once, before any break this step, so a lane a break opens
	# erodes the breakables beyond it from the next step; the-darkness.md doesn't order them.
	var touching: Array[MapState.ObjectState] = []
	for placed: MapState.ObjectState in _breakables(state):
		if _is_touching(state, placed.tile):
			touching.append(placed)
	for placed: MapState.ObjectState in touching:
		# A keg's blast earlier this step may have broken it.
		if placed.is_destroyed:
			continue
		var count: int = darkness.contacts.get(placed.id, 0) + 1
		darkness.contacts[placed.id] = count
		var contact: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_STATE_CHANGED, placed.id)
		contact.tile = placed.tile
		contact.amount = count
		contact.key = (
				MapObjects.Change.ERODED if count >= CONTACT_LIMIT else MapObjects.Change.CONTACTED
		)
		engine.record(contact)
		if count >= CONTACT_LIMIT:
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


# PHASE_END_EFFECTS: each unit of side on a flooded tile, in placement order, takes its darkness
# damage at its tile's layer now. A unit that only passed through darkness is on a dry tile here.
static func _hurt_side(session: CombatSession, side: CombatFact.CombatSide) -> void:
	var state: CombatState = session.state
	for unit_id: String in state.units_of(side):
		if not state.has_unit(unit_id):
			continue
		var layer: WhileLayerCondition.Layer = state.map.darkness.layer_at(state.tile_of(unit_id))
		if layer != WhileLayerCondition.Layer.DRY:
			_deal(session.engine, state, unit_id, layer)


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
	# ASSUMPTION: amount is the HP lost, overkill dropped, as DAMAGE_TAKEN's amount is what got
	# through and as the board reads it (combat UI plan question 14 g).
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
