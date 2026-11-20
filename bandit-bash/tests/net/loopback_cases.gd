# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loopback_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Two-peer harness cases for tests/net/run_all.gd, proving the harness itself on the loopback: a
## host and three clients link, with seeded ids the same on every run, and five peers are refused;
## RPCs arrive in send order one step later, client to client through the host's relay, with no
## engine error; a delay holds a link's packets exactly its steps and no other link's; a scripted
## reorder holds packets until its set is complete, then delivers them in its order; a drop loses
## the packets in flight and every side hears it, a reconnect links again with a new id, and a
## dropped host disconnects every client; [NetGate] answers per branch; stop frees the branches.

const NetHarness = preload("res://tests/net/harness/net_harness.gd")

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const HOST: int = NetHarness.HOST


func run() -> void:
	_test_start()
	_test_in_order()
	_test_delay()
	_test_reorder()
	_test_drop_and_reconnect()
	_test_drop_host()
	_test_gate()
	_test_stop()


func _test_start() -> void:
	var harness: NetHarness = NetHarness.new(_root)
	var started: bool = harness.start(NetHarness.MAX_CLIENTS)
	var host_saw: bool = true
	var clients_linked: bool = true
	var ids: PackedInt32Array = []
	for index: int in range(1, harness.size()):
		ids.append(harness.peer_id(index))
		host_saw = host_saw and harness.has_event(HOST, &"peer_connected", harness.peer_id(index))
		clients_linked = (
				clients_linked
				and harness.has_event(index, &"connected_to_server")
				and harness.has_event(index, &"peer_connected", 1)
		)
	# The host's relay tells each client of the others.
	var others_known: bool = (
			harness.api(1).get_peers().has(harness.peer_id(2))
			and harness.api(1).get_peers().has(harness.peer_id(3))
	)
	var host_peers: int = harness.api(HOST).get_peers().size()
	harness.stop()

	var again: NetHarness = NetHarness.new(_root)
	var started_again: bool = again.start(NetHarness.MAX_CLIENTS)
	var same_ids: bool = started_again
	for index: int in range(1, again.size()):
		same_ids = same_ids and again.peer_id(index) == ids[index - 1]
	again.stop()

	var too_many: NetHarness = NetHarness.new(_root)
	var refused: bool = not too_many.start(NetHarness.MAX_CLIENTS + 1)
	too_many.stop()

	_check("harness: a host and three clients link, each side hearing every join", (
			started
			and host_saw
			and clients_linked
			and others_known
			and host_peers == NetHarness.MAX_CLIENTS
	), "started %s, host saw all %s, clients linked %s, others known %s, host peers %d" % [
		started, host_saw, clients_linked, others_known, host_peers,
	])
	_check("harness: client ids are seeded, distinct and the same on every run", (
			same_ids
			and ids.size() == NetHarness.MAX_CLIENTS
			and ids[0] != ids[1]
			and ids[1] != ids[2]
			and ids[0] != ids[2]
			and not ids.has(1)
	), "ids %s, same again %s" % [ids, same_ids])
	_check("harness: more than three clients are refused", refused)


func _test_in_order() -> void:
	var catcher: ErrorCatcher = ErrorCatcher.new()
	OS.add_logger(catcher)
	var harness: NetHarness = NetHarness.new(_root)
	var started: bool = harness.start(2)
	var client: int = harness.peer_id(1)
	for value: int in 5:
		harness.probe(1).send_to(1, value)
	for value: String in ["a", "b", "c"]:
		harness.probe(HOST).send_to_all(value)
	harness.step()
	var host_got: Array = harness.probe(HOST).payloads()
	var host_from: PackedInt32Array = harness.probe(HOST).senders()
	var first_got: Array = harness.probe(1).payloads()
	var second_got: Array = harness.probe(2).payloads()
	harness.clear_records()
	harness.probe(1).send_to(harness.peer_id(2), "relayed")
	var relay_steps: int = harness.step_until_idle()
	var relayed_got: Array = harness.probe(2).payloads()
	var relayed_from: PackedInt32Array = harness.probe(2).senders()
	harness.stop()
	OS.remove_logger(catcher)
	var errors: PackedStringArray = catcher.get_errors()

	_check("harness: RPCs arrive in send order on the next step", (
			started
			and host_got == [0, 1, 2, 3, 4]
			and host_from == PackedInt32Array([client, client, client, client, client])
			and first_got == ["a", "b", "c"]
			and second_got == ["a", "b", "c"]
	), "host %s from %s, clients %s and %s" % [host_got, host_from, first_got, second_got])
	# At least a step up and a step down; the first call to a node also confirms its path.
	_check("harness: a client's RPC to a client goes through the host's relay", (
			relayed_got == ["relayed"]
			and relayed_from == PackedInt32Array([client])
			and relay_steps >= 2
	), "got %s from %s in %d steps" % [relayed_got, relayed_from, relay_steps])
	_check("harness: loopback traffic raises no engine error", errors.is_empty(), (
			", ".join(errors)
	))


func _test_delay() -> void:
	var harness: NetHarness = NetHarness.new(_root)
	var started: bool = harness.start(1)
	const DELAY: int = 3
	harness.delay(1, HOST, DELAY)
	harness.probe(1).send_to(1, "late")
	harness.probe(HOST).send_to(harness.peer_id(1), "prompt")
	harness.step()
	var prompt_got: Array = harness.probe(1).payloads()
	var held_while: bool = true
	for _step: int in DELAY:
		held_while = held_while and harness.probe(HOST).payloads().is_empty()
		harness.step()
	var late_got: Array = harness.probe(HOST).payloads()
	harness.delay(1, HOST, 0)
	harness.clear_records()
	harness.probe(1).send_to(1, "restored")
	harness.step()
	var restored_got: Array = harness.probe(HOST).payloads()
	harness.stop()

	_check("harness: a delay holds its link's packets exactly its steps, no other link's", (
			started
			and prompt_got == ["prompt"]
			and held_while
			and late_got == ["late"]
			and restored_got == ["restored"]
	), "other link %s, held %s, then %s, after 0 %s" % [
		prompt_got, held_while, late_got, restored_got,
	])


func _test_reorder() -> void:
	var catcher: ErrorCatcher = ErrorCatcher.new()
	OS.add_logger(catcher)
	var harness: NetHarness = NetHarness.new(_root)
	var started: bool = harness.start(1)
	# The first call to a node sends its path; later ones are one packet each.
	harness.probe(1).send_to(1, "warm")
	var warmed: bool = harness.step_until_idle() >= 0
	harness.clear_records()
	var scripted: bool = harness.reorder(1, HOST, PackedInt32Array([2, 0, 1]))
	var held_counts: PackedInt32Array = []
	for value: String in ["a", "b", "c"]:
		harness.probe(1).send_to(1, value)
		held_counts.append(harness.probe(HOST).payloads().size())
		harness.step()
	var got: Array = harness.probe(HOST).payloads()
	harness.clear_records()
	for value: String in ["d", "e"]:
		harness.probe(1).send_to(1, value)
	harness.step()
	var after: Array = harness.probe(HOST).payloads()
	harness.stop()
	OS.remove_logger(catcher)
	var errors: PackedStringArray = catcher.get_errors()

	var bad: NetHarness = NetHarness.new(_root)
	bad.start(1)
	var refused: bool = (
			not bad.reorder(1, HOST, PackedInt32Array([0, 0]))
			and not bad.reorder(1, HOST, PackedInt32Array([1, 2]))
	)
	bad.stop()

	_check("harness: a reorder holds its set, then delivers it in the scripted order", (
			started
			and warmed
			and scripted
			and held_counts == PackedInt32Array([0, 0, 0])
			and got == ["c", "a", "b"]
			and after == ["d", "e"]
			and errors.is_empty()
	), "held %s, got %s, then %s, errors %s" % [held_counts, got, after, errors])
	_check("harness: a reorder that isn't a permutation is refused", refused)


func _test_drop_and_reconnect() -> void:
	var harness: NetHarness = NetHarness.new(_root)
	var started: bool = harness.start(2)
	var old_id: int = harness.peer_id(1)
	harness.clear_records()
	harness.probe(1).send_to(1, "lost on the way")
	harness.probe(HOST).send_to(old_id, "lost too")
	var dropped: bool = harness.drop(1)
	var settled: bool = harness.step_until_idle() >= 0
	var host_heard: bool = harness.has_event(HOST, &"peer_disconnected", old_id)
	var client_heard: bool = harness.has_event(1, &"server_disconnected")
	var other_heard: bool = harness.has_event(2, &"peer_disconnected", old_id)
	var nothing_arrived: bool = (
			harness.probe(HOST).payloads().is_empty() and harness.probe(1).payloads().is_empty()
	)
	var host_peers: PackedInt32Array = harness.api(HOST).get_peers()
	harness.clear_records()

	var rejoined: bool = harness.reconnect(1)
	var new_id: int = harness.peer_id(1)
	var host_saw_new: bool = harness.has_event(HOST, &"peer_connected", new_id)
	var client_linked: bool = harness.has_event(1, &"connected_to_server")
	harness.probe(1).send_to(1, "back")
	harness.step_until_idle()
	var back_got: Array = harness.probe(HOST).payloads()
	var back_from: PackedInt32Array = harness.probe(HOST).senders()
	harness.stop()

	_check("harness: a drop loses packets in flight, and every side hears it", (
			started
			and dropped
			and settled
			and host_heard
			and client_heard
			and other_heard
			and nothing_arrived
			and not host_peers.has(old_id)
	), "host %s, client %s, other client %s, nothing arrived %s, host peers %s" % [
		host_heard, client_heard, other_heard, nothing_arrived, host_peers,
	])
	_check("harness: a reconnect links the branch again with a new id", (
			rejoined
			and new_id != old_id
			and host_saw_new
			and client_linked
			and back_got == ["back"]
			and back_from == PackedInt32Array([new_id])
	), "rejoined %s, id %d (was %d), host saw %s, linked %s, got %s from %s" % [
		rejoined, new_id, old_id, host_saw_new, client_linked, back_got, back_from,
	])


func _test_drop_host() -> void:
	var harness: NetHarness = NetHarness.new(_root)
	var started: bool = harness.start(2)
	var first: int = harness.peer_id(1)
	var second: int = harness.peer_id(2)
	var dropped: bool = harness.drop(HOST)
	var settled: bool = harness.step_until_idle() >= 0
	var clients_heard: bool = (
			harness.has_event(1, &"server_disconnected")
			and harness.has_event(2, &"server_disconnected")
	)
	var host_heard: bool = (
			harness.has_event(HOST, &"peer_disconnected", first)
			and harness.has_event(HOST, &"peer_disconnected", second)
	)
	var unlinked: bool = not harness.is_linked(1) and not harness.is_linked(2)
	harness.stop()

	_check("harness: dropping the host disconnects every client", (
			started and dropped and settled and clients_heard and host_heard and unlinked
	), "clients %s, host %s, unlinked %s" % [clients_heard, host_heard, unlinked])


func _test_gate() -> void:
	var harness: NetHarness = NetHarness.new(_root)
	var started: bool = harness.start(2)
	var host_api: bool = NetGate.is_authoritative(harness.api(HOST))
	var client_api: bool = NetGate.is_authoritative(harness.api(1))
	var host_node: bool = NetGate.is_authoritative(harness.probe(HOST).multiplayer)
	var client_node: bool = NetGate.is_authoritative(harness.probe(2).multiplayer)
	var own_api: bool = (
			harness.probe(HOST).multiplayer == harness.api(HOST)
			and harness.probe(2).multiplayer == harness.api(2)
	)
	var sessions: bool = (
			NetGate.has_session(harness.api(HOST)) and NetGate.has_session(harness.api(1))
	)
	var root_solo: bool = NetGate.is_authoritative(_root.multiplayer)
	harness.stop()

	_check("harness: NetGate is authoritative on the host branch, not on a client branch", (
			started
			and host_api
			and not client_api
			and host_node
			and not client_node
			and own_api
			and sessions
			and root_solo
	), "host %s/%s, client %s/%s, own API %s, sessions %s, root solo %s" % [
		host_api, host_node, client_api, client_node, own_api, sessions, root_solo,
	])


func _test_stop() -> void:
	var harness: NetHarness = NetHarness.new(_root)
	harness.start(1)
	var holder: Node = harness.branch(HOST).get_parent()
	var path: NodePath = harness.branch(1).get_path()
	var probe: Node = harness.probe(1)
	harness.stop()
	_check("harness: stop frees the branches and gives their paths back to the root's API", (
			not is_instance_valid(holder)
			and not is_instance_valid(probe)
			and _root.get_tree().get_multiplayer(path) == _root.multiplayer
	))
