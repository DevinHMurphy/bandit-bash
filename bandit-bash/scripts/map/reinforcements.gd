# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reinforcements.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name Reinforcements
extends RefCounted
## Reinforcement points in a battle: each point's waves drawn at setup, the warnings, the arrivals,
## and a player unit closing a point (combat map plan, Reinforcement points).
##
## A point's arrival turns are authored on its [MapMarker]. Setup step 5 ([method draw_waves]) draws
## one group per arrival turn through a [Reinforcements.GroupSource] (P05's enemy groups);
## [method register] copies the waves into the session's [member MapState.points] and adds:[br]
## - [b]Warnings[/b] ([constant CombatHooks.Hook.INTENTS], after every player Phase Start): one
## [constant CombatFact.Kind.REINFORCEMENT_INCOMING] per open point with the turns until its next
## wave, and in the player phase right before it arrives, the wave's unit types.[br]
## - [b]Closing[/b] ([constant CombatHooks.Hook.PHASE_END_EFFECTS], player side): a player unit
## whose Unit Turn End is on an open point closes it for good. A unit's turn ends at its side's
## Phase End, as for Seize ([Objectives]), so stepping off after acting doesn't close it.[br]
## - [b]Arrival[/b] ([constant CombatHooks.Hook.AFTER_ENEMY_PHASE]): a wave with arrival turn N
## arrives after turn N's enemy phase. Each unit is placed on the point if it is free, else on the
## nearest free tile ([method Pathing.nearest_free_tile]), with Block 0 and full Stance
## ([constant CombatFact.Kind.UNIT_SPAWNED] each); then
## [constant CombatFact.Kind.REINFORCEMENT_ARRIVED].[br]
## A point is [b]open[/b] while it has a wave to come, isn't closed, Rout's win hasn't cancelled the
## waves ([method cancel]) and the darkness hasn't arrived ([method has_darkness_arrived]). Only an
## open point warns, sends or can be closed. Pure rules code: it records through the session's
## engine and never awaits.
##
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md
##
## @todo: TOD-001 - P06 registers its darkness step on AFTER_ENEMY_PHASE before register() runs.
## @todo: TOD-002 - Draw P05's enemy groups and build their units (GroupSource).
## @todo: TOD-003 - Answer has_darkness_arrived() from P06's darkness state.

## Display text of every reinforcement point's id, for describe.
const POINT_LABEL: String = "Reinforcement Point"

## A wave's arrival turn, in each wave Dictionary ([constant Objectives.WAVES_KEY]).
const TURN_KEY: String = "turn"

## A wave's group, in each wave Dictionary: an Array of unit entries, in arrival order, from
## [method GroupSource.draw_group].
const GROUP_KEY: String = "group"

## A unit entry's unit type, the [member CombatUnitState.unit_type] it arrives as; what the
## warnings preview.
const UNIT_TYPE_KEY: String = "unit_type"


## Setup step 5: draws a group for each arrival turn of each reinforcement point on the map, points
## by index and turns in ascending order, from [param ctx]'s shared [code]ENCOUNTER_SETUP[/code]
## stream through [param source], into [member CombatEncounter.EncounterSetup.shared] under
## [constant Objectives.WAVES_KEY]. A turn whose group is empty sends no wave. Register it bound:
## [code]draw_waves.bind(source)[/code].
static func draw_waves(ctx: CombatEncounter.SetupContext, source: GroupSource) -> void:
	var drawn: Dictionary = {}
	for point: MapLayout.Marker in ctx.setup.layout.markers_of(
			MapLayout.MarkerKind.REINFORCEMENT_POINT
	):
		var turns: PackedInt32Array = point.arrival_turns.duplicate()
		turns.sort()
		var waves: Array[Dictionary] = []
		for turn: int in turns:
			var group: Array[Dictionary] = source.draw_group(ctx.stream, point, turn)
			if not group.is_empty():
				waves.append({TURN_KEY: turn, GROUP_KEY: group})
		if not waves.is_empty():
			drawn[str(point.index)] = waves
	ctx.setup.shared[Objectives.WAVES_KEY] = drawn


## Loads [param session]'s reinforcement points ([method load_waves]) and adds [method warn],
## [method close_points] and [method arrive] (bound to [param source]) to its hooks. Call once per
## session, before the battle opens and after P06's darkness step is registered.
static func register(session: CombatSession, source: GroupSource) -> void:
	load_waves(session)
	session.hooks.add(CombatHooks.Hook.INTENTS, Reinforcements.warn)
	session.hooks.add(CombatHooks.Hook.PHASE_END_EFFECTS, Reinforcements.close_points)
	# TODO(TOD-001): P06's darkness step comes first on this hook (the-darkness.md, The darkness
	# step), so the caller registers it before calling this.
	session.hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, Reinforcements.arrive.bind(source))


## Puts one [MapState.PointState] per reinforcement point of [param session]'s layout in its
## [member MapState.points], with the waves setup drew for it, in the order drawn, and names each
## point's id. A point with no waves drawn has none, so it never sends.
static func load_waves(session: CombatSession) -> void:
	var drawn: Dictionary = {}
	if session.setup != null:
		var shared_waves: Variant = session.setup.shared.get(Objectives.WAVES_KEY, {})
		if shared_waves is Dictionary:
			drawn = shared_waves
	session.state.map.points.clear()
	for marker: MapLayout.Marker in session.layout.markers_of(
			MapLayout.MarkerKind.REINFORCEMENT_POINT
	):
		var point: MapState.PointState = MapState.PointState.new()
		point.id = InstanceIdAllocator.point_id(marker.index)
		point.index = marker.index
		point.tile = marker.tile
		var waves: Variant = drawn.get(str(marker.index), [])
		if waves is Array:
			# Untyped: setup results are plain data.
			for wave: Variant in waves:
				if wave is Dictionary:
					point.waves.append((wave as Dictionary).duplicate(true))
		session.ids.set_label(point.id, POINT_LABEL)
		session.state.map.points[marker.index] = point


## Whether reinforcement point [param point_index] on [param state]'s map is open: it has a wave
## to come ([method waves_left]).
static func is_open(state: CombatState, point_index: int) -> bool:
	return waves_left(state, point_index) > 0


## The waves still to come at reinforcement point [param point_index] on [param state]'s map; 0
## once it is closed, the waves are cancelled or the darkness has arrived, and for no such point.
static func waves_left(state: CombatState, point_index: int) -> int:
	var point: MapState.PointState = state.map.points.get(point_index, null)
	if (
			point == null
			or point.is_closed
			or state.map.are_waves_cancelled
			or has_darkness_arrived(state)
	):
		return 0
	return point.waves.size() - point.sent


## Whether the darkness has arrived on [param state]'s map, so no point sends again
## (the-darkness.md, Arrival): the one place reinforcements ask.
static func has_darkness_arrived(state: CombatState) -> bool:
	# TODO(TOD-003): P06's darkness state answers; until then the flag nothing sets.
	return state.map.has_darkness_arrived


## Cancels every wave on [param state]'s map that hasn't arrived: Rout's win
## ([method Objectives.cancel_pending_waves]). Records nothing: the
## [constant CombatFact.Kind.COMBAT_ENDED] it comes with ends the map.
static func cancel(state: CombatState) -> void:
	state.map.are_waves_cancelled = true


## [constant CombatHooks.Hook.INTENTS]: one [constant CombatFact.Kind.REINFORCEMENT_INCOMING] per
## open point on [param session]'s map, by point index, for its next wave; with the wave's unit
## types when it arrives after this turn's enemy phase.
static func warn(session: CombatSession) -> void:
	var state: CombatState = session.state
	for point: MapState.PointState in _points_of(state):
		if not is_open(state, point.index):
			continue
		var wave: Dictionary = point.waves[point.sent]
		var incoming: CombatFact = CombatFact.new(
				CombatFact.Kind.REINFORCEMENT_INCOMING, point.id
		)
		incoming.tile = point.tile
		# Counting this turn: 1 is after this turn's enemy phase. A wave is never overdue, since
		# arrive() sends every wave up to the current turn.
		incoming.amount = maxi(1, _turn_of(wave) - state.turn + 1)
		if incoming.amount == 1:
			incoming.unit_types = _unit_types(wave)
		session.engine.record(incoming)


## [constant CombatHooks.Hook.PHASE_END_EFFECTS]: at the player Phase End, closes for good each
## open point on [param session]'s map that a player unit ended its turn on (its
## [constant CombatFact.Kind.UNIT_TURN_END] this Phase End), recording
## [constant CombatFact.Kind.OBJECT_STATE_CHANGED] with [constant MapObjects.Change.POINT_CLOSED]
## and that unit as the target. Does nothing for [param side] other than the player's.
static func close_points(session: CombatSession, side: CombatFact.CombatSide) -> void:
	if side != CombatFact.CombatSide.PLAYER:
		return
	var state: CombatState = session.state
	var ended_on: Dictionary[Vector2i, String] = _turn_end_tiles(session)
	for point: MapState.PointState in _points_of(state):
		if not is_open(state, point.index) or not ended_on.has(point.tile):
			continue
		point.is_closed = true
		var closed: CombatFact = CombatFact.new(
				CombatFact.Kind.OBJECT_STATE_CHANGED, point.id, ended_on[point.tile]
		)
		closed.tile = point.tile
		closed.key = MapObjects.Change.POINT_CLOSED
		session.engine.record(closed)


## [constant CombatHooks.Hook.AFTER_ENEMY_PHASE], bound to [param source]: each open point on
## [param session]'s map, by point index, sends every wave whose arrival turn is this turn or
## earlier, one after another.
static func arrive(session: CombatSession, source: GroupSource) -> void:
	var state: CombatState = session.state
	for point: MapState.PointState in _points_of(state):
		while is_open(state, point.index) and _turn_of(point.waves[point.sent]) <= state.turn:
			var wave: Dictionary = point.waves[point.sent]
			point.sent += 1
			_send(session, source, point, wave)


# Places every unit of wave, then records REINFORCEMENT_ARRIVED with the count placed.
static func _send(
		session: CombatSession,
		source: GroupSource,
		point: MapState.PointState,
		wave: Dictionary
) -> void:
	var placed: int = 0
	var group: Variant = wave.get(GROUP_KEY, [])
	if group is Array:
		# Untyped: setup results are plain data.
		for entry: Variant in group:
			if entry is Dictionary and _place(session, source, point, entry as Dictionary):
				placed += 1
	var arrived: CombatFact = CombatFact.new(CombatFact.Kind.REINFORCEMENT_ARRIVED, point.id)
	arrived.tile = point.tile
	arrived.amount = placed
	session.engine.record(arrived)


# Builds entry's unit and places it on point's tile when free, else on the nearest free tile its
# movement type can stand on. Returns whether it was placed.
static func _place(
		session: CombatSession,
		source: GroupSource,
		point: MapState.PointState,
		entry: Dictionary
) -> bool:
	var state: CombatState = session.state
	var unit_type: String = _unit_type_of(entry)
	var recruit: Recruit = source.build(session, entry, session.ids.next_enemy_id(unit_type))
	if recruit == null or recruit.unit == null:
		_report(session, "no unit built for %s" % [unit_type], point)
		return false
	var unit: CombatUnitState = recruit.unit
	var tile: Vector2i = point.tile
	if not state.occupant_at(tile).is_empty() or not state.can_stand(tile, unit.movement_type):
		tile = Pathing.nearest_free_tile(state, tile, unit.movement_type)
	# ASSUMPTION: a unit with no free tile it could stand on is lost, not held for a later turn.
	if tile == CombatFact.NO_TILE:
		_report(session, "no free tile for %s" % [unit_type], point)
		return false
	for weapon: CombatState.WeaponStats in recruit.weapons:
		state.add_weapon(weapon)
	unit.tile = tile
	return session.add_unit(unit, recruit.bases)


# Adds a diagnostic about a unit of point's wave that didn't arrive.
static func _report(session: CombatSession, problem: String, point: MapState.PointState) -> void:
	session.engine.diagnostics.append(
			"Reinforcements: %s at %s" % [problem, session.describe(point.id)]
	)


# The players' Unit Turn End tiles at the Phase End just run, each to its unit's id.
static func _turn_end_tiles(session: CombatSession) -> Dictionary[Vector2i, String]:
	var tiles: Dictionary[Vector2i, String] = {}
	var facts: Array[CombatFact] = session.engine.fact_log
	# Back to that Phase End, as Objectives reads Seize.
	for i: int in range(facts.size() - 1, -1, -1):
		var fact: CombatFact = facts[i]
		if fact.kind == CombatFact.Kind.PHASE_END:
			break
		if (
				fact.kind == CombatFact.Kind.UNIT_TURN_END
				and session.state.side_of(fact.actor_id) == CombatFact.CombatSide.PLAYER
		):
			tiles[fact.tile] = fact.actor_id
	return tiles


# The points of state's map by point index.
static func _points_of(state: CombatState) -> Array[MapState.PointState]:
	var indexes: Array[int] = []
	indexes.assign(state.map.points.keys())
	indexes.sort()
	var found: Array[MapState.PointState] = []
	for point_index: int in indexes:
		found.append(state.map.points[point_index])
	return found


static func _turn_of(wave: Dictionary) -> int:
	# A float after a JSON round trip.
	var turn: float = wave.get(TURN_KEY, 0)
	return roundi(turn)


static func _unit_types(wave: Dictionary) -> PackedStringArray:
	var types: PackedStringArray = []
	var group: Variant = wave.get(GROUP_KEY, [])
	if not group is Array:
		return types
	# Untyped: setup results are plain data.
	for entry: Variant in group:
		if entry is Dictionary:
			types.append(_unit_type_of(entry as Dictionary))
	return types


static func _unit_type_of(entry: Dictionary) -> String:
	var unit_type: Variant = entry.get(UNIT_TYPE_KEY, "")
	return unit_type if unit_type is String else ""


## Where reinforcement waves' groups come from: P05's enemy groups. Override both methods; this
## base draws no group, so a map's points send nothing.
class GroupSource:
	extends RefCounted

	## The group of the wave arriving at [param point] on [param turn], drawn from
	## [param stream], the shared [code]ENCOUNTER_SETUP[/code] stream of setup step 5: plain data,
	## one Dictionary per unit in arrival order, each naming its
	## [constant Reinforcements.UNIT_TYPE_KEY]. Empty for no wave.
	func draw_group(_stream: RngStream, _point: MapLayout.Marker, _turn: int) -> Array[Dictionary]:
		# TODO(TOD-002): P05's enemy groups, and build() for their units.
		return []

	## The unit [param entry] (one of [method draw_group]'s) arrives as on [param session]'s map:
	## id [param unit_id], side [constant CombatFact.CombatSide.ENEMY], seat -1, not yet placed.
	## Null when it can't be built, and the unit is skipped.
	func build(_session: CombatSession, _entry: Dictionary, _unit_id: String) -> Recruit:
		return null


## One arriving unit as [method GroupSource.build] makes it.
class Recruit:
	extends RefCounted

	## The unit, off the map; [method Reinforcements.arrive] sets its tile.
	var unit: CombatUnitState = null
	## Its base values, value key to number ([method CombatSession.add_unit]).
	var bases: Dictionary = {}
	## The records of the weapons it holds.
	var weapons: Array[CombatState.WeaponStats] = []
