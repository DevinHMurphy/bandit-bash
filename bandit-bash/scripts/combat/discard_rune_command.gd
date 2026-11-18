# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     discard_rune_command.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name DiscardRuneCommand
extends Command
## A seat throws a rune out of its slots unused ([method RuneResolver.discard]), freeing the slot.
##
## Legal when [method CastRuneCommand.validate] would be, as far as the seat goes: this map's
## player phase, before the seat ends its turn, the rune in the seat's slots. It acts for no unit,
## fires no effect and changes no unit's state. The battle's rune bar sends it after a confirm.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Its name on the wire ([method Command.get_wire_type]). Its one field follows the common ones:
## the rune.
const WIRE_TYPE: String = "discard_rune"

## The rune's instance id, in [member CombatState.rune_slots] of the seat.
var rune_id: String = ""


func _init(sender: int = -1, rune: String = "") -> void:
	seat = sender
	rune_id = rune


func get_label() -> String:
	return "discard rune"


func get_wire_type() -> String:
	return WIRE_TYPE


func validate(session: CombatSession) -> String:
	var reason: String = CommandValidator.player_phase_reason(session, seat)
	if not reason.is_empty():
		return reason
	var slots: PackedStringArray = session.state.rune_slots.get(seat, PackedStringArray())
	if not slots.has(rune_id):
		return "not in the seat's rune slots"
	return ""


func resolve(session: CombatSession) -> void:
	RuneResolver.discard(session.engine, session.state, seat, rune_id)


func _wire_fields() -> Array:
	return [rune_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1 or not values[0] is String:
		return false
	rune_id = values[0]
	return true
