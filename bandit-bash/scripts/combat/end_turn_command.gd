# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     end_turn_command.gd
# Author:
# Created:  October 28, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name EndTurnCommand
extends Command
## A seat ends its turn in the player phase (combat core plan, Commands).
##
## Legal for a seat with units on the map that hasn't ended its turn this phase; once ended, the
## seat can't act until the next player phase. The map's player phase ends when every seat with
## units on it has ended, so the last end turn resolves the rest of the turn as one command
## ([method PhaseRunner.end_turn]): player Phase End, the whole enemy phase, the hooks after it,
## and the next player Phase Start. It acts for no unit.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## Its name on the wire ([method Command.get_wire_type]). It has no fields of its own.
const WIRE_TYPE: String = "end_turn"


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "end turn"


func get_wire_type() -> String:
	return WIRE_TYPE


func validate(session: CombatSession) -> String:
	var reason: String = CommandValidator.player_phase_reason(session, seat)
	if not reason.is_empty():
		return reason
	if not PhaseRunner.seats_with_units(session).has(seat):
		return "seat %d has no units on this map" % [seat]
	return ""


func resolve(session: CombatSession) -> void:
	PhaseRunner.end_turn(session, seat)
