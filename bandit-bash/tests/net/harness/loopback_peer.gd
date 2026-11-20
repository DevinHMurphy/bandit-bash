# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loopback_peer.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends MultiplayerPeerExtension
## One end of a [code]loopback_network.gd[/code]: a peer with no socket, so a host and its clients
## run in one process. The network decides when packets arrive and when peers join or leave; this
## end queues what it sends, hands out what arrived in arrival order, and emits
## [signal MultiplayerPeer.peer_connected] and [signal MultiplayerPeer.peer_disconnected] in its
## poll, as ENet's peer does.[br]
## A client reaches only the host (peer 1), which relays the rest through [SceneMultiplayer]'s
## server relay, as an ENet client does. The methods below the virtuals are the network's; cases
## never call them.

# What ENetMultiplayerPeer answers; the loopback sets no smaller limit (Steam's is measured later).
const MAX_PACKET_SIZE: int = 1 << 24

var _unique_id: int = 0
var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_CONNECTING
var _target_peer: int = 0
var _transfer_channel: int = 0
var _transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _is_refusing: bool = false
# The peers this end has announced as connected, as SceneMultiplayer knows them.
var _linked: Dictionary[int, bool] = {}
var _inbox: Array[Packet] = []
var _outbox: Array[Packet] = []
var _events: Array[LinkEvent] = []
# Set by a lost link: after its events are emitted, the next poll ends the session.
var _is_losing: bool = false
# Set by close(), so the network tells the other ends at its next step.
var _has_closed: bool = false
var _kicks: PackedInt32Array = []


## A peer with id [param unique_id]: connected from the start for the host, connecting for a
## client until the network admits it.
func _init(unique_id: int) -> void:
	_unique_id = unique_id
	if _is_server():
		_status = MultiplayerPeer.CONNECTION_CONNECTED


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _is_server() -> bool:
	return _unique_id == MultiplayerPeer.TARGET_PEER_SERVER


func _is_server_relay_supported() -> bool:
	return true


func _poll() -> void:
	var events: Array[LinkEvent] = _events.duplicate()
	_events.clear()
	for event: LinkEvent in events:
		if event.is_join:
			_linked[event.peer_id] = true
			peer_connected.emit(event.peer_id)
		elif _linked.erase(event.peer_id):
			peer_disconnected.emit(event.peer_id)
	if _is_losing:
		_is_losing = false
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _close() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_has_closed = true
	_clear_traffic()
	_linked.clear()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _linked.has(peer):
		_kicks.append(peer)


func _get_available_packet_count() -> int:
	return _inbox.size()


func _get_max_packet_size() -> int:
	return MAX_PACKET_SIZE


# The packet getters answer for the front packet; this pops it, after SceneMultiplayer has read
# them.
func _get_packet_script() -> PackedByteArray:
	if _inbox.is_empty():
		return PackedByteArray()
	var packet: Packet = _inbox.pop_front()
	return packet.bytes


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var receivers: PackedInt32Array = _receivers()
	if receivers.is_empty():
		return ERR_INVALID_PARAMETER
	for receiver: int in receivers:
		_outbox.append(Packet.new(
				_unique_id, receiver, _transfer_channel, _transfer_mode, buffer
		))
	return OK


func _get_packet_channel() -> int:
	return 0 if _inbox.is_empty() else _inbox[0].channel


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	if _inbox.is_empty():
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return _inbox[0].mode


func _get_packet_peer() -> int:
	return 0 if _inbox.is_empty() else _inbox[0].from_id


func _set_target_peer(peer: int) -> void:
	_target_peer = peer


func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode


func _set_refuse_new_connections(enable: bool) -> void:
	_is_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _is_refusing


## The network: every packet sent since the last call, in send order.
func take_outbox() -> Array[Packet]:
	var sent: Array[Packet] = _outbox.duplicate()
	_outbox.clear()
	return sent


## The network: hands [param packet] to this end; it is read at the next poll.
func deliver(packet: Packet) -> void:
	if _status == MultiplayerPeer.CONNECTION_CONNECTED:
		_inbox.append(packet)


## The network: [param peer_id] joined ([param is_join]) or left, announced at the next poll.
func queue_link(peer_id: int, is_join: bool) -> void:
	_events.append(LinkEvent.new(peer_id, is_join))


## The network: a joining client is admitted, connected from now on.
func admit() -> void:
	if _status == MultiplayerPeer.CONNECTION_CONNECTING:
		_status = MultiplayerPeer.CONNECTION_CONNECTED


## The network: this end's link is gone. A connecting client fails now; a connected one announces
## every peer leaving and ends its session at its next poll, so SceneMultiplayer hears both.
func lose_link() -> void:
	_clear_traffic()
	if _status == MultiplayerPeer.CONNECTION_CONNECTING:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	for peer_id: int in _linked:
		queue_link(peer_id, false)
	_is_losing = not _is_server()


## The network: true once after this end closed itself.
func take_closed() -> bool:
	var closed: bool = _has_closed
	_has_closed = false
	return closed


## The network: the peers this host asked to disconnect since the last call.
func take_kicks() -> PackedInt32Array:
	var kicks: PackedInt32Array = _kicks.duplicate()
	_kicks.clear()
	return kicks


## True while anything waits on this end: unsent or unread packets, or unannounced links.
func has_pending() -> bool:
	return not (_outbox.is_empty() and _inbox.is_empty() and _events.is_empty()) or _is_losing


# The peers a packet goes to: a client reaches only the host; a host reaches one linked peer, all
# of them (0), or all but one (-id).
# A star with the host relaying, as ENet's; the Steam peer's shape is checked live.
func _receivers() -> PackedInt32Array:
	var receivers: PackedInt32Array = []
	if not _is_server():
		if _linked.has(MultiplayerPeer.TARGET_PEER_SERVER) and _target_peer != -1:
			receivers.append(MultiplayerPeer.TARGET_PEER_SERVER)
		return receivers
	if _target_peer > 0:
		if _linked.has(_target_peer):
			receivers.append(_target_peer)
		return receivers
	for peer_id: int in _linked:
		if peer_id != -_target_peer:
			receivers.append(peer_id)
	return receivers


func _clear_traffic() -> void:
	_inbox.clear()
	_outbox.clear()
	_events.clear()
	_is_losing = false


# One packet between two ends. due_step and order are the network's: when it arrives, and its
# place among packets due on the same step.
class Packet:
	extends RefCounted

	var from_id: int = 0
	var to_id: int = 0
	var channel: int = 0
	var mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var bytes: PackedByteArray = []
	var due_step: int = 0
	var order: int = 0

	func _init(
			sender: int,
			receiver: int,
			on_channel: int,
			transfer_mode: MultiplayerPeer.TransferMode,
			data: PackedByteArray,
	) -> void:
		from_id = sender
		to_id = receiver
		channel = on_channel
		mode = transfer_mode
		bytes = data


# A peer joining or leaving, waiting for this end's next poll.
class LinkEvent:
	extends RefCounted

	var peer_id: int = 0
	var is_join: bool = false

	func _init(peer: int, joined: bool) -> void:
		peer_id = peer
		is_join = joined
