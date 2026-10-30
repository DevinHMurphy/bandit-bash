# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_session.gd
# Author:
# Created:  October 28, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name CombatSession
extends RefCounted
## One map of one battle: its rules state, effect engine, roll source, presentation bus, fact log
## and command queue.
##
## The host runs one session per map; a [CombatEncounter] owns them, and sessions never reference
## each other. Commands enter through [method submit], stamped on arrival, and resolve one at a time
## through [method resolve_next]: each resolves atomically, then its facts go out as one
## [FactBatch], to [signal batch_resolved] for the network and to [member playback] for this peer.
## Facts since the last checkpoint stay in memory for a client that rejoins ([method facts_since]).
## Engine diagnostics are reported at ERROR after every batch (event bus plan, question 31).[br]
## The turn loop is [PhaseRunner]'s: [method open_battle] starts it, every command ends with
## [constant CombatHooks.Hook.AFTER_STEP], and other plans plug in through [member hooks].[br]
## Randomness comes only from the roll source it is given: [LiveRolls] over its seat's
## [code]COMBAT_ROLLS[/code] stream. It never sees the run's stream registry.[br]
## Main thread only. It depends on no scene or autoload except [code]NetLog[/code] (through
## [method logger]), and builds no log text unless the line prints.[br]
## [b]Snapshots and mirrors:[/b] [method snapshot] and [method load_snapshot] carry the map between
## commands as plain JSON (its units and turn, the effects, the run seed, the build version and
## the roll stream's state), and are what saving ([CombatStateSection]) and rejoining both build
## on. A client's mirror is a session that only ever receives the host's batches through
## [method apply_batch]: applied once each by seq ([method CombatState.follow]), then checked
## against the host's [member FactBatch.state_hash] in debug builds. [method debug_dump] writes a
## repro file to [code]user://logs/[/code] that replays from the last checkpoint.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Save system design): docs/design/save-system.md
##
## @todo: TOD-002 - Add the map keys and P04's facts the same way (P04 MP8), map objects' units and
## a key's last use included.

## A command was rejected; only [param seat] is told. It cost nothing.
## [param arrival]: the command's arrival stamp. [param reason]: why, with bare ids.
signal command_rejected(seat: int, arrival: int, reason: String)

## A batch of facts is ready to send: a resolved or rejected command's, or facts recorded outside
## any command (deployment, arrivals).
signal batch_resolved(batch: FactBatch)

## A fact was recorded, at resolve time on the host. For host-side observers such as the encounter,
## which mirrors cross-map counters; nothing connected here may change rules state. Presentation
## plays facts through [member bus] instead.
signal fact_recorded(fact: CombatFact)

## A [CampaignGrant] applied in the batch just finished ([member EffectEngine.grants]), once each.
## [param seat]: the effect owner's seat. [param grant]: a [enum CampaignGrant.Grant].
## [param amount]: gold, for [constant CampaignGrant.Grant.GOLD]. [param definition_id]: the
## heirloom, unit type or rune; may be empty. [param source_effect_id]: the effect instance.
signal grant_received(
		seat: int, grant: int, amount: int, definition_id: String, source_effect_id: String
)

## [method next_arrival] when nothing is queued. Arrival stamps start at 1.
const NO_ARRIVAL: int = 0

## [member FactBatch.state_hash] of a batch sent without one (release builds, rejected commands).
const NO_HASH: int = 0

## Where [method debug_dump] writes, next to Godot's own log file.
const DUMP_DIR: String = "user://logs"

# The shape of snapshot() and debug_dump() output; raised when either changes. Snapshots are never
# saved as they are (CombatStateSection saves their parts), so an older format is refused.
const _SNAPSHOT_FORMAT: int = 2

# The fields of each unit's capture that state_hash() leaves out: no fact carries them, so a mirror
# can't follow them (CombatState.follow).
const _UNFOLLOWED_UNIT_FIELDS: PackedStringArray = [
	"tiles_moved", "movement_spent", "is_second_move_pending",
]

# The NetLog autoload's script, used as a type and for its enums. The autoload is reached by node
# path, never by name: the sessions also compile in a headless --script run, before autoload names
# exist (tests/sessions/run_all.gd).
const NetLogScript = preload("res://scripts/autoload/net_log.gd")

## This session's id: the [member CombatFact.session_id] of its facts.
var session_id: int = 0

## The seats with units on this map. One per map in co-op; several when a battle is shared.
var seats: PackedInt32Array = []

## The map, shared read-only with every session of the encounter.
var layout: MapLayout = null

## The map's rules state, over the encounter's shared [MapGrid].
var state: CombatState = null

## The map's effect engine. Rules code records facts through it.
var engine: EffectEngine = null

## Presentation signals for this map's facts, fired during playback.
var bus: CombatBus = null

## Plays this session's batches on [member bus] on this peer.
var playback: FactPlayback = null

## Where other plans' rules plug into this map's turn loop ([PhaseRunner]).
var hooks: CombatHooks = CombatHooks.new()

## The run's id allocator: what [method describe] names ids from. Never null in use.
var ids: InstanceIdAllocator = null

## The encounter's shared setup results (the map, and what steps 2 to 5 drew); null outside an
## encounter.
var setup: CombatEncounter.EncounterSetup = null

## This map's seat's setup results (steps 6 and 7: additions and container contents); null outside
## an encounter.
var seat_setup: CombatEncounter.SeatSetup = null

## Each seat's commander on this map, by seat, as [method deploy] placed it; a seat whose army
## has no commander here has no entry. [Objectives] loses the map when one is defeated.
var commander_ids: Dictionary[int, String] = {}

## Whether this map's combat has ended ([constant CombatFact.Kind.COMBAT_ENDED] was recorded).
## From then on every command is rejected.
var is_finished: bool = false

## Whether the player side won this map: its [constant CombatFact.Kind.COMBAT_ENDED] named the
## player side ([member CombatFact.side]). False while the map is being fought and when it was lost.
var is_won: bool = false

## The per-draw trace for desync and determinism hunts (RNG streams plan, Logging): when on, every
## roll this session made is logged at DEBUG after its batch. Off by default; it changes no roll.
var is_tracing_draws: bool = false

## The run's seed, which [method snapshot] and [method debug_dump] name the run by (RNG streams
## plan, need R-N4). Set by the encounter; 0 outside one.
var run_seed: int = 0

var _clock: ArrivalClock = null
var _queue: Array[Command] = []

# Facts batched since the last checkpoint, for catch-up; and the seq that checkpoint covered.
var _catch_up: Array[CombatFact] = []
var _checkpoint_seq: int = 0

# Index into engine.fact_log of the first fact not yet in a batch.
var _batched_up_to: int = 0

# Engine diagnostics already reported.
var _reported_diagnostics: int = 0

# Roll records already traced (or skipped while tracing was off).
var _traced_rolls: int = 0

# Engine grants already handed on.
var _reported_grants: int = 0

# Base values each placed unit was given, by unit id, so a transfer can carry them to another map.
var _bases: Dictionary[String, Dictionary] = {}

# The last seq a loaded snapshot covered: last_seq() while the fact log is empty.
var _base_seq: int = 0

# What debug_dump() replays from: the snapshot taken when the battle opened or last checkpointed,
# every command resolved since (wire arrays), and whether each of them could be written.
var _replay_snapshot: Dictionary = {}
var _replay_commands: Array = []
var _is_replay_complete: bool = true


## [param grid]: the map, shared with the encounter's other sessions. [param rolls]: [LiveRolls]
## over this seat's [code]COMBAT_ROLLS[/code] stream (a test may pass another source).
## [param clock]: the encounter's arrival clock, so stamps order commands across maps; null gives
## the session its own.
func _init(
		id: int,
		map_seats: PackedInt32Array,
		grid: MapGrid,
		rolls: RollSource,
		allocator: InstanceIdAllocator,
		clock: ArrivalClock = null
) -> void:
	session_id = id
	seats = map_seats.duplicate()
	layout = grid.layout
	state = CombatState.new(grid)
	engine = EffectEngine.new(state, rolls, id)
	bus = CombatBus.new()
	playback = FactPlayback.new(bus)
	ids = allocator
	_clock = clock if clock != null else ArrivalClock.new()
	engine.add_observer(_on_engine_fact)


## The read API for a unit's values: [method EffectEngine.stats].
func stats(unit_id: String) -> StatSheet:
	return engine.stats(unit_id)


## Queues [param command] behind every command already queued and stamps its arrival. Nothing
## resolves until [method resolve_next]. Returns the stamp.
func submit(command: Command) -> int:
	command.arrival = _clock.stamp()
	_queue.append(command)
	return command.arrival


## The arrival stamp of the next queued command; [constant NO_ARRIVAL] when none is queued.
func next_arrival() -> int:
	return NO_ARRIVAL if _queue.is_empty() else _queue[0].arrival


## Resolves the oldest queued command and returns its batch; null when nothing is queued. Checks
## it first (see [Command]); a command that [method Command.needs_fresh_forecast] is stale if any
## fact was recorded after its [member Command.based_on_seq]. A rejected command records nothing,
## tells only its seat through
## [signal command_rejected], and returns a batch with [member FactBatch.rejected_reason] set.
## A resolved command ends its step with [constant CombatHooks.Hook.AFTER_STEP]
## ([method PhaseRunner.end_step]), so the objective checks may end the map inside its batch.
## Facts recorded since the last batch outside any command go out first, as their own batch.
func resolve_next() -> FactBatch:
	if _queue.is_empty():
		return null
	flush("outside commands")
	if _replay_snapshot.is_empty():
		_start_replay()
	var command: Command = _queue.pop_front()
	_record_for_replay(command)
	var batch: FactBatch = FactBatch.new()
	batch.session_id = session_id
	batch.seat = command.seat
	batch.arrival = command.arrival
	batch.label = command.get_label()
	batch.actor_id = command.actor_id
	batch.target_id = command.get_target_id()
	batch.based_on_seq = command.based_on_seq
	batch.rejected_reason = _check(command)
	if batch.is_rejected():
		command_rejected.emit(command.seat, command.arrival, batch.rejected_reason)
		_log_command(batch)
		batch_resolved.emit(batch)
		return batch

	engine.begin_step()
	command.resolve(self)
	engine.drain()
	PhaseRunner.end_step(self)
	_finish_batch(batch)
	_log_command(batch)
	batch_resolved.emit(batch)
	return batch


## Resolves every queued command in arrival order and returns their batches.
func resolve_queued() -> Array[FactBatch]:
	var batches: Array[FactBatch] = []
	while not _queue.is_empty():
		batches.append(resolve_next())
	return batches


## Packs the facts recorded since the last batch outside any command (deployment at battle start,
## arrivals from another map) into a batch of their own, sends it like any other and returns it;
## null when there are none. [param label]: what recorded them, for the log.
func flush(label: String) -> FactBatch:
	if _batched_up_to >= engine.fact_log.size():
		return null
	var batch: FactBatch = FactBatch.new()
	batch.session_id = session_id
	batch.label = label
	_finish_batch(batch)
	_log_command(batch)
	batch_resolved.emit(batch)
	return batch


## Opens the battle once the army is deployed ([method PhaseRunner.open_battle]): the opening swap
## window when any of [param swap_seats] (seats whose opening-swap setting is on) has units here,
## otherwise turn 1's player Phase Start, sent as its own batch with any facts not yet batched.
## Returns that batch; null when there was nothing to send, as when the window opens right after
## the deployment batch (opening it records nothing).
func open_battle(swap_seats: PackedInt32Array = PackedInt32Array()) -> FactBatch:
	PhaseRunner.open_battle(self, swap_seats)
	var batch: FactBatch = flush("battle start")
	_start_replay()
	return batch


## The [member CombatFact.seq] of the last fact recorded or applied; before any, the last one a
## loaded snapshot covered, else 0.
func last_seq() -> int:
	if engine.fact_log.is_empty():
		return _base_seq
	return engine.fact_log[engine.fact_log.size() - 1].seq


## Whether a client that has played every fact up to [param seq] can catch up from memory: the
## facts after it are all kept. False when it is behind the last checkpoint and needs a fresh
## snapshot (EB7), or ahead of this session.
func can_catch_up(seq: int) -> bool:
	return seq >= _checkpoint_seq and seq <= last_seq()


## The batched facts after [param seq], in order, for a client that rejoins; empty when it is
## current or when [method can_catch_up] is false, which is reported at WARN.
func facts_since(seq: int) -> Array[CombatFact]:
	var missed: Array[CombatFact] = []
	if not can_catch_up(seq):
		var net: NetLogScript = _logger(NetLogScript.Level.WARN, NetLogScript.Category.COMBAT)
		if net != null:
			net.warn(
					NetLogScript.Category.COMBAT,
					"s%d catch-up gap: asked from #%d, kept #%d to #%d"
					% [session_id, seq, _checkpoint_seq, last_seq()]
			)
		return missed
	for fact: CombatFact in _catch_up:
		if fact.seq > seq:
			missed.append(fact)
	return missed


## Forgets the catch-up facts up to now: call it when the battle checkpoints, since the saved
## state covers them. [method debug_dump] replays from here on.
func mark_checkpoint() -> void:
	_checkpoint_seq = last_seq()
	_catch_up.clear()
	_start_replay()


## This map's state as plain JSON values, taken between commands: [code]session[/code] (seq, seats,
## whether it ended and was won, commanders, placed units' bases), [code]combat_state[/code]
## ([method CombatState.capture]: units, weapons, turn and phase), [code]effects[/code]
## ([method EffectEngine.capture]) and [code]rolls[/code] (its [LiveRolls] stream's state; empty
## for another roll source), named by the run seed and the build version. Empty, with an error,
## while reactions wait. [method load_snapshot] reverses it.
## [param reference]: names each effect definition; see [method EffectInstance.capture].
func snapshot(reference: Callable = Callable()) -> Dictionary:
	if engine.pending_reactions() > 0:
		push_error("CombatSession: s%d can't be captured while reactions wait" % [session_id])
		return {}
	var live: LiveRolls = engine.rolls as LiveRolls
	return {
		"format": _SNAPSHOT_FORMAT,
		"run_seed": RunSeed.format(run_seed),
		"game_version": _game_version(),
		"session": _capture_session(),
		"combat_state": state.capture(),
		"effects": engine.capture(reference),
		"rolls": "" if live == null else live.capture(),
	}


## Replaces this map's state with [param data] from [method snapshot], also after a trip through
## JSON: the units and turn first, then the effect engine's state (which needs the units back),
## the roll stream's position (left as it is when [code]rolls[/code] is empty) and the session's
## own fields. The fact log, catch-up facts and queue start empty, and seqs go on from the
## snapshot's. The map objects' state isn't in it yet ([code]TOD-002[/code]): load it into a
## session built the way this battle was. [param resolve] and [param shared]: see
## [method EffectEngine.restore]. Returns [constant OK]; [constant ERR_INVALID_DATA], changing
## nothing, when the data is malformed or belongs to another map or build.
func load_snapshot(
		data: Dictionary,
		resolve: Callable = Callable(),
		shared: Dictionary[String, EffectInstance] = {}
) -> Error:
	var part: Variant = data.get("session", null)
	var units: Variant = data.get("combat_state", null)
	var effects: Variant = data.get("effects", null)
	var rolls_state: String = str(data.get("rolls", ""))
	if (
			_wire_int(data.get("format", null)) != _SNAPSHOT_FORMAT
			or not part is Dictionary
			or not units is Dictionary
			or not effects is Dictionary
	):
		return _refuse_snapshot("not a session snapshot")
	var fields: SessionFields = _read_session(part as Dictionary)
	if fields == null:
		return _refuse_snapshot("its session part is malformed")
	var live: LiveRolls = engine.rolls as LiveRolls
	if not rolls_state.is_empty() and (live == null or not RngStream.new(0).restore(rolls_state)):
		return _refuse_snapshot("its roll stream can't be restored")
	if CombatState.new(state.grid).restore(units as Dictionary) != OK:
		return _refuse_snapshot("its combat state is malformed")
	var before: Dictionary = state.capture()
	# Checked on a scratch state above, so it can't fail here.
	state.restore(units as Dictionary)
	var err: Error = engine.restore(effects as Dictionary, resolve, shared)
	if err != OK:
		state.restore(before)
		return err

	if not rolls_state.is_empty():
		live.restore(rolls_state)
	is_finished = fields.is_finished
	is_won = fields.is_won
	commander_ids = fields.commander_ids
	_bases = fields.bases
	_base_seq = fields.last_seq
	_checkpoint_seq = fields.last_seq
	_queue.clear()
	_catch_up.clear()
	_batched_up_to = 0
	_reported_diagnostics = engine.diagnostics.size()
	_reported_grants = engine.grants.size()
	_traced_rolls = engine.rolls.records.size()
	_replay_snapshot = data.duplicate(true)
	_replay_commands.clear()
	_is_replay_complete = true
	return OK


## A number standing for this map's state, compared between the host and a mirror after each batch
## (event bus plan, Logging and debugging): the [code]session[/code], [code]combat_state[/code] and
## [code]effects[/code] parts of [method snapshot], less what no fact lets a mirror follow: each
## unit's tiles moved, movement spent and second move, and map objects (P04,
## [code]TOD-002[/code]). The roll stream is left out, since only the host draws.
func state_hash() -> int:
	var parts: Dictionary = {
		"session": _capture_session(),
		"combat_state": _followed_state(),
		"effects": engine.capture(_name_definition),
	}
	return JSON.stringify(parts, "", true).hash()


## Applies [param batch], the host's, as this session's mirror: each fact not yet applied, in seq
## order, through [method CombatState.follow] (which has the engine follow too), then queued for
## playback. A fact already applied is skipped, so a resent batch changes nothing. A unit spawned
## that this mirror doesn't know can't be followed (the fact carries no unit record) and is
## reported at WARN; the mirror then needs a snapshot. In debug builds, a mirror that ends at the
## batch's last seq compares [method state_hash] with the host's and reports a difference at WARN.
## Returns [constant OK]; [constant ERR_INVALID_PARAMETER] for another map's batch;
## [constant ERR_PARAMETER_RANGE_ERROR] when a seq is missing (the facts before the gap are
## applied, and the client needs [method facts_since] or a snapshot); [constant ERR_INVALID_DATA]
## when applied but the hashes differ.
func apply_batch(batch: FactBatch) -> Error:
	if batch == null or batch.session_id != session_id:
		return ERR_INVALID_PARAMETER
	var applied: Array[CombatFact] = []
	var next: int = last_seq() + 1
	var gap_at: int = -1
	for fact: CombatFact in batch.facts:
		if fact.seq < next:
			continue
		if fact.seq != next:
			gap_at = fact.seq
			break
		applied.append(fact)
		next += 1
	_warn_unknown_spawns(applied)
	state.follow(engine, applied)
	_batched_up_to = engine.fact_log.size()
	_catch_up.append_array(applied)
	for fact: CombatFact in applied:
		if fact.kind == CombatFact.Kind.COMBAT_ENDED:
			is_finished = true
			is_won = fact.side == CombatFact.CombatSide.PLAYER
	playback.enqueue(applied)

	if gap_at >= 0:
		var gap_log: NetLogScript = _logger(NetLogScript.Level.WARN, NetLogScript.Category.COMBAT)
		if gap_log != null:
			gap_log.warn(
					NetLogScript.Category.COMBAT,
					"s%d mirror gap: at #%d, next was #%d" % [session_id, last_seq(), gap_at]
			)
		return ERR_PARAMETER_RANGE_ERROR
	if (
			batch.state_hash == NO_HASH
			or batch.facts.is_empty()
			or last_seq() != batch.last_seq()
			or not OS.is_debug_build()
	):
		return OK
	var local_hash: int = state_hash()
	if local_hash == batch.state_hash:
		return OK
	var net: NetLogScript = _logger(NetLogScript.Level.WARN, NetLogScript.Category.COMBAT)
	if net != null:
		net.warn(
				NetLogScript.Category.COMBAT,
				"s%d#%d mirror hash mismatch: host %d, mirror %d"
				% [session_id, last_seq(), batch.state_hash, local_hash]
		)
	return ERR_INVALID_DATA


## Writes a repro file to [constant DUMP_DIR] and returns its path, or empty when it couldn't be
## written (reported at ERROR). The file is JSON: the run seed, the build version, the roll
## stream's live state, the snapshot the battle opened or last checkpointed with, every command
## resolved since (wire arrays, in order; [code]"complete"[/code] is false when one had no wire
## type) and the facts recorded since. Resolution is deterministic, so loading the snapshot into a
## session opened on the same map and resolving the commands again gives the same facts, from the
## middle of a battle too. Facts recorded outside commands since then, such as units sent from
## another map, replay only through their own call.
func debug_dump() -> String:
	var live: LiveRolls = engine.rolls as LiveRolls
	var base_seq: int = 0
	var base_part: Variant = _replay_snapshot.get("session", {})
	if base_part is Dictionary:
		var recorded: Variant = _wire_int((base_part as Dictionary).get("last_seq"))
		base_seq = 0 if recorded == null else recorded as int
	var facts: Array = []
	for fact: CombatFact in engine.fact_log:
		if fact.seq > base_seq:
			facts.append(fact.to_wire())
	var dump: Dictionary = {
		"format": _SNAPSHOT_FORMAT,
		"run_seed": RunSeed.format(run_seed),
		"game_version": _game_version(),
		"session_id": session_id,
		"written_at": Time.get_datetime_string_from_system(true),
		"rolls": "" if live == null else live.capture(),
		"snapshot": _replay_snapshot,
		"commands": _replay_commands,
		"complete": _is_replay_complete,
		"facts": facts,
	}
	var err: Error = DirAccess.make_dir_recursive_absolute(DUMP_DIR)
	var path: String = "%s/combat_dump_s%d_%d_%d.json" % [
		DUMP_DIR, session_id, Time.get_unix_time_from_system(), Time.get_ticks_usec(),
	]
	var file: FileAccess = null
	if err == OK:
		file = FileAccess.open(path, FileAccess.WRITE)
		err = OK if file != null else FileAccess.get_open_error()
	if err != OK:
		push_error("CombatSession: s%d dump not written - %s" % [session_id, error_string(err)])
		return ""
	file.store_string(JSON.stringify(dump, "\t", true))
	file.close()
	var net: NetLogScript = _logger(NetLogScript.Level.INFO, NetLogScript.Category.COMBAT)
	if net != null:
		net.info(NetLogScript.Category.COMBAT, "s%d dump written: %s" % [session_id, path])
	return path


## Places [param units] (the army in roster order, not yet on the map) on this map's deployment
## tiles with [AutoDeploy], with no random draw, and records
## [constant CombatFact.Kind.UNIT_SPAWNED] for each one placed. Their weapons must already be in
## [member state]. [param bases]: each unit's base values (value key to number) by unit id.
## [param commander_id]: empty when the army has none here; once placed, it is the commander of its
## seat in [member commander_ids]. Returns where each unit went.
func deploy(
		units: Array[CombatUnitState],
		bases: Dictionary[String, Dictionary],
		commander_id: String
) -> AutoDeploy.Placement:
	for unit: CombatUnitState in units:
		var unit_bases: Dictionary = bases.get(unit.id, {})
		_set_bases(unit.id, unit_bases)
	var placement: AutoDeploy.Placement = AutoDeploy.deploy(
			engine,
			state,
			units,
			layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT),
			_enemy_start_tiles(),
			commander_id
	)
	for unit: CombatUnitState in units:
		if placement.tiles.has(unit.id):
			unit.tile = placement.tiles[unit.id]
			add_unit(unit)
	if not commander_id.is_empty() and state.has_unit(commander_id):
		commander_ids[state.seat_of(commander_id)] = commander_id
	return placement


## Places [param unit] on its tile ([method CombatState.place_unit]) after setting
## [param bases] (value key to number), and records [constant CombatFact.Kind.UNIT_SPAWNED]. For
## deployment, spawns and arrivals from another map. Its weapons must already be in
## [member state]. Returns false, placing nothing, when the tile is off the map or taken.
func add_unit(unit: CombatUnitState, bases: Dictionary = {}) -> bool:
	if not bases.is_empty():
		_set_bases(unit.id, bases)
	if not state.place_unit(engine, unit):
		return false
	var spawned: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_SPAWNED, unit.id)
	spawned.tile = unit.tile
	engine.record(spawned)
	return true


## The base values [param unit_id] was given when placed here, value key to number; empty when
## none were.
func bases_of(unit_id: String) -> Dictionary:
	var found: Dictionary = _bases.get(unit_id, {})
	return found


## [param id] in log and error text: an effect as
## [code]bulwark on item:412 (Iron Greatshield, held by unit:57 Drengr)[/code], anything else as
## its id with its display text and holder. An id nobody knows is reported at ERROR and returned
## bare.
func describe(id: String) -> String:
	if id.is_empty():
		return ""
	var instance: EffectInstance = engine.get_instance(id)
	if instance != null:
		var definition_id: String = instance.definition.id
		if definition_id.is_empty():
			definition_id = id
		return "%s on %s" % [definition_id, describe(instance.owner.owner_id)]
	var parts: PackedStringArray = []
	var label: String = _label_of(id)
	if not label.is_empty():
		parts.append(label)
	var holder: String = _holder_of(id)
	if not holder.is_empty():
		parts.append(("held by %s %s" % [holder, _label_of(holder)]).strip_edges())
	if parts.is_empty():
		var net: NetLogScript = _logger(NetLogScript.Level.ERROR, NetLogScript.Category.COMBAT)
		if net != null and not ids.is_known(id) and not state.has_unit(id):
			net.error(NetLogScript.Category.COMBAT, "s%d: unresolvable id %s" % [session_id, id])
		return id
	return "%s (%s)" % [id, ", ".join(parts)]


## The log line of [param batch]: its command, sender, arrival and result, such as
## [code]s0 CMD arrival 7 seat 1 unit:57 (Hakkapel) move+attack enemy:61 (Brute) based_on s0#140
## -> REJECTED stale forecast (s0#141 RUNE_USED after s0#140)[/code]. Facts recorded outside a
## command print as [code]s0 BATCH deployment -> OK s0#1-s0#3[/code].
func describe_batch(batch: FactBatch) -> String:
	var parts: PackedStringArray = ["s%d BATCH" % [session_id]]
	if batch.arrival != NO_ARRIVAL:
		parts[0] = "s%d CMD" % [session_id]
		parts.append("arrival %d seat %d" % [batch.arrival, batch.seat])
	if not batch.actor_id.is_empty():
		parts.append(describe(batch.actor_id))
	parts.append(batch.label)
	if not batch.target_id.is_empty():
		parts.append(describe(batch.target_id))
	if batch.based_on_seq != Command.NO_SEQ:
		parts.append("based_on s%d#%d" % [session_id, batch.based_on_seq])
	if batch.is_rejected():
		parts.append("-> REJECTED %s" % [batch.rejected_reason])
	elif batch.facts.is_empty():
		parts.append("-> OK, no facts")
	else:
		parts.append(
				"-> OK s%d#%d-s%d#%d"
				% [session_id, batch.first_seq(), session_id, batch.last_seq()]
		)
	return " ".join(parts)


## The log line of an effect fact ([constant CombatFact.Kind.COUNTER_CHANGED] or
## [constant CombatFact.Kind.EFFECT_ACTIVATED]): the effect, its owner, what it reacted to, and
## the counter's step or what it did, such as [code]s0#143 EFFECT bulwark on item:412 (Iron
## Greatshield) owner unit:57 (Drengr): HIT_TAKEN counter 9 -> 10[/code].
func describe_effect(fact: CombatFact) -> String:
	var instance: EffectInstance = engine.get_instance(fact.source_effect_id)
	var head: String = "s%d#%d EFFECT %s" % [session_id, fact.seq, describe(fact.source_effect_id)]
	if instance == null:
		return head
	var owner_id: String = instance.owner.holder_id
	if owner_id.is_empty():
		owner_id = instance.owner.owner_id
	head += " owner %s: %s" % [describe(owner_id), _trigger_of(fact)]
	if fact.kind == CombatFact.Kind.COUNTER_CHANGED:
		var reached: int = fact.amount
		if reached == 0:
			reached = _counter_target(instance, fact.key)
		return "%s counter %d -> %d" % [head, reached - 1, reached]
	var inline_text: PackedStringArray = []
	var queued_text: PackedStringArray = []
	for operation: EffectOperation in instance.definition.operations:
		if operation == null:
			continue
		if operation.is_inline():
			inline_text.append(operation.describe())
		else:
			queued_text.append(operation.describe())
	var done: PackedStringArray = []
	if not inline_text.is_empty():
		done.append("inline %s" % ["; ".join(inline_text)])
	if not queued_text.is_empty():
		done.append("queued %s" % ["; ".join(queued_text)])
	return "%s FIRED %s" % [head, ", ".join(done)]


# Every check before a command resolves (see Command); the first failure's reason, or empty.
func _check(command: Command) -> String:
	if is_finished:
		return "the combat on this map has ended"
	if not command.actor_id.is_empty() and state.seat_of(command.actor_id) != command.seat:
		return "%s isn't seat %d's unit" % [command.actor_id, command.seat]
	var reason: String = command.validate(self)
	if not reason.is_empty():
		return reason
	return _stale_reason(command)


# The stale-forecast rule: a command that needs a fresh forecast is stale once any fact has been
# recorded on this map since its forecast's seq. The reason names the first such fact.
func _stale_reason(command: Command) -> String:
	if command.based_on_seq == Command.NO_SEQ or not command.needs_fresh_forecast():
		return ""
	if command.based_on_seq < 0 or command.based_on_seq > last_seq():
		return "forecast based on unknown s%d#%d" % [session_id, command.based_on_seq]
	if command.based_on_seq == last_seq():
		return ""
	# Facts are logged in seq order without gaps, from 1 or from a loaded snapshot's last seq on.
	var index: int = -1
	if not engine.fact_log.is_empty():
		index = command.based_on_seq + 1 - engine.fact_log[0].seq
	if index < 0:
		return "stale forecast (s%d#%d is before this session's log)" % [
			session_id, command.based_on_seq,
		]
	var first: CombatFact = engine.fact_log[index]
	return "stale forecast (s%d#%d %s after s%d#%d)" % [
		session_id,
		first.seq,
		CombatFact.Kind.find_key(first.kind),
		session_id,
		command.based_on_seq,
	]


# Fills batch with the facts not yet batched, keeps them for catch-up, reports new diagnostics
# and queues the facts for playback on this peer.
func _finish_batch(batch: FactBatch) -> void:
	for i: int in range(_batched_up_to, engine.fact_log.size()):
		batch.facts.append(engine.fact_log[i])
	_batched_up_to = engine.fact_log.size()
	_catch_up.append_array(batch.facts)
	var net: NetLogScript = _logger(NetLogScript.Level.ERROR, NetLogScript.Category.EFFECTS)
	for i: int in range(_reported_diagnostics, engine.diagnostics.size()):
		batch.diagnostics.append(engine.diagnostics[i])
		if net != null:
			net.error(
					NetLogScript.Category.EFFECTS, "s%d: %s" % [session_id, engine.diagnostics[i]]
			)
	_reported_diagnostics = engine.diagnostics.size()
	for i: int in range(_reported_grants, engine.grants.size()):
		var grant: EffectEngine.Grant = engine.grants[i]
		grant_received.emit(
				grant.seat, grant.grant, grant.amount, grant.definition_id, grant.source_effect_id
		)
	_reported_grants = engine.grants.size()
	_trace_draws()
	if OS.is_debug_build():
		batch.state_hash = state_hash()
	playback.enqueue(batch.facts)


# The per-draw trace: each roll since the last batch, at DEBUG, when tracing is on.
func _trace_draws() -> void:
	var records: Array[RollRecord] = engine.rolls.records
	var net: NetLogScript = null
	if is_tracing_draws:
		net = _logger(NetLogScript.Level.DEBUG, NetLogScript.Category.COMBAT)
	if net != null:
		for i: int in range(_traced_rolls, records.size()):
			var record: RollRecord = records[i]
			net.debug(
					NetLogScript.Category.COMBAT,
					"s%d DRAW %s %d p %.4f -> %d"
					% [
						session_id,
						RollRecord.Kind.find_key(record.kind),
						record.value,
						record.probability,
						record.outcome,
					]
			)
	_traced_rolls = records.size()


# The snapshot debug_dump() replays from: now, when the battle opens or checkpoints, or before the
# first command of a session that never opened a battle.
func _start_replay() -> void:
	_replay_snapshot = snapshot()
	_replay_commands.clear()
	_is_replay_complete = true


func _record_for_replay(command: Command) -> void:
	if command.get_wire_type().is_empty():
		_is_replay_complete = false
		return
	_replay_commands.append(command.to_wire())


# The snapshot's session part: seats and commanders by number, bases by key id in key order.
func _capture_session() -> Dictionary:
	var commanders: Dictionary = {}
	for seat: int in commander_ids:
		commanders[str(seat)] = commander_ids[seat]
	var unit_ids: Array[String] = []
	unit_ids.assign(_bases.keys())
	unit_ids.sort()
	var bases: Dictionary = {}
	for unit_id: String in unit_ids:
		var keys: Array = _bases[unit_id].keys()
		keys.sort()
		var entries: Array = []
		for key: Variant in keys:
			entries.append([Modifier.key_id(key as int), _bases[unit_id][key]])
		bases[unit_id] = entries
	return {
		"session_id": session_id,
		"seats": Array(seats),
		"last_seq": last_seq(),
		"is_finished": is_finished,
		"is_won": is_won,
		"commander_ids": commanders,
		"bases": bases,
	}


# The combat_state part state_hash() compares: the capture less the fields a mirror can't follow
# and the map objects' units (side NONE), whose facts are P04's (TOD-002).
func _followed_state() -> Dictionary:
	var captured: Dictionary = state.capture()
	var units: Array = []
	for entry: Variant in captured["units"]:
		var unit: Dictionary = entry
		if unit["side"] == CombatFact.CombatSide.find_key(CombatFact.CombatSide.NONE):
			continue
		for field: String in _UNFOLLOWED_UNIT_FIELDS:
			unit.erase(field)
		units.append(unit)
	captured["units"] = units
	return captured


# A mirror can't place a unit it has never seen: UNIT_SPAWNED names it and its tile only.
func _warn_unknown_spawns(facts: Array[CombatFact]) -> void:
	for fact: CombatFact in facts:
		if fact.kind != CombatFact.Kind.UNIT_SPAWNED or state.unit(fact.actor_id) != null:
			continue
		var net: NetLogScript = _logger(NetLogScript.Level.WARN, NetLogScript.Category.COMBAT)
		if net != null:
			net.warn(
					NetLogScript.Category.COMBAT,
					"s%d#%d mirror can't follow the spawn of %s: it needs a snapshot"
					% [session_id, fact.seq, fact.actor_id]
			)


# The fields of a snapshot's session part, checked; null when malformed, for another map or for
# other seats.
func _read_session(part: Dictionary) -> SessionFields:
	var id: Variant = _wire_int(part.get("session_id", null))
	var seq: Variant = _wire_int(part.get("last_seq", null))
	var part_seats: Variant = part.get("seats", null)
	var commanders: Variant = part.get("commander_ids", null)
	var bases: Variant = part.get("bases", null)
	if (
			id != session_id
			or seq == null
			or (seq as int) < 0
			or not part_seats is Array
			or not commanders is Dictionary
			or not bases is Dictionary
	):
		return null
	var seat_list: PackedInt32Array = []
	# Untyped: the parts come from JSON and are checked entry by entry.
	for seat: Variant in part_seats:
		var seat_number: Variant = _wire_int(seat)
		if seat_number == null:
			return null
		seat_list.append(seat_number as int)
	if seat_list != seats:
		return null
	var fields: SessionFields = SessionFields.new()
	fields.last_seq = seq
	fields.is_finished = part.get("is_finished", false) == true
	fields.is_won = part.get("is_won", false) == true
	var by_seat: Dictionary = commanders
	for seat_text: Variant in by_seat:
		if not str(seat_text).is_valid_int() or not by_seat[seat_text] is String:
			return null
		fields.commander_ids[str(seat_text).to_int()] = by_seat[seat_text] as String
	var by_unit: Dictionary = bases
	for unit_id: Variant in by_unit:
		if not by_unit[unit_id] is Array:
			return null
		var kept: Dictionary = {}
		for entry: Variant in by_unit[unit_id]:
			if not entry is Array or (entry as Array).size() != 2:
				return null
			var pair: Array = entry
			var key: int = Modifier.key_from_id(str(pair[0]))
			if key == Modifier.NO_KEY or not (pair[1] is float or pair[1] is int):
				return null
			var value: float = pair[1]
			kept[key] = value
		fields.bases[str(unit_id)] = kept
	return fields


func _refuse_snapshot(reason: String) -> Error:
	push_error("CombatSession: s%d can't load the snapshot - %s" % [session_id, reason])
	return ERR_INVALID_DATA


func _set_bases(unit_id: String, bases: Dictionary) -> void:
	var kept: Dictionary = {}
	# Untyped: callers pass dictionary literals, which are untyped.
	for key: Variant in bases:
		var value: float = bases[key] as float
		var value_key: int = key
		engine.set_base(unit_id, value_key, value)
		kept[value_key] = value
	_bases[unit_id] = kept


# The enemies' starting tiles deployment ranks by: the enemies already on the map (placed by P05's
# enemy slot step), or the map's enemy slots when none are.
func _enemy_start_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for enemy_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
		tiles.append(state.tile_of(enemy_id))
	if tiles.is_empty():
		tiles = layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	return tiles


func _label_of(id: String) -> String:
	var label: String = ids.label_of(id)
	if label.is_empty():
		label = state.unit_type_of(id)
	return label


# The unit holding an item: the holder of the item's effects, or the unit carrying it.
func _holder_of(item_id: String) -> String:
	for unit_id: String in state.unit_ids():
		var unit: CombatUnitState = state.unit(unit_id)
		if (
				unit.equipped_weapon_id == item_id
				or unit.stowed_weapon_id == item_id
				or unit.pouch_item_id == item_id
		):
			return unit_id
	for instance: EffectInstance in engine.get_instances():
		if instance.owner.kind == EffectOwner.Kind.ITEM and instance.owner.owner_id == item_id:
			return instance.owner.holder_id
	return ""


# The kind of fact an effect fact reacted to: the last fact before it that isn't about an effect.
# The engine records an effect's facts right after the fact that triggered it (after the finished
# fact, for an inline window), so this holds whenever it is asked.
func _trigger_of(effect_fact: CombatFact) -> String:
	var index: int = effect_fact.seq - 1
	if index < 0 or index >= engine.fact_log.size() or engine.fact_log[index] != effect_fact:
		return "?"
	for i: int in range(index - 1, -1, -1):
		var earlier: CombatFact = engine.fact_log[i]
		if (
				earlier.kind != CombatFact.Kind.EFFECT_ACTIVATED
				and earlier.kind != CombatFact.Kind.COUNTER_CHANGED
		):
			return CombatFact.Kind.find_key(earlier.kind) as String
	return "?"


# The engine's observer: every fact as it is recorded. Tracks the map's end, logs, and tells
# host-side observers.
func _on_engine_fact(fact: CombatFact) -> void:
	if fact.kind == CombatFact.Kind.COMBAT_ENDED:
		is_finished = true
		is_won = fact.side == CombatFact.CombatSide.PLAYER
	_log_fact(fact)
	fact_recorded.emit(fact)


# Every fact at DEBUG, effect facts as effect lines; phase changes at INFO.
func _log_fact(fact: CombatFact) -> void:
	var net: NetLogScript = null
	match fact.kind:
		CombatFact.Kind.EFFECT_ACTIVATED, CombatFact.Kind.COUNTER_CHANGED:
			net = _logger(NetLogScript.Level.DEBUG, NetLogScript.Category.EFFECTS)
			if net != null:
				net.debug(NetLogScript.Category.EFFECTS, describe_effect(fact))
			return
		CombatFact.Kind.PHASE_START, CombatFact.Kind.PHASE_END:
			net = _logger(NetLogScript.Level.INFO, NetLogScript.Category.COMBAT)
			if net != null:
				net.info(NetLogScript.Category.COMBAT, fact.to_log_line(describe))
		_:
			net = _logger(NetLogScript.Level.DEBUG, NetLogScript.Category.COMBAT)
			if net != null:
				net.debug(NetLogScript.Category.COMBAT, fact.to_log_line(describe))


# Resolved commands at INFO, rejected ones at WARN.
func _log_command(batch: FactBatch) -> void:
	if batch.is_rejected():
		var warn_log: NetLogScript = _logger(NetLogScript.Level.WARN, NetLogScript.Category.COMBAT)
		if warn_log != null:
			warn_log.warn(NetLogScript.Category.COMBAT, describe_batch(batch))
		return
	var net: NetLogScript = _logger(NetLogScript.Level.INFO, NetLogScript.Category.COMBAT)
	if net != null:
		net.info(NetLogScript.Category.COMBAT, describe_batch(batch))


func _logger(level: NetLogScript.Level, category: NetLogScript.Category) -> NetLogScript:
	return CombatSession.logger(level, category)


## The [code]NetLog[/code] autoload, reached by node path, when a line at [param level] in
## [param category] would print; null when it wouldn't, or before autoloads exist (during a
## headless [code]--script[/code] run's [code]_init[/code]), so nothing is logged then. The
## sessions layer logs only through this: check it before building a line.
static func logger(
		level: NetLogScript.Level, category: NetLogScript.Category
) -> NetLogScript:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var net: NetLogScript = tree.root.get_node_or_null(^"NetLog") as NetLogScript
	if net == null or not net.would_log(level, category):
		return null
	return net


# The count an every-Nth counter in lane reaches when it passes (and starts over at 0).
static func _counter_target(instance: EffectInstance, lane: int) -> int:
	for condition: EffectCondition in instance.definition.conditions:
		var counter: CounterCondition = condition as CounterCondition
		if counter != null and counter.lane == lane:
			return counter.count if counter.mode == CounterCondition.Mode.EVERY_NTH else 1
	return 1


# The build's version (application/config/version), which snapshots and dumps name.
static func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


# Names a definition by its own id: enough for state_hash(), and no catalog search.
static func _name_definition(definition: EffectDefinition) -> String:
	return "" if definition == null else definition.id


# value as an int when it is one, or when it is a whole float within JSON's exact range; null
# otherwise.
# NOTE: The same rule as CombatFact._normalize_wire, Command._wire_int and
# FactBatch._whole_number; keep them in step.
static func _wire_int(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var number: float = value
	if number != floorf(number) or absf(number) > CombatFact.MAX_EXACT_JSON_INT:
		return null
	return int(number)


## Hands out arrival stamps. One clock is shared by every session of an encounter, so stamps give
## the host's arrival order across maps.
class ArrivalClock:
	extends RefCounted

	var _last: int = 0

	## The next stamp: 1 for the first, then rising by 1.
	func stamp() -> int:
		_last += 1
		return _last


## The facts one command produced, or the reason it was rejected: the unit sent to every peer.
class FactBatch:
	extends RefCounted

	## The session it happened in.
	var session_id: int = 0
	## The seat that sent the command; -1 for facts recorded outside a command.
	var seat: int = -1
	## The command's arrival stamp; [constant CombatSession.NO_ARRIVAL] outside a command.
	var arrival: int = 0
	## The command's short name, or what recorded facts outside a command.
	var label: String = ""
	## The unit the command acted for; empty when none.
	var actor_id: String = ""
	## The unit or object the command acted on; empty when none.
	var target_id: String = ""
	## The seq the command's forecast was based on, or [constant Command.NO_SEQ].
	var based_on_seq: int = Command.NO_SEQ
	## Every fact it recorded, reactions included, in seq order. Empty when rejected.
	var facts: Array[CombatFact] = []
	## Why the command was rejected; empty when it resolved.
	var rejected_reason: String = ""
	## Engine diagnostics raised while it resolved, already reported at ERROR.
	var diagnostics: PackedStringArray = []
	## The host's [method CombatSession.state_hash] after it, which a mirror checks itself against;
	## [constant CombatSession.NO_HASH] in release builds and for a rejected command.
	var state_hash: int = NO_HASH

	## Whether the command was rejected.
	func is_rejected() -> bool:
		return not rejected_reason.is_empty()

	## The seq of its first fact; 0 when it has none.
	func first_seq() -> int:
		return 0 if facts.is_empty() else facts[0].seq

	## The seq of its last fact; 0 when it has none.
	func last_seq() -> int:
		return 0 if facts.is_empty() else facts[facts.size() - 1].seq

	## This batch as an Array of primitives, for RPCs and repro dumps: session, seat, arrival,
	## label, actor, target, based-on seq, rejection, diagnostics, state hash, then each fact's
	## [method CombatFact.to_wire]. [method from_wire] reverses it. The slot order is a network
	## contract: append new fields at the end only.
	func to_wire() -> Array:
		var fact_wires: Array = []
		for fact: CombatFact in facts:
			fact_wires.append(fact.to_wire())
		return [
			session_id,
			seat,
			arrival,
			label,
			actor_id,
			target_id,
			based_on_seq,
			rejected_reason,
			Array(diagnostics),
			state_hash,
			fact_wires,
		]

	## Rebuilds a batch from [method to_wire] output, also after a trip through JSON, where
	## numbers arrive as floats. Returns [code]null[/code] (with a warning) for a wrong length or
	## type, a number that isn't whole, or a fact [method CombatFact.from_wire] refuses.
	static func from_wire(data: Array) -> FactBatch:
		if data.size() != 11 or not data[8] is Array or not data[10] is Array:
			push_warning("FactBatch: malformed wire data - %s" % [data])
			return null
		var numbers: Array = []
		for i: int in [0, 1, 2, 6, 9]:
			numbers.append(_whole_number(data[i]))
		var texts_ok: bool = true
		for i: int in [3, 4, 5, 7]:
			texts_ok = texts_ok and data[i] is String
		if numbers.has(null) or not texts_ok:
			push_warning("FactBatch: wire data out of range - %s" % [data])
			return null
		var batch: FactBatch = FactBatch.new()
		batch.session_id = numbers[0]
		batch.seat = numbers[1]
		batch.arrival = numbers[2]
		batch.label = data[3]
		batch.actor_id = data[4]
		batch.target_id = data[5]
		batch.based_on_seq = numbers[3]
		batch.rejected_reason = data[7]
		batch.state_hash = numbers[4]
		for line: Variant in data[8]:
			batch.diagnostics.append(str(line))
		for wire: Variant in data[10]:
			var fact: CombatFact = CombatFact.from_wire(wire as Array) if wire is Array else null
			if fact == null:
				push_warning("FactBatch: a fact can't be read - %s" % [wire])
				return null
			batch.facts.append(fact)
		return batch

	# value as an int, or null: the outer class's _wire_int() rule, which an inner class can't call
	# unqualified.
	# NOTE: Keep in step with CombatSession._wire_int().
	static func _whole_number(value: Variant) -> Variant:
		if value is int:
			return value
		if not value is float:
			return null
		var number: float = value
		if number != floorf(number) or absf(number) > CombatFact.MAX_EXACT_JSON_INT:
			return null
		return int(number)


# A snapshot's session part, read and checked by _read_session() before anything changes.
class SessionFields:
	extends RefCounted

	var last_seq: int = 0
	var is_finished: bool = false
	var is_won: bool = false
	var commander_ids: Dictionary[int, String] = {}
	var bases: Dictionary[String, Dictionary] = {}
