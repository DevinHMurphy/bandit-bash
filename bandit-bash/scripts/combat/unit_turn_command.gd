# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_turn_command.gd
# Author:
# Created:  October 28, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name UnitTurnCommand
extends Command
## One unit's turn as one command: a path, then one action (combat core plan, Commands). Player
## seats send it; enemies send it through [constant CombatHooks.Hook.ENEMY_COMMANDS] with seat -1.
##
## The move and the action are atomic: [method validate] walks the path and checks the action from
## its last tile on a sandbox copy of the engine, so a rejected turn changes nothing, and
## [method resolve] does the same for real. Actions: Wait, Attack (any weapon, attack staves
## included; [member weapon_id] may name the stowed weapon when Sidearm makes the swap free), use a
## Block or heal staff, Shove, use a Pouch item, swap weapons (the action), use a map object, and
## [constant Action.MOVE]: the second move after acting that
## [constant CombatValue.Permission.MAY_MOVE_AFTER_ACTING] allows, with the movement left.
## A staff of range 0 targets its user:
## the command names no target and the user is filled in (question 14). An attack always needs a
## target at range 1 or more. The action ends the unit's turn; it fires no Unit Turn End.[br]
## Before turn 1, in the opening swap window, the only action is [constant Action.OPENING_SWAP]
## (question 17); it records [constant CombatFact.Kind.UNIT_MOVED] for both units.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## What the unit does after moving. Sent over the network as an int: [b]append only[/b], with
## explicit values.
enum Action {
	## Ends the turn without acting ([constant CombatFact.Kind.UNIT_WAITED]).
	WAIT = 0,
	## Starts an exchange with [member target_id] ([ExchangeResolver]).
	ATTACK = 1,
	## Uses the Block or heal staff in the Weapon slot on [member target_id], or on the user when
	## the staff's range is 0 and no target is named ([StaffResolver]).
	STAFF = 2,
	## Shoves [member target_id] ([ShoveResolver]).
	SHOVE = 3,
	## Uses Pouch item [member item_id] on [member target_id]: itself or an adjacent ally
	## ([ItemUseResolver]).
	ITEM = 4,
	## Swaps the Weapon slot and the stowed weapon as the action ([WeaponSwap]).
	SWAP_WEAPON = 5,
	## Only moves: the second move after acting, while one is pending.
	MOVE = 6,
	## Trades tiles with [member target_id], another of the seat's units, both on deployment tiles,
	## in the opening swap window before turn 1 ([method AutoDeploy.check_opening_swap]). Takes no
	## path and ends no turn.
	OPENING_SWAP = 7,
	## Uses the map object [member target_id] (open, search, pull, light, take a passage), with
	## [member item_id] as the key or lockpick when it opens a lock ([method MapObjects.use]).
	USE_OBJECT = 8,
}

## The tiles the unit walks, starting on its own tile ([method CombatState.validate_path]). Empty:
## it stays where it is.
var path: Array[Vector2i] = []

## What it does after moving.
var action: Action = Action.WAIT

## The unit the action is aimed at. Empty for Wait, a weapon swap, a move, and a range-0 staff.
var target_id: String = ""

## The Pouch item an [constant Action.ITEM] uses, or the key or lockpick an
## [constant Action.USE_OBJECT] opens a lock with; empty for none.
var item_id: String = ""

## The weapon an [constant Action.ATTACK] uses: empty or the Weapon slot's for that weapon, the
## stowed weapon to swap it in first for free with Sidearm.
var weapon_id: String = ""


func _init(
		sender: int = -1,
		unit_id: String = "",
		turn_action: Action = Action.WAIT,
		action_target_id: String = "",
		walk: Array[Vector2i] = []
) -> void:
	seat = sender
	actor_id = unit_id
	action = turn_action
	target_id = action_target_id
	path = walk.duplicate()


func get_label() -> String:
	var action_name: String = (Action.find_key(action) as String).to_lower()
	if path.size() > 1 and action != Action.MOVE:
		return "move+%s" % [action_name]
	return action_name


func get_target_id() -> String:
	if action == Action.STAFF and target_id.is_empty():
		return actor_id
	return target_id


## Attacks, staves and shoves act on what their forecast showed; every other action only needs to
## be legal.
func needs_fresh_forecast() -> bool:
	return action == Action.ATTACK or action == Action.STAFF or action == Action.SHOVE


func validate(session: CombatSession) -> String:
	if action == Action.OPENING_SWAP:
		return _swap_reason(session)
	var reason: String = CommandValidator.unit_phase_reason(session, actor_id)
	if not reason.is_empty():
		return reason
	var unit: CombatUnitState = session.state.unit(actor_id)
	if action == Action.MOVE:
		if not unit.is_second_move_pending:
			return "%s has no move left after acting" % [actor_id]
	elif unit.has_acted:
		return "%s has acted" % [actor_id]
	# The path and the action are checked on a copy, so nothing real moves.
	var trial: EffectEngine = session.engine.copy_for_sandbox(ForcedRolls.new())
	var trial_state: CombatState = trial.state
	var check: CombatGrid.PathCheck = walk_path(trial, trial_state, actor_id, path)
	if not check.is_legal:
		return "path: %s" % [check.reason]
	return _action_reason(trial, trial_state)


func resolve(session: CombatSession) -> void:
	var engine: EffectEngine = session.engine
	var state: CombatState = session.state
	if action == Action.OPENING_SWAP:
		state.swap_units(actor_id, target_id)
		for unit_id: String in [actor_id, target_id]:
			var moved: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, unit_id)
			moved.tile = state.tile_of(unit_id)
			engine.record(moved)
		return
	walk_path(engine, state, actor_id, path)
	match action:
		Action.WAIT:
			state.wait(engine, actor_id)
		Action.ATTACK:
			if _uses_sidearm(state):
				WeaponSwap.resolve(engine, state, actor_id, true)
			ExchangeResolver.resolve(engine, state, actor_id, target_id)
		Action.STAFF:
			StaffResolver.resolve(engine, state, actor_id, _staff_target(engine))
		Action.SHOVE:
			ShoveResolver.resolve(engine, state, actor_id, target_id)
		Action.ITEM:
			ItemUseResolver.resolve(engine, state, actor_id, target_id, item_id)
		Action.SWAP_WEAPON:
			WeaponSwap.resolve(engine, state, actor_id, false)
		Action.USE_OBJECT:
			MapObjects.use(engine, state, actor_id, target_id, item_id)
		Action.MOVE:
			state.unit(actor_id).is_second_move_pending = false
			return
	if (
			state.has_unit(actor_id)
			and engine.stats(actor_id).is_allowed(CombatValue.Permission.MAY_MOVE_AFTER_ACTING)
	):
		state.unit(actor_id).is_second_move_pending = true


# Why the action can't be taken by a unit already standing at the path's end in state; empty when
# it can. Runs on a sandbox copy: a Sidearm swap before an attack happens there first.
func _action_reason(engine: EffectEngine, state: CombatState) -> String:
	match action:
		Action.WAIT, Action.MOVE:
			return ""
		Action.ATTACK:
			if target_id.is_empty() or target_id == actor_id:
				return "an attack needs a target at range 1 or more"
			if _uses_sidearm(state):
				var swap_reason: String = WeaponSwap.check(engine, state, actor_id, true)
				if not swap_reason.is_empty():
					return swap_reason
				WeaponSwap.resolve(engine, state, actor_id, true)
			elif not weapon_id.is_empty() and weapon_id != state.equipped_weapon_id(actor_id):
				return "%s doesn't hold %s" % [actor_id, weapon_id]
			return ExchangeResolver.check(engine, state, actor_id, target_id)
		Action.STAFF:
			var target: String = _staff_target(engine)
			if target.is_empty():
				return "the staff needs a target"
			return StaffResolver.check(engine, state, actor_id, target)
		Action.SHOVE:
			return ShoveResolver.check(engine, state, actor_id, target_id)
		Action.ITEM:
			return ItemUseResolver.check(engine, state, actor_id, target_id, item_id)
		Action.SWAP_WEAPON:
			return WeaponSwap.check(engine, state, actor_id, false)
		Action.USE_OBJECT:
			return MapObjects.check_use(engine, state, actor_id, target_id, item_id)
	return "unknown action %d" % [action]


# Why the opening swap can't be made now; empty when it can.
func _swap_reason(session: CombatSession) -> String:
	var reason: String = CommandValidator.swap_window_reason(session, seat)
	if not reason.is_empty():
		return reason
	if path.size() > 1:
		return "a swap takes no path"
	return AutoDeploy.check_opening_swap(
			session.state,
			seat,
			actor_id,
			target_id,
			session.layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT)
	)


# The staff's target: the one named, else the user for a range-0 staff; empty when neither.
func _staff_target(engine: EffectEngine) -> String:
	if not target_id.is_empty():
		return target_id
	if engine.stats(actor_id).get_int(CombatValue.Key.RANGE_MAX) == 0:
		return actor_id
	return ""


# Whether the attack names the stowed weapon, which Sidearm swaps in for free first.
func _uses_sidearm(state: CombatState) -> bool:
	var unit: CombatUnitState = state.unit(actor_id)
	return (
			not weapon_id.is_empty()
			and weapon_id != unit.equipped_weapon_id
			and weapon_id == unit.stowed_weapon_id
	)


## Walks [param unit_id] along [param path] in [param state]: checks it
## ([method CombatState.validate_path]; an empty path stays on the unit's tile) and, if it is legal
## and leaves the tile, moves the unit to its last tile, adds the tiles and movement cost to its
## turn, and records [constant CombatFact.Kind.UNIT_MOVED]. An illegal path changes nothing.
## The command and [CombatForecast] both walk through this, so a forecast walks as the command
## does. Returns the path's check.
static func walk_path(
		engine: EffectEngine, state: CombatState, unit_id: String, path: Array[Vector2i]
) -> CombatGrid.PathCheck:
	var walk: Array[Vector2i] = path
	if walk.is_empty():
		walk = [state.tile_of(unit_id)]
	var check: CombatGrid.PathCheck = state.validate_path(engine, unit_id, walk)
	if not check.is_legal or check.tiles_moved == 0:
		return check
	var end: Vector2i = walk[walk.size() - 1]
	state.move_unit(unit_id, end)
	var unit: CombatUnitState = state.unit(unit_id)
	unit.tiles_moved += check.tiles_moved
	unit.movement_spent += check.cost
	var moved: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, unit_id)
	moved.tile = end
	engine.record(moved)
	return check
