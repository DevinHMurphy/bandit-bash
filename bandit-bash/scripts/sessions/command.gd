# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     command.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

@abstract
class_name Command
extends RefCounted
## One request from a seat to a combat session: a unit's turn, an end turn, a rune.
##
## A command enters its session's queue on the host, stamped on arrival, and resolves there
## atomically: [method resolve], every reaction, and the drained reaction queue, before the next
## command starts. It is checked against the state at resolve time, never at send time, so the first
## arrival wins and a rejected command changes nothing and costs nothing. [CombatSession] checks, in
## order: the map's combat is still going; the seat controls [member actor_id]; [method validate];
## the stale-forecast rule ([method forecast_reads]). The combat core's command types extend this
## class (P02 CC6).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## [member based_on_seq] of a command sent without a forecast.
const NO_SEQ: int = -1

## The seat that sent it. The host sets it from the connection, never from the message.
var seat: int = -1

## Instance id of the unit it acts for; the seat must control it. Empty: it acts for no unit, as a
## rune does, so any seat may send it.
var actor_id: String = ""

## The session [member CombatFact.seq] the sender's forecast was based on; [constant NO_SEQ] when
## it had none.
var based_on_seq: int = NO_SEQ

## Arrival stamp, set when it enters a queue: the host's order of arrival across every map of an
## encounter. 0 until then.
var arrival: int = 0


## A short name for log lines, such as [code]move+attack[/code].
func get_label() -> String:
	return "command"


## The unit or object it acts on, for log lines; empty when none.
func get_target_id() -> String:
	return ""


## Ids the sender's forecast read: the actor, the target, and every unit its effects read. A fact
## since [member based_on_seq] about any of them makes the command stale. Empty: no stale check, as
## for a move, which only needs to be legal.
func forecast_reads() -> PackedStringArray:
	return PackedStringArray()


## Tiles the sender's forecast read; a fact on any of them since [member based_on_seq] makes the
## command stale. Empty: no tile check.
func forecast_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	return tiles


## Why the command can't resolve on [param session] now; empty when it can. Changes nothing.
func validate(_session: CombatSession) -> String:
	return ""


## Resolves the command on [param session] once every check passed. Rules code: pure, never awaits,
## and records every change as a fact through [member CombatSession.engine]. The session drains
## the reaction queue afterwards.
@abstract func resolve(session: CombatSession) -> void
