# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enet_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## The one real transport case for tests/net/run_all.gd: a host and a client on ENet over
## 127.0.0.1, each under its own harness branch in this process, link and exchange an RPC each
## way through Godot's own RPC path. The host binds a port the system picks, so parallel runs
## never collide; where none can be opened the case skips and says why. Every wait has a limit,
## so a link that never forms fails rather than hangs.

const NetHarness = preload("res://tests/net/harness/net_harness.gd")

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const LOCALHOST: String = "127.0.0.1"
# Port 0: the system picks a free one, read back from the host.
const ANY_PORT: int = 0
const ONE_CLIENT: int = 1
# A link or reply not seen within this limit is a failure, not a skip; localhost
# links in milliseconds, so the limit only stops a hang, well inside the runner's suite limit.
const WAIT_LIMIT_MSEC: int = 5000
# The pause between polls while waiting, so the wait doesn't spin a core.
const POLL_PAUSE_MSEC: int = 1


func run() -> void:
	_test_enet_localhost()


func _test_enet_localhost() -> void:
	const CASE_NAME: String = "enet: a host and a client on 127.0.0.1 exchange an RPC each way"
	var host_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip(LOCALHOST)
	var error: Error = host_peer.create_server(ANY_PORT, ONE_CLIENT)
	if error != OK:
		_skip(CASE_NAME, "no port can be opened on %s (%s)" % [LOCALHOST, error_string(error)])
		return
	var port: int = host_peer.host.get_local_port()
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	error = client_peer.create_client(LOCALHOST, port)
	if error != OK:
		host_peer.close()
		_skip(CASE_NAME, "the client can't open a socket (%s)" % [error_string(error)])
		return
	var client_id: int = client_peer.get_unique_id()
	var harness: NetHarness = NetHarness.new(_root)
	harness.start_with_peers([host_peer, client_peer])

	var linked: bool = _wait(harness, func() -> bool: return (
			harness.is_linked(1) and harness.api(NetHarness.HOST).get_peers().has(client_id)
	))
	if linked:
		harness.probe(1).send_to(1, "up")
		harness.probe(NetHarness.HOST).send_to(client_id, "down")
	var exchanged: bool = linked and _wait(harness, func() -> bool: return (
			not harness.probe(NetHarness.HOST).payloads().is_empty()
			and not harness.probe(1).payloads().is_empty()
	))
	var host_got: Array = harness.probe(NetHarness.HOST).payloads()
	var host_from: PackedInt32Array = harness.probe(NetHarness.HOST).senders()
	var client_got: Array = harness.probe(1).payloads()
	var gate: bool = (
			NetGate.is_authoritative(harness.api(NetHarness.HOST))
			and not NetGate.is_authoritative(harness.api(1))
	)
	harness.stop()

	_check(CASE_NAME, (
			linked
			and exchanged
			and host_got == ["up"]
			and host_from == PackedInt32Array([client_id])
			and client_got == ["down"]
			and gate
	), "port %d, linked %s, host got %s from %s, client got %s, gate %s" % [
		port, linked, host_got, host_from, client_got, gate,
	])


# Polls every branch until done answers true, at most WAIT_LIMIT_MSEC. Real sockets need real
# time; the loopback cases never wait on the clock.
func _wait(harness: NetHarness, done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + WAIT_LIMIT_MSEC
	while Time.get_ticks_msec() < deadline:
		harness.poll()
		if done.call():
			return true
		OS.delay_msec(POLL_PAUSE_MSEC)
	return false
