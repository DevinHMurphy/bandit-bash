# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     net_harness.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## A host and up to three clients in one process, for the net suite's cases. Each peer is a
## branch: a node under the scene tree's root with its own [SceneMultiplayer]
## ([method SceneTree.set_multiplayer]), so a node under a branch reads that branch's
## [code]multiplayer[/code], and an RPC from one branch reaches the node at the same path under the
## others. Branch 0 is the host. Every branch holds a [code]harness_probe.gd[/code] and records its
## API's connection signals.[br]
## [method start] links the branches through a [code]loopback_network.gd[/code], stepped only by
## [method step], never by frames or the clock. [method start_with_peers] takes real peers (ENet)
## instead, and the case polls. Call [method stop] when done: it frees the branches.
##
## @tutorial(Net transport plan): docs/plans/2026-11-19-net-transport.md

const LoopbackNetwork = preload("res://tests/net/harness/loopback_network.gd")
const LoopbackPeer = preload("res://tests/net/harness/loopback_peer.gd")
const HarnessProbe = preload("res://tests/net/harness/harness_probe.gd")

## The host's branch index.
const HOST: int = 0
## The most clients [method start] links: four peers, the most a run seats.
const MAX_CLIENTS: int = 3
## The most steps [method step_until_idle] takes by default before giving up. A guard against a
## case that never settles, not a timing: loopback traffic settles in a few steps.
const STEP_LIMIT: int = 200

var _root: Window = null
var _holder: Node = null
var _network: LoopbackNetwork = null
var _branches: Array[Branch] = []


## A harness under [param root], the scene tree's root, whose loopback network draws client ids
## from [param id_seed].
func _init(root: Window, id_seed: int = LoopbackNetwork.DEFAULT_SEED) -> void:
	_root = root
	_network = LoopbackNetwork.new(id_seed)


## Builds the host's branch and [param client_count] clients' on the loopback network, and steps
## until every client is linked. False, with an error, when the count is out of range, the
## harness is already started, or a client didn't connect.
func start(client_count: int) -> bool:
	if client_count < 0 or client_count > MAX_CLIENTS or not _branches.is_empty():
		push_error("NetHarness: can't start %d clients (started: %s)" % [
			client_count, not _branches.is_empty(),
		])
		return false
	var peers: Array[MultiplayerPeer] = [_network.create_host()]
	for _index: int in client_count:
		peers.append(_network.create_client())
	start_with_peers(peers)
	if step_until_idle() < 0:
		push_error("NetHarness: the network didn't settle while linking")
		return false
	for index: int in range(1, _branches.size()):
		if not is_linked(index):
			push_error("NetHarness: client %d didn't connect" % [index])
			return false
	return true


## Builds one branch per peer in [param peers], the first the host's, and steps nothing: for a
## transport the case polls itself, as ENet's. The harness owns the peers from now on and closes
## them in [method stop].
func start_with_peers(peers: Array[MultiplayerPeer]) -> void:
	_holder = Node.new()
	_holder.name = &"NetHarness"
	_root.add_child(_holder, true)
	for index: int in peers.size():
		_add_branch(index, peers[index])


## Frees every branch and closes its peer; the branches' paths answer the root's API again.
func stop() -> void:
	var tree: SceneTree = _root.get_tree()
	for branch: Branch in _branches:
		tree.set_multiplayer(null, branch.root.get_path())
		if branch.api.multiplayer_peer != null:
			branch.api.multiplayer_peer.close()
			branch.api.multiplayer_peer = null
	_branches.clear()
	if is_instance_valid(_holder):
		_holder.free()
	_holder = null


## One loopback step, then a poll of every branch, the host's first.
func step() -> void:
	_network.step()
	poll()


## Steps until the loopback network is idle, at most [param limit] steps. Returns the steps taken,
## 0 when it was idle already, or -1 when it was still busy after the limit.
func step_until_idle(limit: int = STEP_LIMIT) -> int:
	for taken: int in limit + 1:
		if _network.is_idle():
			return taken
		if taken < limit:
			step()
	return -1


## Polls every branch's API, the host's first, without stepping the network.
func poll() -> void:
	for branch: Branch in _branches:
		if branch.api.multiplayer_peer != null:
			branch.api.poll()


## How many branches there are, the host's included.
func size() -> int:
	return _branches.size()


## The loopback network, for its switches by peer id. Unused after [method start_with_peers].
func get_network() -> LoopbackNetwork:
	return _network


## Branch [param index]'s own API.
func api(index: int) -> SceneMultiplayer:
	return _branches[index].api


## Branch [param index]'s root node. A node added under every branch with the same name is the
## same RPC target on each.
func branch(index: int) -> Node:
	return _branches[index].root


## Branch [param index]'s probe.
func probe(index: int) -> HarnessProbe:
	return _branches[index].probe


## Branch [param index]'s current peer id.
func peer_id(index: int) -> int:
	var peer: MultiplayerPeer = _branches[index].api.multiplayer_peer
	return 0 if peer == null else peer.get_unique_id()


## The branch whose current peer id is [param id], or -1.
func index_of(id: int) -> int:
	for index: int in _branches.size():
		if peer_id(index) == id:
			return index
	return -1


## True when branch [param index] is connected: the host always, a client once it has peer 1.
func is_linked(index: int) -> bool:
	var peer: MultiplayerPeer = _branches[index].api.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return index == HOST or _branches[index].api.get_peers().has(LoopbackNetwork.HOST_ID)


## Holds every later packet from branch [param from_index] to [param to_index] for [param steps]
## more steps; see the network's [code]set_delay()[/code].
func delay(from_index: int, to_index: int, steps: int) -> void:
	_network.set_delay(peer_id(from_index), peer_id(to_index), steps)


## Reorders the next packets from branch [param from_index] to [param to_index] by
## [param order]; see the network's [code]reorder_next()[/code].
func reorder(from_index: int, to_index: int, order: PackedInt32Array) -> bool:
	return _network.reorder_next(peer_id(from_index), peer_id(to_index), order)


## Loses the next [param count] packets from branch [param from_index] to [param to_index]; see
## the network's [code]lose_next()[/code].
func lose_next(from_index: int, to_index: int, count: int) -> void:
	_network.lose_next(peer_id(from_index), peer_id(to_index), count)


## Cuts branch [param index] off the loopback network now; every side hears it as the next steps
## poll. Dropping the host cuts every client. False when it wasn't on the network.
func drop(index: int) -> bool:
	return _network.drop(peer_id(index))


## Gives client branch [param index] a new loopback peer, with a new id as a real rejoin has, and
## steps until it is linked. The branch keeps its nodes and records. False, with an error, for the
## host or when it didn't connect.
func reconnect(index: int) -> bool:
	if index == HOST or index < 0 or index >= _branches.size():
		push_error("NetHarness: branch %d can't reconnect" % [index])
		return false
	var old: MultiplayerPeer = _branches[index].api.multiplayer_peer
	if old != null and old.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		_network.drop(old.get_unique_id())
		step_until_idle()
	var client: LoopbackPeer = _network.create_client()
	if client == null:
		return false
	_branches[index].api.multiplayer_peer = client
	if step_until_idle() < 0 or not is_linked(index):
		push_error("NetHarness: branch %d didn't reconnect" % [index])
		return false
	return true


## Branch [param index]'s connection signals so far, in order, each as
## [code]"<signal name> <peer id>"[/code], the id 0 for signals without one:
## [code]"peer_connected 1"[/code], [code]"connected_to_server 0"[/code].
func events(index: int) -> PackedStringArray:
	return _branches[index].events.duplicate()


## True when branch [param index] recorded [param signal_name] for [param id] (0 for signals
## without an id).
func has_event(index: int, signal_name: StringName, id: int = 0) -> bool:
	return _branches[index].events.has(_event(signal_name, id))


## Forgets every branch's probe calls and connection signals.
func clear_records() -> void:
	for branch_record: Branch in _branches:
		branch_record.probe.clear()
		branch_record.events.clear()


func _add_branch(index: int, peer: MultiplayerPeer) -> void:
	var branch_record: Branch = Branch.new()
	branch_record.root = Node.new()
	branch_record.root.name = "Host" if index == HOST else "Client%d" % [index]
	_holder.add_child(branch_record.root)
	branch_record.api = SceneMultiplayer.new()
	_root.get_tree().set_multiplayer(branch_record.api, branch_record.root.get_path())
	branch_record.probe = HarnessProbe.new()
	branch_record.probe.name = HarnessProbe.NODE_NAME
	branch_record.root.add_child(branch_record.probe)
	# Bound to the index, not the branch, so the API's connections hold no reference back to it.
	branch_record.api.peer_connected.connect(_on_api_peer_signal.bind(&"peer_connected", index))
	branch_record.api.peer_disconnected.connect(
			_on_api_peer_signal.bind(&"peer_disconnected", index)
	)
	branch_record.api.connected_to_server.connect(
			_on_api_signal.bind(&"connected_to_server", index)
	)
	branch_record.api.connection_failed.connect(_on_api_signal.bind(&"connection_failed", index))
	branch_record.api.server_disconnected.connect(
			_on_api_signal.bind(&"server_disconnected", index)
	)
	branch_record.api.multiplayer_peer = peer
	_branches.append(branch_record)


func _on_api_peer_signal(id: int, signal_name: StringName, index: int) -> void:
	_branches[index].events.append(_event(signal_name, id))


func _on_api_signal(signal_name: StringName, index: int) -> void:
	_branches[index].events.append(_event(signal_name, 0))


static func _event(signal_name: StringName, id: int) -> String:
	return "%s %d" % [signal_name, id]


# One peer's branch: its root node, its own API, its probe and its recorded connection signals.
class Branch:
	extends RefCounted

	var root: Node = null
	var api: SceneMultiplayer = null
	var probe: HarnessProbe = null
	var events: PackedStringArray = []
