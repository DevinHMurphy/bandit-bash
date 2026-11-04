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
## The darkness step at the end of every turn, arrival, and the facts every change to the
## darkness records (the-darkness.md, The darkness step; darkness plan, DK3).
##
## [method register] puts [method step] first on [constant CombatHooks.Hook.AFTER_ENEMY_PHASE],
## before [method Reinforcements.arrive]. [method advance], in order: [b]creep[/b] (every wave's
## reach grows), [b]release[/b] when a wave is due ([method is_release_due]), then
## [b]erosion[/b]: each standing breakable 4-adjacent to a flooded tile gains a turn of contact,
## and at [constant CONTACT_LIMIT] breaks through [method MapObjects.erode]. The first release is
## arrival: it sets [member MapState.has_darkness_arrived], which stops reinforcement points and
## turns the AI aggressive.[br]
## Any break or door change lets the darkness flow anew through [method recalculate], which
## [MapObjects] calls. Nothing here deals damage.[br]
## [b]Facts[/b], in order: one [constant CombatFact.Kind.DARKNESS_ADVANCED] per tile deepened;
## per released wave, one with [constant CombatFact.Flag.DARKNESS_RELEASED] (and
## [constant CombatFact.Flag.DARKNESS_ARRIVED] at the first release) before its own tiles;
## erosion as [constant CombatFact.Kind.OBJECT_STATE_CHANGED] with
## [constant MapObjects.Change.CONTACTED] or [constant MapObjects.Change.ERODED]. Payloads are on
## [constant CombatFact.Kind.DARKNESS_ADVANCED].[br]
## Pure, static rules code: it reads and changes only the engine and state it is handed, so it
## runs unchanged on a sandbox or a stand-in session, and never awaits.
##
## @tutorial(The darkness): docs/design/the-darkness.md
## @tutorial(The darkness plan): docs/plans/2026-11-03-the-darkness.md

## Turns between one wave and the next (the-darkness.md, Values: every 2 turns).
const WAVE_INTERVAL: int = 2

## Turns of contact that break a breakable (the-darkness.md, Values: breakable contact limit 3).
const CONTACT_LIMIT: int = 3

## The earliest turn whose darkness step may release the first wave: the darkness can't arrive
## before the player has played a turn (darkness plan question 12 d).
const EARLIEST_RELEASE: int = 1


## Puts [method step] on [param session]'s [constant CombatHooks.Hook.AFTER_ENEMY_PHASE]. Call
## once per session, before [method Reinforcements.register], so the darkness step runs first.
static func register(session: CombatSession) -> void:
	session.hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, Darkness.step)


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
## has no active source.
static func release_turn(darkness: DarknessState) -> int:
	if darkness.sources.is_empty():
		return DarknessState.NO_RELEASE
	# NOTE: tests sources, not first_release == NO_RELEASE: turn par 1 with Short Wick sets
	# first_release to -1, the same number, on a map whose darkness does come.
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
