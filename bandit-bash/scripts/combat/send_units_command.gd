# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     send_units_command.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name SendUnitsCommand
extends Command
## A co-op winner sends surviving units from a won map to a teammate's map still being fought, or
## sends none ([member unit_ids] empty), which is final too.
##
## Submitted on the won map through [method CombatEncounter.submit], which takes it before that
## map's queue and checks it at resolve time: the map is won; the target is still being fought;
## every unit is the seat's, alive and current on that map, and not on its way; one target for the
## whole send; once per seat, except that while any map is frozen every send must take at least
## one unit to a frozen map. A map's own queue refuses it. Each unit records
## [constant CombatFact.Kind.UNIT_SENT] on the encounter and lands by the battle clock
## ([method CombatEncounter.deliver_arrivals]).
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## Its name on the wire ([method Command.get_wire_type]). Its fields follow the common ones: the
## unit ids, then the target map.
const WIRE_TYPE: String = "send_units"

## [member to_session_id] of a send of no units.
const NO_TARGET: int = -1

## The units sent, by instance id, in the order chosen. Empty: the seat sends none.
var unit_ids: PackedStringArray = []

## The session id of the map they go to; [constant NO_TARGET] when none are sent.
var to_session_id: int = NO_TARGET


func _init(
		sender: int = -1, units: PackedStringArray = PackedStringArray(), to_map: int = NO_TARGET
) -> void:
	seat = sender
	unit_ids = units
	to_session_id = to_map


func get_label() -> String:
	return "send units" if not unit_ids.is_empty() else "send none"


func get_wire_type() -> String:
	return WIRE_TYPE


func validate(_session: CombatSession) -> String:
	return "a send goes through the encounter"


# Never reached: validate() refuses it on every map, and the encounter resolves it.
func resolve(_session: CombatSession) -> void:
	pass


func _wire_fields() -> Array:
	return [Array(unit_ids), to_session_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 2 or not values[0] is Array:
		return false
	var target: Variant = _wire_int(values[1])
	if target == null:
		return false
	var units: PackedStringArray = []
	# Untyped: the list comes from the wire and is checked entry by entry.
	for unit_id: Variant in values[0]:
		if not unit_id is String:
			return false
		units.append(unit_id as String)
	unit_ids = units
	to_session_id = target
	return true
