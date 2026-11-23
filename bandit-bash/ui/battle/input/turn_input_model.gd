# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     turn_input_model.gd
# Author:
# Created:  November 4, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name TurnInputModel
extends RefCounted
## What turn input offers a seat, as plain data read from a [CombatSession]: which units can act
## (and the cycle through them), each one's move, attack and support tiles, an enemy's range and
## the danger zone's support tiles, the walk to a tile, the legal actions and targets there, the
## opening swap's partners and End Turn.
##
## Every action and target holds a built command that its own [method Command.validate] accepted
## on the session as it stands ([UnitTurnCommand], [CastRuneCommand], [EndTurnCommand]); the
## [CommandValidator] phase checks run inside those. So a menu lists only what the session would
## accept, and nothing here re-derives a rule. Runes come by kind ([method rune_options]): Recall's
## first unit holds its partners' commands; the rune bar reads [method held_runes]. Reading only:
## validation runs on sandbox copies and nothing changes the session. [BattleController] draws it;
## tests check it without rendering
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
	## A rune from the seat's slots ([CastRuneCommand]); acts for no unit. Its option lists
	## [member ActionOption.runes], not targets.
	RUNE = 5,
	## Ends the unit's turn where it stands; with a second move pending, ends that move
	## ([constant UnitTurnCommand.Action.MOVE] to another tile, a Wait where it stands).
	WAIT = 6,
	## A map object at the tile picked: visit a house, open a chest or door, pull a lever, take a
	## passage, light a brazier ([constant UnitTurnCommand.Action.USE_OBJECT]).
	USE = 7,
	## An exchange with a standing breakable, debris or a powder keg: the same
	## [constant UnitTurnCommand.Action.ATTACK], kept apart from Attack (Godot_FE's Demolish) so a
	## misclick on Attack never hits an object.
	DEMOLISH = 8,
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
	"Demolish",
]

# ASSUMPTION: Use goes after Shove, as game-vision.md's action table lists map objects after Shove;
# the plan's question 6 order names no Use.
## The order the menu lists actions in. Demolish follows Staff, as Godot_FE listed Attack,
## Support, Demolish.
const MENU_ORDER: Array[ActionKind] = [
	ActionKind.ATTACK,
	ActionKind.STAFF,
	ActionKind.DEMOLISH,
	ActionKind.ITEM,
	ActionKind.SHOVE,
	ActionKind.USE,
	ActionKind.SWAP,
	ActionKind.RUNE,
	ActionKind.WAIT,
]

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# ASSUMPTION: the three refusal wordings; no design doc words them.
## Why a rune with [member RuneDefinition.needs_unacted_target] refuses a unit (Haste).
const ACTED_REASON: String = "has acted"

## Why a unit rune refuses a unit of its side for any other reason.
const REFUSED_REASON: String = "can't take it now"

## Why Recall refuses one of the seat's units: none of the others can trade tiles with it.
const NO_PARTNER_REASON: String = "can't swap with any of your units"

# ASSUMPTION: the wording; no design doc words it.
## Why the rune bar can't cast a held rune now: nothing on the map is a legal target for it.
const NO_TARGET_REASON: String = "no target now"


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
## unit range, [code]CombatUnitRangeManager.gd[/code]), drawn red. Empty for a unit that holds
## nothing that attacks ([method DangerZone.attack_ranges]), such as a healer: its reach is
## support, in [method enemy_support_tiles].
static func enemy_range_tiles(session: CombatSession, enemy_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var state: CombatState = session.state
	if not state.has_unit(enemy_id):
		return tiles
	if DangerZone.attack_ranges(session.engine, enemy_id).is_empty():
		return tiles
	var covered: Dictionary[Vector2i, bool] = {}
	for end: Vector2i in _next_phase_ends(session, enemy_id):
		covered[end] = true
	for tile: Vector2i in DangerZone.tiles_for(session.engine, enemy_id):
		covered[tile] = true
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


# ASSUMPTION: support is a Block or heal staff in hand. Pouch items on allies (one tile) and runes
# aren't drawn as support ranges, and no staff kind buffs yet (the vision's "buff").
## Each range [param unit_id] could support at, as (shortest, longest): the Block or heal staff
## in its Weapon slot, the only one the Staff action uses ([method StaffResolver.check]). Empty
## when it holds none.
static func support_ranges(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	var state: CombatState = session.state
	if not state.has_unit(unit_id):
		return spans
	var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
	if held == null or not held.is_staff() or held.staff == CombatState.WeaponStats.Staff.ATTACK:
		return spans
	var sheet: StatSheet = session.stats(unit_id)
	spans.append(Vector2i(
			sheet.get_int(CombatValue.Key.RANGE_MIN), sheet.get_int(CombatValue.Key.RANGE_MAX)
	))
	return spans


## Every map tile [param unit_id] could support from some tile of [method move_tiles]
## ([method support_ranges]), less its move tiles and its [method attack_tiles], in row-major
## order: the selection's purple tiles. Empty for a unit that has acted.
static func support_tiles(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var state: CombatState = session.state
	if not state.has_unit(unit_id) or state.unit(unit_id).has_acted:
		return tiles
	var spans: Array[Vector2i] = support_ranges(session, unit_id)
	if spans.is_empty():
		return tiles
	var ends: Dictionary[Vector2i, int] = Pathing.reach(session.engine, state, unit_id)
	var red: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in attack_tiles(session, unit_id):
		red[tile] = true
	var covered: Dictionary[Vector2i, bool] = {}
	for end: Vector2i in ends:
		for span: Vector2i in spans:
			for tile: Vector2i in DangerZone.tiles_within(end, span):
				if not ends.has(tile) and not red.has(tile) and _is_on_map(state, tile):
					covered[tile] = true
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


## Every tile [param enemy_id] could support next phase ([method support_reach]), with the free
## tiles its movement reaches when it can't attack, less its [method enemy_range_tiles], in
## row-major order: its purple tiles when its range is toggled on.
static func enemy_support_tiles(session: CombatSession, enemy_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var reach: Array[Vector2i] = support_reach(session, enemy_id)
	if reach.is_empty():
		return tiles
	var covered: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in reach:
		covered[tile] = true
	if DangerZone.attack_ranges(session.engine, enemy_id).is_empty():
		for end: Vector2i in _next_phase_ends(session, enemy_id):
			covered[end] = true
	for tile: Vector2i in enemy_range_tiles(session, enemy_id):
		covered.erase(tile)
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


## Every tile some enemy in [param zone] could support next phase that none could attack
## ([member DangerZone.combined]), in row-major order: the danger zone's purple tiles.
static func danger_support_tiles(session: CombatSession, zone: DangerZone) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var covered: Dictionary[Vector2i, bool] = {}
	for enemy_id: String in zone.enemy_ids:
		if not session.state.has_unit(enemy_id):
			continue
		for tile: Vector2i in support_reach(session, enemy_id):
			if not zone.is_threatened(tile):
				covered[tile] = true
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


## The tiles [param unit_id] could support next phase, in row-major order: each
## [method support_ranges] span from every free tile its full movement reaches, as
## [method DangerZone.tiles_for] reads attacks. Empty for a unit with no support.
static func support_reach(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var state: CombatState = session.state
	var spans: Array[Vector2i] = support_ranges(session, unit_id)
	if spans.is_empty():
		return tiles
	var covered: Dictionary[Vector2i, bool] = {}
	for end: Vector2i in _next_phase_ends(session, unit_id):
		for span: Vector2i in spans:
			for tile: Vector2i in DangerZone.tiles_within(end, span):
				if _is_on_map(state, tile):
					covered[tile] = true
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


# ASSUMPTION: a Shove and a Use show red whatever their target; only Staff and Item are support by
# kind.
## Whether [param kind] is a support action, whose targets show on the purple support overlay:
## Staff and Item. Every other targeted action's show on the red attack overlay, but a rune's
## colour is its own ([member RuneOption.is_support]).
static func is_support_action(kind: ActionKind) -> bool:
	return kind == ActionKind.STAFF or kind == ActionKind.ITEM


## The seat's unit [param from_unit] cycles to among its [method acting_units], in state order,
## wrapping: the next ([param forward]) or the previous one that can act, counted from
## [param from_unit]'s place among the seat's units. From a unit that isn't the seat's (or none),
## the first that can act, as Godot_FE's [code]get_first_available_unit[/code]. Empty when none
## can act.
static func cycle_unit(
		session: CombatSession, seat: int, from_unit: String, forward: bool
) -> String:
	var acting: PackedStringArray = acting_units(session, seat)
	if acting.is_empty():
		return ""
	var own: PackedStringArray = []
	for unit_id: String in session.state.units_of(PLAYER):
		if session.state.seat_of(unit_id) == seat:
			own.append(unit_id)
	var at: int = own.find(from_unit)
	if at < 0:
		return acting[0]
	var step: int = 1 if forward else -1
	for i: int in range(1, own.size() + 1):
		var candidate: String = own[posmod(at + step * i, own.size())]
		if acting.has(candidate):
			return candidate
	return acting[0]


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
## move pending gets only Wait, which ends that move ([constant UnitTurnCommand.Action.MOVE], or
## a Wait where it stands). Attack lists each enemy, Demolish each standing breakable in spot
## order, both with every weapon accepted. Use lists each object usable from the path's end, with
## no item or the Pouch item (a key or lockpick). Rune, on the unit's own tile only, lists the
## runes that can be cast on the unit ([method runes_for_unit]). Empty when it can't act.
static func actions_at(
		session: CombatSession, unit_id: String, path: Array[Vector2i]
) -> Array[ActionOption]:
	var options: Array[ActionOption] = []
	if not can_act(session, unit_id):
		return options
	var state: CombatState = session.state
	var seat: int = state.seat_of(unit_id)
	if is_second_move(session, unit_id):
		# The session refuses a move that ends where the unit stands, so staying is a Wait.
		var stays: bool = path.is_empty() or path[path.size() - 1] == state.tile_of(unit_id)
		_add_untargeted(options, ActionKind.WAIT, _turn(
				session,
				unit_id,
				UnitTurnCommand.Action.WAIT if stays else UnitTurnCommand.Action.MOVE,
				"",
				path
		))
		return options
	var unit: CombatUnitState = state.unit(unit_id)
	var attack: ActionOption = ActionOption.new(ActionKind.ATTACK)
	_fill_exchanges(session, unit_id, path, state.units_of(ENEMY), attack)
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

	var demolish: ActionOption = ActionOption.new(ActionKind.DEMOLISH)
	_fill_exchanges(session, unit_id, path, _breakables(state), demolish)
	_add_targeted(options, demolish)

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

	# A rune is offered only on the unit's own tile: a cast acts for no unit and carries no path,
	# so offered after a move it would drop the move.
	if path.size() <= 1:
		var rune: ActionOption = ActionOption.new(ActionKind.RUNE)
		rune.runes = runes_for_unit(session, seat, unit_id)
		if not rune.runes.is_empty():
			options.append(rune)

	_add_untargeted(options, ActionKind.WAIT, _turn(
			session, unit_id, UnitTurnCommand.Action.WAIT, "", path
	))
	return options


## Every rune in [param seat]'s slots that can be cast now, in slot order, each with its targets
## by its [member RuneDefinition.target_kind]: a unit rune's units, Recall's first units (each
## with its [member TargetOption.partners]), Spark's kegs. Each target's command passed
## [method CastRuneCommand.validate]; a rune with none is left out.
static func rune_options(session: CombatSession, seat: int) -> Array[RuneOption]:
	var found: Array[RuneOption] = []
	var slots: PackedStringArray = session.state.rune_slots.get(seat, PackedStringArray())
	for rune_id: String in slots:
		var option: RuneOption = _rune_option(session, seat, rune_id)
		if option != null and not option.targets.is_empty():
			found.append(option)
	return found


## The runes of [param seat] that can be cast on [param unit_id], each narrowed to that one
## target: a unit rune whose targets include the unit, and Recall with the unit as its first pick
## (its partners still to choose). Spark, and a rune the unit can't take, are left out; the rune
## bar ([method held_runes]) casts those.
static func runes_for_unit(
		session: CombatSession, seat: int, unit_id: String
) -> Array[RuneOption]:
	var found: Array[RuneOption] = []
	for option: RuneOption in rune_options(session, seat):
		if option.target_kind == ContentIds.RUNE_OBJECT:
			continue
		for target: TargetOption in option.targets:
			if target.target_id == unit_id:
				option.targets = [target]
				option.refused = []
				found.append(option)
				break
	return found


## Every rune in [param seat]'s slots, in slot order, as the rune bar shows it: each with its
## [method rune_options] entry when it can be cast now, and the command that discards it.
static func held_runes(session: CombatSession, seat: int) -> Array[HeldRune]:
	var held: Array[HeldRune] = []
	var slots: PackedStringArray = session.state.rune_slots.get(seat, PackedStringArray())
	for rune_id: String in slots:
		var definition: RuneDefinition = RuneResolver.definition_of(session.engine, rune_id)
		var rune: HeldRune = HeldRune.new()
		rune.rune_id = rune_id
		rune.definition_id = "" if definition == null else definition.id
		rune.label = BattleText.name_of(session, rune_id)
		rune.text = "" if definition == null else " ".join(definition.describe())
		rune.marked_text = "" if definition == null else " ".join(definition.describe_marked())
		var option: RuneOption = _rune_option(session, seat, rune_id)
		if option != null and not option.targets.is_empty():
			rune.option = option
		else:
			rune.reason = NO_TARGET_REASON
		var discard: DiscardRuneCommand = DiscardRuneCommand.new(seat, rune_id)
		if discard.validate(session).is_empty():
			rune.discard = discard
		held.append(rune)
	return held


## What the battle message says when accept on [param tile] picks none of [param rune]'s targets:
## the reason of a refused unit there ([member RuneOption.refused]), such as
## [code]Haste: Archer has acted.[/code], else who the rune is cast on, such as
## [code]Shatter targets an enemy.[/code]
static func rune_refusal(rune: RuneOption, tile: Vector2i) -> String:
	for refused: TargetOption in rune.refused:
		if refused.tile == tile:
			return "%s: %s %s." % [rune.label, refused.label, refused.reason]
	return "%s targets %s." % [rune.label, rune.target_noun]


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


# rune_id's option with its targets and refused units by its kind, possibly no target at all; null
# when it has no definition on this map.
static func _rune_option(session: CombatSession, seat: int, rune_id: String) -> RuneOption:
	var definition: RuneDefinition = RuneResolver.definition_of(session.engine, rune_id)
	if definition == null:
		return null
	var option: RuneOption = RuneOption.new()
	option.rune_id = rune_id
	option.label = BattleText.name_of(session, rune_id)
	option.text = " ".join(definition.describe())
	option.marked_text = " ".join(definition.describe_marked())
	option.target_kind = definition.target_kind
	option.target_noun = definition.target_noun()
	option.title = "%s: %s" % [option.label, option.target_noun]
	option.is_support = (
			definition.target_kind == ContentIds.RUNE_UNIT
			and definition.target_side != ContentIds.RUNE_SIDE_ENEMY
	)
	match definition.target_kind:
		ContentIds.RUNE_UNIT:
			_fill_unit_rune(session, seat, definition, option)
		ContentIds.RUNE_PAIR:
			_fill_pair_rune(session, seat, option)
		ContentIds.RUNE_OBJECT:
			_fill_object_rune(session, seat, option)
	return option


# A unit rune's targets: every unit its cast validates on, in state order. A unit of the rune's
# side that it refuses (one that has acted, for Haste) is listed in option.refused with why.
static func _fill_unit_rune(
		session: CombatSession, seat: int, definition: RuneDefinition, option: RuneOption
) -> void:
	var state: CombatState = session.state
	# The side RuneResolver.target_reason() asks for; only the picker's refused rows read it.
	var side: CombatFact.CombatSide = (
			ENEMY if definition.target_side == ContentIds.RUNE_SIDE_ENEMY else PLAYER
	)
	for unit_id: String in state.unit_ids():
		var cast: CastRuneCommand = CastRuneCommand.new(seat, option.rune_id, unit_id)
		if cast.validate(session).is_empty():
			option.targets.append(_target(session, unit_id, cast))
		elif state.side_of(unit_id) == side:
			var refused: TargetOption = _target(session, unit_id, null)
			var has_acted: bool = state.unit(unit_id).has_acted
			refused.reason = (
					ACTED_REASON if definition.needs_unacted_target and has_acted
					else REFUSED_REASON
			)
			option.refused.append(refused)


# Recall's targets: each of the seat's units with a partner the cast validates with, each partner
# a target of its own in TargetOption.partners. A unit with none is refused.
static func _fill_pair_rune(session: CombatSession, seat: int, option: RuneOption) -> void:
	var state: CombatState = session.state
	var own: PackedStringArray = []
	for unit_id: String in state.units_of(PLAYER):
		if state.seat_of(unit_id) == seat:
			own.append(unit_id)
	for first_id: String in own:
		var first: TargetOption = _target(session, first_id, null)
		for second_id: String in own:
			if second_id == first_id:
				continue
			var cast: CastRuneCommand = CastRuneCommand.new(
					seat, option.rune_id, first_id, second_id
			)
			if cast.validate(session).is_empty():
				first.partners.append(_target(session, second_id, cast))
		if first.partners.is_empty():
			first.reason = NO_PARTNER_REASON
			option.refused.append(first)
		else:
			option.targets.append(first)


# Spark's targets: each standing object's tile the cast validates on, once, in spot order.
static func _fill_object_rune(session: CombatSession, seat: int, option: RuneOption) -> void:
	var tiles: Dictionary[Vector2i, bool] = {}
	for placed: MapState.ObjectState in _standing_objects(session.state):
		if tiles.has(placed.tile):
			continue
		var cast: CastRuneCommand = CastRuneCommand.new(
				seat, option.rune_id, "", "", placed.tile
		)
		if cast.validate(session).is_empty():
			tiles[placed.tile] = true
			var target: TargetOption = _target(session, placed.id, cast)
			target.tile = placed.tile
			option.targets.append(target)


# Fills option's targets with each of defenders, in order, that unit_id can attack after walking
# path: one target per defender, holding one command per weapon the session accepts (the one in
# hand first, then the stowed one through Sidearm's free swap).
static func _fill_exchanges(
		session: CombatSession,
		unit_id: String,
		path: Array[Vector2i],
		defenders: PackedStringArray,
		option: ActionOption
) -> void:
	var unit: CombatUnitState = session.state.unit(unit_id)
	var weapons: PackedStringArray = [""]
	if not unit.stowed_weapon_id.is_empty() and unit.stowed_weapon_id != unit.equipped_weapon_id:
		weapons.append(unit.stowed_weapon_id)
	for defender_id: String in defenders:
		var found: TargetOption = null
		for weapon_id: String in weapons:
			var command: UnitTurnCommand = _turn(
					session, unit_id, UnitTurnCommand.Action.ATTACK, defender_id, path, weapon_id
			)
			if command == null:
				continue
			if found == null:
				found = _target(session, defender_id, command)
				option.targets.append(found)
			else:
				found.commands.append(command)


# Every standing breakable (debris, a powder keg) in spot order: the map objects ExchangeResolver
# takes as a defender, which Demolish is tried on. The validator says which the unit can reach.
static func _breakables(state: CombatState) -> PackedStringArray:
	var found: PackedStringArray = []
	for placed: MapState.ObjectState in _standing_objects(state):
		if MapObjects.BREAKABLE_STATS.has(placed.kind) and state.has_unit(placed.id):
			found.append(placed.id)
	return found


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


# A target for target_id with command; with none (a refused unit, Recall's first pick), no
# command at all.
static func _target(session: CombatSession, target_id: String, command: Command) -> TargetOption:
	var option: TargetOption = TargetOption.new()
	option.target_id = target_id
	option.tile = session.state.tile_of(target_id)
	option.label = BattleText.name_of(session, target_id)
	option.command = command
	if command != null:
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


# The free tiles unit_id could end on next phase with its full movement from where it stands, its
# own included, as DangerZone.tiles_for floods them.
static func _next_phase_ends(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var ends: Array[Vector2i] = []
	var state: CombatState = session.state
	if not state.has_unit(unit_id):
		return ends
	var mover: CombatUnitState = state.unit(unit_id)
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			session.stats(unit_id).get_int(CombatValue.Key.MOVEMENT),
			mover.movement_type,
			mover.side
	)
	for end: Vector2i in walked:
		var occupant: String = state.occupant_at(end)
		if occupant.is_empty() or occupant == unit_id:
			ends.append(end)
	return ends


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
	## Rune only: the runes that can be cast, which the rune menu lists in place of
	## [member targets] ([method TurnInputModel.rune_options]); empty for every other action.
	var runes: Array[RuneOption] = []

	func _init(action_kind: ActionKind = ActionKind.WAIT) -> void:
		kind = action_kind
		label = TurnInputModel.ACTION_LABELS[action_kind]

	## Whether a target is picked before the command is sent.
	func has_targets() -> bool:
		return command == null


## One target an action can be aimed at, with the command that aims it there.
class TargetOption:
	extends RefCounted

	## The target's instance id: a unit's, or a map object's for Use, Spark and Demolish (a
	## breakable's unit has its object's id).
	var target_id: String = ""
	## Its tile, where the cursor shows it.
	var tile: Vector2i = CombatFact.NO_TILE
	## Its label in the target picker: its name ([method BattleText.name_of]).
	var label: String = ""
	## The command sent when this target is confirmed: the first of [member commands]. Null for
	## Recall's first unit, whose command is a partner's, and for a refused unit.
	var command: Command = null
	## Every command that aims the action here: for an exchange, one per weapon the session accepts
	## (the one in hand first, then the stowed one through Sidearm's free swap), which the forecast
	## cycles; otherwise only [member command].
	var commands: Array[Command] = []
	## Recall's first unit only: each unit it can swap with, with that cast's command, picked next.
	var partners: Array[TargetOption] = []
	## A refused unit only ([member RuneOption.refused]): why it can't be picked, such as
	## [code]has acted[/code]; empty for a target.
	var reason: String = ""


## One rune the rune menu lists, with what it can be cast on now.
class RuneOption:
	extends RefCounted

	## The rune's instance id, in the seat's slots.
	var rune_id: String = ""
	## Its name, such as "Haste".
	var label: String = ""
	## Its text ([method RuneDefinition.describe]), such as "Heal an ally for 10".
	var text: String = ""
	## [member text] with its keywords marked, for the rune menu's [EffectText]
	## ([method RuneDefinition.describe_marked]).
	var marked_text: String = ""
	## Its [member RuneDefinition.target_kind]: [code]unit[/code], [code]pair[/code] (Recall) or
	## [code]object[/code] (Spark).
	var target_kind: String = ""
	## Who it is cast on ([method RuneDefinition.target_noun]), such as "an enemy".
	var target_noun: String = ""
	## The target picker's heading: its name and [member target_noun].
	var title: String = ""
	## Whether its targets show on the purple support overlay: a player-side unit rune. Recall's
	## show on the move overlay, every other's on the red attack overlay.
	var is_support: bool = false
	## What it can be cast on, each with its command: a unit rune's units, Recall's first units
	## (each with its [member TargetOption.partners]), Spark's kegs.
	var targets: Array[TargetOption] = []
	## Units it can't be cast on now that the picker lists greyed with their
	## [member TargetOption.reason]: a unit of its side it refuses, or Recall's unit with no
	## partner. Never in [member targets].
	var refused: Array[TargetOption] = []


## One rune in a seat's slots, as the rune bar shows it, castable now or not.
class HeldRune:
	extends RefCounted

	## The rune's instance id, in the seat's slots.
	var rune_id: String = ""
	## Its [RuneDefinition]'s id, such as [code]mend[/code], which picks its icon; empty when the
	## map knows no definition for it.
	var definition_id: String = ""
	## Its name, such as "Mend".
	var label: String = ""
	## Its text ([method RuneDefinition.describe]); empty with no definition.
	var text: String = ""
	## [member text] with its keywords marked ([method RuneDefinition.describe_marked]); empty with
	## no definition.
	var marked_text: String = ""
	## What casting it offers now, its targets included; null when nothing can be cast on.
	var option: RuneOption = null
	## Why it can't be cast now ([constant TurnInputModel.NO_TARGET_REASON]); empty when it can.
	var reason: String = ""
	## The command that discards it; null when the session would refuse one now.
	var discard: DiscardRuneCommand = null
