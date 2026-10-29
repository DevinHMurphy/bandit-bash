# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_session.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
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
## [method logger]), and builds no log text unless the line prints.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

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
## has no commander here has no entry. [Objectives] loses the map when one is defeated. Not saved
## yet (P02 CC8).
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
## it first (see [Command]); a rejected command records nothing, tells only its seat through
## [signal command_rejected], and returns a batch with [member FactBatch.rejected_reason] set.
## A resolved command ends its step with [constant CombatHooks.Hook.AFTER_STEP]
## ([method PhaseRunner.end_step]), so the objective checks may end the map inside its batch.
## Facts recorded since the last batch outside any command go out first, as their own batch.
func resolve_next() -> FactBatch:
	if _queue.is_empty():
		return null
	flush("outside commands")
	var command: Command = _queue.pop_front()
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
	return flush("battle start")


## The [member CombatFact.seq] of the last fact recorded; 0 before any.
func last_seq() -> int:
	return 0 if engine.fact_log.is_empty() else engine.fact_log[engine.fact_log.size() - 1].seq


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
## state covers them.
func mark_checkpoint() -> void:
	_checkpoint_seq = last_seq()
	_catch_up.clear()


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
## -> REJECTED stale forecast (s0#142 touched enemy:61)[/code]. Facts recorded outside a command
## print as [code]s0 BATCH deployment -> OK s0#1-s0#3[/code].
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


# The stale-forecast rule: any fact since the forecast's seq about an id or tile it read.
func _stale_reason(command: Command) -> String:
	if command.based_on_seq == Command.NO_SEQ:
		return ""
	var reads: PackedStringArray = command.forecast_reads()
	var tiles: Array[Vector2i] = command.forecast_tiles()
	if reads.is_empty() and tiles.is_empty():
		return ""
	if command.based_on_seq < 0 or command.based_on_seq > last_seq():
		return "forecast based on unknown s%d#%d" % [session_id, command.based_on_seq]
	# Facts are logged in seq order from 1, so the first fact after based_on_seq is at that index.
	for i: int in range(command.based_on_seq, engine.fact_log.size()):
		var fact: CombatFact = engine.fact_log[i]
		var touched: String = ""
		if not fact.actor_id.is_empty() and reads.has(fact.actor_id):
			touched = fact.actor_id
		elif not fact.target_id.is_empty() and reads.has(fact.target_id):
			touched = fact.target_id
		elif fact.tile != CombatFact.NO_TILE and tiles.has(fact.tile):
			touched = str(fact.tile)
		if not touched.is_empty():
			return "stale forecast (s%d#%d touched %s)" % [session_id, fact.seq, touched]
	return ""


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

	## Whether the command was rejected.
	func is_rejected() -> bool:
		return not rejected_reason.is_empty()

	## The seq of its first fact; 0 when it has none.
	func first_seq() -> int:
		return 0 if facts.is_empty() else facts[0].seq

	## The seq of its last fact; 0 when it has none.
	func last_seq() -> int:
		return 0 if facts.is_empty() else facts[facts.size() - 1].seq
