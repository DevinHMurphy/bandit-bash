# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     net_relay.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends Node
## Every run message between host and clients: commands up, batches down, each command's settle,
## and presentation notices. Autoload [code]NetRelay[/code], after [code]CampaignService[/code].
##
## It reads its own node's [code]multiplayer[/code] ([NetGate]) and [member seats], never Steam, so
## a two-peer test puts one under each branch. [b]On the host[/b] a client's command takes its seat
## from the connection, never the message, is refused while the run is paused, is filled
## ([HostFill]) and goes through [code]CampaignService[/code] as the host's screens send theirs; its
## sender alone hears how it settled. Every batch the run makes goes to every client in the host's
## order on one reliable channel, a rejection to its sender only, campaign batches with the run's
## capture. [b]Clients[/b] hand what arrives on through the [code]*_received[/code] signals.
## Notices are presentation only: rules never read them.
##
## @tutorial(Net transport plan): docs/plans/2026-11-19-net-transport.md

## The host settled the command this client sent with [param token]: [param reason] is empty when
## it resolved, else why it was refused or rejected. Clients only, after the command's batch.
signal command_settled(token: int, reason: String)

## A map's batch arrived from the host ([method CombatSession.FactBatch.to_wire]). Clients only.
signal combat_batch_received(wire: Array)

## An encounter batch arrived from the host ([signal CombatEncounter.batch_resolved]). Clients only.
signal encounter_batch_received(wire: Array)

## A campaign batch arrived: [param facts] is its [method CampaignBatch.to_wire], empty when only
## the run changed (a battle's end); [param run] is the run's capture, each shared section's data
## by key and, under [code]"seats"[/code], each seat's sections by seat, then by key. Clients only.
signal campaign_batch_received(facts: Array, run: Dictionary)

## [param seat] sent a notice of [enum NoticeKind] [param kind] with [param data]. Presentation
## only. Never emitted for this machine's own notices.
signal notice_received(seat: int, kind: int, data: Array)

## What a notice says. Sent as an int: [b]append only[/b], with explicit values; the build
## fingerprint covers it ([NetContract]).
enum NoticeKind {
	## The sender's selected unit on a map, for teammates' markers: data
	## [code][session id, unit id][/code], the id empty for none.
	SELECTION = 0,
}

## The token [method send_combat] and [method send_campaign] return when nothing was sent. Real
## tokens start at 1.
const NO_TOKEN: int = 0

# The NetLog autoload's script, for its Category type.
const NetLogScript = preload("res://scripts/autoload/net_log.gd")

# The host's peer id, on every peer of a Godot session.
const _HOST_PEER: int = 1

# Why a client's command settled without resolving, before any rule looked at it.
const _NOT_SEATED: String = "not seated"
const _PAUSED: String = "paused"
const _MALFORMED: String = "malformed"
const _NO_RUN: String = "no run"
const _NO_BATTLE: String = "no battle"
const _NO_MAP: String = "no such map"

# The key the run capture keeps its seats' sections under.
const _RUN_SEATS_KEY: String = "seats"

# Slots of a SELECTION notice's data: the map's session id, the unit id.
const _SELECTION_FIELDS: int = 2

## The host's seats: which connection holds which seat. [b]Null:[/b] none is known, so every
## client's command settles "not seated". Unused on a client.
var seats: SeatDirectory = null

var _next_token: int = NO_TOKEN + 1

# The run session and battle whose batches the host sends; null when there is none.
var _session: CampaignSession = null
var _encounter: CombatEncounter = null


func _ready() -> void:
	CampaignService.session_started.connect(_on_campaign_service_session_started)
	CampaignService.session_ended.connect(_on_campaign_service_session_ended)
	# A relay that joins the tree after the session was built (one under a test branch) follows it
	# from now.
	_follow(CampaignService.session)


func _exit_tree() -> void:
	_follow(null)
	CampaignService.session_started.disconnect(_on_campaign_service_session_started)
	CampaignService.session_ended.disconnect(_on_campaign_service_session_ended)


## Sends [param command], for the map [param session_id], from this client to the host and
## returns its token for [signal command_settled]. Nothing changes here until batches arrive.
## [constant NO_TOKEN], sending nothing, on the host, in solo, for null, or for a command with
## no wire form.
func send_combat(command: Command, session_id: int) -> int:
	if command == null or not _is_client():
		push_error("NetRelay: only a client sends a combat command to the host.")
		return NO_TOKEN
	var wire: Array = command.to_wire()
	if wire.is_empty():
		return NO_TOKEN
	var token: int = _take_token()
	var err: Error = rpc_id(_HOST_PEER, &"_submit_combat", wire, session_id, token)
	if err != OK:
		push_error("NetRelay: a combat command wasn't sent - %s" % [error_string(err)])
		return NO_TOKEN
	return token


## As [method send_combat], for a campaign command.
func send_campaign(command: CampaignCommand) -> int:
	if command == null or not _is_client():
		push_error("NetRelay: only a client sends a campaign command to the host.")
		return NO_TOKEN
	var wire: Array = command.to_wire()
	if wire.is_empty():
		return NO_TOKEN
	var token: int = _take_token()
	var err: Error = rpc_id(_HOST_PEER, &"_submit_campaign", wire, token)
	if err != OK:
		push_error("NetRelay: a campaign command wasn't sent - %s" % [error_string(err)])
		return NO_TOKEN
	return token


## Tells every other peer this machine's notice of [enum NoticeKind] [param kind] with
## [param data]: a client's goes through the host, which forwards it, the host's straight to every
## client. Does nothing in solo. Refused, with an error, for data its kind doesn't allow or a host
## that holds no seat in [member seats].
func send_notice(kind: int, data: Array) -> void:
	if not NetGate.has_session(multiplayer):
		return
	if not _is_notice_valid(kind, data):
		push_error("NetRelay: notice %d with data %s isn't allowed." % [kind, data])
		return
	if not multiplayer.is_server():
		_notice.rpc_id(_HOST_PEER, SeatDirectory.NO_SEAT, kind, data)
		return
	var seat: int = _seat_of(multiplayer.get_unique_id())
	if seat == SeatDirectory.NO_SEAT:
		push_error("NetRelay: the host holds no seat to send a notice for.")
		return
	_notice.rpc(seat, kind, data)


# A client's combat command, on the host: the sender's seat, the pause, the wire form and the map
# are checked first, then it resolves as the host's own would. The sender is told how it settled.
@rpc("any_peer", "call_remote", "reliable")
func _submit_combat(wire: Array, session_id: int, token: int) -> void:
	if not _is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if token <= NO_TOKEN:
		_log_dropped(sender, "a combat command with token %d" % [token])
		return
	var seat: int = _seat_of(sender)
	var reason: String = _seat_reason(seat)
	if reason.is_empty():
		var command: Command = Command.from_wire(wire)
		if command == null:
			reason = _MALFORMED
		else:
			command.seat = seat
			reason = _route_combat(command, session_id)
	_settle(sender, token, reason, NetLog.Category.COMBAT)


# As _submit_combat(), for a campaign command, filled by HostFill before it resolves.
@rpc("any_peer", "call_remote", "reliable")
func _submit_campaign(wire: Array, token: int) -> void:
	if not _is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if token <= NO_TOKEN:
		_log_dropped(sender, "a campaign command with token %d" % [token])
		return
	var seat: int = _seat_of(sender)
	var reason: String = _seat_reason(seat)
	if reason.is_empty():
		var command: CampaignCommand = CampaignCommand.from_wire(wire)
		if command == null:
			reason = _MALFORMED
		else:
			command.seat = seat
			reason = _route_campaign(command)
	_settle(sender, token, reason, NetLog.Category.CAMPAIGN)


@rpc("authority", "call_remote", "reliable")
func _command_settled(token: int, reason: String) -> void:
	if multiplayer.is_server():
		return
	command_settled.emit(token, reason)


@rpc("authority", "call_remote", "reliable")
func _combat_batch(wire: Array) -> void:
	if multiplayer.is_server():
		return
	combat_batch_received.emit(wire)


@rpc("authority", "call_remote", "reliable")
func _encounter_batch(wire: Array) -> void:
	if multiplayer.is_server():
		return
	encounter_batch_received.emit(wire)


@rpc("authority", "call_remote", "reliable")
func _campaign_batch(facts: Array, run: Dictionary) -> void:
	if multiplayer.is_server():
		return
	campaign_batch_received.emit(facts, run)


# A notice. Up: any client to the host, which takes the seat from the connection and forwards it
# to every other client. Down: only the host's forward is heard, so a client's direct call to
# another client is ignored.
@rpc("any_peer", "call_remote", "reliable")
func _notice(seat: int, kind: int, data: Array) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _is_notice_valid(kind, data):
		_log_dropped(sender, "notice %d with data %s" % [kind, data])
		return
	if not multiplayer.is_server():
		if sender == _HOST_PEER and seat > SeatDirectory.NO_SEAT:
			notice_received.emit(seat, kind, data)
		return
	var from_seat: int = _seat_of(sender)
	if from_seat == SeatDirectory.NO_SEAT:
		_log_dropped(sender, "a notice from no seat")
		return
	notice_received.emit(from_seat, kind, data)
	for peer: int in multiplayer.get_peers():
		if peer != sender:
			_notice.rpc_id(peer, from_seat, kind, data)


func _is_host() -> bool:
	return NetGate.has_session(multiplayer) and multiplayer.is_server()


func _is_client() -> bool:
	return NetGate.has_session(multiplayer) and not multiplayer.is_server()


func _take_token() -> int:
	var token: int = _next_token
	_next_token += 1
	return token


# The seat peer_id holds in seats; NO_SEAT without a directory.
func _seat_of(peer_id: int) -> int:
	return SeatDirectory.NO_SEAT if seats == null else seats.seat_of_peer(peer_id)


# The peer to tell about seat's own rejection; NO_PEER for this machine, a dropped seat or none.
func _peer_of(seat: int) -> int:
	if seats == null:
		return SeatDirectory.NO_PEER
	var peer: int = seats.peer_of_seat(seat)
	return SeatDirectory.NO_PEER if peer == multiplayer.get_unique_id() else peer


# Why a command from seat can't be taken now: no seat, or the run paused by a dropped seat.
func _seat_reason(seat: int) -> String:
	if seat == SeatDirectory.NO_SEAT:
		return _NOT_SEATED
	if not seats.dropped_seats().is_empty():
		return _PAUSED
	return ""


# Resolves command on the map session_id of the open battle; returns its rejection, empty when it
# resolved.
func _route_combat(command: Command, session_id: int) -> String:
	var run_session: CampaignSession = CampaignService.session
	if run_session == null or run_session.encounter == null:
		return _NO_BATTLE
	if run_session.encounter.get_session(session_id) == null:
		return _NO_MAP
	for batch: CombatSession.FactBatch in CampaignService.submit_combat(command, session_id):
		if batch.arrival == command.arrival and batch.is_rejected():
			return batch.rejected_reason
	return ""


# Fills and resolves command on the run; returns its rejection, empty when it resolved.
func _route_campaign(command: CampaignCommand) -> String:
	var run_session: CampaignSession = CampaignService.session
	if run_session == null or run_session.run == null:
		return _NO_RUN
	var filled: CampaignCommand = HostFill.complete(command, run_session)
	if filled == null:
		return _MALFORMED
	var batch: CampaignBatch = CampaignService.submit_command(filled)
	return _NO_RUN if batch == null else batch.rejected_reason


func _settle(sender: int, token: int, reason: String, category: NetLogScript.Category) -> void:
	if not reason.is_empty():
		NetLog.warn(
				category,
				"NetRelay: peer %d's command %d settled - %s" % [sender, token, reason]
		)
	_command_settled.rpc_id(sender, token, reason)


func _log_dropped(sender: int, what: String) -> void:
	NetLog.warn(NetLog.Category.LOBBY, "NetRelay: dropped %s from peer %d." % [what, sender])


# Follows followed's campaign batches and battles, letting go of the session followed before.
func _follow(followed: CampaignSession) -> void:
	if _session == followed:
		return
	_follow_battle(null)
	if _session != null:
		_session.campaign_batch_resolved.disconnect(_on_session_campaign_batch_resolved)
		_session.combat_encounter_opened.disconnect(_on_session_combat_encounter_opened)
		_session.combat_encounter_closed.disconnect(_on_session_combat_encounter_closed)
	_session = followed
	if _session == null:
		return
	_session.campaign_batch_resolved.connect(_on_session_campaign_batch_resolved)
	_session.combat_encounter_opened.connect(_on_session_combat_encounter_opened)
	_session.combat_encounter_closed.connect(_on_session_combat_encounter_closed)
	_follow_battle(_session.encounter)


# Follows battle's encounter batches and every map's, letting go of the battle followed before.
func _follow_battle(battle: CombatEncounter) -> void:
	if _encounter == battle:
		return
	if _encounter != null:
		_encounter.session_opened.disconnect(_on_encounter_session_opened)
		_encounter.batch_resolved.disconnect(_on_encounter_batch_resolved)
		for map: CombatSession in _encounter.get_sessions():
			if map.batch_resolved.is_connected(_on_map_batch_resolved):
				map.batch_resolved.disconnect(_on_map_batch_resolved)
	_encounter = battle
	if _encounter == null:
		return
	_encounter.session_opened.connect(_on_encounter_session_opened)
	_encounter.batch_resolved.connect(_on_encounter_batch_resolved)
	for map: CombatSession in _encounter.get_sessions():
		_on_encounter_session_opened(map)


# The run's six sections as they are now: a fresh RunSaveSections holds nothing, so attaching it
# reads the session's run without changing it (its attach() returns ERR_DOES_NOT_EXIST then).
func _capture_run() -> Dictionary:
	var captured: Dictionary = {}
	if _session == null or _session.run == null:
		return captured
	var sections: RunSaveSections = RunSaveSections.new()
	if sections.attach(_session) != ERR_DOES_NOT_EXIST:
		push_error("NetRelay: the run couldn't be captured.")
		return captured
	captured[sections.map.get_key()] = sections.map.capture()
	captured[sections.flow.get_key()] = sections.flow.capture()
	var by_seat: Dictionary = {}
	for seat: int in _session.seats:
		var parts: Dictionary = {}
		for section: RunSaveSections.SeatSection in sections.seat_sections:
			parts[section.get_key()] = section.capture(seat)
		by_seat[seat] = parts
	captured[_RUN_SEATS_KEY] = by_seat
	sections.detach()
	return captured


func _on_campaign_service_session_started(started: CampaignSession) -> void:
	_follow(started)


func _on_campaign_service_session_ended(ended: CampaignSession) -> void:
	if ended == _session:
		_follow(null)


func _on_session_campaign_batch_resolved(batch: CampaignBatch) -> void:
	if not _is_host():
		return
	if not batch.is_rejected():
		_campaign_batch.rpc(batch.to_wire(), _capture_run())
		return
	var peer: int = _peer_of(batch.seat)
	if peer != SeatDirectory.NO_PEER:
		_campaign_batch.rpc_id(peer, batch.to_wire(), _capture_run())


func _on_session_combat_encounter_opened(encounter: CombatEncounter) -> void:
	_follow_battle(encounter)


# The battle's end has applied to the run by now (CampaignService.end_battle()), so the run goes
# out with no facts; a battle dropped without applying sends the run as it stands, still the truth.
func _on_session_combat_encounter_closed(encounter: CombatEncounter) -> void:
	if encounter == _encounter:
		_follow_battle(null)
	if _is_host():
		_campaign_batch.rpc([], _capture_run())


func _on_encounter_session_opened(map: CombatSession) -> void:
	if not map.batch_resolved.is_connected(_on_map_batch_resolved):
		map.batch_resolved.connect(_on_map_batch_resolved)


func _on_encounter_batch_resolved(batch: CombatSession.FactBatch) -> void:
	if _is_host():
		_encounter_batch.rpc(batch.to_wire())


func _on_map_batch_resolved(batch: CombatSession.FactBatch) -> void:
	if not _is_host():
		return
	if not batch.is_rejected():
		_combat_batch.rpc(batch.to_wire())
		return
	var peer: int = _peer_of(batch.seat)
	if peer != SeatDirectory.NO_PEER:
		_combat_batch.rpc_id(peer, batch.to_wire())


# Whether data is what a notice of kind carries.
static func _is_notice_valid(kind: int, data: Array) -> bool:
	match kind:
		NoticeKind.SELECTION:
			return (
					data.size() == _SELECTION_FIELDS
					and data[0] is int
					and (data[0] as int) >= 0
					and data[1] is String
			)
	return false
