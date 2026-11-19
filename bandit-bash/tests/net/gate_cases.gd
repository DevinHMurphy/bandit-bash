# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     gate_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Authority gate cases for tests/net/run_all.gd ([NetGate]): no API, no peer and the offline
## peer are solo (no session, authoritative); a fake host peer is a session with authority, a fake
## client peer, connected or still connecting, one without; two APIs in one process answer each
## for itself; SteamNetwork's helpers agree outside a lobby; and BUG-016's regression.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

# A client's Godot peer id; real ones are large and random.
const CLIENT_PEER: int = 1384211520


func run() -> void:
	_test_no_session()
	_test_session()
	_test_two_apis()
	_test_steam_network_solo()
	_test_local_peer_after_leaving()


func _test_no_session() -> void:
	var api: SceneMultiplayer = SceneMultiplayer.new()
	var is_offline: bool = api.multiplayer_peer is OfflineMultiplayerPeer
	var offline_ok: bool = not NetGate.has_session(api) and NetGate.is_authoritative(api)
	api.multiplayer_peer = null
	var cleared_ok: bool = not NetGate.has_session(api) and NetGate.is_authoritative(api)
	_check("gate: no API, no peer or the offline peer is solo: no session, authoritative", (
			not NetGate.has_session(null)
			and NetGate.is_authoritative(null)
			and is_offline
			and offline_ok
			and cleared_ok
	), "offline %s, solo with offline %s, solo with none %s" % [
		is_offline, offline_ok, cleared_ok,
	])


func _test_session() -> void:
	var host: SceneMultiplayer = _api(MultiplayerPeer.TARGET_PEER_SERVER)
	var client: SceneMultiplayer = _api(CLIENT_PEER)
	var connecting: SceneMultiplayer = _api(
			CLIENT_PEER, MultiplayerPeer.CONNECTION_CONNECTING
	)
	_check("gate: a host peer is a session with authority", (
			NetGate.has_session(host) and NetGate.is_authoritative(host)
	))
	_check("gate: a client peer, connected or connecting, is a session without authority", (
			NetGate.has_session(client)
			and not NetGate.is_authoritative(client)
			and NetGate.has_session(connecting)
			and not NetGate.is_authoritative(connecting)
	))


func _test_two_apis() -> void:
	var host: SceneMultiplayer = _api(MultiplayerPeer.TARGET_PEER_SERVER)
	var client: SceneMultiplayer = _api(CLIENT_PEER)
	var host_first: bool = NetGate.is_authoritative(host)
	var client_then: bool = NetGate.is_authoritative(client)
	_check("gate: two APIs in one process each answer for themselves", (
			host_first
			and not client_then
			and NetGate.is_authoritative(host)
			and not NetGate.is_authoritative(client)
	))


func _test_steam_network_solo() -> void:
	var steam: Node = _root.get_node(^"SteamNetwork")
	_check("gate: outside a lobby SteamNetwork is solo, as NetGate is", (
			not (steam.call(&"has_active_session") as bool)
			and (steam.call(&"is_authoritative") as bool)
			and NetGate.is_authoritative(_root.multiplayer)
	))


# BUG-016: SteamNetwork.leave_lobby() clears the multiplayer peer, as SceneRouter does on the
# menus; local_peer_id() after it answers 1, as in solo play, with no engine error. The peer from
# before is put back.
func _test_local_peer_after_leaving() -> void:
	var api: MultiplayerAPI = _root.multiplayer
	var peer_before: MultiplayerPeer = api.multiplayer_peer
	var steam: Node = _root.get_node(^"SteamNetwork")
	steam.call(&"leave_lobby")
	var is_cleared: bool = api.multiplayer_peer == null
	var catcher: ErrorCatcher = ErrorCatcher.new()
	OS.add_logger(catcher)
	var peer_id: int = steam.call(&"local_peer_id")
	OS.remove_logger(catcher)
	api.multiplayer_peer = peer_before
	var errors: PackedStringArray = catcher.get_errors()
	_check("gate: BUG-016 local_peer_id() with no peer is 1 and raises no engine error", (
			is_cleared
			and peer_id == MultiplayerPeer.TARGET_PEER_SERVER
			and errors.is_empty()
	), "peer cleared %s, id %d, errors %s" % [is_cleared, peer_id, errors])


# A SceneMultiplayer outside the tree with a fake peer of unique id peer_id in status.
func _api(
		peer_id: int,
		status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_CONNECTED,
) -> SceneMultiplayer:
	var api: SceneMultiplayer = SceneMultiplayer.new()
	api.multiplayer_peer = FakePeer.new(peer_id, status)
	return api


# A peer that sends and receives nothing: it only reports an id and a connection status, which
# is all NetGate reads. The two-peer harness's loopback peers carry real traffic.
class FakePeer:
	extends MultiplayerPeerExtension

	var _unique_id: int = 0
	var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_CONNECTED
	var _target: int = 0
	var _channel: int = 0
	var _mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var _is_refusing: bool = false

	func _init(unique_id: int, status: MultiplayerPeer.ConnectionStatus) -> void:
		_unique_id = unique_id
		_status = status

	func _get_unique_id() -> int:
		return _unique_id

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return _status

	func _is_server() -> bool:
		return _unique_id == MultiplayerPeer.TARGET_PEER_SERVER

	func _is_server_relay_supported() -> bool:
		return false

	func _poll() -> void:
		pass

	func _close() -> void:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED

	func _disconnect_peer(_peer: int, _force: bool) -> void:
		pass

	func _get_available_packet_count() -> int:
		return 0

	func _get_max_packet_size() -> int:
		return 0

	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()

	func _put_packet_script(_buffer: PackedByteArray) -> Error:
		return OK

	func _get_packet_channel() -> int:
		return 0

	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _get_packet_peer() -> int:
		return MultiplayerPeer.TARGET_PEER_SERVER

	func _set_target_peer(peer: int) -> void:
		_target = peer

	func _set_transfer_channel(channel: int) -> void:
		_channel = channel

	func _get_transfer_channel() -> int:
		return _channel

	func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
		_mode = mode

	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return _mode

	func _set_refuse_new_connections(enable: bool) -> void:
		_is_refusing = enable

	func _is_refusing_new_connections() -> bool:
		return _is_refusing
