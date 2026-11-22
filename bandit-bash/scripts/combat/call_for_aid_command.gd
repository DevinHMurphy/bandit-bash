# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     call_for_aid_command.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name CallForAidCommand
extends Command
## A co-op player raises or lowers the call for aid on their own map, shown on every winner's
## status panel.
##
## Submitted on the caller's map through [method CombatEncounter.submit], which resolves it: the
## map's owner seat only, while the map is still being fought (frozen too), and only to change the
## flag. It records [constant CombatFact.Kind.AID_CALLED] on the encounter; the flag is saved and
## stays as it was when the map ends ([method CombatEncounter.is_aid_called]). A map's own queue
## refuses it.
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## Its name on the wire ([method Command.get_wire_type]). Its one field follows the common ones:
## whether the call is raised.
const WIRE_TYPE: String = "call_for_aid"

## True raises the call; false lowers it.
var is_raised: bool = true


func _init(sender: int = -1, raised: bool = true) -> void:
	seat = sender
	is_raised = raised


func get_label() -> String:
	return "call for aid" if is_raised else "lower call for aid"


func get_wire_type() -> String:
	return WIRE_TYPE


func validate(_session: CombatSession) -> String:
	return "a call for aid goes through the encounter"


# Never reached: validate() refuses it on every map, and the encounter resolves it.
func resolve(_session: CombatSession) -> void:
	pass


func _wire_fields() -> Array:
	return [is_raised]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1 or not values[0] is bool:
		return false
	is_raised = values[0]
	return true
