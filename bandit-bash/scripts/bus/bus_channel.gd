# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     bus_channel.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name BusChannel
extends RefCounted
## Base for one domain of a bus: a group of typed signals, one per fact kind.
##
## A subclass declares its signals and routes each to its fact kind with [method _route] in
## [code]_init[/code]. The owning bus ([CombatBus], [CampaignBus]) reads [method get_kinds] once to
## build its kind lookup, then calls [method emit_fact] during playback. A kind is routed to one
## signal in one channel only.

# The signal each fact kind plays on.
var _routes: Dictionary[int, Signal] = {}


## The fact kinds this channel has a signal for.
func get_kinds() -> PackedInt32Array:
	return PackedInt32Array(_routes.keys())


## Emits the signal routed to [param kind] with [param fact].
##
## Returns [code]false[/code] when this channel has no signal for [param kind].
func emit_fact(kind: int, fact: RefCounted) -> bool:
	if not _routes.has(kind):
		return false
	_routes[kind].emit(fact)
	return true


## Routes fact [param kind] to [param target], a signal of this channel taking one fact.
func _route(kind: int, target: Signal) -> void:
	if _routes.has(kind):
		push_error("BusChannel: kind %d routed twice - %s" % [kind, target.get_name()])
		return
	_routes[kind] = target
