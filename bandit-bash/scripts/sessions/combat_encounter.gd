# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_encounter.gd
# Author:
# Created:  October 28, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name CombatEncounter
extends RefCounted
## One combat node's battle: its sessions, one per map, the setup they share, and everything that
## crosses maps. Sessions never reference each other; this is the only path between them.
##
## [b]Setup[/b] ([method run_setup]) runs the [enum SetupStep]s once, in order, from
## [SetupStreams] that live only inside the call, so a battle restarted from Begin rolls the same
## setup. Sessions get the results and only their own seat's [code]COMBAT_ROLLS[/code] stream.[br]
## [b]Across maps:[/b] cross-map effects ([method add_cross_map]), whose counter and activation
## facts are mirrored into [member fact_log]; commands stamped by one clock ([method submit]),
## the co-op sends and calls for aid resolved here ([SendUnitsCommand], [CallForAidCommand]);
## units on their way, landing by the battle clock or going back when their target ends first.
## In co-op an empty map freezes ([method is_frozen]) until help lands, and [method is_run_lost]
## says when none can.[br]
## [b]Snapshots[/b] ([method snapshot], [method load_snapshot]) hold the encounter's own state and
## every map's, for the save sections ([CombatStateSection]); encounter facts go out on
## [signal batch_resolved] and a mirror applies them with [method apply_batch].
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## A map's session was opened: emitted once per map by [method open_sessions].
signal session_opened(session: CombatSession)

## A batch of encounter facts is ready to send: a send or call for aid resolved, or the facts a
## map's batch led to here (cross-map counters, units sent back), right after that map's batch.
## [member CombatSession.FactBatch.session_id] is that map. A mirror applies it with
## [method apply_batch].
signal batch_resolved(batch: CombatSession.FactBatch)

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

# The shape of snapshot() output; raised when it changes. Never saved as it is
# (CombatStateSection saves its parts), so another format is refused.
const _SNAPSHOT_FORMAT: int = 3

## The campaign floor of the combat node: part of every stream key of the battle.
var floor_number: int = -1

## The combat node on its floor: part of every stream key of the battle.
var node: int = -1

## The seats in the battle, ascending. Each gets its own map and session.
var seats: PackedInt32Array = []

## The run's id allocator, shared by every session. Never null in use.
var ids: InstanceIdAllocator = null

## The run's seed, handed to every session ([member CombatSession.run_seed]) so snapshots and
## dumps name their run. Set by the campaign session before [method open_sessions]; draws nothing.
var run_seed: int = 0

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

# Sends and calls for aid stamped by the clock, waiting for resolve_queued(), and the map each was
# submitted on, index for index.
var _queue: Array[Command] = []
var _queue_maps: Array[int] = []

# Each seat's latest send, by seat: [the target's session id or -1 for none, the turn its map was
# won on].
var _sends: Dictionary[int, PackedInt32Array] = {}

# The seats whose sent units landed on each map, ascending, by session id.
var _senders: Dictionary[int, PackedInt32Array] = {}

# The maps whose call for aid is raised, ascending.
var _aid_called: PackedInt32Array = []

# Seats that left the battle: saved, and empty until forfeits exist.
var _forfeited: PackedInt32Array = []

# Index into fact_log of the first fact not yet in a batch.
var _batched_up_to: int = 0


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
## is session 0. Each session's map state starts as a copy of its seat's
## [member SeatSetup.map], container contents included, and it gets the encounter's arrivals
## ([method deliver_arrivals]) and the objective checks ([method Objectives.register]) as hooks.
## Call once, after [method run_setup].
## Returns false, opening nothing, before setup, when already open, or when a seat has no stream.
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
		session.run_seed = run_seed
		# A copy, so the setup result stays as rolled while the battle changes the map.
		session.state.map = setup.seats[seat].map.copy()
		session.fact_recorded.connect(_on_session_fact_recorded)
		session.hooks.add(CombatHooks.Hook.ARRIVALS, _on_session_arrivals_due)
		Objectives.register(session)
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
	_drop_landed()
	return _current_session_of(unit_id)


## Adds [param instance] as a cross-map effect: it counts facts on every map and its operations
## land where its trigger happened. Its combat lane starts fresh; campaign-lane values copied in
## before are kept. Call after [method open_sessions]. Returns false, adding nothing, for an
## instance [method is_cross_map] refuses or one already added.
func add_cross_map(instance: EffectInstance) -> bool:
	if not is_cross_map(instance) or _cross_map.has(instance.instance_id):
		return false
	instance.reset_lane(EffectTerms.Lane.COMBAT)
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
## a rune cast on a teammate's map is routed this way with the caster's seat. A send (on the
## sender's won map) or a call for aid (on the caller's map) waits in the encounter's own queue
## instead, never the map's. Nothing resolves until [method resolve_queued]. Returns the arrival
## stamp, or [constant CombatSession.NO_ARRIVAL] when there is no such session.
func submit(command: Command, session_id: int) -> int:
	var session: CombatSession = get_session(session_id)
	if session == null or is_closed:
		return CombatSession.NO_ARRIVAL
	if not (command is SendUnitsCommand or command is CallForAidCommand):
		return session.submit(command)
	command.arrival = _clock.stamp()
	_queue.append(command)
	_queue_maps.append(session_id)
	return command.arrival


## Resolves every queued command on every map, and the encounter's own, in arrival order, so
## cross-map counters see the host's order. After each map batch, units bound for a map that has
## ended go back ([constant CombatFact.Kind.UNIT_RETURNED]) and the encounter facts go out on
## [signal batch_resolved]. Returns the map batches in order: a send's or call's refusal, and a
## frozen map's restart, are map batches; the encounter's facts are not.
func resolve_queued() -> Array[CombatSession.FactBatch]:
	var batches: Array[CombatSession.FactBatch] = []
	while true:
		var next: CombatSession = _next_to_resolve()
		var own: int = CombatSession.NO_ARRIVAL if _queue.is_empty() else _queue[0].arrival
		if next == null and own == CombatSession.NO_ARRIVAL:
			break
		if own != CombatSession.NO_ARRIVAL and (next == null or own < next.next_arrival()):
			batches.append_array(_resolve_own())
			continue
		var batch: CombatSession.FactBatch = next.resolve_next()
		batches.append(batch)
		_return_from_finished()
		_flush(batch.session_id, batch.seat, batch.arrival, batch.label)
	return batches


## Sends [param unit_id], a surviving player unit on the won map [param from_session_id], toward
## the map [param to_session_id], still being fought, aimed at [param arrival_tile]
## ([constant CombatFact.NO_TILE]: the receiving commander), as [SendUnitsCommand] sends one but
## without its seat's rules. Its effects leave with their state; the won map keeps the unit's
## record as it was. A frozen target restarts at once. For tools and tests; play sends through
## [method submit]. Returns why it can't be sent, or empty when it was.
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
	if units_in_transit().has(unit_id):
		return "%s is already on its way" % [unit_id]
	var units: PackedStringArray = [unit_id]
	_send(source.state.seat_of(unit_id), source, units, to_session_id, arrival_tile)
	_flush(from_session_id, -1, CombatSession.NO_ARRIVAL, "unit sent")
	_restart(to_session_id)
	return ""


## Places every unit on its way to [param session_id] now, the battle clock ignored (the
## receiving map's [constant CombatHooks.Hook.ARRIVALS] keeps it): its effects join the map with
## their counters and charges, then it is placed with Block 0 and full Stance, recording
## [constant CombatFact.Kind.UNIT_SPAWNED]. It lands on its aimed tile when that is free and dry,
## else on [method Pathing.nearest_free_tile]'s, dry first. Returns the ids placed; a unit with no
## free tile stays on its way.
func deliver_arrivals(session_id: int) -> PackedStringArray:
	return _deliver(session_id, false)


## Ids of the units on their way to another map.
func units_in_transit() -> PackedStringArray:
	_drop_landed()
	var waiting: PackedStringArray = []
	for transfer: Transfer in _in_transit:
		waiting.append(transfer.unit.id)
	return waiting


## Whether [param seat] has sent, units or none. A seat that has sends again only to a frozen map.
func has_sent(seat: int) -> bool:
	return _sends.has(seat)


## The seats whose sent units landed on the map [param session_id], ascending: that map earns no
## speed bonus when any did. Empty for a map that received none.
func senders_of(session_id: int) -> PackedInt32Array:
	_drop_landed()
	var found: PackedInt32Array = _senders.get(session_id, PackedInt32Array())
	return found.duplicate()


## Whether the map [param session_id]'s call for aid is raised ([CallForAidCommand]). It stays as
## it was when the map ends.
func is_aid_called(session_id: int) -> bool:
	return _aid_called.has(session_id)


## Whether the map [param session_id] is frozen: a co-op map still being fought with no player unit
## left, held after its enemy phase at the next player Phase Start ([method PhaseRunner.resume]).
## Read between steps. Derived from the map's state, never saved or sent, so a mirror and a
## resumed battle answer the same. False in solo and for an unknown map.
func is_frozen(session_id: int) -> bool:
	var session: CombatSession = get_session(session_id)
	if session == null or seats.size() <= 1 or session.is_finished:
		return false
	var state: CombatState = session.state
	return (
			state.phase_side == CombatFact.CombatSide.ENEMY
			and state.is_phase_ended
			and state.units_of(CombatFact.CombatSide.PLAYER).is_empty()
	)


## Whether the co-op run is lost: a map is frozen ([method is_frozen]) with no unit on its way to
## it, and no map can still help: none is still being fought and no won map holds a player unit it
## could yet send. A map still being fought may win and send, so the run waits for it. A pure
## query: ask it whenever a map freezes or ends; the encounter ends nothing itself. Always false
## in solo.
func is_run_lost() -> bool:
	if seats.size() <= 1:
		return false
	_drop_landed()
	var awaited: Dictionary[int, bool] = {}
	for transfer: Transfer in _in_transit:
		awaited[transfer.to_session_id] = true
	var is_stranded: bool = false
	for session: CombatSession in _sessions:
		if is_frozen(session.session_id):
			# ASSUMPTION: a frozen map with a unit on its way resumes when it lands, so it counts as
			# help for another frozen map too.
			if awaited.has(session.session_id):
				return false
			is_stranded = true
		elif not session.is_finished:
			return false
		elif session.is_won and _has_unit_to_send(session):
			return false
	return is_stranded


## Whether every map's combat has ended ([member CombatSession.is_finished]): a map's end ends only
## its own session, and the battle ends with the last one. False before [method open_sessions].
func is_finished() -> bool:
	if _sessions.is_empty():
		return false
	for session: CombatSession in _sessions:
		if not session.is_finished:
			return false
	return true


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


## The battle's state as plain JSON values, between commands: [code]encounter[/code] (the next
## encounter seq, where sent units arrived, every cross-map instance, every unit on its way with
## its bases, weapons, effects and clock turn, each seat's send, each map's senders and call for
## aid, forfeited seats) and [code]sessions[/code], each map's [method CombatSession.snapshot] by
## session id, named by the run seed and the build version. [method load_snapshot] reverses it.
## [param reference]: see [method EffectInstance.capture].
func snapshot(reference: Callable = Callable()) -> Dictionary:
	_drop_landed()
	var sessions: Array = []
	for session: CombatSession in _sessions:
		sessions.append(session.snapshot(reference))
	return {
		"format": _SNAPSHOT_FORMAT,
		"run_seed": RunSeed.format(run_seed),
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"encounter": _capture_encounter(reference),
		"sessions": sessions,
	}


## Replaces the battle's state with [param data] from [method snapshot], also after a trip
## through JSON: the cross-map instances first, then each map with
## [method CombatSession.load_snapshot], the same cross-map objects shared by every map's engine,
## then the units on their way. Load it into an encounter built the way this battle was (same
## node, seats and setup, sessions open). [param resolve]: see
## [method EffectInstance.from_capture]. Returns [constant OK], or [constant ERR_INVALID_DATA]
## when the data is malformed or for another battle; a map that refused leaves the maps before it
## loaded, so drop the encounter then.
func load_snapshot(data: Dictionary, resolve: Callable = Callable()) -> Error:
	var part: Variant = data.get("encounter", null)
	var maps: Variant = data.get("sessions", null)
	if (
			_whole(data.get("format", null)) != _SNAPSHOT_FORMAT
			or not part is Dictionary
			or not maps is Array
			or (maps as Array).size() != _sessions.size()
	):
		return _refuse_snapshot("not a snapshot of these maps")
	var encounter_part: Dictionary = part
	var next: Variant = encounter_part.get("next_seq", null)
	var arrived: Variant = encounter_part.get("arrived_on", null)
	var captured: Variant = encounter_part.get("cross_map", null)
	var travelling: Variant = encounter_part.get("in_transit", null)
	var sends: Variant = _sends_from(encounter_part.get("sends", null))
	var senders: Variant = _senders_from(encounter_part.get("senders", null))
	var aid: Variant = _whole_list(encounter_part.get("aid", null))
	var forfeited: Variant = _whole_list(encounter_part.get("forfeited", null))
	if (
			_whole(encounter_part.get("floor", null)) != floor_number
			or _whole(encounter_part.get("node", null)) != node
			or not (next is float or next is int)
			or not arrived is Dictionary
			or not captured is Array
			or not travelling is Array
			or sends == null
			or senders == null
			or aid == null
			or forfeited == null
	):
		return _refuse_snapshot("its encounter part is malformed or for another battle")
	var in_transit: Array[Transfer] = []
	for entry: Variant in travelling:
		var transfer: Transfer = (
				_transfer_from(entry as Dictionary, resolve) if entry is Dictionary else null
		)
		if transfer == null:
			return _refuse_snapshot("a unit on its way can't be restored")
		in_transit.append(transfer)
	var shared: Dictionary[String, EffectInstance] = {}
	# Untyped: the parts come from JSON and are checked entry by entry.
	for entry: Variant in captured:
		var instance: EffectInstance = (
				EffectInstance.from_capture(entry as Dictionary, resolve)
				if entry is Dictionary else null
		)
		if instance == null:
			return _refuse_snapshot("a cross-map instance can't be restored")
		shared[instance.instance_id] = instance
	var arrived_on: Dictionary[String, int] = {}
	var by_unit: Dictionary = arrived
	for unit_id: Variant in by_unit:
		var where: Variant = by_unit[unit_id]
		if not (where is float or where is int):
			return _refuse_snapshot("arrival of %s" % [unit_id])
		var where_number: float = where
		arrived_on[str(unit_id)] = roundi(where_number)
	var map_list: Array = maps
	for index: int in _sessions.size():
		if not map_list[index] is Dictionary:
			return _refuse_snapshot("map %d isn't a snapshot" % [index])
		var err: Error = _sessions[index].load_snapshot(
				map_list[index] as Dictionary, resolve, shared
		)
		if err != OK:
			return err

	_cross_map = shared
	_arrived_on = arrived_on
	_in_transit = in_transit
	_sends = sends
	_senders = senders
	_aid_called = aid
	_forfeited = forfeited
	_queue.clear()
	_queue_maps.clear()
	var next_number: float = next
	_next_seq = roundi(next_number)
	fact_log.clear()
	_batched_up_to = 0
	return OK


## A number standing for the encounter's own state: the [code]encounter[/code] part of
## [method snapshot]. Each map has its own ([method CombatSession.state_hash]).
func state_hash() -> int:
	_drop_landed()
	var by_id: Callable = func(definition: EffectDefinition) -> String:
		return definition.id
	return JSON.stringify(_capture_encounter(by_id), "", true).hash()


## Applies [param batch], encounter facts from the host, as this encounter's mirror, which follows
## every map of its encounter too: each fact not yet applied, in encounter seq order, joins
## [member fact_log] and playback. A counter fact sets its cross-map instance's count; a send takes
## the unit from this mirror's won map onto its way, a return puts it back, a call for aid sets
## the flag; a unit on its way that its target's batch already placed has landed. A fact already
## applied is skipped. Returns [constant OK]; [constant ERR_INVALID_PARAMETER] for null;
## [constant ERR_PARAMETER_RANGE_ERROR] when a seq is missing (the facts before the gap apply);
## [constant ERR_INVALID_DATA] in debug builds when applied but the hashes differ.
func apply_batch(batch: CombatSession.FactBatch) -> Error:
	if batch == null:
		return ERR_INVALID_PARAMETER
	var applied: Array[CombatFact] = []
	var gap_at: int = -1
	for fact: CombatFact in batch.facts:
		if fact.seq < _next_seq:
			continue
		if fact.seq != _next_seq:
			gap_at = fact.seq
			break
		_next_seq += 1
		applied.append(fact)
		fact_log.append(fact)
		_follow(fact)
	_batched_up_to = fact_log.size()
	playback.enqueue(applied)
	_drop_landed()
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.WARN, NetLogScript.Category.COMBAT
	)
	if gap_at >= 0:
		if net != null:
			net.warn(
					NetLogScript.Category.COMBAT,
					"%s mirror gap: next was #%d, got #%d" % [_tag(), _next_seq, gap_at]
			)
		return ERR_PARAMETER_RANGE_ERROR
	if (
			batch.state_hash == CombatSession.NO_HASH
			or batch.facts.is_empty()
			or _next_seq - 1 != batch.last_seq()
			or not OS.is_debug_build()
	):
		return OK
	var local_hash: int = state_hash()
	if local_hash == batch.state_hash:
		return OK
	if net != null:
		net.warn(
				NetLogScript.Category.COMBAT,
				"%s#%d mirror hash mismatch: host %d, mirror %d"
				% [_tag(), _next_seq - 1, batch.state_hash, local_hash]
		)
	return ERR_INVALID_DATA


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


# Lands transfer on target, as deliver_arrivals() describes; false when no tile is free.
func _arrive(target: CombatSession, transfer: Transfer) -> bool:
	var unit: CombatUnitState = transfer.unit
	var tile: Vector2i = transfer.tile
	if tile == CombatFact.NO_TILE:
		tile = _anchor_of(target)
		if tile == CombatFact.NO_TILE:
			return false
	if (
			not target.state.occupant_at(tile).is_empty()
			or not target.state.can_stand(tile, unit.movement_type)
			or target.state.map.darkness.layer_at(tile) != WhileLayerCondition.Layer.DRY
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
	_landed(target, unit)

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


# Whether the won map session holds a player unit send_unit would take: one whose current record
# is there (a unit it sent keeps a record there) and that isn't on its way.
func _has_unit_to_send(session: CombatSession) -> bool:
	var travelling: PackedStringArray = units_in_transit()
	for unit_id: String in session.state.units_of(CombatFact.CombatSide.PLAYER):
		if not travelling.has(unit_id) and _current_session_of(unit_id) == session:
			return true
	return false


# The session whose record of unit_id is current (session_of_unit), with no landing settled first.
func _current_session_of(unit_id: String) -> CombatSession:
	if _arrived_on.has(unit_id):
		return get_session(_arrived_on[unit_id])
	for session: CombatSession in _sessions:
		if session.state.unit(unit_id) != null:
			return session
	return null


# Takes the oldest send or call for aid off the encounter's queue and resolves it, or refuses it
# on the map it was submitted on. Returns the map batches it made.
func _resolve_own() -> Array[CombatSession.FactBatch]:
	var command: Command = _queue.pop_front()
	var session_id: int = _queue_maps.pop_front()
	var batches: Array[CombatSession.FactBatch] = []
	var map: CombatSession = get_session(session_id)
	var send: SendUnitsCommand = command as SendUnitsCommand
	var call: CallForAidCommand = command as CallForAidCommand
	var reason: String = ""
	if seats.size() <= 1:
		reason = "only in co-op"
	elif send != null:
		reason = _send_reason(send, map)
	else:
		reason = _aid_reason(call, map)
	if not reason.is_empty():
		batches.append(map.reject(command, reason))
		return batches
	if send != null:
		_send(send.seat, map, send.unit_ids, send.to_session_id, CombatFact.NO_TILE)
		_flush(session_id, send.seat, send.arrival, send.get_label())
		var restarted: CombatSession.FactBatch = _restart(send.to_session_id)
		if restarted != null:
			batches.append(restarted)
		return batches
	_set_aid(session_id, call.is_raised)
	var called: CombatFact = CombatFact.new(CombatFact.Kind.AID_CALLED)
	called.session_id = session_id
	called.amount = call.seat
	called.key = 1 if call.is_raised else 0
	_record(called)
	_flush(session_id, call.seat, call.arrival, call.get_label())
	return batches


# Why send can't go from source now (SendUnitsCommand's rules); empty when it can.
func _send_reason(send: SendUnitsCommand, source: CombatSession) -> String:
	if not source.is_finished:
		return "s%d is still being fought" % [source.session_id]
	if not source.is_won:
		return "s%d was lost" % [source.session_id]
	var is_any_frozen: bool = false
	for session: CombatSession in _sessions:
		is_any_frozen = is_any_frozen or is_frozen(session.session_id)
	if is_any_frozen and send.unit_ids.is_empty():
		return "a map is frozen: send at least one unit"
	if is_any_frozen and not is_frozen(send.to_session_id):
		return "a map is frozen: send to a frozen map"
	if not is_any_frozen and has_sent(send.seat):
		return "seat %d has sent already" % [send.seat]
	if send.unit_ids.is_empty():
		return ""
	var target: CombatSession = get_session(send.to_session_id)
	if target == null or target == source:
		return "no map s%d to send to" % [send.to_session_id]
	if target.is_finished:
		return "s%d has finished" % [send.to_session_id]
	var travelling: PackedStringArray = units_in_transit()
	var named: PackedStringArray = []
	for unit_id: String in send.unit_ids:
		if named.has(unit_id):
			return "%s is named twice" % [unit_id]
		named.append(unit_id)
		if (
				not source.state.has_unit(unit_id)
				or source.state.side_of(unit_id) != CombatFact.CombatSide.PLAYER
				or source.state.seat_of(unit_id) != send.seat
		):
			return "%s isn't a surviving unit of seat %d on s%d" % [
				unit_id, send.seat, source.session_id,
			]
		if travelling.has(unit_id):
			return "%s is already on its way" % [unit_id]
		if _current_session_of(unit_id) != source:
			return "%s has left s%d" % [unit_id, source.session_id]
	return ""


# Why call can't change map's call for aid now (CallForAidCommand's rules); empty when it can.
func _aid_reason(call: CallForAidCommand, map: CombatSession) -> String:
	if not map.seats.has(call.seat):
		return "seat %d doesn't own s%d" % [call.seat, map.session_id]
	if map.is_finished:
		return "the combat on this map has ended"
	if is_aid_called(map.session_id) == call.is_raised:
		return "the call for aid is already %s" % ["raised" if call.is_raised else "lowered"]
	return ""


# Records seat's send from source to the map to_session_id (-1 for none): each unit taken onto
# its way, aimed at tile, with a UNIT_SENT; a send of none is one UNIT_SENT with no actor.
func _send(
		seat: int,
		source: CombatSession,
		unit_ids: PackedStringArray,
		to_session_id: int,
		tile: Vector2i
) -> void:
	var target_id: int = to_session_id if not unit_ids.is_empty() else SendUnitsCommand.NO_TARGET
	_sends[seat] = PackedInt32Array([target_id, source.state.turn])
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.COMBAT
	)
	if unit_ids.is_empty():
		var none: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_SENT)
		none.session_id = source.session_id
		none.amount = seat
		none.key = target_id
		_record(none)
	for unit_id: String in unit_ids:
		_in_transit.append(_take_from(source, unit_id, to_session_id, tile))
		var sent: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_SENT, unit_id)
		sent.session_id = source.session_id
		sent.amount = seat
		sent.key = to_session_id
		sent.tile = tile
		_record(sent)
		if net != null:
			net.info(
					NetLogScript.Category.COMBAT,
					"%s UNIT SENT %s s%d -> s%d"
					% [_tag(), source.describe(unit_id), source.session_id, to_session_id]
			)


# unit_id on its way from source to the map to_session_id, aimed at tile: a copy of its record,
# bases and weapons, and its effects taken off source's engine in id order, due by the clock
# after the turn source was won on.
func _take_from(
		source: CombatSession, unit_id: String, to_session_id: int, tile: Vector2i
) -> Transfer:
	var transfer: Transfer = Transfer.new()
	transfer.unit = source.state.unit(unit_id).copy()
	transfer.to_session_id = to_session_id
	transfer.tile = tile
	transfer.clock_turn = source.state.turn
	transfer.bases = source.bases_of(unit_id).duplicate()
	for weapon_id: String in [transfer.unit.equipped_weapon_id, transfer.unit.stowed_weapon_id]:
		var weapon: CombatState.WeaponStats = source.state.weapon(weapon_id)
		if weapon != null:
			transfer.weapons.append(weapon)
	var held: Array[String] = []
	for instance: EffectInstance in source.engine.get_instances():
		if instance.owner.holder_id == unit_id:
			held.append(instance.instance_id)
	held.sort()
	for instance_id: String in held:
		transfer.instances.append(source.engine.unregister(instance_id))
	return transfer


# Restarts the map session_id when it is frozen and units on their way land there at once (the
# clock waived), sending its batch; units then bound for an ended map go back. Returns the map's
# batch, or null when it didn't restart.
func _restart(session_id: int) -> CombatSession.FactBatch:
	var target: CombatSession = get_session(session_id)
	if target == null or not is_frozen(session_id) or not PhaseRunner.resume(target):
		return null
	var batch: CombatSession.FactBatch = target.flush("frozen map resumed")
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.COMBAT
	)
	if net != null:
		net.info(
				NetLogScript.Category.COMBAT,
				"%s RESUMED s%d at turn %d" % [_tag(), session_id, target.state.turn]
		)
	_return_from_finished()
	_flush(session_id, -1, CombatSession.NO_ARRIVAL, "frozen map resumed")
	return batch


# Lands the units on their way to session_id that are due: all of them when keeps_clock is false
# or the map has no player unit (a frozen map; the clock is waived), else those whose clock turn
# its turn has reached, so they land at its first player Phase Start after that turn.
func _deliver(session_id: int, keeps_clock: bool) -> PackedStringArray:
	var delivered: PackedStringArray = []
	var target: CombatSession = get_session(session_id)
	if target == null:
		return delivered
	# At the ARRIVALS hook the turn hasn't risen yet: turn N's Phase Start runs at turn N - 1.
	var is_waived: bool = (
			not keeps_clock
			or target.state.units_of(CombatFact.CombatSide.PLAYER).is_empty()
	)
	var waiting: Array[Transfer] = []
	for transfer: Transfer in _in_transit:
		if (
				transfer.to_session_id != session_id
				or (not is_waived and target.state.turn < transfer.clock_turn)
				or not _arrive(target, transfer)
		):
			waiting.append(transfer)
		else:
			delivered.append(transfer.unit.id)
	_in_transit = waiting
	return delivered


# Sends every unit on its way to a map that has ended back onto the won map it left, unharmed:
# that map kept its record, so only its effects go back. Each records UNIT_RETURNED.
func _return_from_finished() -> void:
	_drop_landed()
	var waiting: Array[Transfer] = []
	var returning: Array[Transfer] = []
	for transfer: Transfer in _in_transit:
		var target: CombatSession = get_session(transfer.to_session_id)
		if target != null and target.is_finished:
			returning.append(transfer)
		else:
			waiting.append(transfer)
	_in_transit = waiting
	for transfer: Transfer in returning:
		var home: CombatSession = _put_back(transfer)
		var returned: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_RETURNED, transfer.unit.id)
		returned.session_id = transfer.to_session_id
		returned.amount = transfer.unit.seat
		returned.key = -1 if home == null else home.session_id
		_record(returned)


# Registers transfer's effects again on the won map that kept the unit's record. Returns that map.
func _put_back(transfer: Transfer) -> CombatSession:
	var home: CombatSession = _current_session_of(transfer.unit.id)
	if home == null:
		return null
	for instance: EffectInstance in transfer.instances:
		home.engine.register(instance, true)
	return home


# A mirror's units on their way that their target's own batch already placed: they have landed.
# Changes nothing on the host, where a landing leaves the list as it lands.
func _drop_landed() -> void:
	if _in_transit.is_empty():
		return
	var waiting: Array[Transfer] = []
	for transfer: Transfer in _in_transit:
		var target: CombatSession = get_session(transfer.to_session_id)
		if target != null and target.state.unit(transfer.unit.id) != null:
			_landed(target, target.state.unit(transfer.unit.id))
		else:
			waiting.append(transfer)
	_in_transit = waiting


# unit has landed on target: its current record is there, and a unit of another seat makes that
# seat a sender to target.
func _landed(target: CombatSession, unit: CombatUnitState) -> void:
	_arrived_on[unit.id] = target.session_id
	if target.seats.has(unit.seat) or unit.seat < 0:
		return
	var senders: PackedInt32Array = _senders.get(target.session_id, PackedInt32Array())
	if not senders.has(unit.seat):
		senders.append(unit.seat)
		senders.sort()
	_senders[target.session_id] = senders


# The tile a unit sent with no tile aims at on target: its owner's commander's, else its first
# deployment tile (_arrive() then takes the nearest free one); NO_TILE when it has neither.
func _anchor_of(target: CombatSession) -> Vector2i:
	for seat: int in target.seats:
		var commander: String = target.commander_ids.get(seat, "")
		if not commander.is_empty() and target.state.has_unit(commander):
			return target.state.tile_of(commander)
	var deployment: Array[Vector2i] = target.layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT)
	return CombatFact.NO_TILE if deployment.is_empty() else deployment[0]


func _set_aid(session_id: int, is_raised: bool) -> void:
	var index: int = _aid_called.find(session_id)
	if is_raised and index < 0:
		_aid_called.append(session_id)
		_aid_called.sort()
	elif not is_raised and index >= 0:
		_aid_called.remove_at(index)


# Records fact on the encounter's log with the next encounter seq and queues it for playback.
func _record(fact: CombatFact) -> void:
	fact.seq = _next_seq
	_next_seq += 1
	fact_log.append(fact)
	var facts: Array[CombatFact] = [fact]
	playback.enqueue(facts)
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.DEBUG, NetLogScript.Category.COMBAT
	)
	if net != null:
		net.debug(
				NetLogScript.Category.COMBAT,
				"%s#%d %s" % [_tag(), fact.seq, fact.to_log_line(describe)]
		)


# Sends the encounter facts recorded since the last batch on batch_resolved, named by the map, seat,
# arrival and label of what led to them, with the encounter's hash in debug builds. Returns the
# batch, or null when there were none.
func _flush(
		session_id: int, seat: int, arrival: int, label: String
) -> CombatSession.FactBatch:
	if _batched_up_to >= fact_log.size():
		return null
	var batch: CombatSession.FactBatch = CombatSession.FactBatch.new()
	batch.session_id = session_id
	batch.seat = seat
	batch.arrival = arrival
	batch.label = label
	for i: int in range(_batched_up_to, fact_log.size()):
		batch.facts.append(fact_log[i])
	_batched_up_to = fact_log.size()
	if OS.is_debug_build():
		batch.state_hash = state_hash()
	batch_resolved.emit(batch)
	return batch


# A mirror's follow of one encounter fact from the host (apply_batch).
func _follow(fact: CombatFact) -> void:
	match fact.kind:
		CombatFact.Kind.COUNTER_CHANGED:
			# ASSUMPTION: a cross-map charge is spent by the activation fact on the map where it
			# fired (CombatSession.apply_batch), so a client follows every map of its encounter; a
			# count is a value, not a step, so applying it here too changes nothing.
			var instance: EffectInstance = _cross_map.get(fact.source_effect_id, null)
			if instance != null:
				instance.set_counter(fact.key as EffectTerms.Lane, fact.amount)
		CombatFact.Kind.UNIT_SENT:
			var source: CombatSession = get_session(fact.session_id)
			if source == null:
				return
			_sends[fact.amount] = PackedInt32Array([fact.key, source.state.turn])
			if not fact.actor_id.is_empty() and source.state.unit(fact.actor_id) != null:
				_in_transit.append(_take_from(source, fact.actor_id, fact.key, fact.tile))
		CombatFact.Kind.UNIT_RETURNED:
			for index: int in _in_transit.size():
				if _in_transit[index].unit.id == fact.actor_id:
					_put_back(_in_transit[index])
					_in_transit.remove_at(index)
					return
		CombatFact.Kind.AID_CALLED:
			_set_aid(fact.session_id, fact.key == 1)


# A session's ARRIVALS hook: its player Phase Start is starting, so the units due there land.
func _on_session_arrivals_due(session: CombatSession) -> void:
	_deliver(session.session_id, true)


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


# The snapshot's encounter part, in a fixed order so equal states write equal text.
func _capture_encounter(reference: Callable) -> Dictionary:
	var unit_ids: Array[String] = []
	unit_ids.assign(_arrived_on.keys())
	unit_ids.sort()
	var arrived: Dictionary = {}
	for unit_id: String in unit_ids:
		arrived[unit_id] = _arrived_on[unit_id]
	var cross_map: Array = []
	for instance: EffectInstance in get_cross_map_instances():
		cross_map.append(instance.capture(reference))
	var in_transit: Array = []
	for transfer: Transfer in _in_transit:
		in_transit.append(_capture_transfer(transfer, reference))
	var send_seats: Array[int] = []
	send_seats.assign(_sends.keys())
	send_seats.sort()
	var sends: Dictionary = {}
	for seat: int in send_seats:
		sends[str(seat)] = Array(_sends[seat])
	var receiving: Array[int] = []
	receiving.assign(_senders.keys())
	receiving.sort()
	var senders: Dictionary = {}
	for session_id: int in receiving:
		senders[str(session_id)] = Array(_senders[session_id])
	return {
		"floor": floor_number,
		"node": node,
		"seats": Array(seats),
		"next_seq": _next_seq,
		"arrived_on": arrived,
		"cross_map": cross_map,
		"in_transit": in_transit,
		"sends": sends,
		"senders": senders,
		"aid": Array(_aid_called),
		"forfeited": Array(_forfeited),
	}


# A unit on its way as plain JSON: its CombatUnitState, where it goes, the tile it aims at, its
# clock turn, its bases by key id in key order, its weapon records and its effect instances.
func _capture_transfer(transfer: Transfer, reference: Callable) -> Dictionary:
	var keys: Array = transfer.bases.keys()
	keys.sort()
	var bases: Array = []
	for key: Variant in keys:
		bases.append([Modifier.key_id(key as int), transfer.bases[key]])
	var weapons: Array = []
	for weapon: CombatState.WeaponStats in transfer.weapons:
		weapons.append(weapon.capture())
	var instances: Array = []
	for instance: EffectInstance in transfer.instances:
		instances.append(instance.capture(reference))
	return {
		"unit": transfer.unit.capture(),
		"to_session_id": transfer.to_session_id,
		"tile": [transfer.tile.x, transfer.tile.y],
		"clock_turn": transfer.clock_turn,
		"bases": bases,
		"weapons": weapons,
		"instances": instances,
	}


# The Transfer _capture_transfer() wrote; null when any part is malformed or names a map that
# isn't open.
func _transfer_from(data: Dictionary, resolve: Callable) -> Transfer:
	var unit_data: Variant = data.get("unit", null)
	var tile_data: Variant = data.get("tile", null)
	var bases: Variant = data.get("bases", null)
	var weapons: Variant = data.get("weapons", null)
	var instances: Variant = data.get("instances", null)
	var to_id: int = _whole(data.get("to_session_id", null))
	var clock_turn: int = _whole(data.get("clock_turn", null))
	if (
			not unit_data is Dictionary
			or not tile_data is Array
			or (tile_data as Array).size() != 2
			or not bases is Array
			or not weapons is Array
			or not instances is Array
			or get_session(to_id) == null
			or clock_turn < 0
	):
		return null
	var transfer: Transfer = Transfer.new()
	transfer.unit = CombatUnitState.from_capture(unit_data as Dictionary)
	transfer.to_session_id = to_id
	transfer.clock_turn = clock_turn
	var tile_parts: Array = tile_data
	var x: Variant = _whole_or_null(tile_parts[0])
	var y: Variant = _whole_or_null(tile_parts[1])
	if transfer.unit == null or x == null or y == null:
		return null
	transfer.tile = Vector2i(x as int, y as int)
	# A map tile, or NO_TILE for a unit aimed at the receiving commander.
	if (transfer.tile.x < 0 or transfer.tile.y < 0) and transfer.tile != CombatFact.NO_TILE:
		return null
	# Untyped: the parts come from JSON and are checked entry by entry.
	for entry: Variant in bases:
		if not entry is Array or (entry as Array).size() != 2:
			return null
		var pair: Array = entry
		var key: int = Modifier.key_from_id(str(pair[0]))
		if key == Modifier.NO_KEY or not (pair[1] is float or pair[1] is int):
			return null
		var value: float = pair[1]
		transfer.bases[key] = value
	for entry: Variant in weapons:
		var weapon: CombatState.WeaponStats = (
				CombatState.WeaponStats.from_capture(entry as Dictionary)
				if entry is Dictionary else null
		)
		if weapon == null:
			return null
		transfer.weapons.append(weapon)
	for entry: Variant in instances:
		var instance: EffectInstance = (
				EffectInstance.from_capture(entry as Dictionary, resolve)
				if entry is Dictionary else null
		)
		if instance == null:
			return null
		transfer.instances.append(instance)
	return transfer


func _refuse_snapshot(reason: String) -> Error:
	push_error("CombatEncounter: %s can't load the snapshot - %s" % [_tag(), reason])
	return ERR_INVALID_DATA


## Whether the whole battle saves after [param batch], a map's: it ends that map's player phase
## (the last End Turn, whose batch runs on to the next player Phase Start), or it restarts a
## frozen map (a player Phase Start past turn 1 outside any command). Either way the save holds the
## start of a player phase.
static func is_save_point(batch: CombatSession.FactBatch) -> bool:
	if batch == null or batch.is_rejected():
		return false
	for fact: CombatFact in batch.facts:
		if fact.side != CombatFact.CombatSide.PLAYER:
			continue
		if fact.kind == CombatFact.Kind.PHASE_END:
			return true
		if (
				fact.kind == CombatFact.Kind.PHASE_START
				and fact.amount > 1
				and batch.arrival == CombatSession.NO_ARRIVAL
		):
			return true
	return false


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
	var scope: EffectTerms.Scope = instance.definition.scope
	if scope != EffectTerms.Scope.ANY_ALLY_UNIT and scope != EffectTerms.Scope.ANY_UNIT:
		return false
	for condition: EffectCondition in instance.definition.conditions:
		if condition is WhilePositionCondition:
			return false
	return true


# A whole number read from saved data, or -1 when it isn't one (never a floor, node or seat).
static func _whole(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = value
	return roundi(number) if number == floorf(number) else -1


# A whole number read from saved data, negative ones included, as an int; null when it isn't one.
static func _whole_or_null(value: Variant) -> Variant:
	if not (value is int or value is float):
		return null
	var number: float = value
	return roundi(number) if number == floorf(number) else null


# A list of whole numbers 0 or above from saved data, as _capture_encounter() wrote its aid and
# forfeited lists; null when value isn't one.
static func _whole_list(value: Variant) -> Variant:
	if not value is Array:
		return null
	var numbers: PackedInt32Array = []
	# Untyped: the list comes from JSON and is checked entry by entry.
	for entry: Variant in value:
		var number: int = _whole(entry)
		if number < 0:
			return null
		numbers.append(number)
	return numbers


# The sends _capture_encounter() wrote, by seat: [target or -1, turn]; null when malformed.
static func _sends_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var sends: Dictionary[int, PackedInt32Array] = {}
	var by_seat: Dictionary = value
	for key: Variant in by_seat:
		var pair: Variant = by_seat[key]
		var seat: int = str(key).to_int() if str(key).is_valid_int() else -1
		if seat < 0 or not pair is Array or (pair as Array).size() != 2:
			return null
		var target: Variant = _whole_or_null((pair as Array)[0])
		var turn: int = _whole((pair as Array)[1])
		if target == null or (target as int) < SendUnitsCommand.NO_TARGET or turn < 0:
			return null
		sends[seat] = PackedInt32Array([target as int, turn])
	return sends


# The senders _capture_encounter() wrote, by session id: ascending seats; null when malformed.
static func _senders_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var senders: Dictionary[int, PackedInt32Array] = {}
	var by_map: Dictionary = value
	for key: Variant in by_map:
		var session_id: int = str(key).to_int() if str(key).is_valid_int() else -1
		var seat_list: Variant = _whole_list(by_map[key])
		if session_id < 0 or seat_list == null:
			return null
		senders[session_id] = seat_list
	return senders


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
				"contents": seats[seat].map.contents,
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
	## This seat's map state as setup leaves it: step 7 writes each container's contents into its
	## [member MapState.contents] (event bus plan, questions 40 and 46). Each session starts from a
	## copy ([method CombatEncounter.open_sessions]).
	var map: MapState = MapState.new()

	func _init(owner_seat: int) -> void:
		seat = owner_seat


# A unit on its way from a won map to another one. tile is NO_TILE when it aims at the receiving
# commander; clock_turn is the turn the map it left was won on.
class Transfer:
	extends RefCounted

	var unit: CombatUnitState = null
	var to_session_id: int = -1
	var tile: Vector2i = CombatFact.NO_TILE
	var clock_turn: int = 0
	var bases: Dictionary = {}
	var weapons: Array[CombatState.WeaponStats] = []
	var instances: Array[EffectInstance] = []
