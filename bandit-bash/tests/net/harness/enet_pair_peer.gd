# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enet_pair_peer.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends SceneTree
## One side of the net suite's two-instance ENet battle: [code]enet_dev_cases.gd[/code] launches
## two headless instances of the project on this script, with the ENet dev flags after
## [code]--[/code], and this ticks that file's [code]PairPeer[/code] every frame, quitting with
## its verdict (0 passed, 1 failed, 2 when it couldn't be made). The suite never runs it itself.
## The case file is loaded at run time: it names autoloads, which a main script can't at compile
## time.

const _CASES_PATH: String = "res://tests/net/enet_dev_cases.gd"
const _PEER_CLASS: String = "PairPeer"
const _RUNNING: int = -1
const _BROKEN: int = 2

var _peer: RefCounted = null
var _has_ended: bool = false


func _process(delta: float) -> bool:
	if _has_ended:
		return false
	if _peer == null:
		_peer = _make_peer()
		if _peer == null:
			_end(_BROKEN)
			return false
	var verdict: int = _peer.call("tick", delta)
	if verdict != _RUNNING:
		_end(verdict)
	return false


func _make_peer() -> RefCounted:
	var cases: GDScript = load(_CASES_PATH) as GDScript
	if cases == null:
		push_error("enet_pair_peer: %s doesn't load" % [_CASES_PATH])
		return null
	var peer_class: GDScript = cases.get_script_constant_map().get(_PEER_CLASS) as GDScript
	if peer_class == null:
		push_error("enet_pair_peer: %s has no %s" % [_CASES_PATH, _PEER_CLASS])
		return null
	return peer_class.new(self) as RefCounted


func _end(verdict: int) -> void:
	_has_ended = true
	quit(verdict)
