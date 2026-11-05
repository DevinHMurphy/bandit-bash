# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     target_list.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name TargetList
extends RefCounted
## Every valid target of one chosen action, with a current target and a current weapon, moved by
## next and previous target and weapon, wrapping (combat UI plan, question 21; Godot_FE's
## [code]combat_map_unit_action_targetting_resource.gd[/code]).
##
## Device-free: keys, the mouse and the target picker all move the same list, so they send the
## same command. Built once from a [TurnInputModel.ActionOption] ([method build]), whose targets
## each hold one command per weapon the validator accepted
## ([member TurnInputModel.TargetOption.commands]), so nothing here re-derives a rule and nothing
## changes combat state.[br]
## [b]Weapon kept across targets:[/b] moving to another target keeps the current weapon when that
## target accepts it, else takes its first. Godot_FE cycled only the targets the current weapon
## reached; here every target is in the cycle, since every valid target is outlined and the mouse
## can pick any of them.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

var _targets: Array[TurnInputModel.TargetOption] = []
var _target_index: int = 0
var _weapon_index: int = 0


## [param targets]: the targets, in cycling order; [method build] passes an action's.
func _init(targets: Array[TurnInputModel.TargetOption] = []) -> void:
	_targets.assign(targets)


## How many targets there are.
func size() -> int:
	return _targets.size()


## Whether there are none.
func is_empty() -> bool:
	return _targets.is_empty()


## Every target, in cycling order.
func targets() -> Array[TurnInputModel.TargetOption]:
	return _targets.duplicate()


## The current target; null when the list is empty.
func current() -> TurnInputModel.TargetOption:
	return null if _targets.is_empty() else _targets[_target_index]


## The current target's place in [method targets]; 0 when empty.
func current_index() -> int:
	return _target_index


## Which of the current target's commands is current; 0 when empty.
func weapon_index() -> int:
	return _weapon_index


## How many weapons the current target accepts; 0 when empty.
func weapon_count() -> int:
	var target: TurnInputModel.TargetOption = current()
	return 0 if target == null else target.commands.size()


## The command for the current target and weapon; null when empty.
func command() -> Command:
	var target: TurnInputModel.TargetOption = current()
	if target == null or target.commands.is_empty():
		return null if target == null else target.command
	return target.commands[_weapon_index]


## The place of the first target on [param tile]; -1 for none.
func index_at(tile: Vector2i) -> int:
	for i: int in _targets.size():
		if _targets[i].tile == tile:
			return i
	return -1


## The place of [param target_id]; -1 for none.
func index_of(target_id: String) -> int:
	for i: int in _targets.size():
		if _targets[i].target_id == target_id:
			return i
	return -1


## Makes target [param index] current, keeping the weapon where it can (class doc). Returns
## whether the current target changed; false for the current one or an index out of range.
func select(index: int) -> bool:
	if index < 0 or index >= _targets.size() or index == _target_index:
		return false
	var key: String = weapon_key(command())
	_target_index = index
	_weapon_index = 0
	var commands: Array[Command] = _targets[index].commands
	for i: int in commands.size():
		if weapon_key(commands[i]) == key:
			_weapon_index = i
			break
	return true


## Moves to the next target, wrapping. Returns false, doing nothing, with fewer than two.
func next_target() -> bool:
	return _step_target(1)


## Moves to the previous target, wrapping. Returns false, doing nothing, with fewer than two.
func previous_target() -> bool:
	return _step_target(-1)


## Moves to the current target's next weapon, wrapping. Returns false, doing nothing, with fewer
## than two.
func next_weapon() -> bool:
	return _step_weapon(1)


## Moves to the current target's previous weapon, wrapping. Returns false, doing nothing, with
## fewer than two.
func previous_weapon() -> bool:
	return _step_weapon(-1)


## Goes back to the current target's first weapon (the one in hand).
func reset_weapon() -> void:
	_weapon_index = 0


func _step_target(step: int) -> bool:
	if _targets.size() < 2:
		return false
	return select(posmod(_target_index + step, _targets.size()))


func _step_weapon(step: int) -> bool:
	var count: int = weapon_count()
	if count < 2:
		return false
	_weapon_index = posmod(_weapon_index + step, count)
	return true


## The list of [param option]'s targets, in its order, the first current with its first weapon.
## Empty for an action with no targets.
static func build(option: TurnInputModel.ActionOption) -> TargetList:
	if option == null:
		return TargetList.new()
	return TargetList.new(option.targets)


## Which weapon [param command] uses: its [member UnitTurnCommand.weapon_id] (the stowed weapon,
## through Sidearm's free swap), or empty for the one in hand and for any other command.
static func weapon_key(command: Command) -> String:
	var turn: UnitTurnCommand = command as UnitTurnCommand
	return "" if turn == null else turn.weapon_id
