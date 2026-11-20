# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loopback_network.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## An in-process network joining one host and its clients, each a [code]loopback_peer.gd[/code].
## Time is a step count, never the clock: [method step] admits joining clients, moves every packet
## sent since the last step onto its link and hands each receiver the ones now due, so the same
## calls deliver the same packets in the same order on every run.[br]
## A packet sent before a step arrives in it, after its link's delay in further steps. Packets due
## together arrive in send order, unless a scripted reorder released them. Client ids come from a
## seeded generator: large and random-looking, as real ones are, and the same on every run.[br]
## Switches: [method drop] a peer, [method set_delay] a link, [method reorder_next] its packets.

const LoopbackPeer = preload("res://tests/net/harness/loopback_peer.gd")

## The host's peer id, as Godot's: 1.
const HOST_ID: int = MultiplayerPeer.TARGET_PEER_SERVER
## The seed client ids are drawn from when none is given.
const DEFAULT_SEED: int = 20261119
# Godot peer ids are positive 32-bit ints; 1 is the host's.
const MIN_CLIENT_ID: int = 2
const MAX_CLIENT_ID: int = 0x7FFFFFFF

var _step: int = 0
var _sent: int = 0
var _host: LoopbackPeer = null
# Every end on the network, by id, in the order they joined. A dropped end leaves it.
var _peers: Dictionary[int, LoopbackPeer] = {}
# Every end ever created, dropped ones too: they still poll their last announcements, and what
# they send is taken and lost.
var _ends: Array[LoopbackPeer] = []
var _joining: Array[LoopbackPeer] = []
var _used_ids: Dictionary[int, bool] = {}
var _in_flight: Array[LoopbackPeer.Packet] = []
# Each switch by link: Vector2i(sender id, receiver id).
var _delays: Dictionary[Vector2i, int] = {}
var _reorders: Dictionary[Vector2i, PackedInt32Array] = {}
var _held: Dictionary[Vector2i, Array] = {}
var _ids: RandomNumberGenerator = RandomNumberGenerator.new()


## A network whose client ids are drawn from [param id_seed].
func _init(id_seed: int = DEFAULT_SEED) -> void:
	_ids.seed = id_seed
	_used_ids[HOST_ID] = true


## The host's end, connected now. Null, with an error, while a host is on the network.
func create_host() -> LoopbackPeer:
	if _host != null and _peers.has(HOST_ID):
		push_error("LoopbackNetwork: a host is already on the network")
		return null
	_host = LoopbackPeer.new(HOST_ID)
	_peers[HOST_ID] = _host
	_ends.append(_host)
	return _host


## A client's end, connecting until the next [method step] admits it, or fails it when no host is
## on the network or the host refuses new connections. [param peer_id] 0 draws the next id; a
## given one must be unused. Null, with an error, otherwise.
func create_client(peer_id: int = 0) -> LoopbackPeer:
	var id: int = peer_id if peer_id != 0 else _next_client_id()
	if id < MIN_CLIENT_ID or _used_ids.has(id):
		push_error("LoopbackNetwork: client id %d is the host's, used or out of range" % [id])
		return null
	_used_ids[id] = true
	var client: LoopbackPeer = LoopbackPeer.new(id)
	_joining.append(client)
	_ends.append(client)
	return client


## Advances one step: closes and kicks first, then joins, then every packet sent since the last
## step goes onto its link, and every packet now due reaches its receiver's inbox.
func step() -> void:
	_step += 1
	_take_leaves()
	_admit_joins()
	for peer: LoopbackPeer in _ends:
		for packet: LoopbackPeer.Packet in peer.take_outbox():
			_route(packet)
	_deliver_due()


## True when nothing waits anywhere: no join, packet in flight or held, nor any end, dropped ones
## included, with unread, unsent or unannounced traffic. A reorder still holding packets is not
## idle.
func is_idle() -> bool:
	if not (_joining.is_empty() and _in_flight.is_empty() and _held.is_empty()):
		return false
	for peer: LoopbackPeer in _ends:
		if peer.has_pending():
			return false
	return true


## Steps taken so far.
func get_step() -> int:
	return _step


## Packets on their links, not yet delivered, held ones included.
func in_flight_count() -> int:
	var count: int = _in_flight.size()
	for held: Array in _held.values():
		count += held.size()
	return count


## Cuts [param peer_id] off now: every packet to or from it is lost, and the ends it was linked
## to announce it leaving at their next poll, as it announces them. Dropping the host cuts every
## client. False when it isn't on the network.
func drop(peer_id: int) -> bool:
	# ASSUMPTION: both sides hear a drop at once; no silent cut waiting on a timeout is modelled.
	for client: LoopbackPeer in _joining:
		if client.get_unique_id() == peer_id:
			_joining.erase(client)
			client.lose_link()
			return true
	if not _peers.has(peer_id):
		return false
	if peer_id == HOST_ID:
		for id: int in _peers.keys():
			_cut(id)
		return true
	_cut(peer_id)
	if _host != null and _peers.has(HOST_ID):
		_host.queue_link(peer_id, false)
	return true


## Holds every later packet from [param from_id] to [param to_id] for [param steps] more steps.
## 0 is no delay. Packets already on the link keep their arrival step.
func set_delay(from_id: int, to_id: int, steps: int) -> void:
	_delays[Vector2i(from_id, to_id)] = maxi(steps, 0)


## Holds the next [code]order.size()[/code] packets from [param from_id] to [param to_id], then
## puts them on the link at once in [param order]'s sequence of their send indices:
## [code][2, 0, 1][/code] delivers the third, then the first, then the second. False, with an
## error, unless [param order] is a permutation of 0 to size - 1.
func reorder_next(from_id: int, to_id: int, order: PackedInt32Array) -> bool:
	var seen: Dictionary[int, bool] = {}
	for index: int in order:
		if index < 0 or index >= order.size() or seen.has(index):
			push_error("LoopbackNetwork: reorder %s is not a permutation" % [order])
			return false
		seen[index] = true
	if order.is_empty():
		return true
	_reorders[Vector2i(from_id, to_id)] = order.duplicate()
	return true


func _next_client_id() -> int:
	var id: int = _ids.randi_range(MIN_CLIENT_ID, MAX_CLIENT_ID)
	while _used_ids.has(id):
		id = _ids.randi_range(MIN_CLIENT_ID, MAX_CLIENT_ID)
	return id


# Ends that closed themselves, and peers the host kicked, leave the network.
func _take_leaves() -> void:
	for id: int in _peers.keys():
		if _peers.has(id) and _peers[id].take_closed():
			drop(id)
	if _host != null and _peers.has(HOST_ID):
		for kicked: int in _host.take_kicks():
			drop(kicked)


func _admit_joins() -> void:
	var joining: Array[LoopbackPeer] = _joining.duplicate()
	_joining.clear()
	var has_host: bool = _host != null and _peers.has(HOST_ID)
	for client: LoopbackPeer in joining:
		if not has_host or _host.is_refusing_new_connections():
			client.lose_link()
			continue
		var id: int = client.get_unique_id()
		_peers[id] = client
		client.admit()
		client.queue_link(HOST_ID, true)
		_host.queue_link(id, true)


# Puts packet on its link, or into the link's held set while a reorder is collecting. A packet
# from or for an end no longer on the network is lost.
func _route(packet: LoopbackPeer.Packet) -> void:
	if not (_peers.has(packet.from_id) and _peers.has(packet.to_id)):
		return
	var link: Vector2i = Vector2i(packet.from_id, packet.to_id)
	if not _reorders.has(link):
		_launch(packet, link)
		return
	var held: Array = _held.get(link, [])
	held.append(packet)
	_held[link] = held
	var order: PackedInt32Array = _reorders[link]
	if held.size() < order.size():
		return
	_reorders.erase(link)
	_held.erase(link)
	for index: int in order:
		var released: LoopbackPeer.Packet = held[index]
		_launch(released, link)


func _launch(packet: LoopbackPeer.Packet, link: Vector2i) -> void:
	packet.due_step = _step + _delays.get(link, 0)
	packet.order = _sent
	_sent += 1
	_in_flight.append(packet)


func _deliver_due() -> void:
	var due: Array[LoopbackPeer.Packet] = []
	var waiting: Array[LoopbackPeer.Packet] = []
	for packet: LoopbackPeer.Packet in _in_flight:
		if packet.due_step <= _step:
			due.append(packet)
		else:
			waiting.append(packet)
	_in_flight = waiting
	due.sort_custom(_arrives_before)
	for packet: LoopbackPeer.Packet in due:
		if _peers.has(packet.to_id):
			_peers[packet.to_id].deliver(packet)


# Removes peer_id from the network with every packet to or from it, and tells its end.
func _cut(peer_id: int) -> void:
	var peer: LoopbackPeer = _peers[peer_id]
	_peers.erase(peer_id)
	var kept: Array[LoopbackPeer.Packet] = []
	for packet: LoopbackPeer.Packet in _in_flight:
		if packet.from_id != peer_id and packet.to_id != peer_id:
			kept.append(packet)
	_in_flight = kept
	for link: Vector2i in _held.keys():
		if link.x == peer_id or link.y == peer_id:
			_held.erase(link)
			_reorders.erase(link)
	peer.lose_link()


static func _arrives_before(a: LoopbackPeer.Packet, b: LoopbackPeer.Packet) -> bool:
	if a.due_step != b.due_step:
		return a.due_step < b.due_step
	return a.order < b.order
