# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_encounter.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name CombatEncounter
extends RefCounted
## One combat node's battle: its sessions, one per map, the setup they share, and everything that
## crosses maps. Sessions never reference each other; this is the only path between them.
##
## [b]Setup[/b] runs once, at battle start, inside [method run_setup]: a fixed, ordered list of
## [enum SetupStep]s other plans register into with [method add_setup_step]. Steps 1 to 5 draw
## from the shared [code]ENCOUNTER_SETUP[/code] stream, then for each seat step 6 from that seat's
## [code]ENCOUNTER_SETUP[/code] stream and step 7 from its [code]MAP_LOOT[/code] streams, one per
## container. Setup streams are derived fresh for the call and live only inside it, so a battle
## restarted from Begin rolls the same setup, loot included. Sessions get the results, never a
## setup stream, and only their own seat's [code]COMBAT_ROLLS[/code] stream, in [LiveRolls].[br]
## [b]Across maps:[/b] cross-map effect instances ([method add_cross_map]) count facts on every
## map, and their counter and activation facts are mirrored here with the encounter's own
## [member CombatFact.seq] and played on [member bus]. Commands are routed to a map by
## [method submit] (a rune cast on a teammate's map) and stamped by one clock, so cross-map order
## is the host's arrival order. Units move between maps with [method send_unit] and
## [method deliver_arrivals].
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

## A map's session was opened: emitted once per map by [method open_sessions].
signal session_opened(session: CombatSession)

## The battle-setup steps, run in this order whatever the order they were registered in (event
## bus plan, question 40). Saved as an int: [b]append only[/b].
enum SetupStep {
	## The map drawn from the pool, loaded through [MapLoader]. Built in; registered steps run
	## after the choice.
	MAP_CHOICE = 1,
	## Which object spots hold an object, so which containers exist (P04).
	OBJECTS = 2,
	## Which darkness source candidates are active (P06).
	DARKNESS_SOURCES = 3,
	## What fills each enemy slot: classes, levels, gear, prefixes (P05).
	ENEMY_SLOTS = 4,
	## Every reinforcement wave's group, drawn now so no session rolls one later (P04).
	REINFORCEMENT_WAVES = 5,
	## Per seat: additions to that seat's map only, such as the Hunted curse's extra enemy (P05).
	SEAT_ADDITIONS = 6,
	## Per seat: every container's contents, each from its own [code]MAP_LOOT[/code] stream by
	## container index (P04).
	CONTAINER_CONTENTS = 7,
}

const _SHARED_STEPS: Array[SetupStep] = [
	SetupStep.MAP_CHOICE,
	SetupStep.OBJECTS,
	SetupStep.DARKNESS_SOURCES,
	SetupStep.ENEMY_SLOTS,
	SetupStep.REINFORCEMENT_WAVES,
]

# The NetLog autoload's script, for its type and enums; see CombatSession.logger().
const NetLogScript = preload("res://scripts/autoload/net_log.gd")

## The campaign floor of the combat node: part of every stream key of the battle.
var floor_number: int = -1

## The combat node on its floor: part of every stream key of the battle.
var node: int = -1

## The seats in the battle, ascending. Each gets its own map and session.
var seats: PackedInt32Array = []

## The run's id allocator, shared by every session. Never null in use.
var ids: InstanceIdAllocator = null

## The setup results; null until [method run_setup] succeeds.
var setup: EncounterSetup = null

## Presentation signals for encounter facts (cross-map counters and activations), on every peer.
var bus: CombatBus = CombatBus.new()

## Plays encounter facts on [member bus] on this peer.
var playback: FactPlayback = null

## Encounter facts in order, each with the encounter's [member CombatFact.seq] and the
## [member CombatFact.session_id] of the map it happened on.
var fact_log: Array[CombatFact] = []

## Whether [method close] was called. A closed encounter opens nothing and routes nothing.
var is_closed: bool = false

# Registered steps: an Array[Callable] per SetupStep, in registration order.
var _steps: Dictionary[int, Array] = {}

var _sessions: Array[CombatSession] = []
var _session_of_seat: Dictionary[int, int] = {}
var _grid: MapGrid = null
var _clock: CombatSession.ArrivalClock = CombatSession.ArrivalClock.new()
var _cross_map: Dictionary[String, EffectInstance] = {}
var _in_transit: Array[Transfer] = []
var _next_seq: int = 1

# The session each unit sent from another map last arrived on, by unit id.
var _arrived_on: Dictionary[String, int] = {}


## [param battle_seats]: every seat in the battle; each gets a map.
func _init(
		floor_index: int,
		node_index: int,
		battle_seats: PackedInt32Array,
		allocator: InstanceIdAllocator
) -> void:
	floor_number = floor_index
	node = node_index
	seats = battle_seats.duplicate()
	seats.sort()
	ids = allocator
	playback = FactPlayback.new(bus)


## Registers [param run] for [param step], after the steps already registered for it. It is called
## as [code]run.call(ctx)[/code] with a [SetupContext]; it draws only from the context's streams
## and writes only plain data into the context's results. Register before [method run_setup].
func add_setup_step(step: SetupStep, run: Callable) -> void:
	if not _steps.has(step):
		var runs: Array[Callable] = []
		_steps[step] = runs
	_steps[step].append(run)


## Runs every setup step once, in [enum SetupStep] order, drawing from [param streams], then closes
## them. Step 1 draws the map from [param pool] (in the given order; a pool of one draws nothing).
## Returns [constant OK]; [constant ERR_ALREADY_IN_USE] when setup already ran or the encounter is
## closed; [constant ERR_UNCONFIGURED] for closed streams; [constant ERR_CANT_OPEN] when no map
## could be chosen and loaded, with nothing set up.
func run_setup(pool: Array[CombatMapDefinition], streams: SetupStreams) -> Error:
	if setup != null or is_closed:
		return ERR_ALREADY_IN_USE
	if streams == null or not streams.is_open():
		return ERR_UNCONFIGURED
	var results: EncounterSetup = EncounterSetup.new()
	var shared: SetupContext = SetupContext.new(results, -1, null, streams.shared(), streams)
	shared.step = SetupStep.MAP_CHOICE
	if not _choose_map(pool, shared):
		streams.close()
		return ERR_CANT_OPEN
	for step: SetupStep in _SHARED_STEPS:
		shared.step = step
		for run: Callable in _steps.get(step, []):
			run.call(shared)
	shared.end()

	for seat: int in seats:
		var seat_setup: SeatSetup = SeatSetup.new(seat)
		results.seats[seat] = seat_setup
		var seat_ctx: SetupContext = SetupContext.new(
				results, seat, seat_setup, streams.for_seat(seat), streams
		)
		seat_ctx.step = SetupStep.SEAT_ADDITIONS
		for run: Callable in _steps.get(SetupStep.SEAT_ADDITIONS, []):
			run.call(seat_ctx)
		seat_ctx.step = SetupStep.CONTAINER_CONTENTS
		seat_ctx.stream = null
		for run: Callable in _steps.get(SetupStep.CONTAINER_CONTENTS, []):
			run.call(seat_ctx)
		seat_ctx.end()
	streams.close()
	setup = results

	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.COMBAT
	)
	if net != null:
		net.info(
				NetLogScript.Category.COMBAT,
				"%s SETUP map %s for seats %s" % [_tag(), results.map.id, seats]
		)
	return OK


## Opens one session per seat on the chosen map, each rolling from its seat's
## [code]COMBAT_ROLLS[/code] stream in [param combat_rolls] (by seat) wrapped in [LiveRolls], and
## emits [signal session_opened] for each. Session ids follow [member seats]: the lowest seat's map
## is session 0. Call once, after [method run_setup]. Returns false, opening nothing, before setup,
## when already open, or when a seat has no stream.
func open_sessions(combat_rolls: Dictionary[int, RngStream]) -> bool:
	if setup == null or is_closed or not _sessions.is_empty():
		return false
	for seat: int in seats:
		if combat_rolls.get(seat, null) == null:
			return false
	_grid = MapGrid.new(setup.layout)
	for index: int in seats.size():
		var seat: int = seats[index]
		var session: CombatSession = CombatSession.new(
				index,
				PackedInt32Array([seat]),
				_grid,
				LiveRolls.new(combat_rolls[seat]),
				ids,
				_clock
		)
		session.setup = setup
		session.seat_setup = setup.seats[seat]
		session.fact_recorded.connect(_on_session_fact_recorded)
		_sessions.append(session)
		_session_of_seat[seat] = index
	for session: CombatSession in _sessions:
		session_opened.emit(session)
	return true


## The session with [param session_id]; null when there is none.
func get_session(session_id: int) -> CombatSession:
	if session_id < 0 or session_id >= _sessions.size():
		return null
	return _sessions[session_id]


## Every session, by session id.
func get_sessions() -> Array[CombatSession]:
	return _sessions.duplicate()


## The session of [param seat]'s map; null when the seat isn't in the battle.
func session_of_seat(seat: int) -> CombatSession:
	var session_id: int = _session_of_seat.get(seat, -1)
	return get_session(session_id)


## The session whose record of [param unit_id] is current: the map it last arrived on from another
## map, else the first map that has it. Null when no map has it. A won map keeps the record of
## a unit it sent away, so read a unit through this, never by searching the sessions.
func session_of_unit(unit_id: String) -> CombatSession:
	if _arrived_on.has(unit_id):
		return get_session(_arrived_on[unit_id])
	for session: CombatSession in _sessions:
		if session.state.unit(unit_id) != null:
			return session
	return null


## Adds [param instance] as a cross-map effect: it counts facts on every map and its operations
## land where its trigger happened. Its combat lane starts fresh; campaign-lane values copied in
## before are kept. Call after [method open_sessions]. Returns false, adding nothing, for an
## instance [method is_cross_map] refuses or one already added.
func add_cross_map(instance: EffectInstance) -> bool:
	if not is_cross_map(instance) or _cross_map.has(instance.instance_id):
		return false
	instance.reset_lane(EffectDefinition.Lane.COMBAT)
	_cross_map[instance.instance_id] = instance
	# ASSUMPTION: one instance registered in every session's engine is how a cross-map effect
	# forwards, since the engine has no forwarding hook: each map dispatches it from its own trigger
	# index and the shared object holds the one counter. Its queued operations resolve on the map
	# where the trigger happened, so "Your Units" never reaches the owner's map from another one;
	# deferred, since no MVP content needs it.
	for session: CombatSession in _sessions:
		session.engine.register(instance, true)
	return true


## Every cross-map instance, by instance id.
func get_cross_map_instances() -> Array[EffectInstance]:
	var instances: Array[EffectInstance] = []
	instances.assign(_cross_map.values())
	instances.sort_custom(func(a: EffectInstance, b: EffectInstance) -> bool:
		return a.instance_id < b.instance_id
	)
	return instances


## Routes [param command] to the session [param session_id], stamped by the encounter's one clock;
## a rune cast on a teammate's map is routed this way with the caster's seat. Nothing resolves
## until [method resolve_queued]. Returns the arrival stamp, or
## [constant CombatSession.NO_ARRIVAL] when there is no such session.
func submit(command: Command, session_id: int) -> int:
	var session: CombatSession = get_session(session_id)
	if session == null or is_closed:
		return CombatSession.NO_ARRIVAL
	return session.submit(command)


## Resolves every queued command on every map in arrival order, so cross-map counters see the
## host's order. Returns the batches in that order.
func resolve_queued() -> Array[CombatSession.FactBatch]:
	var batches: Array[CombatSession.FactBatch] = []
	var next: CombatSession = _next_to_resolve()
	while next != null:
		batches.append(next.resolve_next())
		next = _next_to_resolve()
	return batches


## Sends [param unit_id], a surviving player unit on the won map [param from_session_id], toward
## the map [param to_session_id], still being fought, where it arrives at that map's next Phase
## Start ([method deliver_arrivals]) on [param arrival_tile] or the nearest free tile. Only a won
## map sends (the vision: "a player who wins their map can send any of their surviving units"); a
## lost map's player spectates. Its effects leave with their state; the won map keeps the unit's
## record as it was. Returns why it can't be sent, or empty when it was.
func send_unit(
		unit_id: String, from_session_id: int, to_session_id: int, arrival_tile: Vector2i
) -> String:
	var source: CombatSession = get_session(from_session_id)
	var target: CombatSession = get_session(to_session_id)
	if source == null or target == null or source == target:
		return "no such pair of maps"
	if not source.is_finished:
		return "s%d is still being fought" % [from_session_id]
	if not source.is_won:
		return "s%d was lost" % [from_session_id]
	if target.is_finished:
		return "s%d has finished" % [to_session_id]
	if (
			not source.state.has_unit(unit_id)
			or source.state.side_of(unit_id) != CombatFact.CombatSide.PLAYER
	):
		return "%s isn't a player unit on s%d" % [unit_id, from_session_id]
	for waiting: Transfer in _in_transit:
		if waiting.unit.id == unit_id:
			return "%s is already on its way" % [unit_id]

	var transfer: Transfer = Transfer.new()
	transfer.unit = source.state.unit(unit_id).copy()
	transfer.to_session_id = to_session_id
	transfer.tile = arrival_tile
	transfer.bases = source.bases_of(unit_id).duplicate()
	for weapon_id: String in [transfer.unit.equipped_weapon_id, transfer.unit.stowed_weapon_id]:
		var weapon: CombatState.WeaponStats = source.state.weapon(weapon_id)
		if weapon != null:
			transfer.weapons.append(weapon)
	for instance: EffectInstance in source.engine.get_instances():
		if instance.owner.holder_id == unit_id:
			transfer.instances.append(source.engine.unregister(instance.instance_id))
	_in_transit.append(transfer)

	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.COMBAT
	)
	if net != null:
		net.info(
				NetLogScript.Category.COMBAT,
				"%s UNIT SENT %s s%d -> s%d"
				% [_tag(), source.describe(unit_id), from_session_id, to_session_id]
		)
	return ""


## Places every unit on its way to [param session_id], at the receiving map's Phase Start (the
## combat core's phase runner calls this before the Block and Stance refresh, P02 CC6): its
## effects join the map with their counters and charges, then it is placed with Block 0 and full
## Stance, recording [constant CombatFact.Kind.UNIT_SPAWNED]. Returns the ids placed; a unit with
## no free tile stays on its way.
func deliver_arrivals(session_id: int) -> PackedStringArray:
	var delivered: PackedStringArray = []
	var target: CombatSession = get_session(session_id)
	if target == null:
		return delivered
	var waiting: Array[Transfer] = []
	for transfer: Transfer in _in_transit:
		if transfer.to_session_id != session_id or not _arrive(target, transfer):
			waiting.append(transfer)
		else:
			delivered.append(transfer.unit.id)
	_in_transit = waiting
	return delivered


## Ids of the units on their way to another map.
func units_in_transit() -> PackedStringArray:
	var waiting: PackedStringArray = []
	for transfer: Transfer in _in_transit:
		waiting.append(transfer.unit.id)
	return waiting


## Ends the encounter: its sessions stop reporting here and routing stops. The caller writes
## campaign-lane values back first (the campaign bridge, through the instances it registered).
func close() -> void:
	if is_closed:
		return
	is_closed = true
	for session: CombatSession in _sessions:
		if session.fact_recorded.is_connected(_on_session_fact_recorded):
			session.fact_recorded.disconnect(_on_session_fact_recorded)
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.COMBAT
	)
	if net != null:
		net.info(NetLogScript.Category.COMBAT, "%s CLOSED" % [_tag()])


## [param id] in log text, from whichever map knows it best: the first session that has the unit
## or instance, else the allocator.
func describe(id: String) -> String:
	for session: CombatSession in _sessions:
		if session.state.has_unit(id) or session.engine.get_instance(id) != null:
			return session.describe(id)
	return ids.describe(id)


# Step 1: the map, drawn from the pool with the shared stream.
func _choose_map(pool: Array[CombatMapDefinition], ctx: SetupContext) -> bool:
	if pool.is_empty():
		push_error("CombatEncounter: no map in the pool - %s" % [_tag()])
		return false
	var definition: CombatMapDefinition = pool[ctx.stream.pick_index(pool.size())]
	var layout: MapLayout = MapLoader.load_layout(definition)
	if layout == null:
		return false
	ctx.setup.map = definition
	ctx.setup.layout = layout
	return true


# The session whose next queued command arrived first; null when none has one.
func _next_to_resolve() -> CombatSession:
	var next: CombatSession = null
	for session: CombatSession in _sessions:
		var arrival: int = session.next_arrival()
		if arrival == CombatSession.NO_ARRIVAL:
			continue
		if next == null or arrival < next.next_arrival():
			next = session
	return next


func _arrive(target: CombatSession, transfer: Transfer) -> bool:
	var unit: CombatUnitState = transfer.unit
	var tile: Vector2i = transfer.tile
	if (
			not target.state.occupant_at(tile).is_empty()
			or not target.state.can_stand(tile, unit.movement_type)
	):
		tile = Pathing.nearest_free_tile(target.state, tile, unit.movement_type)
	if tile == CombatFact.NO_TILE:
		return false
	for weapon: CombatState.WeaponStats in transfer.weapons:
		target.state.add_weapon(weapon)
	# Effects first, so the full Stance set at placement counts them.
	for instance: EffectInstance in transfer.instances:
		target.engine.register(instance, true)
	unit.tile = tile
	unit.has_acted = false
	unit.tiles_moved = 0
	unit.movement_spent = 0
	unit.is_second_move_pending = false
	unit.has_been_shoved = false
	unit.has_used_sidearm = false
	target.add_unit(unit, transfer.bases)
	_arrived_on[unit.id] = target.session_id

	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.COMBAT
	)
	if net != null:
		net.info(
				NetLogScript.Category.COMBAT,
				"%s UNIT ARRIVED %s on s%d at %s"
				% [_tag(), target.describe(unit.id), target.session_id, tile]
		)
	return true


# Mirrors a cross-map instance's counter and activation facts as encounter facts.
func _on_session_fact_recorded(fact: CombatFact) -> void:
	if not _cross_map.has(fact.source_effect_id):
		return
	if (
			fact.kind != CombatFact.Kind.COUNTER_CHANGED
			and fact.kind != CombatFact.Kind.EFFECT_ACTIVATED
	):
		return
	var mirrored: CombatFact = CombatFact.from_wire(fact.to_wire())
	mirrored.seq = _next_seq
	_next_seq += 1
	fact_log.append(mirrored)
	var facts: Array[CombatFact] = [mirrored]
	playback.enqueue(facts)
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.DEBUG, NetLogScript.Category.EFFECTS
	)
	if net != null:
		net.debug(
				NetLogScript.Category.EFFECTS,
				"%s#%d mirrors %s" % [_tag(), mirrored.seq, fact.to_log_line(describe)]
		)


# The encounter's tag in log lines: "e2.5", its floor and node.
func _tag() -> String:
	return "e%d.%d" % [floor_number, node]


## Whether [param instance] belongs in the encounter as a cross-map effect: a player's army effect
## (a heirloom or curse) scoped Any Ally Unit or Any Unit with no position condition, which never
## matches across maps. Everything else registers in its own map's session.
static func is_cross_map(instance: EffectInstance) -> bool:
	if instance == null or instance.definition == null:
		return false
	# Only army owners are cross-map: a unit's or item's effect sleeps on every map its holder
	# isn't on (event bus plan, fix F8), so it can't count on a partner's map.
	if instance.owner.kind != EffectOwner.Kind.ARMY:
		return false
	var scope: EffectDefinition.Scope = instance.definition.scope
	if scope != EffectDefinition.Scope.ANY_ALLY_UNIT and scope != EffectDefinition.Scope.ANY_UNIT:
		return false
	for condition: EffectCondition in instance.definition.conditions:
		if condition is WhilePositionCondition:
			return false
	return true


## The battle's setup streams, derived fresh from the run seed and the node for one
## [method run_setup] call, then closed: after that every request returns null. Made by the
## campaign session, which owns the run seed; the encounter never keeps one. Each stream is created
## on first request, logged at DEBUG with its key and seed, and the same one is returned for the
## same key until closed.
class SetupStreams:
	extends RefCounted

	var _run_seed: int = 0
	var _floor_number: int = -1
	var _node: int = -1
	var _is_open: bool = true
	var _streams: Dictionary[String, RngStream] = {}

	func _init(seed_of_run: int, floor_index: int, node_index: int) -> void:
		_run_seed = seed_of_run
		_floor_number = floor_index
		_node = node_index

	## Whether requests still give streams.
	func is_open() -> bool:
		return _is_open

	## The shared [code]ENCOUNTER_SETUP[/code] stream: steps 1 to 5.
	func shared() -> RngStream:
		return _stream_for(RngKey.RngPurpose.ENCOUNTER_SETUP, -1, -1)

	## [param seat]'s own [code]ENCOUNTER_SETUP[/code] stream: step 6.
	func for_seat(seat: int) -> RngStream:
		return _stream_for(RngKey.RngPurpose.ENCOUNTER_SETUP, seat, -1)

	## The [code]MAP_LOOT[/code] stream of container [param container_index] on [param seat]'s map:
	## step 7.
	func loot(seat: int, container_index: int) -> RngStream:
		return _stream_for(RngKey.RngPurpose.MAP_LOOT, seat, container_index)

	## Ends the setup call: every later request returns null and the streams are dropped.
	func close() -> void:
		_is_open = false
		_streams.clear()

	func _stream_for(purpose: RngKey.RngPurpose, seat: int, index: int) -> RngStream:
		if not _is_open:
			push_error("CombatEncounter: a setup stream was asked for after setup")
			return null
		var key: RngKey = RngKey.new(purpose, _floor_number, _node, seat, index)
		var save_key: String = key.to_save_key()
		if _streams.has(save_key):
			return _streams[save_key]
		var stream_seed: int = RngKey.derive_seed(
				_run_seed, purpose, _floor_number, _node, seat, index
		)
		var created: RngStream = RngStream.new(stream_seed)
		_streams[save_key] = created
		var net: NetLogScript = CombatSession.logger(
				NetLogScript.Level.DEBUG, NetLogScript.Category.COMBAT
		)
		if net != null:
			net.debug(
					NetLogScript.Category.COMBAT,
					"stream %s key %s seed %d"
					% [RngKey.RngPurpose.find_key(purpose), save_key, stream_seed]
			)
		return created


## What one setup step sees: the results so far, the seat, and the stream it may draw from.
class SetupContext:
	extends RefCounted

	## The setup results so far; steps add theirs.
	var setup: EncounterSetup = null
	## The step running.
	var step: SetupStep = SetupStep.MAP_CHOICE
	## The seat, for steps 6 and 7; -1 for the shared steps.
	var seat: int = -1
	## That seat's results, for steps 6 and 7; null for the shared steps.
	var seat_setup: SeatSetup = null
	## The stream to draw from: the shared [code]ENCOUNTER_SETUP[/code] for steps 1 to 5, the seat's
	## for step 6; null for step 7 ([method loot_stream]) and once setup has ended.
	var stream: RngStream = null

	var _streams: SetupStreams = null

	func _init(
			results: EncounterSetup,
			for_seat: int,
			results_of_seat: SeatSetup,
			draw_from: RngStream,
			streams: SetupStreams
	) -> void:
		setup = results
		seat = for_seat
		seat_setup = results_of_seat
		stream = draw_from
		_streams = streams

	## The [code]MAP_LOOT[/code] stream of container [param container_index] on this seat's map
	## ([member MapLayout.Marker.container_index]). Step 7 only; null in any other step or after
	## setup.
	func loot_stream(container_index: int) -> RngStream:
		if step != SetupStep.CONTAINER_CONTENTS or _streams == null:
			return null
		return _streams.loot(seat, container_index)

	## Ends the context: it gives no stream from now on.
	func end() -> void:
		stream = null
		_streams = null


## The results every map of the battle shares: the map, and what steps 2 to 5 drew.
class EncounterSetup:
	extends RefCounted

	## The map drawn from the pool (step 1).
	var map: CombatMapDefinition = null
	## Its layout, shared read-only by every session.
	var layout: MapLayout = null
	## What steps 2 to 5 drew, under a key each owning plan chooses: plain data only, ids as
	## strings.
	var shared: Dictionary[String, Variant] = {}
	## Each seat's results (steps 6 and 7), by seat.
	var seats: Dictionary[int, SeatSetup] = {}

	## Every result as one line of text with sorted keys, for comparing two setups.
	func summary() -> String:
		var by_seat: Dictionary = {}
		for seat: int in seats:
			by_seat[str(seat)] = {
				"additions": seats[seat].additions,
				"contents": seats[seat].contents,
			}
		var data: Dictionary = {
			"map": "" if map == null else map.id,
			"shared": shared,
			"seats": by_seat,
		}
		return JSON.stringify(data, "", true)


## One seat's own setup results: steps 6 and 7.
class SeatSetup:
	extends RefCounted

	## The seat they belong to.
	var seat: int = -1
	## Additions to this seat's map only (step 6), under a key each owning plan chooses.
	var additions: Dictionary[String, Variant] = {}
	# ASSUMPTION: contents stay in the seat's setup result until MapState holds them (P04 MP6);
	# decision 40 makes them map state.
	## Each container's contents on this seat's map (step 7), by container index: plain data, such
	## as an item definition id.
	var contents: Dictionary[int, Variant] = {}

	func _init(owner_seat: int) -> void:
		seat = owner_seat


# A unit on its way from a won map to another one.
class Transfer:
	extends RefCounted

	var unit: CombatUnitState = null
	var to_session_id: int = -1
	var tile: Vector2i = CombatFact.NO_TILE
	var bases: Dictionary = {}
	var weapons: Array[CombatState.WeaponStats] = []
	var instances: Array[EffectInstance] = []
