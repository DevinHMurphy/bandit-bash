# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     client_mirror.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name ClientMirror
extends RefCounted
## A client's copy of the host's run and battle, kept equal to the host's from what one
## [code]NetRelay[/code] hears, never resolving anything. [member session] is a [CampaignSession]
## flagged [member CampaignSession.is_mirror]: each campaign batch restores its run from the run's
## capture (the path [method RunSaveSections.attach] takes), then announces itself on the session's
## own signals, so screens read a mirror as they read the host's. The battle is rebuilt as a resume
## rebuilds one ([method CampaignSession.resume_battle]) and loads the host's snapshot, then
## follows every map's and the encounter's batches; a batch for a battle not built is dropped.[br]
## [b]Sync:[/b] state it lacks (no run, a battle, a gap, a debug hash mismatch) is asked for with
## [code]NetRelay.request_sync()[/code] every [constant SYNC_INTERVAL] s, at most
## [constant SYNC_ATTEMPTS] times. [method advance] runs that clock, so its owner sets the time.
##
## @tutorial(Net transport plan): docs/plans/2026-11-19-net-transport.md

## [member session] was built from the host's first capture.
signal session_built(session: CampaignSession)

## The host didn't answer [constant SYNC_ATTEMPTS] requests for state: something other than
## timing is broken. The mirror stays as it was.
signal sync_gave_up(attempts: int)

## Seconds between two requests for state (the kit's retry interval).
const SYNC_INTERVAL: float = 1.0

## Requests for state, the first included, before giving up (the kit's attempt count).
const SYNC_ATTEMPTS: int = 15

# The relay's script, for its type: the autoload has no class name.
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")

# Keys of a sync request (NetRelay._request_sync()): the battle held as [floor, node], or empty;
# each map's last seq by session id; whether only a fresh snapshot will do.
const _HAVE_BATTLE: String = "battle"
const _HAVE_SEQS: String = "seqs"
const _HAVE_FRESH: String = "fresh"

# The run capture's key for its seats' sections (NetRelay's).
const _RUN_SEATS_KEY: String = "seats"

# The arrival of a campaign command the host refused before stamping it: a command's
# CampaignCommand.arrival before CampaignSession.submit(); stamps start at 1.
const _UNSTAMPED: int = 0

## The mirrored run; null until the host's first capture arrives.
var session: CampaignSession = null

var _relay: NetRelayScript = null
var _run_seed: int = 0

# A request for state is due: whether one is wanted, whether only a fresh snapshot will do,
# requests sent so far, and seconds since the last one (or since the need, before the first).
var _wants_sync: bool = false
var _wants_fresh: bool = false
var _attempts: int = 0
var _since_ask: float = 0.0

# The campaign commands sent and not yet settled, by token; and whether a rejected campaign batch
# for the local seat was announced, so its settle isn't announced again.
var _campaign_tokens: Dictionary[int, bool] = {}
var _heard_rejection: bool = false


## A mirror of the run seeded [param run_seed] (the host's campaign seed), fed by [param relay],
## a client's relay. Asks for nothing until [method start].
func _init(relay: NetRelayScript, run_seed: int) -> void:
	_relay = relay
	_run_seed = run_seed
	_relay.campaign_batch_received.connect(_on_relay_campaign_batch_received)
	_relay.combat_batch_received.connect(_on_relay_combat_batch_received)
	_relay.encounter_batch_received.connect(_on_relay_encounter_batch_received)
	_relay.command_settled.connect(_on_relay_command_settled)
	_relay.sync_received.connect(_on_relay_sync_received)


## Asks the host for the run, and its battle when one is open, now.
func start() -> void:
	_need(false, true)


## Stops following the relay and closes [member session]; the mirror is done.
func close() -> void:
	if is_instance_valid(_relay):
		_relay.campaign_batch_received.disconnect(_on_relay_campaign_batch_received)
		_relay.combat_batch_received.disconnect(_on_relay_combat_batch_received)
		_relay.encounter_batch_received.disconnect(_on_relay_encounter_batch_received)
		_relay.command_settled.disconnect(_on_relay_command_settled)
		_relay.sync_received.disconnect(_on_relay_sync_received)
	_relay = null
	_wants_sync = false
	if session != null:
		session.close()


## The seat this client plays: its peer's in the relay's [member NetRelay.seats].
func local_seat() -> int:
	if is_instance_valid(_relay) and _relay.seats != null:
		var seat: int = _relay.seats.seat_of_peer(_relay.multiplayer.get_unique_id())
		if seat != SeatDirectory.NO_SEAT:
			return seat
	# ASSUMPTION: until NT6 gives a client its seat directory, a client acts and shows as the host
	# seat; the host still takes every command's seat from the connection.
	return CampaignData.HOST_SEAT


## Sends [param command] for the map [param session_id] to the host and returns its token for
## [signal NetRelay.command_settled]; nothing changes here until the host's batches arrive.
## [constant NetRelay.NO_TOKEN] when nothing was sent.
func submit_combat(command: Command, session_id: int) -> int:
	if not is_instance_valid(_relay):
		return NetRelayScript.NO_TOKEN
	return _relay.send_combat(command, session_id)


## As [method submit_combat], for a campaign command. A refusal reaches
## [signal CampaignSession.command_rejected] when it settles.
func submit_campaign(command: CampaignCommand) -> int:
	if not is_instance_valid(_relay):
		return NetRelayScript.NO_TOKEN
	var token: int = _relay.send_campaign(command)
	if token != NetRelayScript.NO_TOKEN:
		_campaign_tokens[token] = true
	return token


## Runs the request clock on by [param seconds]: the next request goes once
## [constant SYNC_INTERVAL] has passed since the last, and after [constant SYNC_ATTEMPTS]
## unanswered ones the mirror gives up ([signal sync_gave_up]).
func advance(seconds: float) -> void:
	if not _wants_sync:
		return
	_since_ask += seconds
	if _since_ask >= SYNC_INTERVAL:
		_ask()


## Whether a request for state is outstanding.
func is_syncing() -> bool:
	return _wants_sync


# Wants state from the host: a fresh snapshot when fresh, asked at once when now, else after one
# interval (a battle's opening, whose snapshot the host pushes). A later need joins the one open.
func _need(fresh: bool, now: bool) -> void:
	_wants_fresh = _wants_fresh or fresh
	if not _wants_sync:
		_wants_sync = true
		_since_ask = 0.0
	if now:
		_ask()


func _ask() -> void:
	if not is_instance_valid(_relay):
		return
	if _attempts >= SYNC_ATTEMPTS:
		NetLog.warn(
				NetLog.Category.LOBBY,
				"ClientMirror: no answer to %d requests for state; giving up." % [_attempts]
		)
		var attempts: int = _attempts
		_wants_sync = false
		_attempts = 0
		sync_gave_up.emit(attempts)
		return
	_attempts += 1
	_since_ask = 0.0
	_relay.request_sync(_have())


# What this mirror holds, for the host's answer: the battle and each map's last seq.
func _have() -> Dictionary:
	var battle: Array = []
	var seqs: Array = []
	var held: CombatEncounter = _battle()
	if held != null:
		battle = [held.floor_number, held.node]
		for map: CombatSession in held.get_sessions():
			seqs.append(map.last_seq())
	return {_HAVE_BATTLE: battle, _HAVE_SEQS: seqs, _HAVE_FRESH: _wants_fresh}


func _battle() -> CombatEncounter:
	return null if session == null else session.encounter


# Restores the run from run, the host's capture, building the session on the first; carries the
# facts already heard over, and batch's new facts after them, for the screens' playback. False,
# changing nothing, for an empty or unusable capture, or one for other seats.
func _restore_run(run: Dictionary, batch: CampaignBatch) -> bool:
	var by_seat: Variant = run.get(_RUN_SEATS_KEY, null)
	if run.is_empty() or not by_seat is Dictionary:
		return false
	var seats: PackedInt32Array = []
	for seat: Variant in by_seat:
		if not seat is int or not (by_seat as Dictionary)[seat] is Dictionary:
			return false
		seats.append(seat as int)
	seats.sort()
	if session != null and session.seats != seats:
		NetLog.warn(NetLog.Category.CAMPAIGN, "ClientMirror: a capture for seats %s" % [seats])
		return false
	var sections: RunSaveSections = RunSaveSections.new()
	var restored: bool = (
			_restore_part(sections.map, run.get(sections.map.get_key(), null))
			and _restore_part(sections.flow, run.get(sections.flow.get_key(), null))
	)
	for seat: int in seats:
		var parts: Dictionary = (by_seat as Dictionary)[seat]
		for section: RunSaveSections.SeatSection in sections.seat_sections:
			var data: Variant = parts.get(section.get_key(), null)
			restored = (
					restored
					and data is Dictionary
					and section.restore(seat, data as Dictionary) == OK
			)
	var is_new: bool = session == null
	var target: CampaignSession = session
	if is_new:
		target = CampaignSession.new(CampaignData.Mode.MULTIPLAYER, _run_seed, seats)
		target.is_mirror = true
	var heard: Array[CampaignFact] = []
	if target.run != null:
		heard = target.run.fact_log
	if not restored or sections.attach(target) != OK:
		NetLog.warn(NetLog.Category.CAMPAIGN, "ClientMirror: the host's run capture can't load.")
		sections.detach()
		return false
	sections.detach()
	var last_seq: int = 0 if heard.is_empty() else heard[heard.size() - 1].seq
	if batch != null:
		for fact: CampaignFact in batch.facts:
			if fact.seq > last_seq:
				heard.append(fact)
	target.run.fact_log = heard
	if is_new:
		session = target
		session_built.emit(session)
	return true


# Rebuilds the battle from snapshot, the host's encounter snapshot, as a resume would: from the
# mirror run's request and the run seed, with the snapshot loaded instead of a save. False,
# leaving no battle, when it can't.
func _build_battle(snapshot: Dictionary) -> bool:
	if session == null or session.run == null:
		return false
	if str(snapshot.get("run_seed", "")) != RunSeed.format(_run_seed):
		NetLog.warn(NetLog.Category.COMBAT, "ClientMirror: a battle snapshot from another run.")
		return false
	session.abandon_battle()
	var request: CampaignSession.BattleRequest = session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return false
	var load_snapshot: Callable = func(battle: CombatEncounter) -> Error:
		return battle.load_snapshot(snapshot)
	return session.resume_battle(request, load_snapshot) != null


# What applying a batch to map (null: the encounter) returned: a gap asks for the facts missed,
# a debug hash mismatch dumps the map and asks for a fresh snapshot.
func _after_apply(map: CombatSession, batch: CombatSession.FactBatch, err: Error) -> void:
	match err:
		OK:
			return
		ERR_PARAMETER_RANGE_ERROR:
			# The encounter keeps no facts to catch up from, so its gap needs a snapshot.
			_need(map == null, true)
		ERR_INVALID_DATA:
			var dumped: CombatSession = map
			if dumped == null:
				dumped = _battle().get_session(batch.session_id)
			var path: String = "" if dumped == null else dumped.debug_dump()
			NetLog.warn(
					NetLog.Category.COMBAT,
					"ClientMirror: s%d differs from the host's (dump: %s); resyncing."
					% [batch.session_id, path]
			)
			_need(true, true)
		_:
			_need(true, true)


func _on_relay_campaign_batch_received(facts: Array, run: Dictionary) -> void:
	var batch: CampaignBatch = null
	if not facts.is_empty():
		batch = CampaignBatch.from_wire(facts)
		if batch == null:
			_need(false, true)
			return
	var is_rejection: bool = batch != null and batch.is_rejected()
	# A battle's end arrives as the run with no facts; nothing else resolves during a battle.
	if not is_rejection and _battle() != null:
		session.abandon_battle()
	if not _restore_run(run, batch):
		_need(false, true)
		return
	if batch == null:
		return
	if is_rejection and batch.seat == local_seat():
		_heard_rejection = true
		session.command_rejected.emit(batch.seat, batch.arrival, batch.rejected_reason)
	session.campaign_batch_resolved.emit(batch)


func _on_relay_combat_batch_received(wire: Array) -> void:
	var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
	var battle: CombatEncounter = _battle()
	if batch == null or battle == null:
		# Dropped: the battle's snapshot covers it. The host pushes one as its battle opens.
		_need(batch == null, batch == null)
		return
	if batch.is_rejected():
		return
	var map: CombatSession = battle.get_session(batch.session_id)
	if map == null:
		_need(true, true)
		return
	_after_apply(map, batch, map.apply_batch(batch))


func _on_relay_encounter_batch_received(wire: Array) -> void:
	var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
	var battle: CombatEncounter = _battle()
	if batch == null or battle == null:
		_need(batch == null, batch == null)
		return
	_after_apply(null, batch, battle.apply_batch(batch))


# A campaign command's refusal with no batch of its own (a pause, no seat, malformed) reaches the
# session as a rejection, with no arrival; one whose rejected batch was announced isn't announced
# twice, since the host settles a command right after its batch. Combat settles are
# CampaignService's, which knows the map each was sent for.
func _on_relay_command_settled(token: int, reason: String) -> void:
	if not _campaign_tokens.has(token):
		return
	_campaign_tokens.erase(token)
	var was_heard: bool = _heard_rejection
	_heard_rejection = false
	if reason.is_empty() or was_heard or session == null:
		return
	session.command_rejected.emit(local_seat(), _UNSTAMPED, reason)


func _on_relay_sync_received(
		run: Dictionary, battle: Dictionary, facts: Array, screen: int
) -> void:
	# Answered: any need left after applying it is a new one. An answer that can't be used (no run
	# yet, a snapshot that won't load) is asked again after an interval, not at once.
	_wants_sync = false
	if not _restore_run(run, null):
		_need(false, false)
		return
	var is_battle_open: bool = screen == SceneRouter.Screen.GAMEPLAY
	if not battle.is_empty():
		if not _build_battle(battle):
			_need(true, false)
			return
		_wants_fresh = false
	elif not is_battle_open:
		session.abandon_battle()
	var held: CombatEncounter = _battle()
	for wire: Variant in facts:
		var catch_up: CombatSession.FactBatch = (
				CombatSession.FactBatch.from_wire(wire as Array) if wire is Array else null
		)
		var map: CombatSession = (
				null if catch_up == null or held == null else held.get_session(catch_up.session_id)
		)
		if map == null:
			_need(true, true)
			return
		_after_apply(map, catch_up, map.apply_batch(catch_up))
	if is_battle_open and held == null:
		_need(false, false)
	if not _wants_sync:
		_attempts = 0


static func _restore_part(section: RunSaveSections.SharedSection, data: Variant) -> bool:
	return data is Dictionary and section.restore(data as Dictionary) == OK
