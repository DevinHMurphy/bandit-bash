# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     turn_input_model.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name TurnInputModel
extends RefCounted
## What turn input offers a seat, as plain data read from a [CombatSession]: which units can act,
## each one's move and attack tiles, the walk to a tile, the legal actions and targets there, the
## opening swap's partners and End Turn.
##
## Every action and target holds a built command that its own [method Command.validate] accepted
## on the session as it stands ([UnitTurnCommand], [CastRuneCommand], [EndTurnCommand]); the
## [CommandValidator] phase checks run inside those. So a menu lists only what the session would
## accept, and nothing here re-derives a rule. Reading only: validation runs on sandbox copies and
## nothing changes the session. [BattleController] draws it; tests check it without rendering
## (combat UI plan, question 13). Targets are labelled by name ([method BattleText.name_of]).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The actions a unit's menu can list (combat UI plan, questions 6 and 15 f). The menu lists them
## in [constant MENU_ORDER], not by value: values are only appended.
enum ActionKind {
	## An exchange with an enemy ([constant UnitTurnCommand.Action.ATTACK]).
	ATTACK = 0,
	## The Block or heal staff in the Weapon slot ([constant UnitTurnCommand.Action.STAFF]).
	STAFF = 1,
	## The Pouch item, on the unit or an adjacent ally ([constant UnitTurnCommand.Action.ITEM]).
	ITEM = 2,
	## A shove ([constant UnitTurnCommand.Action.SHOVE]).
	SHOVE = 3,
	## The weapon swap as the action ([constant UnitTurnCommand.Action.SWAP_WEAPON]).
	SWAP = 4,
	## A rune from the seat's slots ([CastRuneCommand]); acts for no unit.
	RUNE = 5,
	## Ends the unit's turn where it stands; with a second move pending, ends that move
	## ([constant UnitTurnCommand.Action.MOVE]).
	WAIT = 6,
	## A map object at the tile picked: visit a house, open a chest or door, pull a lever, take a
	## passage, light a brazier ([constant UnitTurnCommand.Action.USE_OBJECT]).
	USE = 7,
}

## The menu label of each [enum ActionKind], by value.
const ACTION_LABELS: Array[String] = [
	"Attack",
	"Staff",
	"Item",
	"Shove",
	"Swap",
	"Rune",
	"Wait",
	"Use",
]

# ASSUMPTION: Use goes after Shove, as game-vision.md's action table lists map objects after Shove;
# the plan's question 6 order names no Use.
## The order the menu lists actions in.
const MENU_ORDER: Array[ActionKind] = [
	ActionKind.ATTACK,
	ActionKind.STAFF,
	ActionKind.ITEM,
	ActionKind.SHOVE,
	ActionKind.USE,
	ActionKind.SWAP,
	ActionKind.RUNE,
	ActionKind.WAIT,
]

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY


## Whether [param unit_id] can still take its turn now: a player unit, in its seat's player phase,
## that hasn't acted or has a second move pending ([member CombatUnitState.is_second_move_pending]).
static func can_act(session: CombatSession, unit_id: String) -> bool:
	var state: CombatState = session.state
	if not state.has_unit(unit_id) or state.side_of(unit_id) != PLAYER:
		return false
	if not CommandValidator.unit_phase_reason(session, unit_id).is_empty():
		return false
	var unit: CombatUnitState = state.unit(unit_id)
	return not unit.has_acted or unit.is_second_move_pending


## Whether [param unit_id] can act only by moving: it acted and has its second move pending.
static func is_second_move(session: CombatSession, unit_id: String) -> bool:
	var unit: CombatUnitState = session.state.unit(unit_id)
	return unit != null and unit.has_acted and unit.is_second_move_pending


## The units of [param seat] that [method can_act], in state order.
static func acting_units(session: CombatSession, seat: int) -> PackedStringArray:
	var found: PackedStringArray = []
	for unit_id: String in session.state.units_of(PLAYER):
		if session.state.seat_of(unit_id) == seat and can_act(session, unit_id):
			found.append(unit_id)
	return found


## Every tile [param unit_id] can end its move on now ([method Pathing.reach]), its own tile
## included, in row-major order.
static func move_tiles(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(Pathing.reach(session.engine, session.state, unit_id).keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


## Every map tile [param unit_id] could attack from some tile of [method move_tiles], with each
## weapon [method DangerZone.attack_ranges] counts, less the move tiles themselves (drawn as move
## tiles), in row-major order. Empty for a unit that has acted.
static func attack_tiles(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var state: CombatState = session.state
	if not state.has_unit(unit_id) or state.unit(unit_id).has_acted:
		return tiles
	var spans: Array[Vector2i] = DangerZone.attack_ranges(session.engine, unit_id)
	var ends: Dictionary[Vector2i, int] = Pathing.reach(session.engine, state, unit_id)
	var covered: Dictionary[Vector2i, bool] = {}
	for end: Vector2i in ends:
		for span: Vector2i in spans:
			for tile: Vector2i in DangerZone.tiles_within(end, span):
				if not ends.has(tile) and _is_on_map(state, tile):
					covered[tile] = true
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


## Every tile [param enemy_id] could move to or attack next phase, in row-major order: the free
## tiles its full movement reaches and its [method DangerZone.tiles_for] (Godot_FE's selected
## unit range, [code]CombatUnitRangeManager.gd[/code]).
static func enemy_range_tiles(session: CombatSession, enemy_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var state: CombatState = session.state
	if not state.has_unit(enemy_id):
		return tiles
	var mover: CombatUnitState = state.unit(enemy_id)
	# Next phase's full movement, as DangerZone.tiles_for reads it.
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			session.stats(enemy_id).get_int(CombatValue.Key.MOVEMENT),
			mover.movement_type,
			mover.side
	)
	var covered: Dictionary[Vector2i, bool] = {}
	for end: Vector2i in walked:
		var occupant: String = state.occupant_at(end)
		if occupant.is_empty() or occupant == enemy_id:
			covered[end] = true
	for tile: Vector2i in DangerZone.tiles_for(session.engine, enemy_id):
		covered[tile] = true
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


## The walk [param unit_id] takes to [param tile], one of its [method move_tiles], starting on its
## own tile: a cheapest walk, each step back to the first neighbor in
## [constant CombatGrid.DIRECTIONS] order whose cost leads to it, as the enemies walk
## ([method Intents.preview]). This is the [member UnitTurnCommand.path] the command is sent with,
## and so what [method UnitTurnCommand.walk_path] walks. Empty for its own tile or a tile it
## can't end on.
static func path_to(session: CombatSession, unit_id: String, tile: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var state: CombatState = session.state
	if not state.has_unit(unit_id):
		return path
	var mover: CombatUnitState = state.unit(unit_id)
	if tile == mover.tile or not Pathing.reach(session.engine, state, unit_id).has(tile):
		return path
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(session.engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
	path.append(tile)
	var at: Vector2i = tile
	while at != mover.tile:
		var entry: int = state.grid.move_cost(at, mover.movement_type)
		var came_from: Vector2i = CombatFact.NO_TILE
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			var before: Vector2i = state.grid.step(at, direction)
			if walked.has(before) and walked[before] + entry == walked[at]:
				came_from = before
				break
		if came_from == CombatFact.NO_TILE:
			path.clear()
			return path
		path.push_front(came_from)
		at = came_from
	return path


## Every action [param unit_id] can take after walking [param path] ([method path_to]; empty to
## stay), in [constant MENU_ORDER], each with at least one legal command. A unit with a second
## move pending gets only Wait, which ends that move ([constant UnitTurnCommand.Action.MOVE]).
## Use lists each map object whose use the session accepts from the path's end, with no item or
## else the unit's Pouch item (a key or lockpick). Empty when it can't act.
static func actions_at(
		session: CombatSession, unit_id: String, path: Array[Vector2i]
) -> Array[ActionOption]:
	var options: Array[ActionOption] = []
	if not can_act(session, unit_id):
		return options
	var state: CombatState = session.state
	var seat: int = state.seat_of(unit_id)
	if is_second_move(session, unit_id):
		_add_untargeted(options, ActionKind.WAIT, _turn(
				session, unit_id, UnitTurnCommand.Action.MOVE, "", path
		))
		return options
	var unit: CombatUnitState = state.unit(unit_id)
	var attack: ActionOption = ActionOption.new(ActionKind.ATTACK)
	var weapons: PackedStringArray = [""]
	if not unit.stowed_weapon_id.is_empty() and unit.stowed_weapon_id != unit.equipped_weapon_id:
		weapons.append(unit.stowed_weapon_id)
	for enemy_id: String in state.units_of(ENEMY):
		var found: TargetOption = null
		for weapon_id: String in weapons:
			var command: UnitTurnCommand = _turn(
					session, unit_id, UnitTurnCommand.Action.ATTACK, enemy_id, path, weapon_id
			)
			if command == null:
				continue
			if found == null:
				found = _target(session, enemy_id, command)
				attack.targets.append(found)
			else:
				found.commands.append(command)
	_add_targeted(options, attack)

	var staff: ActionOption = ActionOption.new(ActionKind.STAFF)
	var on_self: UnitTurnCommand = _turn(session, unit_id, UnitTurnCommand.Action.STAFF, "", path)
	if on_self != null:
		staff.targets.append(_target(session, unit_id, on_self))
	for target_id: String in state.unit_ids():
		if on_self != null and target_id == unit_id:
			continue
		var command: UnitTurnCommand = _turn(
				session, unit_id, UnitTurnCommand.Action.STAFF, target_id, path
		)
		if command != null:
			staff.targets.append(_target(session, target_id, command))
	_add_targeted(options, staff)

	var item: ActionOption = ActionOption.new(ActionKind.ITEM)
	if not unit.pouch_item_id.is_empty():
		for target_id: String in state.units_of(PLAYER):
			var command: UnitTurnCommand = _turn(
					session, unit_id, UnitTurnCommand.Action.ITEM, target_id, path
			)
			if command != null:
				item.targets.append(_target(session, target_id, command))
	_add_targeted(options, item)

	var shove: ActionOption = ActionOption.new(ActionKind.SHOVE)
	for target_id: String in state.unit_ids():
		if target_id == unit_id:
			continue
		var command: UnitTurnCommand = _turn(
				session, unit_id, UnitTurnCommand.Action.SHOVE, target_id, path
		)
		if command != null:
			shove.targets.append(_target(session, target_id, command))
	_add_targeted(options, shove)

	var use: ActionOption = ActionOption.new(ActionKind.USE)
	for placed: MapState.ObjectState in _standing_objects(state):
		var command: UnitTurnCommand = _turn(
				session, unit_id, UnitTurnCommand.Action.USE_OBJECT, placed.id, path
		)
		if command == null and not unit.pouch_item_id.is_empty():
			command = _turn(
					session, unit_id, UnitTurnCommand.Action.USE_OBJECT, placed.id, path, "",
					unit.pouch_item_id
			)
		if command != null:
			var option: TargetOption = _target(session, placed.id, command)
			option.tile = placed.tile
			use.targets.append(option)
	_add_targeted(options, use)

	_add_untargeted(options, ActionKind.SWAP, _turn(
			session, unit_id, UnitTurnCommand.Action.SWAP_WEAPON, "", path
	))

	# ASSUMPTION: a rune is offered only on the unit's own tile. A cast acts for no unit and
	# carries no path, so offering it after a move would drop the move; Recall (two targets)
	# isn't offered until the rune catalog (P03) says which rune is Recall.
	if path.size() <= 1:
		var rune: ActionOption = ActionOption.new(ActionKind.RUNE)
		var slots: PackedStringArray = state.rune_slots.get(seat, PackedStringArray())
		for rune_id: String in slots:
			for target_id: String in state.unit_ids():
				var cast: CastRuneCommand = CastRuneCommand.new(seat, rune_id, target_id)
				if cast.validate(session).is_empty():
					var option: TargetOption = _target(session, target_id, cast)
					option.label = "%s on %s" % [
						BattleText.name_of(session, rune_id), option.label,
					]
					rune.targets.append(option)
		_add_targeted(options, rune)

	_add_untargeted(options, ActionKind.WAIT, _turn(
			session, unit_id, UnitTurnCommand.Action.WAIT, "", path
	))
	return options


## Whether [param seat] is in the opening swap window, before its Start
## ([method CommandValidator.swap_window_reason]).
static func is_swapping(session: CombatSession, seat: int) -> bool:
	return CommandValidator.swap_window_reason(session, seat).is_empty()


## Every unit [param unit_id] may trade tiles with in the opening swap window, each with its
## [constant UnitTurnCommand.Action.OPENING_SWAP] command, in state order. Empty outside the window.
static func swap_partners(session: CombatSession, unit_id: String) -> Array[TargetOption]:
	var partners: Array[TargetOption] = []
	var state: CombatState = session.state
	if not state.has_unit(unit_id):
		return partners
	var seat: int = state.seat_of(unit_id)
	for other_id: String in state.units_of(PLAYER):
		if other_id == unit_id or state.seat_of(other_id) != seat:
			continue
		var swap: UnitTurnCommand = UnitTurnCommand.new(
				seat, unit_id, UnitTurnCommand.Action.OPENING_SWAP, other_id
		)
		if swap.validate(session).is_empty():
			partners.append(_target(session, other_id, swap))
	return partners


## [param seat]'s End Turn when the session would accept it now; null when it wouldn't.
static func end_turn_command(session: CombatSession, seat: int) -> EndTurnCommand:
	var command: EndTurnCommand = EndTurnCommand.new(seat)
	return command if command.validate(session).is_empty() else null


## [param seat]'s Start in the opening swap window when the session would accept it now; null
## when it wouldn't.
static func start_command(session: CombatSession, seat: int) -> StartCommand:
	var command: StartCommand = StartCommand.new(seat)
	return command if command.validate(session).is_empty() else null


# A unit-turn command for unit_id when its validate() accepts it on session; null otherwise. An
# Item always uses the Pouch item; any other action uses item_id (a key or lockpick for a use).
static func _turn(
		session: CombatSession,
		unit_id: String,
		action: UnitTurnCommand.Action,
		target_id: String,
		path: Array[Vector2i],
		weapon_id: String = "",
		item_id: String = ""
) -> UnitTurnCommand:
	var command: UnitTurnCommand = UnitTurnCommand.new(
			session.state.seat_of(unit_id), unit_id, action, target_id, path
	)
	command.weapon_id = weapon_id
	command.item_id = item_id
	if action == UnitTurnCommand.Action.ITEM:
		command.item_id = session.state.unit(unit_id).pouch_item_id
	return command if command.validate(session).is_empty() else null


# The map's objects not broken off it, in spot order: what a Use is tried on. The validator says
# which of them the unit can use.
static func _standing_objects(state: CombatState) -> Array[MapState.ObjectState]:
	var standing: Array[MapState.ObjectState] = []
	for placed: MapState.ObjectState in state.map.objects.values():
		if not placed.is_destroyed:
			standing.append(placed)
	standing.sort_custom(func(a: MapState.ObjectState, b: MapState.ObjectState) -> bool:
		return a.index < b.index
	)
	return standing


static func _target(session: CombatSession, target_id: String, command: Command) -> TargetOption:
	var option: TargetOption = TargetOption.new()
	option.target_id = target_id
	option.tile = session.state.tile_of(target_id)
	option.label = BattleText.name_of(session, target_id)
	option.command = command
	option.commands.append(command)
	return option


static func _add_targeted(options: Array[ActionOption], option: ActionOption) -> void:
	if not option.targets.is_empty():
		options.append(option)


static func _add_untargeted(
		options: Array[ActionOption], kind: ActionKind, command: Command
) -> void:
	if command == null:
		return
	var option: ActionOption = ActionOption.new(kind)
	option.command = command
	options.append(option)


static func _is_on_map(state: CombatState, tile: Vector2i) -> bool:
	return state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE


## One action a unit's menu lists.
class ActionOption:
	extends RefCounted

	## Which action.
	var kind: ActionKind = ActionKind.WAIT
	## Its menu label ([constant TurnInputModel.ACTION_LABELS]).
	var label: String = ""
	## Its targets, each with its own command; empty for an action with no target.
	var targets: Array[TargetOption] = []
	## The command an action with no target sends; null for an action with targets.
	var command: Command = null

	func _init(action_kind: ActionKind = ActionKind.WAIT) -> void:
		kind = action_kind
		label = TurnInputModel.ACTION_LABELS[action_kind]

	## Whether a target is picked before the command is sent.
	func has_targets() -> bool:
		return command == null


## One target an action can be aimed at, with the command that aims it there.
class TargetOption:
	extends RefCounted

	## The target's instance id: a unit's, or a map object's for Use.
	var target_id: String = ""
	## Its tile, where the cursor shows it.
	var tile: Vector2i = CombatFact.NO_TILE
	## Its label in the target picker: its name ([method BattleText.name_of]).
	var label: String = ""
	## The command sent when this target is confirmed: the first of [member commands].
	var command: Command = null
	## Every command that aims the action here: for an attack, one per weapon the session accepts
	## (the one in hand first, then the stowed one through Sidearm's free swap), which the forecast
	## cycles; otherwise only [member command].
	var commands: Array[Command] = []
