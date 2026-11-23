# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     net_relay.gd
# Author:
# Created:  November 22, 2026
# Modified: November 23, 2026
# ==============================================================================

extends Node
## Every run message between host and clients: commands up, batches down, settles, notices, seat
## settings, and the seats' drops and rejoins. Autoload [code]NetRelay[/code], after
## [code]CampaignService[/code]; it reads its own node's [code]multiplayer[/code] ([NetGate]) and
## [member seats], never Steam but to seat a lobby's run, so a test puts one under each branch.
## [b]Host:[/b] a client's command takes its seat from the connection, is refused while paused, is
## filled ([HostFill]) and resolves as the host's own; its sender alone hears how it settled.
## Batches go to every seated client in order on one reliable channel (a rejection to its sender),
## campaign batches with the run's capture, a battle's snapshot the idle frame after it opens. A
## dropped seat pauses the run until it rejoins (a fresh snapshot) or is removed. [b]Clients[/b]
## pass it on through the [code]*_received[/code] signals and send their settings
## ([method seat_settings]). [code]_sync[/code] and [code]_campaign_batch[/code] travel packed;
## nothing over Steam's message limit is sent; each message is a NetLog line (kind, size, peer).
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

## State from the host (an answer to [method request_sync], a battle's opening, a rejoin): the
## run's capture; the encounter's [method CombatEncounter.snapshot] or empty; each map's missed
## facts as [method CombatSession.FactBatch.to_wire]s; [param screen] is
## [code]SceneRouter.Screen.GAMEPLAY[/code] while a battle is open, else -1. Clients only.
signal sync_received(run: Dictionary, battle: Dictionary, facts: Array, screen: int)

## [param seat] lost its connection during the run, which is paused until it is back or removed.
## Every peer, the host included, on the host's word.
signal seat_dropped(seat: int)

## The dropped [param seat] is connected again, with the run from a fresh snapshot. Every peer that
## was waiting for it.
signal seat_rejoined(seat: int)

## The host removed the dropped [param seat] after its wait ([method remove_seat]); it never comes
## back. Every peer. No rule acts on a removal yet: its map stays in the battle.
signal seat_removed(seat: int)

## What a notice says. Sent as an int: [b]append only[/b], with explicit values; the build
## fingerprint covers it ([NetContract]).
enum NoticeKind {
	## The sender's selected unit on a map, for teammates' markers: data
	## [code][session id, unit id][/code], the id empty for none.
	SELECTION = 0,
	## A client's move for everyone ([code]SceneRouter.goto_screen_for_everyone()[/code]), data
	## empty: the host routes everyone itself, by its own run. Never forwarded; dropped while
	## paused.
	ROUTE = 1,
	## The sender's fast-forward hold changed: data [code][session id, held][/code], the map it
	## holds on and whether it holds. A map other players have units on plays fast only while
	## every one of them holds ([BattleController]).
	FAST_FORWARD = 2,
}

## The token [method send_combat] and [method send_campaign] return when nothing was sent. Real
## tokens start at 1.
const NO_TOKEN: int = 0

## Seconds a seat must have been dropped before [method remove_seat] may remove it (the vision's
## first pass).
const REMOVE_WAIT: float = 120.0

# The NetLog autoload's script, for its Category type.
const NetLogScript = preload("res://scripts/autoload/net_log.gd")

# The wait overlay, loaded at the first wait, so a run nobody drops from never loads UI here.
const _OVERLAY_PATH: String = "res://ui/net/seat_wait_overlay.tscn"

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

# Slots of a FAST_FORWARD notice's data: the map's session id, whether the sender holds.
const _FAST_FORWARD_FIELDS: int = 2

# The settings a client sends the host (seat_settings()), each a SettingsData key.
# NOTE: the fingerprint covers RPCs and notice kinds, not these keys: a key added here is a wire
# change it misses, so an older host drops the newer client's settings as malformed (logged) and
# uses each setting's default.
const _SEAT_SETTING_KEYS: PackedStringArray = [SettingsData.OPENING_SWAP_KEY]

# A sync request's keys (ClientMirror's): the battle held as [floor, node] or empty, each map's
# last seq by session id, and whether only a fresh snapshot will do.
const _HAVE_BATTLE: String = "battle"
const _HAVE_SEQS: String = "seqs"
const _HAVE_FRESH: String = "fresh"

# _sync()'s screen when no battle is open.
const _NO_SCREEN: int = -1

# A catch-up batch's label, for the client's log.
const _CATCH_UP_LABEL: String = "catch-up"

# Steam's limit on one message (k_cbMaxSteamNetworkingSocketsMessageSizeSend, Valve's
# steamnetworkingtypes.h); a larger send fails. ENet's and the loopback's are far larger.
const _STEAM_MESSAGE_LIMIT: int = 512 * 1024
# ASSUMPTION: room for Godot's RPC header and GodotSteam's own packet header, which couldn't be
# read; NT8 checks it live.
const _SEND_MARGIN: int = 1024
# The most a message's measured size may be: _size_of() of its arguments.
const _SEND_BUDGET: int = _STEAM_MESSAGE_LIMIT - _SEND_MARGIN

# The packed form of _sync's and _campaign_batch's arguments: this format byte, their encoded
# size (u32), their MD5 (16 bytes), then their var_to_bytes() compressed with _PACK_MODE. The
# fingerprint covers the format (NetContract); change it with the layout or the mode.
const _PACK_FORMAT: int = 1
const _PACK_MODE: FileAccess.CompressionMode = FileAccess.COMPRESSION_ZSTD
const _PACK_SIZE_AT: int = 1
const _PACK_DIGEST_AT: int = 5
const _PACK_HEADER: int = 21
# ASSUMPTION: Godot's own default limit on one Variant decoded from a packet peer
# (PacketPeer.encode_buffer_max_size, 8 MiB); the largest message measured is about 350 KB.
const _UNPACK_LIMIT: int = 8 * 1024 * 1024

## Which connection holds which seat. On the host it decides every client's seat; on a client it
## gives this machine's own. [b]Null:[/b] none is known, so every client's command settles "not
## seated" and no client hears the run. Built by [method seat_members] for a lobby's run.
var seats: SeatDirectory = null

var _next_token: int = NO_TOKEN + 1

# The run session and battle whose batches the host sends; null when there is none.
var _session: CampaignSession = null
var _encounter: CombatEncounter = null

# The API whose connection signals are connected: the one this node had when it entered the tree.
var _api: MultiplayerAPI = null

# The battle's snapshot is due on the next frame.
var _push_pending: bool = false

# Seconds each seat this machine waits for has waited, from the host's _seat_changed(); on a
# client that lost the host, the host's seat alone.
var _waits: Dictionary[int, float] = {}
var _host_lost: bool = false

# Each seat's Steam id, as seat_members() last gave them; empty when seats was set from outside.
var _players: Dictionary[int, int] = {}

var _overlay: SeatWaitOverlay = null

# Host: each client seat's settings as it last sent them this run, by seat. Never saved: settings
# belong to each player's save file, not the run.
var _settings_by_seat: Dictionary[int, Dictionary] = {}

# Client: the settings object last sent to the host; SaveService replaces it on every Apply, so a
# new one is sent. Null until the first send of a run, and again once the host is lost.
var _sent_settings: SettingsData = null


func _ready() -> void:
	CampaignService.session_started.connect(_on_campaign_service_session_started)
	CampaignService.session_ended.connect(_on_campaign_service_session_ended)
	SteamNetwork.lobby_state_changed.connect(_on_steam_network_lobby_state_changed)
	_api = multiplayer
	_api.peer_disconnected.connect(_on_multiplayer_peer_disconnected)
	_api.server_disconnected.connect(_on_multiplayer_server_disconnected)
	# A relay that joins the tree after the session was built (one under a test branch) follows it
	# from now.
	_follow(CampaignService.session)


func _exit_tree() -> void:
	_follow(null)
	CampaignService.session_started.disconnect(_on_campaign_service_session_started)
	CampaignService.session_ended.disconnect(_on_campaign_service_session_ended)
	SteamNetwork.lobby_state_changed.disconnect(_on_steam_network_lobby_state_changed)
	if is_instance_valid(_api):
		_api.peer_disconnected.disconnect(_on_multiplayer_peer_disconnected)
		_api.server_disconnected.disconnect(_on_multiplayer_server_disconnected)
	_api = null


# Pushes a battle's snapshot on the idle frame after it opened, counts every wait on, and on a
# client in a run sends its settings when they are new to the host.
func _process(delta: float) -> void:
	if _push_pending:
		_push_pending = false
		_push_battle()
	for seat: int in _waits.keys():
		_waits[seat] += delta
	if _session != null and SaveService.settings != _sent_settings and _is_client():
		_send_settings()


## Asks the host for the state [param have] describes as missing ([ClientMirror]'s request) and
## returns whether it was sent; the answer is [signal sync_received]. False, sending nothing, on
## the host and in solo.
func request_sync(have: Dictionary) -> bool:
	if not _is_client():
		push_error("NetRelay: only a client asks the host for state.")
		return false
	return _send([_HOST_PEER], &"_request_sync", [have])


## Sends [param command], for the map [param session_id], from this client to the host and
## returns its token for [signal command_settled]. Nothing changes here until batches arrive.
## [constant NO_TOKEN], sending nothing, on the host, in solo, for null, for a command with no
## wire form, or when it can't be sent (over the message limit).
func send_combat(command: Command, session_id: int) -> int:
	if command == null or not _is_client():
		push_error("NetRelay: only a client sends a combat command to the host.")
		return NO_TOKEN
	var wire: Array = command.to_wire()
	if wire.is_empty():
		return NO_TOKEN
	var token: int = _take_token()
	if not _send([_HOST_PEER], &"_submit_combat", [wire, session_id, token]):
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
	if not _send([_HOST_PEER], &"_submit_campaign", [wire, token]):
		return NO_TOKEN
	return token


## Tells every other seated peer this machine's notice of [enum NoticeKind] [param kind] with
## [param data]: a client's goes through the host, which forwards it, the host's straight to every
## client. Does nothing in solo. Refused, with an error, for data its kind doesn't allow, a
## [constant NoticeKind.ROUTE] from the host, or a host that holds no seat in [member seats].
func send_notice(kind: int, data: Array) -> void:
	if not NetGate.has_session(multiplayer):
		return
	if not _is_notice_valid(kind, data):
		push_error("NetRelay: notice %d with data %s isn't allowed." % [kind, data])
		return
	if not multiplayer.is_server():
		_send([_HOST_PEER], &"_notice", [SeatDirectory.NO_SEAT, kind, data])
		return
	if kind == NoticeKind.ROUTE:
		push_error("NetRelay: the host routes everyone itself; it sends no route notice.")
		return
	var seat: int = _seat_of(multiplayer.get_unique_id())
	if seat == SeatDirectory.NO_SEAT:
		push_error("NetRelay: the host holds no seat to send a notice for.")
		return
	_send(_seated_peers(), &"_notice", [seat, kind, data])


## Seats the run: [param steam_ids_by_seat] is each seat's Steam id (the campaign's players),
## [param peers_by_steam_id] each admitted member's peer. The first call builds [member seats]
## ([method SeatDirectory.build]); later ones bring it up to date, a seat whose member left
## dropped, one whose Steam id is back under a peer reconnected. On the host a drop pauses the run
## for everyone, and a return is the rejoin, sent a fresh snapshot. A removed seat stays removed.
func seat_members(
		steam_ids_by_seat: Dictionary[int, int], peers_by_steam_id: Dictionary[int, int]
) -> void:
	_players = steam_ids_by_seat.duplicate()
	if seats == null:
		seats = SeatDirectory.build(steam_ids_by_seat, peers_by_steam_id)
		_admit_campaign()
		for seat: int in seats.dropped_seats():
			_announce_drop(seat)
		return
	for seat: int in seats.seats():
		if seats.state_of(seat) == SeatDirectory.State.REMOVED:
			continue
		var steam_id: int = seats.steam_id_of_seat(seat)
		var peer: int = peers_by_steam_id.get(steam_id, SeatDirectory.NO_PEER)
		var held: int = seats.peer_of_seat(seat)
		if peer == held:
			continue
		if held != SeatDirectory.NO_PEER:
			seats.drop_peer(held)
			_announce_drop(seat)
		if peer > SeatDirectory.NO_PEER and seats.reconnect(steam_id, peer) == seat:
			_announce_rejoin(seat, peer)


## Host only: removes the dropped [param seat] for good once it has waited [constant REMOVE_WAIT]
## seconds, telling every peer ([signal seat_removed]); its Steam id is no longer admitted. Returns
## false, changing nothing, off the host, for a seat that isn't dropped, or before the wait.
func remove_seat(seat: int) -> bool:
	if not _is_host() or seats == null:
		push_error("NetRelay: only the host removes a seat.")
		return false
	var waited_for: float = waited(seat)
	if seats.state_of(seat) != SeatDirectory.State.DROPPED or waited_for < REMOVE_WAIT:
		return false
	seats.remove_seat(seat)
	_admit_campaign()
	_send_seat_changed(seat, SeatDirectory.State.REMOVED, waited_for)
	return true


## The settings [param seat]'s player last sent the host this run, by [SettingsData] key
## ([code]"opening_swap"[/code]: bool); a copy. Empty for a seat that sent none, the host's own
## seat (its settings are this machine's) and off the host. Kept until the run ends or the seat
## is removed, never saved.
func seat_settings(seat: int) -> Dictionary:
	var kept: Dictionary = _settings_by_seat.get(seat, {})
	return kept.duplicate()


## Whether this machine waits for a seat: a dropped one, or, on a client, the host it lost.
## Nothing resolves meanwhile; batches already sent still play.
func is_paused() -> bool:
	return not _waits.is_empty()


## The seats this machine waits for, in ascending order: the dropped ones, or the host's alone on
## a client that lost it ([method is_host_lost]).
func waiting_seats() -> PackedInt32Array:
	var waiting: PackedInt32Array = PackedInt32Array(_waits.keys())
	waiting.sort()
	return waiting


## Seconds [param seat] has been waited for, counted on this machine from the host's word; 0 when
## it isn't.
func waited(seat: int) -> float:
	return _waits.get(seat, 0.0)


## Whether this client lost the host during the run and waits to be back.
func is_host_lost() -> bool:
	return _host_lost


# A client's combat command, on the host: the sender's seat, the pause, the wire form and the map
# are checked first, then it resolves as the host's own would. The sender is told how it settled.
@rpc("any_peer", "call_remote", "reliable")
func _submit_combat(wire: Array, session_id: int, token: int) -> void:
	_log_received(&"_submit_combat", [wire, session_id, token])
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
	_log_received(&"_submit_campaign", [wire, token])
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
	_log_received(&"_command_settled", [token, reason])
	if multiplayer.is_server():
		return
	command_settled.emit(token, reason)


@rpc("authority", "call_remote", "reliable")
func _combat_batch(wire: Array) -> void:
	_log_received(&"_combat_batch", [wire])
	if multiplayer.is_server():
		return
	combat_batch_received.emit(wire)


@rpc("authority", "call_remote", "reliable")
func _encounter_batch(wire: Array) -> void:
	_log_received(&"_encounter_batch", [wire])
	if multiplayer.is_server():
		return
	encounter_batch_received.emit(wire)


# A campaign batch's facts and the run's capture, packed (_pack()); one that doesn't unpack to
# that shape is dropped, and the next batch or sync brings the run again.
@rpc("authority", "call_remote", "reliable")
func _campaign_batch(packed: PackedByteArray) -> void:
	_log_received(&"_campaign_batch", [packed])
	if multiplayer.is_server():
		return
	var args: Array = _unpack(packed)
	if not _is_campaign_batch_shape(args):
		_log_dropped(multiplayer.get_remote_sender_id(), "a campaign batch that doesn't unpack")
		return
	campaign_batch_received.emit(args[0] as Array, args[1] as Dictionary)


# A seated client's request for state, on the host: answered to it alone, the same way however
# often it asks, so a retry's duplicate is harmless. An unseated or malformed one is dropped.
@rpc("any_peer", "call_remote", "reliable")
func _request_sync(have: Dictionary) -> void:
	_log_received(&"_request_sync", [have])
	if not _is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _seat_of(sender) == SeatDirectory.NO_SEAT:
		_log_dropped(sender, "a request for state from no seat")
		return
	if not _is_have_valid(have):
		_log_dropped(sender, "a malformed request for state %s" % [have])
		return
	var battle: Dictionary = {}
	var facts: Array = []
	var screen: int = _NO_SCREEN
	if _is_battle_open():
		screen = SceneRouter.Screen.GAMEPLAY
		var caught_up: Variant = _catch_up(have)
		if caught_up == null:
			battle = _encounter.snapshot()
		else:
			facts = caught_up
	_send_sync([sender], _capture_run(), battle, facts, screen)


# The run, the battle, missed facts and the screen, packed (_pack()); one that doesn't unpack to
# that shape is dropped, and the client's request clock asks again. A client back from losing the
# host has its state here, after the seats' news: the wait is over.
@rpc("authority", "call_remote", "reliable")
func _sync(packed: PackedByteArray) -> void:
	_log_received(&"_sync", [packed])
	if multiplayer.is_server():
		return
	var args: Array = _unpack(packed)
	if not _is_sync_shape(args):
		_log_dropped(multiplayer.get_remote_sender_id(), "a sync that doesn't unpack")
		return
	if _host_lost:
		_host_lost = false
		_waits.erase(CampaignData.HOST_SEAT)
	sync_received.emit(
			args[0] as Dictionary, args[1] as Dictionary, args[2] as Array, args[3] as int
	)


# A seat's connection changed, on every peer, the host's own call included: the waits, the
# signals and, on a client, its directory's drop or removal (a return comes with the member
# list, which carries the new peer). state is a SeatDirectory.State.
@rpc("authority", "call_local", "reliable")
func _seat_changed(seat: int, state: int, waited_for: float) -> void:
	# The host calls it directly too, at times inside another peer's RPC: that is no message.
	if not multiplayer.is_server():
		_log_received(&"_seat_changed", [seat, state, waited_for])
	if seat < 0 or waited_for < 0.0 or not SeatDirectory.State.values().has(state):
		_log_dropped(
				multiplayer.get_remote_sender_id(),
				"a seat change %d to %d after %.1f s" % [seat, state, waited_for]
		)
		return
	var is_client_directory: bool = seats != null and not multiplayer.is_server()
	match state:
		SeatDirectory.State.DROPPED:
			if is_client_directory:
				seats.drop_peer(seats.peer_of_seat(seat))
			var is_new: bool = not _waits.has(seat)
			_waits[seat] = waited_for
			if is_new:
				seat_dropped.emit(seat)
		SeatDirectory.State.CONNECTED:
			if _waits.erase(seat):
				seat_rejoined.emit(seat)
		SeatDirectory.State.REMOVED:
			if is_client_directory:
				seats.drop_peer(seats.peer_of_seat(seat))
				seats.remove_seat(seat)
			_waits.erase(seat)
			_settings_by_seat.erase(seat)
			seat_removed.emit(seat)
	_show_overlay()


# A notice. Up: any client to the host, which takes the seat from the connection and forwards it
# to every other seated client, or, for a route, routes everyone itself. Down: only the host's
# forward is heard, so a client's direct call to another client is ignored.
@rpc("any_peer", "call_remote", "reliable")
func _notice(seat: int, kind: int, data: Array) -> void:
	_log_received(&"_notice", [seat, kind, data])
	var sender: int = multiplayer.get_remote_sender_id()
	if not _is_notice_valid(kind, data):
		_log_dropped(sender, "notice %d with data %s" % [kind, data])
		return
	if not multiplayer.is_server():
		if sender == _HOST_PEER and seat > SeatDirectory.NO_SEAT and kind != NoticeKind.ROUTE:
			notice_received.emit(seat, kind, data)
		return
	var from_seat: int = _seat_of(sender)
	if from_seat == SeatDirectory.NO_SEAT:
		_log_dropped(sender, "a notice from no seat")
		return
	if kind == NoticeKind.ROUTE:
		if is_paused():
			_log_dropped(sender, "a route while the run is paused")
		else:
			notice_received.emit(from_seat, kind, data)
		return
	notice_received.emit(from_seat, kind, data)
	var others: Array[int] = _seated_peers()
	others.erase(sender)
	_send(others, &"_notice", [from_seat, kind, data])


# A client's settings, on the host: kept for the seat the connection holds, replacing what it
# sent before. One from no seat, or not exactly the settings _SEAT_SETTING_KEYS names, is dropped.
@rpc("any_peer", "call_remote", "reliable")
func _seat_settings(settings: Dictionary) -> void:
	_log_received(&"_seat_settings", [settings])
	if not _is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var seat: int = _seat_of(sender)
	if seat == SeatDirectory.NO_SEAT:
		_log_dropped(sender, "settings from no seat")
		return
	if not _keep_settings(seat, settings):
		_log_dropped(sender, "malformed settings %s" % [settings])


func _is_host() -> bool:
	return NetGate.has_session(multiplayer) and multiplayer.is_server()


func _is_client() -> bool:
	return NetGate.has_session(multiplayer) and not multiplayer.is_server()


# Whether this is the relay on SteamNetwork's API in a lobby: the one that seats a real run.
func _is_lobby_relay() -> bool:
	return SteamNetwork.has_active_session() and multiplayer == SteamNetwork.multiplayer


func _is_battle_open() -> bool:
	return _encounter != null and not _encounter.is_closed


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


# The connected peers that hold a seat: the only ones the run's traffic goes to. Empty with no
# directory, so a connection the host hasn't admitted (or is refusing) hears nothing.
func _seated_peers() -> Array[int]:
	var peers: Array[int] = []
	if seats == null:
		return peers
	for peer: int in multiplayer.get_peers():
		if seats.seat_of_peer(peer) != SeatDirectory.NO_SEAT:
			peers.append(peer)
	return peers


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
	_send([sender], &"_command_settled", [token, reason])


# Keeps settings as seat's when they are exactly _SEAT_SETTING_KEYS, each a bool; returns whether
# they were kept.
func _keep_settings(seat: int, settings: Dictionary) -> bool:
	if settings.size() != _SEAT_SETTING_KEYS.size():
		return false
	for key: String in _SEAT_SETTING_KEYS:
		if not settings.get(key, null) is bool:
			return false
	_settings_by_seat[seat] = settings.duplicate()
	return true


# Client: this machine's settings to the host, the one SaveService holds now.
func _send_settings() -> void:
	_sent_settings = SaveService.settings
	var settings: Dictionary = {SettingsData.OPENING_SWAP_KEY: _sent_settings.is_opening_swap_on}
	_send([_HOST_PEER], &"_seat_settings", [settings])


func _log_dropped(sender: int, what: String) -> void:
	NetLog.warn(NetLog.Category.LOBBY, "NetRelay: dropped %s from peer %d." % [what, sender])


# Sends the RPC method with args to each of peers, one message each, and logs each; returns
# whether every one went. Measured once: over _SEND_BUDGET it goes to nobody, with an error, since
# Steam would refuse it; a batch lost so is repaired as any gap is (a client's sync request).
func _send(peers: Array[int], method: StringName, args: Array) -> bool:
	if peers.is_empty():
		return true
	var size: int = _size_of(args)
	var category: NetLogScript.Category = _category_of(method)
	if size > _SEND_BUDGET:
		NetLog.error(category, "NetRelay: %s is %d B, over the %d B a message may be; not sent." % [
			_kind_of(method), size, _SEND_BUDGET,
		])
		return false
	var is_logged: bool = NetLog.would_log(NetLog.Level.INFO, category)
	var sent: bool = true
	for peer: int in peers:
		var err: Error = callv(&"rpc_id", [peer, method] + args)
		if err != OK:
			push_error("NetRelay: %s to peer %d wasn't sent - %s" % [
				_kind_of(method), peer, error_string(err),
			])
			sent = false
		elif is_logged:
			NetLog.info(category, "NetRelay: sent %s, %d B, to peer %d." % [
				_kind_of(method), size, peer,
			])
	return sent


# _sync's arguments, packed once for every peer.
func _send_sync(
		peers: Array[int], run: Dictionary, battle: Dictionary, facts: Array, screen: int
) -> void:
	if not peers.is_empty():
		_send(peers, &"_sync", [_pack([run, battle, facts, screen])])


# A campaign batch's facts with the run's capture as it stands, packed once for every peer.
func _send_campaign_batch(peers: Array[int], facts: Array) -> void:
	if not peers.is_empty():
		_send(peers, &"_campaign_batch", [_pack([facts, _capture_run()])])


# The line for a relay message that arrived, before anything checks it; the host's own call of a
# call_local RPC has no sender and isn't a message.
func _log_received(method: StringName, args: Array) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	var category: NetLogScript.Category = _category_of(method)
	if sender == 0 or not NetLog.would_log(NetLog.Level.INFO, category):
		return
	NetLog.info(category, "NetRelay: received %s, %d B, from peer %d." % [
		_kind_of(method), _size_of(args), sender,
	])


# The open battle's snapshot to every seated client, as it stands between commands.
func _push_battle() -> void:
	if not _is_host() or not _is_battle_open():
		return
	var battle: Dictionary = _encounter.snapshot()
	if battle.is_empty():
		return
	_send_sync(_seated_peers(), _capture_run(), battle, [], SceneRouter.Screen.GAMEPLAY)


# Host: tells every seated peer, and this one, that seat's connection is now state.
func _send_seat_changed(seat: int, state: SeatDirectory.State, waited_for: float) -> void:
	_send(_seated_peers(), &"_seat_changed", [seat, state, waited_for])
	_seat_changed(seat, state, waited_for)


# Host: seat dropped, so the run pauses for everyone.
func _announce_drop(seat: int) -> void:
	if not _is_host():
		return
	NetLog.warn(NetLog.Category.LOBBY, "NetRelay: seat %d dropped; the run is paused." % [seat])
	_send_seat_changed(seat, SeatDirectory.State.DROPPED, 0.0)


# Host: seat is back as peer. Everyone hears it; the peer also hears every seat still dropped or
# removed, gets the run's replica on a lobby's run (a crashed client holds none), and a fresh
# snapshot of the run and the open battle, never a catch-up across the reconnect.
func _announce_rejoin(seat: int, peer: int) -> void:
	if not _is_host():
		return
	NetLog.info(NetLog.Category.LOBBY, "NetRelay: seat %d rejoined as peer %d." % [seat, peer])
	_send_seat_changed(seat, SeatDirectory.State.CONNECTED, waited(seat))
	for other: int in seats.seats():
		var state: int = seats.state_of(other)
		if state == SeatDirectory.State.DROPPED or state == SeatDirectory.State.REMOVED:
			_send([peer], &"_seat_changed", [other, state, waited(other)])
	if _is_lobby_relay():
		SaveService.send_run_to(peer)
	var battle: Dictionary = {}
	var screen: int = _NO_SCREEN
	if _is_battle_open():
		battle = _encounter.snapshot()
		screen = SceneRouter.Screen.GAMEPLAY
	_send_sync([peer], _capture_run(), battle, [], screen)


# Host of a lobby's run: only the run's seats that aren't removed may join, so a dropped seat's
# account gets back in and nobody else does (LobbyAdmission refuses a connected one's repeat).
func _admit_campaign() -> void:
	if not _is_lobby_relay() or not multiplayer.is_server():
		return
	var steam_ids: PackedInt64Array = []
	for seat: int in seats.seats():
		if seats.state_of(seat) != SeatDirectory.State.REMOVED:
			steam_ids.append(seats.steam_id_of_seat(seat))
	SteamNetwork.set_required_steam_ids(steam_ids)


# A lobby's run, seated from its campaign (the host's, or a client's replica of it) and the
# admitted members. Nothing elsewhere.
func _seat_lobby() -> void:
	if not _is_lobby_relay():
		return
	var campaign: CampaignData = SaveService.campaign
	if not multiplayer.is_server():
		campaign = SaveService.multiplayer_replica
	if campaign == null or campaign.mode != CampaignData.Mode.MULTIPLAYER:
		return
	var steam_ids: Dictionary[int, int] = {}
	for player: CampaignData.PlayerRun in campaign.players:
		steam_ids[player.seat] = player.steam_id.to_int()
	var peers: Dictionary[int, int] = {}
	for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
		peers[member.steam_id] = member.peer_id
	seat_members(steam_ids, peers)


# The wait overlay, made at the first wait; it shows itself while this relay waits.
func _show_overlay() -> void:
	if _overlay != null:
		return
	var scene: PackedScene = load(_OVERLAY_PATH) as PackedScene
	if scene == null:
		push_error("NetRelay: no wait overlay at %s" % [_OVERLAY_PATH])
		return
	_overlay = scene.instantiate() as SeatWaitOverlay
	if _overlay == null:
		push_error("NetRelay: %s isn't a SeatWaitOverlay" % [_OVERLAY_PATH])
		return
	add_child(_overlay)
	_overlay.follow(self)


# A run's end: no waits or settings, and the seats seat_members() built go with it.
func _end_run() -> void:
	_waits.clear()
	_host_lost = false
	_push_pending = false
	_settings_by_seat.clear()
	_sent_settings = null
	if not _players.is_empty():
		seats = null
		_players.clear()


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


# The open battle's facts a client holding have missed, a catch-up batch per map that has any;
# null when only a snapshot will do: another battle or none held, a fresh one asked for, a map
# behind its last checkpoint, or a missed spawn, whose unit no catch-up carries.
func _catch_up(have: Dictionary) -> Variant:
	var held: Array = have[_HAVE_BATTLE]
	var seqs: Array = have[_HAVE_SEQS]
	var maps: Array[CombatSession] = _encounter.get_sessions()
	if (
			have[_HAVE_FRESH]
			or held != [_encounter.floor_number, _encounter.node]
			or seqs.size() != maps.size()
	):
		return null
	var wires: Array = []
	for index: int in maps.size():
		var map: CombatSession = maps[index]
		var seq: int = seqs[index]
		if seq == map.last_seq():
			continue
		if not map.can_catch_up(seq):
			return null
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.new()
		batch.session_id = map.session_id
		batch.label = _CATCH_UP_LABEL
		batch.facts = map.facts_since(seq)
		for fact: CombatFact in batch.facts:
			if fact.kind == CombatFact.Kind.UNIT_SPAWNED:
				return null
		wires.append(batch.to_wire())
	return wires


func _on_campaign_service_session_started(started: CampaignSession) -> void:
	_follow(started)
	if started.mode == CampaignData.Mode.MULTIPLAYER:
		_seat_lobby()


func _on_campaign_service_session_ended(ended: CampaignSession) -> void:
	if ended == _session:
		_follow(null)
		_end_run()


# The admitted members changed: a lobby's run follows them (a drop, a rejoin, a client's own new
# peer after it reconnected).
func _on_steam_network_lobby_state_changed() -> void:
	if seats != null and not _players.is_empty():
		_seat_lobby()


# Host: a seated peer's connection is gone; its seat is kept, dropped.
func _on_multiplayer_peer_disconnected(peer_id: int) -> void:
	if not _is_host() or seats == null:
		return
	var seat: int = seats.drop_peer(peer_id)
	if seat != SeatDirectory.NO_SEAT:
		_announce_drop(seat)


# Client: the host is gone mid-run; this machine waits for it (SteamNetwork tries to get back)
# and sends its settings again once it is, in case the host came back without them.
func _on_multiplayer_server_disconnected() -> void:
	if seats == null:
		return
	NetLog.warn(NetLog.Category.LOBBY, "NetRelay: lost the host; waiting to be back.")
	_host_lost = true
	_sent_settings = null
	_waits.clear()
	_waits[CampaignData.HOST_SEAT] = 0.0
	_show_overlay()


func _on_session_campaign_batch_resolved(batch: CampaignBatch) -> void:
	if not _is_host():
		return
	var wire: Array = batch.to_wire()
	if not batch.is_rejected():
		_send_campaign_batch(_seated_peers(), wire)
		return
	var sender: int = _peer_of(batch.seat)
	if sender != SeatDirectory.NO_PEER:
		_send_campaign_batch([sender], wire)


# Begin and a resume are still setting the battle up here; its snapshot goes out once they are done.
func _on_session_combat_encounter_opened(encounter: CombatEncounter) -> void:
	_follow_battle(encounter)
	if _is_host():
		_push_pending = true


# The battle's end has applied to the run by now (CampaignService.end_battle()), so the run goes
# out with no facts; a battle dropped without applying sends the run as it stands, still the truth.
func _on_session_combat_encounter_closed(encounter: CombatEncounter) -> void:
	if encounter == _encounter:
		_follow_battle(null)
	if _is_host():
		_send_campaign_batch(_seated_peers(), [])


func _on_encounter_session_opened(map: CombatSession) -> void:
	if not map.batch_resolved.is_connected(_on_map_batch_resolved):
		map.batch_resolved.connect(_on_map_batch_resolved)


func _on_encounter_batch_resolved(batch: CombatSession.FactBatch) -> void:
	if not _is_host():
		return
	_send(_seated_peers(), &"_encounter_batch", [batch.to_wire()])


func _on_map_batch_resolved(batch: CombatSession.FactBatch) -> void:
	if not _is_host():
		return
	var wire: Array = batch.to_wire()
	if not batch.is_rejected():
		_send(_seated_peers(), &"_combat_batch", [wire])
		return
	var sender: int = _peer_of(batch.seat)
	if sender != SeatDirectory.NO_PEER:
		_send([sender], &"_combat_batch", [wire])


# Whether have is a sync request: exactly its three keys, a battle of two whole numbers or none,
# each map's seq a whole number of at least 0, and a flag.
static func _is_have_valid(have: Dictionary) -> bool:
	var held: Variant = have.get(_HAVE_BATTLE, null)
	var seqs: Variant = have.get(_HAVE_SEQS, null)
	if (
			have.size() != 3
			or not held is Array
			or not seqs is Array
			or not have.get(_HAVE_FRESH, null) is bool
			or not ((held as Array).is_empty() or (held as Array).size() == 2)
	):
		return false
	for number: Variant in (held as Array) + (seqs as Array):
		if not number is int or (number as int) < 0:
			return false
	return true


# Whether args are _sync's: the run, the battle, the missed facts and the screen.
static func _is_sync_shape(args: Array) -> bool:
	return (
			args.size() == 4
			and args[0] is Dictionary
			and args[1] is Dictionary
			and args[2] is Array
			and args[3] is int
	)


# Whether args are _campaign_batch's: the facts and the run.
static func _is_campaign_batch_shape(args: Array) -> bool:
	return args.size() == 2 and args[0] is Array and args[1] is Dictionary


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
		NoticeKind.ROUTE:
			return data.is_empty()
		NoticeKind.FAST_FORWARD:
			return (
					data.size() == _FAST_FORWARD_FIELDS
					and data[0] is int
					and (data[0] as int) >= 0
					and data[1] is bool
			)
	return false


# args encoded as one Variant: at least what Godot's RPC encoding of them carries, so the measure
# the send guard and the log lines use.
static func _size_of(args: Array) -> int:
	return var_to_bytes(args).size()


# A message's kind as its log line names it: the RPC method without its underscore.
static func _kind_of(method: StringName) -> String:
	return String(method).trim_prefix("_")


# Which NetLog category a relay message's lines go under: a map's traffic Combat, the run's
# Campaign, the rest (settles, syncs, seats, notices) Lobby.
static func _category_of(method: StringName) -> NetLogScript.Category:
	match method:
		&"_submit_combat", &"_combat_batch", &"_encounter_batch":
			return NetLogScript.Category.COMBAT
		&"_submit_campaign", &"_campaign_batch":
			return NetLogScript.Category.CAMPAIGN
	return NetLogScript.Category.LOBBY


# args as one packed message (see _PACK_FORMAT): the format byte, the encoded size, its MD5, then
# the encoded args compressed.
static func _pack(args: Array) -> PackedByteArray:
	var raw: PackedByteArray = var_to_bytes(args)
	var packed: PackedByteArray = PackedByteArray()
	packed.resize(_PACK_DIGEST_AT)
	packed.encode_u8(0, _PACK_FORMAT)
	packed.encode_u32(_PACK_SIZE_AT, raw.size())
	packed.append_array(_md5(raw))
	packed.append_array(raw.compress(_PACK_MODE))
	return packed


# The args _pack() packed; empty when packed is another format, says a size over _UNPACK_LIMIT,
# doesn't decompress to that size, fails its MD5 or isn't an Array. Never decodes objects.
static func _unpack(packed: PackedByteArray) -> Array:
	var refused: Array = []
	if packed.size() <= _PACK_HEADER or packed.decode_u8(0) != _PACK_FORMAT:
		return refused
	var raw_size: int = packed.decode_u32(_PACK_SIZE_AT)
	if raw_size <= 0 or raw_size > _UNPACK_LIMIT:
		return refused
	var raw: PackedByteArray = packed.slice(_PACK_HEADER).decompress(raw_size, _PACK_MODE)
	if raw.size() != raw_size or _md5(raw) != packed.slice(_PACK_DIGEST_AT, _PACK_HEADER):
		return refused
	var args: Variant = bytes_to_var(raw)
	if not args is Array:
		return refused
	return args as Array


static func _md5(bytes: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(bytes)
	return context.finish()
