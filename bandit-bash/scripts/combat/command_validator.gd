# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     command_validator.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name CommandValidator
extends RefCounted
## The phase checks every combat-core command shares: whose phase it is, whether the seat has
## ended its turn, and the opening swap window before turn 1.
##
## [CombatSession]'s queue checks only what every command shares (the map still being fought,
## ownership, the stale forecast; see [Command]); the queue knows nothing of phases, so each
## command type calls these from its [method Command.validate]. Each returns why the command can't
## act now, or empty when it can. Changes nothing.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md


## Why [param seat] can't act in the player phase of [param session] now: it isn't the player
## phase (before turn 1 included), the phase has ended, or the seat has ended its turn.
static func player_phase_reason(session: CombatSession, seat: int) -> String:
	var state: CombatState = session.state
	if state.phase_side != CombatFact.CombatSide.PLAYER or state.is_phase_ended:
		return "not the player phase"
	if state.ended_seats.has(seat):
		return "seat %d has ended its turn" % [seat]
	return ""


## Why [param unit_id] can't take its turn now: it isn't on the map, it isn't its side's phase, or
## (for a player unit) its seat has ended its turn.
static func unit_phase_reason(session: CombatSession, unit_id: String) -> String:
	var state: CombatState = session.state
	if not state.has_unit(unit_id):
		return "%s isn't on the map" % [unit_id]
	var side: CombatFact.CombatSide = state.side_of(unit_id)
	if side == CombatFact.CombatSide.PLAYER:
		return player_phase_reason(session, state.seat_of(unit_id))
	if side != CombatFact.CombatSide.ENEMY:
		return "%s takes no turns" % [unit_id]
	if state.phase_side != CombatFact.CombatSide.ENEMY or state.is_phase_ended:
		return "not the enemy phase"
	return ""
