# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     start_command.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name StartCommand
extends Command
## A seat's Start in the opening swap window before turn 1 (combat core plan, Turn and phase loop,
## question 17): the seat is done swapping.
##
## Legal only while the window is open and the seat hasn't started
## ([method CommandValidator.swap_window_reason]). When it is the last seat on the map to start, it
## closes the window and runs turn 1's player Phase Start ([method PhaseRunner.start]); before then
## it records nothing. With the opening-swap setting off there is no window, and it is rejected.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "start"


func validate(session: CombatSession) -> String:
	return CommandValidator.swap_window_reason(session, seat)


func resolve(session: CombatSession) -> void:
	PhaseRunner.start(session, seat)
