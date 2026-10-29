# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     phase_runner.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name PhaseRunner
extends RefCounted
## The turn loop of one map: Phase Start and Phase End for each side, the enemy phase as one
## command, and the [CombatHooks] other plans register into (combat core plan, Turn and phase
## loop).
##
## [b]Battle start[/b] ([method open_battle]): with a seat's opening-swap setting on, the battle
## opens in the swap window before turn 1, and turn 1's player Phase Start runs once every such
## seat has sent Start ([method start]); with it off, Phase Start runs at once.[br]
## A turn is one player phase, then one enemy phase; [member CombatState.turn] rises at the player
## Phase Start. [b]Phase Start[/b], in order: (player only) [constant CombatHooks.Hook.ARRIVALS];
## each unit of the side has its Block cleared and Stance set to its maximum
## ([constant CombatFact.Kind.BLOCK_STANCE_REFRESHED]); terrain healing; one
## [constant CombatFact.Kind.PHASE_START]; [constant CombatFact.Kind.UNIT_TURN_START] for each unit
## in placement order (roster, then spawn); the drain; then, for the player side,
## [constant CombatHooks.Hook.INTENTS]. [b]Phase End[/b] mirrors it:
## [constant CombatFact.Kind.PHASE_END], [constant CombatFact.Kind.UNIT_TURN_END] for each unit,
## the drain, [constant CombatHooks.Hook.PHASE_END_EFFECTS], the drain again, then "until Phase
## End" modifiers expire. A unit's action ends its turn but fires no Unit Turn End of its own.[br]
## The last seat's end turn resolves, as one command: player Phase End, enemy Phase Start, each
## enemy's turn, enemy Phase End, [constant CombatHooks.Hook.AFTER_ENEMY_PHASE], and the next
## player Phase Start. Every step ends with [constant CombatHooks.Hook.AFTER_STEP]
## ([method end_step]); once the map's combat has ended, nothing more runs.[br]
## Pure rules code on the session's state and engine: it never awaits and records every change as
## a fact. Main thread only.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## How many commands the [constant CombatHooks.Hook.ENEMY_COMMANDS] hook may give per enemy on the
## map at the enemy Phase Start: its action, and a second move after acting. More is an AI fault,
## reported as a diagnostic, and the side's turns end.
const ENEMY_COMMANDS_PER_UNIT: int = 2


## Opens the battle on [param session] once its army is deployed. When any of [param swap_seats]
## (the seats whose opening-swap setting is on) has units on the map, opens the opening swap
## window instead ([member MapState.opening_swap_open], [member CombatState.seats_to_start]) and
## records nothing; turn 1 waits for their Start commands ([method start]). Otherwise runs turn
## 1's player Phase Start, then the step's end. Records outside any command; the caller flushes
## the batch.
static func open_battle(
		session: CombatSession, swap_seats: PackedInt32Array = PackedInt32Array()
) -> void:
	var waiting: PackedInt32Array = []
	for seat: int in seats_with_units(session):
		if swap_seats.has(seat):
			waiting.append(seat)
	if not waiting.is_empty():
		session.state.seats_to_start = waiting
		session.state.map.opening_swap_open = true
		return
	_phase_start(session, CombatFact.CombatSide.PLAYER)
	end_step(session)


## [param seat]'s Start in the opening swap window. When no seat is left to start, closes the
## window and runs turn 1's player Phase Start, so position effects read the tiles after every
## swap. The session ends the step ([method CombatSession.resolve_next]).
static func start(session: CombatSession, seat: int) -> void:
	var state: CombatState = session.state
	var index: int = state.seats_to_start.find(seat)
	if index >= 0:
		state.seats_to_start.remove_at(index)
	if not state.seats_to_start.is_empty():
		return
	state.map.opening_swap_open = false
	_phase_start(session, CombatFact.CombatSide.PLAYER)


## Ends [param seat]'s turn in the player phase. When every seat with units on the map has ended,
## resolves the rest of the turn as one command: player Phase End, the enemy phase and the next
## player Phase Start. The session ends the last step ([method CombatSession.resolve_next]).
static func end_turn(session: CombatSession, seat: int) -> void:
	session.state.ended_seats.append(seat)
	if not seats_to_end(session).is_empty():
		return
	_phase_end(session, CombatFact.CombatSide.PLAYER)
	if not end_step(session):
		return
	_phase_start(session, CombatFact.CombatSide.ENEMY)
	if not end_step(session):
		return
	if not _enemy_turns(session):
		return
	_phase_end(session, CombatFact.CombatSide.ENEMY)
	if not end_step(session):
		return
	for run: Callable in session.hooks.get_registered(CombatHooks.Hook.AFTER_ENEMY_PHASE):
		session.engine.begin_step()
		run.call(session)
		session.engine.drain()
		if not end_step(session):
			return
	_phase_start(session, CombatFact.CombatSide.PLAYER)


## Ends a resolution step: [constant CombatHooks.Hook.AFTER_STEP] in registration order, then the
## drain. Skipped once the map's combat has ended. Returns whether the combat goes on.
static func end_step(session: CombatSession) -> bool:
	if session.is_finished:
		return false
	for run: Callable in session.hooks.get_registered(CombatHooks.Hook.AFTER_STEP):
		run.call(session)
		session.engine.drain()
	return not session.is_finished


## The seats of [param session] with units on its map that haven't ended their turn this player
## phase, ascending. The player phase ends when none is left.
static func seats_to_end(session: CombatSession) -> PackedInt32Array:
	var waiting: PackedInt32Array = []
	for seat: int in seats_with_units(session):
		if not session.state.ended_seats.has(seat):
			waiting.append(seat)
	return waiting


## The seats of [param session] that have at least one unit on its map, ascending.
static func seats_with_units(session: CombatSession) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for unit_id: String in session.state.units_of(CombatFact.CombatSide.PLAYER):
		var seat: int = session.state.seat_of(unit_id)
		if session.seats.has(seat) and not found.has(seat):
			found.append(seat)
	found.sort()
	return found


static func _phase_start(session: CombatSession, side: CombatFact.CombatSide) -> void:
	var state: CombatState = session.state
	var engine: EffectEngine = session.engine
	engine.begin_step()
	if side == CombatFact.CombatSide.PLAYER:
		for run: Callable in session.hooks.get_registered(CombatHooks.Hook.ARRIVALS):
			run.call(session)
		state.turn += 1
		state.ended_seats.clear()
	state.phase_side = side
	state.is_phase_ended = false
	# A unit can be shoved once per phase, whichever side's phase it is.
	for unit_id: String in state.unit_ids():
		state.unit(unit_id).has_been_shoved = false

	var units: PackedStringArray = state.units_of(side)
	for unit_id: String in units:
		_refresh(engine, state, unit_id)
	for unit_id: String in units:
		_heal_on_terrain(session, unit_id)
	var started: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_START)
	started.side = side
	started.amount = state.turn
	engine.record(started)
	for unit_id: String in state.units_of(side):
		var turn_start: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_TURN_START, unit_id)
		turn_start.tile = state.tile_of(unit_id)
		engine.record(turn_start)
	engine.drain()
	if side == CombatFact.CombatSide.PLAYER:
		for run: Callable in session.hooks.get_registered(CombatHooks.Hook.INTENTS):
			run.call(session)
			engine.drain()


static func _phase_end(session: CombatSession, side: CombatFact.CombatSide) -> void:
	var state: CombatState = session.state
	var engine: EffectEngine = session.engine
	engine.begin_step()
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_END)
	ended.side = side
	engine.record(ended)
	for unit_id: String in state.units_of(side):
		var turn_end: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_TURN_END, unit_id)
		turn_end.tile = state.tile_of(unit_id)
		engine.record(turn_end)
	# Phase End and Unit Turn End effects land before the darkness (combat core plan, question 12).
	engine.drain()
	for run: Callable in session.hooks.get_registered(CombatHooks.Hook.PHASE_END_EFFECTS):
		run.call(session, side)
	engine.drain()
	engine.reach_boundary(EffectEngine.Boundary.PHASE_END)
	state.is_phase_ended = true


# Each enemy's turn, one step each. Returns whether the combat goes on.
static func _enemy_turns(session: CombatSession) -> bool:
	var state: CombatState = session.state
	var engine: EffectEngine = session.engine
	if not session.hooks.has_registered(CombatHooks.Hook.ENEMY_COMMANDS):
		for unit_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
			if not state.has_unit(unit_id) or state.unit(unit_id).has_acted:
				continue
			engine.begin_step()
			state.wait(engine, unit_id)
			engine.drain()
			if not end_step(session):
				return false
		return true

	var limit: int = ENEMY_COMMANDS_PER_UNIT * state.units_of(CombatFact.CombatSide.ENEMY).size()
	for given: int in limit + 1:
		var command: Command = _next_enemy_command(session)
		if command == null:
			return true
		if given == limit:
			engine.diagnostics.append(
					"PhaseRunner: ENEMY_COMMANDS gave more than %d commands" % [limit]
			)
			return true
		var reason: String = _enemy_command_reason(session, command)
		if not reason.is_empty():
			engine.diagnostics.append(
					"PhaseRunner: enemy %s %s rejected - %s"
					% [command.get_label(), command.actor_id, reason]
			)
			continue
		engine.begin_step()
		command.resolve(session)
		engine.drain()
		if not end_step(session):
			return false
	return true


static func _next_enemy_command(session: CombatSession) -> Command:
	for run: Callable in session.hooks.get_registered(CombatHooks.Hook.ENEMY_COMMANDS):
		var command: Command = run.call(session)
		if command != null:
			return command
	return null


# The checks the session's queue makes, for a command no seat sent: it acts for an enemy, which
# has no seat.
static func _enemy_command_reason(session: CombatSession, command: Command) -> String:
	var state: CombatState = session.state
	if (
			command.actor_id.is_empty()
			or state.side_of(command.actor_id) != CombatFact.CombatSide.ENEMY
			or state.seat_of(command.actor_id) != command.seat
	):
		return "not an enemy's command"
	return command.validate(session)


# Phase Start step 1: Block 0 and full Stance, and the turn's own state cleared.
static func _refresh(engine: EffectEngine, state: CombatState, unit_id: String) -> void:
	var unit: CombatUnitState = state.unit(unit_id)
	unit.has_acted = false
	unit.tiles_moved = 0
	unit.movement_spent = 0
	unit.is_second_move_pending = false
	unit.has_used_sidearm = false
	state.set_block(unit_id, 0)
	state.set_stance(unit_id, engine.stats(unit_id).get_int(CombatValue.Key.STANCE_MAX))
	engine.record(CombatFact.new(CombatFact.Kind.BLOCK_STANCE_REFRESHED, unit_id))


# Phase Start step 2: the tile's flat and percent healing, through the engine's one heal path, for
# a damaged unit whose heal no TERRAIN_HEALING_ALLOWED registration stops.
static func _heal_on_terrain(session: CombatSession, unit_id: String) -> void:
	var state: CombatState = session.state
	var bonus: CombatGrid.TileBonus = state.grid.tile_bonus(state.tile_of(unit_id))
	if bonus.heal_flat <= 0 and bonus.heal_percent <= 0:
		return
	var max_hp: int = session.engine.stats(unit_id).get_int(CombatValue.Key.HP)
	if state.get_hp(unit_id) >= max_hp:
		return
	for run: Callable in session.hooks.get_registered(CombatHooks.Hook.TERRAIN_HEALING_ALLOWED):
		var is_allowed: bool = run.call(session, unit_id)
		if not is_allowed:
			return
	# ASSUMPTION: the percent part is exact and the heal path rounds the total once, half up
	# (event bus plan, questions 17 and 29); Godot_FE floored the percent part on its own.
	var amount: float = bonus.heal_flat + max_hp * bonus.heal_percent / 100.0
	session.engine.heal(unit_id, amount)
