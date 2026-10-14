# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     steam_network.gd
# Author:
# Created:  October 9, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Node
## Steam lobby host and join, and the bridge from a Steam lobby to Godot's MultiplayerAPI.
##
## Registered as autoload [code]SteamNetwork[/code], after [code]SteamManager[/code]. Once
## [code]multiplayer.multiplayer_peer[/code] is a [code]SteamMultiplayerPeer[/code], every
## [code]@rpc[/code] in the project behaves as it would over ENet; nothing else needs to know
## Steam is underneath.[br]
## [b]Session helpers:[/b] gameplay code asks [method has_active_session],
## [method is_authoritative] and [method local_peer_id] here, so solo play (no lobby) and hosting
## share one code path.[br]
## [b]No separate "am I host" flag:[/b] [code]@rpc("authority")[/code] checks
## [code]multiplayer.is_server()[/code], and a parallel flag can disagree with it.[br]
## [b]Admission:[/b] a client that connects asks to be admitted with its game version; the host
## checks it with [LobbyAdmission], using the Steam id of the connection, and refuses with a
## reason the client shows. Only admitted machines are lobby members with a Ready flag. The member
## list is built on the host and broadcast (kit P15); clients never build it.[br]
## [b]Invites:[/b] an accepted Steam invite, while running or at launch, is held in
## [member pending_invite_lobby_id] and announced with [signal invite_received];
## [code]SceneRouter[/code] decides when to act on it.
##
## @tutorial(Save system design): docs/design/save-system.md

## Steam confirmed or refused the lobby this machine asked to create.
## [param success]: false on any Steam-side failure; details are logged.
signal lobby_created(success: bool)

## Steam answered this machine's request to join someone else's lobby.
## [param success]: false if Steam refused the join; details are logged.
signal lobby_joined(success: bool)

## The Steam-side member list changed (join, leave, disconnect).
##
## Fires before the MultiplayerAPI peer is RPC-ready; use [signal peer_connected] for gameplay.
signal lobby_members_changed()

## A MultiplayerAPI peer is connected and RPC-ready. [param peer_id]: Godot peer id.
signal peer_connected(peer_id: int)

## A MultiplayerAPI peer left. [param peer_id]: Godot peer id.
signal peer_disconnected(peer_id: int)

## This machine lost its connection to the host and the session has already been torn down.
signal session_ended()

## This machine left its lobby, by choice or because the session ended. Fires once per lobby.
signal lobby_left()

## The admitted members or their Ready flags changed. Built on the host, broadcast to clients.
signal lobby_state_changed()

## The host refused this machine's join; the lobby was already left.
## [param refusal]: a [enum LobbyAdmission.Refusal] value, or an unknown int from a newer host.
signal join_refused(refusal: int)

## A Steam invite or "Join Game" was accepted for [param lobby_id], while running or at launch.
signal invite_received(lobby_id: int)

## Steam delivered lobby data (such as the game version) for [param lobby_id].
signal lobby_data_updated(lobby_id: int)

## Steam lobby visibility. Friends-only suits "play with friends"; a public lobby plus lobby data
## and search is needed for matchmaking.
const LOBBY_TYPE: int = Steam.LOBBY_TYPE_FRIENDS_ONLY

## SteamMultiplayerPeer virtual port. Host and client must use the same value.
const VIRTUAL_PORT: int = 0

## Lobby capacity used when [method host_lobby] is given no value.
const DEFAULT_MAX_PLAYERS: int = 4

## Lobby data key holding the host's game version, readable before joining.
const LOBBY_DATA_VERSION_KEY: String = "game_version"

## Launch argument Steam passes when an invite is accepted while the game isn't running.
const LAUNCH_INVITE_ARG: String = "+connect_lobby"

# How long the host waits after telling a refused client why before cutting the connection, so the
# reason arrives first. The client also leaves by itself on receiving it.
# ASSUMPTION: no basis for this value; long enough for one reliable message on a normal link.
const _REFUSAL_DISCONNECT_SECONDS: float = 1.0

## Steam lobby id this machine is in, or 0 when not in a lobby.
##
## Identical on every member, so it also serves as the lobby code players type to join.
var current_lobby_id: int = 0

## Lobby id of an accepted invite not yet acted on, or 0. Read with [method take_pending_invite].
var pending_invite_lobby_id: int = 0

## The reason of the last refusal this machine received, or -1.
var last_join_refusal: int = -1

var _peer: MultiplayerPeer = null

# Admitted members, in admission order (the host first), as parallel arrays so the whole list goes
# out in one RPC. Built on the host; a copy on clients.
var _member_peer_ids: PackedInt64Array = []
var _member_steam_ids: PackedInt64Array = []
var _member_ready: PackedByteArray = []

# Host only: Steam ids allowed in when resuming a campaign. Empty admits anyone.
var _required_steam_ids: PackedInt64Array = []


func _ready() -> void:
	Steam.lobby_created.connect(_on_steam_lobby_created)
	Steam.lobby_joined.connect(_on_steam_lobby_joined)
	Steam.lobby_chat_update.connect(_on_steam_lobby_chat_update)
	Steam.join_requested.connect(_on_steam_join_requested)
	Steam.lobby_data_update.connect(_on_steam_lobby_data_update)

	multiplayer.peer_connected.connect(_on_multiplayer_peer_connected)
	multiplayer.peer_disconnected.connect(_on_multiplayer_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_multiplayer_connected_to_server)
	multiplayer.connection_failed.connect(_on_multiplayer_connection_failed)
	multiplayer.server_disconnected.connect(_on_multiplayer_server_disconnected)


## True only with a real lobby and an attached peer.
##
## Guard every [code].rpc()[/code] and every [code]multiplayer.multiplayer_peer[/code] touch
## behind this.
func has_active_session() -> bool:
	return current_lobby_id != 0 and multiplayer.multiplayer_peer != null


## True on the host, and always true in solo play.
##
## The single gate for "may this machine decide shared state?": spawning, validation, scoring and
## round flow.
func is_authoritative() -> bool:
	return not has_active_session() or multiplayer.is_server()


## This machine's Godot peer id: 1 on the host and in solo play, a large random int on clients.
func local_peer_id() -> int:
	return multiplayer.get_unique_id()


## Creates a Steam lobby; [signal lobby_created] reports the result.
##
## Ignored with a warning when Steam is unavailable or this machine is already in a lobby.
## [param max_players]: lobby capacity, host included.
func host_lobby(max_players: int = DEFAULT_MAX_PLAYERS) -> void:
	if not SteamManager.is_available:
		NetLog.warn(NetLog.Category.LOBBY, "Cannot host, Steam is not available.")
		return
	if current_lobby_id != 0:
		NetLog.warn(
				NetLog.Category.LOBBY, "Cannot host, already in lobby %d." % [current_lobby_id]
		)
		return

	NetLog.info(NetLog.Category.LOBBY, "Creating a lobby (max %d players)..." % [max_players])
	Steam.createLobby(LOBBY_TYPE, max_players)


## Joins the lobby with Steam id [param lobby_id]; [signal lobby_joined] reports the result.
##
## Ignored with a warning when Steam is unavailable or this machine is already in a lobby.
func join_lobby(lobby_id: int) -> void:
	if not SteamManager.is_available:
		NetLog.warn(NetLog.Category.LOBBY, "Cannot join, Steam is not available.")
		return
	if current_lobby_id != 0:
		NetLog.warn(
				NetLog.Category.LOBBY, "Cannot join, already in lobby %d." % [current_lobby_id]
		)
		return

	last_join_refusal = -1
	NetLog.info(NetLog.Category.LOBBY, "Joining lobby %d..." % [lobby_id])
	Steam.joinLobby(lobby_id)


## Leaves the lobby and drops the peer. Safe whether hosting, joined or not in a lobby.
func leave_lobby() -> void:
	var was_in_lobby: bool = current_lobby_id != 0
	if was_in_lobby:
		NetLog.info(NetLog.Category.LOBBY, "Leaving lobby %d." % [current_lobby_id])
		Steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0
	_peer = null
	multiplayer.multiplayer_peer = null
	_clear_members()
	_required_steam_ids = PackedInt64Array()
	if was_in_lobby:
		lobby_left.emit()


## Steam ids of every lobby member, this machine included, in Steam's order.
##
## Empty when not in a lobby. Steam ids are not Godot peer ids. Includes machines the host hasn't
## admitted yet; use [method get_members] for the admitted list.
func get_lobby_members() -> Array[int]:
	var members: Array[int] = []
	if current_lobby_id == 0:
		return members

	var count: int = Steam.getNumLobbyMembers(current_lobby_id)
	for i: int in count:
		members.append(Steam.getLobbyMemberByIndex(current_lobby_id, i))
	return members


## Steam id of the current lobby's host, or 0 when not in a lobby.
func get_lobby_owner() -> int:
	if current_lobby_id == 0:
		return 0
	return Steam.getLobbyOwner(current_lobby_id)


## Display name for [param steam_id].
##
## Remote names come from Steam's cache and may lag a join briefly.
func get_member_name(steam_id: int) -> String:
	if steam_id == Steam.getSteamID():
		return Steam.getPersonaName()
	return Steam.getFriendPersonaName(steam_id)


## Steam id of the machine behind Godot peer [param peer_id], or 0 when unknown.
##
## Comes from the Steam connection, so a client can't fake it. This machine's own id is answered
## directly.
func get_peer_steam_id(peer_id: int) -> int:
	if not SteamManager.is_available:
		return 0
	if peer_id == local_peer_id():
		return Steam.getSteamID()
	var steam_peer: SteamMultiplayerPeer = _peer as SteamMultiplayerPeer
	if steam_peer == null:
		return 0
	return steam_peer.get_steam_id_for_peer_id(peer_id)


## Admitted lobby members in admission order, the host first. Empty outside a session.
func get_members() -> Array[LobbyMember]:
	var members: Array[LobbyMember] = []
	for i: int in _member_peer_ids.size():
		var member: LobbyMember = LobbyMember.new()
		member.peer_id = _member_peer_ids[i]
		member.steam_id = _member_steam_ids[i]
		member.is_ready = _member_ready[i] == 1
		members.append(member)
	return members


## True when there is at least one admitted member and every one is Ready.
func are_all_members_ready() -> bool:
	if _member_ready.is_empty():
		return false
	return not _member_ready.has(0)


## Sets this machine's Ready flag. The host applies it directly; a client asks the host, and the
## change shows once the host broadcasts it.
func set_local_ready(is_ready: bool) -> void:
	if not has_active_session():
		return
	if multiplayer.is_server():
		_set_member_ready(local_peer_id(), is_ready)
	else:
		_request_ready.rpc_id(1, is_ready)


## Host only: limits admission to [param steam_ids] (resuming a campaign). Empty admits anyone.
func set_required_steam_ids(steam_ids: PackedInt64Array) -> void:
	_required_steam_ids = steam_ids.duplicate()


## Opens the Steam overlay's invite dialog for the current lobby. Needs Steam and a lobby.
func invite_friends() -> void:
	if not SteamManager.is_available or current_lobby_id == 0:
		NetLog.warn(NetLog.Category.LOBBY, "Cannot invite, no lobby.")
		return
	Steam.activateGameOverlayInviteDialog(current_lobby_id)


## Returns the pending invite's lobby id and forgets it, or 0 when there is none.
func take_pending_invite() -> int:
	var lobby_id: int = pending_invite_lobby_id
	pending_invite_lobby_id = 0
	return lobby_id


## Checks the launch arguments for an invite accepted while the game wasn't running
## ([constant LAUNCH_INVITE_ARG]) and announces it. [code]boot.gd[/code] calls this once.
func check_launch_invite() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	var index: int = args.find(LAUNCH_INVITE_ARG)
	if index == -1 or index + 1 >= args.size():
		return
	var lobby_text: String = args[index + 1]
	if not lobby_text.is_valid_int() or lobby_text.to_int() <= 0:
		NetLog.warn(NetLog.Category.LOBBY, "Ignoring launch invite '%s'." % [lobby_text])
		return
	_receive_invite(lobby_text.to_int())


## The game version a lobby advertises, or "" when Steam hasn't delivered its data yet (see
## [method request_lobby_data]).
func get_lobby_version(lobby_id: int) -> String:
	if not SteamManager.is_available or lobby_id == 0:
		return ""
	return Steam.getLobbyData(lobby_id, LOBBY_DATA_VERSION_KEY)


## Asks Steam for a lobby's data without joining; [signal lobby_data_updated] reports arrival.
func request_lobby_data(lobby_id: int) -> void:
	if SteamManager.is_available and lobby_id != 0:
		Steam.requestLobbyData(lobby_id)


## Friends currently in a Bandit Bash lobby, for the lobby screen's list. Empty without Steam.
##
## Lobbies are friends-only, which Steam's lobby search doesn't return, so this walks the friends
## list instead.
func get_friend_lobbies() -> Array[FriendLobby]:
	var lobbies: Array[FriendLobby] = []
	if not SteamManager.is_available:
		return lobbies

	var app_id: int = Steam.getAppID()
	var count: int = Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE)
	for i: int in count:
		var friend_id: int = Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
		var game: Dictionary = Steam.getFriendGamePlayed(friend_id)
		# ASSUMPTION: GodotSteam reports the app as "id" and the lobby as "lobby"; unverified live.
		var lobby_id: int = int(game.get("lobby", 0))
		if int(game.get("id", 0)) != app_id or lobby_id == 0:
			continue
		var entry: FriendLobby = FriendLobby.new()
		entry.friend_steam_id = friend_id
		entry.friend_name = Steam.getFriendPersonaName(friend_id)
		entry.lobby_id = lobby_id
		lobbies.append(entry)
	return lobbies


func _receive_invite(lobby_id: int) -> void:
	pending_invite_lobby_id = lobby_id
	NetLog.info(NetLog.Category.LOBBY, "Invite accepted for lobby %d." % [lobby_id])
	invite_received.emit(lobby_id)


func _clear_members() -> void:
	_member_peer_ids = PackedInt64Array()
	_member_steam_ids = PackedInt64Array()
	_member_ready = PackedByteArray()
	lobby_state_changed.emit()


func _set_member_ready(peer_id: int, is_ready: bool) -> void:
	var index: int = _member_peer_ids.find(peer_id)
	if index == -1:
		return
	_member_ready[index] = 1 if is_ready else 0
	_broadcast_members()


# Host only. Sends the whole admitted list; clients replace theirs (kit P15).
func _broadcast_members() -> void:
	if has_active_session():
		_sync_members.rpc(_member_peer_ids, _member_steam_ids, _member_ready)
	else:
		lobby_state_changed.emit()


func _refuse(peer_id: int, refusal: int) -> void:
	NetLog.info(
			NetLog.Category.LOBBY,
			"Refusing peer %d: %s" % [peer_id, LobbyAdmission.Refusal.find_key(refusal)]
	)
	_join_refused.rpc_id(peer_id, refusal)
	get_tree().create_timer(_REFUSAL_DISCONNECT_SECONDS).timeout.connect(
			_disconnect_refused_peer.bind(peer_id)
	)


func _disconnect_refused_peer(peer_id: int) -> void:
	if not has_active_session() or not multiplayer.get_peers().has(peer_id):
		return
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)


# A client asks to be admitted. Every argument is untrusted.
@rpc("any_peer", "reliable", "call_remote")
func _request_admission(game_version: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _member_peer_ids.has(sender):
		return

	var steam_id: int = get_peer_steam_id(sender)
	var decision: int = LobbyAdmission.decide(
			SaveFile.get_running_version(),
			game_version,
			steam_id,
			_required_steam_ids,
			_member_steam_ids
	)
	if decision != LobbyAdmission.ADMIT:
		_refuse(sender, decision)
		return

	_member_peer_ids.append(sender)
	_member_steam_ids.append(steam_id)
	_member_ready.append(0)
	NetLog.info(NetLog.Category.LOBBY, "Admitted peer %d (Steam %d)." % [sender, steam_id])
	_broadcast_members()


@rpc("any_peer", "reliable", "call_remote")
func _request_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	_set_member_ready(multiplayer.get_remote_sender_id(), is_ready)


@rpc("authority", "reliable", "call_local")
func _sync_members(
		peer_ids: PackedInt64Array, steam_ids: PackedInt64Array, ready_flags: PackedByteArray
) -> void:
	if peer_ids.size() != steam_ids.size() or peer_ids.size() != ready_flags.size():
		NetLog.warn(NetLog.Category.LOBBY, "Ignoring a malformed member list.")
		return
	_member_peer_ids = peer_ids
	_member_steam_ids = steam_ids
	_member_ready = ready_flags
	lobby_state_changed.emit()


@rpc("authority", "reliable", "call_remote")
func _join_refused(refusal: int) -> void:
	last_join_refusal = refusal
	NetLog.warn(NetLog.Category.LOBBY, "The host refused the join (%d)." % [refusal])
	leave_lobby()
	join_refused.emit(refusal)


func _on_steam_lobby_created(connect_result: int, lobby_id: int) -> void:
	if connect_result != Steam.RESULT_OK:
		NetLog.warn(
				NetLog.Category.LOBBY, "Lobby creation failed (result %d)." % [connect_result]
		)
		lobby_created.emit(false)
		return

	current_lobby_id = lobby_id
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	peer.create_host(VIRTUAL_PORT)
	_peer = peer
	multiplayer.multiplayer_peer = _peer
	Steam.setLobbyData(lobby_id, LOBBY_DATA_VERSION_KEY, SaveFile.get_running_version())

	_member_peer_ids = PackedInt64Array([local_peer_id()])
	_member_steam_ids = PackedInt64Array([Steam.getSteamID()])
	_member_ready = PackedByteArray([0])

	NetLog.info(
			NetLog.Category.LOBBY,
			"Hosting lobby %d, unique_id=%d is_server=%s"
			% [lobby_id, multiplayer.get_unique_id(), multiplayer.is_server()]
	)
	lobby_created.emit(true)
	lobby_members_changed.emit()
	lobby_state_changed.emit()


# Steam fires this for every lobby entry, including the creator's own automatic entry right after
# lobby_created. The owner check is load-bearing: without it the host replaces its own server peer
# with a client peer pointed at itself and loses authority.
func _on_steam_lobby_joined(
		lobby_id: int, _permissions: int, _locked: bool, response: int
) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		NetLog.warn(
				NetLog.Category.LOBBY,
				"Joining lobby %d failed (response %d)." % [lobby_id, response]
		)
		lobby_joined.emit(false)
		return

	var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
	if host_steam_id == Steam.getSteamID():
		return

	current_lobby_id = lobby_id
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	peer.create_client(host_steam_id, VIRTUAL_PORT)
	_peer = peer
	multiplayer.multiplayer_peer = _peer

	NetLog.info(
			NetLog.Category.LOBBY,
			"Joined lobby %d (host %d), unique_id=%d is_server=%s"
			% [lobby_id, host_steam_id, multiplayer.get_unique_id(), multiplayer.is_server()]
	)
	lobby_joined.emit(true)
	lobby_members_changed.emit()


func _on_steam_lobby_chat_update(
		_lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int
) -> void:
	lobby_members_changed.emit()


func _on_steam_join_requested(lobby_id: int, _friend_steam_id: int) -> void:
	_receive_invite(lobby_id)


func _on_steam_lobby_data_update(_success: int, lobby_id: int, _member_id: int) -> void:
	lobby_data_updated.emit(lobby_id)


func _on_multiplayer_peer_connected(peer_id: int) -> void:
	NetLog.info(
			NetLog.Category.LOBBY,
			"Peer %d connected (my unique_id=%d, is_server=%s)"
			% [peer_id, multiplayer.get_unique_id(), multiplayer.is_server()]
	)
	peer_connected.emit(peer_id)


func _on_multiplayer_peer_disconnected(peer_id: int) -> void:
	NetLog.info(NetLog.Category.LOBBY, "Peer %d disconnected." % [peer_id])
	if multiplayer.is_server():
		var index: int = _member_peer_ids.find(peer_id)
		if index != -1:
			_member_peer_ids.remove_at(index)
			_member_steam_ids.remove_at(index)
			_member_ready.remove_at(index)
			_broadcast_members()
	peer_disconnected.emit(peer_id)


# The connection is up but this machine isn't a member until the host admits it. Autoloads exist
# at the same path on every peer from boot, so this can't race a scene load (no retry needed).
func _on_multiplayer_connected_to_server() -> void:
	NetLog.info(
			NetLog.Category.LOBBY,
			"Connected to host (my unique_id=%d)." % [multiplayer.get_unique_id()]
	)
	_request_admission.rpc_id(1, SaveFile.get_running_version())


func _on_multiplayer_connection_failed() -> void:
	NetLog.error(NetLog.Category.LOBBY, "Connection to host failed.")


func _on_multiplayer_server_disconnected() -> void:
	NetLog.warn(NetLog.Category.LOBBY, "Disconnected from host.")
	leave_lobby()
	session_ended.emit()


## One admitted lobby member.
class LobbyMember:
	extends RefCounted

	## Godot peer id; 1 is the host.
	var peer_id: int = 0
	## Steam id, from the host's view of the connection.
	var steam_id: int = 0
	## The member pressed Ready.
	var is_ready: bool = false


## A friend currently in a Bandit Bash lobby.
class FriendLobby:
	extends RefCounted

	## The friend's Steam id.
	var friend_steam_id: int = 0
	## The friend's display name.
	var friend_name: String = ""
	## The lobby to join.
	var lobby_id: int = 0
