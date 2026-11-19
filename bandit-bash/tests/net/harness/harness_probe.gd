# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     harness_probe.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Node
## The RPC target every [code]net_harness.gd[/code] branch holds at the same path, so a call on one
## branch's probe runs on the others'. It records each call it receives with its sender, for cases
## to assert on. It takes calls from any peer unchecked on purpose: it records, never decides.

## Its name under every branch; the same on each, so RPC paths match.
const NODE_NAME: StringName = &"Probe"

var _senders: PackedInt32Array = []
var _payloads: Array = []


## Records [param payload] and the peer that sent it.
@rpc("any_peer", "call_remote", "reliable")
func receive(payload: Variant) -> void:
	_senders.append(multiplayer.get_remote_sender_id())
	_payloads.append(payload)


## Sends [param payload] to [param peer_id]'s probe, reliably.
func send_to(peer_id: int, payload: Variant) -> Error:
	return rpc_id(peer_id, &"receive", payload)


## Sends [param payload] to every other peer's probe, reliably.
func send_to_all(payload: Variant) -> Error:
	return rpc(&"receive", payload)


## The sender of each call received, in arrival order.
func senders() -> PackedInt32Array:
	return _senders.duplicate()


## The payload of each call received, in arrival order.
func payloads() -> Array:
	return _payloads.duplicate()


## Forgets every call received.
func clear() -> void:
	_senders.clear()
	_payloads.clear()
