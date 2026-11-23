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
## flagged [member CampaignSession.is_mirror]: each campaign batch restores its run, events and
## open swap proposals from the run's capture, then announces itself on the session's signals, so
## screens read a mirror as they read the host's. Only a battle's end (a batch of no seat) closes
## its battle, adding the facts it recorded; a seat that left the run leaves the session's seats
## once a capture no longer holds it. The battle is rebuilt as a resume rebuilds one
## ([method CampaignSession.resume_battle]) from the host's snapshot, then follows every map's and
## the encounter's batches, a seat's leave included ([constant CombatFact.Kind.UNIT_LEFT]).[br]
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

# The run capture's key for its seats' sections, and for the open swap proposals (NetRelay's).
const _RUN_SEATS_KEY: String = "seats"
const _RUN_PROPOSALS_KEY: String = "swap_proposals"

# The arrival of a campaign command the host refused before stamping it: a command's
# CampaignCommand.arrival before CampaignSession.submit(); stamps start at 1.
const _UNSTAMPED: int = 0

## The mirrored run; null until the host's first capture arrives.
var session: CampaignSession = null

var _relay: NetRelayScript = null
var _run_seed: int = 0

# The seat local_seat() last found.
var _seat: int = SeatDirectory.NO_SEAT

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

# Seats whose map a closed battle held forfeited: they have left the run, though a mirror built
# after a resume never heard their SEAT_FORFEITED.
var _departed: PackedInt32Array = []


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


## The seat this client plays: its peer's in the relay's [member NetRelay.seats]. Kept through a
## reconnect, while the relay has no peer or its directory doesn't hold the new one yet;
## [constant SeatDirectory.NO_SEAT] before the directory first seats it.
func local_seat() -> int:
	if is_instance_valid(_relay) and _relay.seats != null and _has_host():
		var seat: int = _relay.seats.seat_of_peer(_relay.multiplayer.get_unique_id())
		if seat != SeatDirectory.NO_SEAT:
			_seat = seat
	return _seat


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
## unanswered ones the mirror gives up ([signal sync_gave_up]). The clock stands still while the
## relay has no host: the rejoin brings fresh state anyway.
func advance(seconds: float) -> void:
	if not _wants_sync or not _has_host():
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
	if not _has_host():
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


# Whether the relay is connected to a host now; not while a client reconnects.
func _has_host() -> bool:
	if not is_instance_valid(_relay) or not NetGate.has_session(_relay.multiplayer):
		return false
	var status: MultiplayerPeer.ConnectionStatus = (
			_relay.multiplayer.multiplayer_peer.get_connection_status()
	)
	return status == MultiplayerPeer.CONNECTION_CONNECTED


func _battle() -> CombatEncounter:
	return null if session == null else session.encounter


# Whether run, a host's capture, is the run after this client's own seat left it: the session
# holds the seat and the capture doesn't.
func _is_leaving(run: Dictionary) -> bool:
	var seat: int = local_seat()
	if session == null or seat == SeatDirectory.NO_SEAT or not session.seats.has(seat):
		return false
	var kept: PackedInt32Array = _seats_of(run)
	return not kept.is_empty() and not kept.has(seat)


# Whether kept, a capture's seats, is the session's less only seats that left the run: each named
# by a SEAT_FORFEITED this mirror heard (batch's included), forfeited on a battle it held, or
# removed in the relay's directory, as a client back from a drop hears of a removal it missed.
func _lacks_only_departed(kept: PackedInt32Array, batch: CampaignBatch) -> bool:
	for seat: int in kept:
		if not session.seats.has(seat):
			return false
	for seat: int in session.seats:
		if not kept.has(seat) and not _has_left(seat, batch):
			return false
	return true


func _has_left(seat: int, batch: CampaignBatch) -> bool:
	var held: CombatEncounter = _battle()
	if _departed.has(seat) or (held != null and held.forfeited_seats().has(seat)):
		return true
	var directory: SeatDirectory = _relay.seats if is_instance_valid(_relay) else null
	if directory != null and directory.state_of(seat) == SeatDirectory.State.REMOVED:
		return true
	var heard: Array[CampaignFact] = []
	if session.run != null:
		heard.append_array(session.run.fact_log)
	if batch != null:
		heard.append_array(batch.facts)
	for fact: CampaignFact in heard:
		if fact.kind == CampaignFact.Kind.SEAT_FORFEITED and fact.seat == seat:
			return true
	return false


# Restores the run from run, the host's capture, building the session on the first: its sections,
# then the events and the open swap proposals; carries the facts already heard over, and batch's
# new facts after them, for the screens' playback. A capture without seats that left the run
# takes them out of the session's seats. False, changing nothing, for an empty or unusable
# capture, one missing a part, or one for other seats.
func _restore_run(run: Dictionary, batch: CampaignBatch) -> bool:
	var seats: PackedInt32Array = _seats_of(run)
	if seats.is_empty():
		return false
	if session != null and session.seats != seats and not _lacks_only_departed(seats, batch):
		NetLog.warn(NetLog.Category.CAMPAIGN, "ClientMirror: a capture for seats %s" % [seats])
		return false
	var by_seat: Dictionary = run[_RUN_SEATS_KEY]
	var sections: RunSaveSections = RunSaveSections.new()
	var events: EventSaveSection = EventSaveSection.new()
	var proposals: Array[UnitSwap] = []
	var restored: bool = (
			_restore_part(sections.map, run.get(sections.map.get_key(), null))
			and _restore_part(sections.flow, run.get(sections.flow.get_key(), null))
			and _restore_part(events, run.get(events.get_key(), null))
			and _read_proposals(run.get(_RUN_PROPOSALS_KEY, null), proposals)
	)
	for seat: int in seats:
		var parts: Dictionary = by_seat[seat]
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
	# The sections build the run for the session's seats, so seats that left go first.
	var seats_before: PackedInt32Array = target.seats
	target.seats = seats
	if not restored or sections.attach(target) != OK:
		target.seats = seats_before
		NetLog.warn(NetLog.Category.CAMPAIGN, "ClientMirror: the host's run capture can't load.")
		sections.detach()
		return false
	sections.detach()
	# The run exists now and restore() checked the events, so neither can fail.
	events.attach(target)
	events.detach()
	target.run.swap_proposals = proposals
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
	# The leaving seat's own mirror keeps what it holds: its record and the main menu follow.
	if _is_leaving(run):
		return
	# A battle's end arrives as the run with what it recorded (a batch of no seat) or no facts. A
	# forfeit is the only other batch a battle resolves, and its battle goes on.
	var is_battle_end: bool = batch == null or batch.seat == CampaignFact.NO_SEAT
	if not is_rejection and is_battle_end and _battle() != null:
		_departed.append_array(_battle().forfeited_seats())
		session.abandon_battle()
	if not _restore_run(run, batch):
		_need(false, true)
		return
	# No command made a battle end's batch, and the host's session announces none for it.
	if batch == null or (batch.seat == CampaignFact.NO_SEAT and not is_rejection):
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
	# yet, a snapshot that won't load) is asked again after an interval, not at once; one for a run
	# this seat has left is not.
	_wants_sync = false
	if _is_leaving(run):
		return
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


# The seats run, a host's capture, holds sections for, ascending; empty for one with none, or with
# a seat entry that isn't a whole number holding a Dictionary.
static func _seats_of(run: Dictionary) -> PackedInt32Array:
	var seats: PackedInt32Array = []
	var by_seat: Variant = run.get(_RUN_SEATS_KEY, null)
	if not by_seat is Dictionary:
		return seats
	for seat: Variant in by_seat as Dictionary:
		if not seat is int or not (by_seat as Dictionary)[seat] is Dictionary:
			return PackedInt32Array()
		seats.append(seat as int)
	seats.sort()
	return seats


static func _restore_part(section: SaveSection, data: Variant) -> bool:
	return data is Dictionary and section.restore(data as Dictionary) == OK


# Reads the capture's open swap proposals, data, into into, in order. False for anything but an
# Array of proposals UnitSwap.restore() accepts.
static func _read_proposals(data: Variant, into: Array[UnitSwap]) -> bool:
	if not data is Array:
		return false
	for entry: Variant in data as Array:
		var proposal: UnitSwap = UnitSwap.restore(entry)
		if proposal == null:
			return false
		into.append(proposal)
	return true
