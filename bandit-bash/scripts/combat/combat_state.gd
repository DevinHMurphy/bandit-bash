# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_state.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name CombatState
extends SandboxState
## One map's combat state: its units, occupancy, turn, phase and rune slots, and the effect
## engine's whole view of the map.
##
## Implements every [SandboxState] read and write, so the engine's conditions, selectors and
## resource paths work on the real map. The writes ([method set_hp], [method set_block],
## [method set_stance]) are for the engine's resource paths only; the combat core's damage rules
## and [SplashResolver] are the other writers, and every change they make emits a fact. A unit's
## effects go dormant while [method has_unit] is false, and a stowed weapon's while it isn't
## [method equipped_weapon_id], so nothing is ever unregistered for a defeat or a swap.[br]
## Plain data with ids only: [method copy_for_sandbox] copies everything except [member grid],
## which is shared and never changed by rules code.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md
##
## @todo: TOD-001 - Answer darkness_layer() from the darkness plan (P06); every tile is DRY.

## Terrain, walls and objects. Shared with sandbox copies. Never null in use.
var grid: CombatGrid = null

## The turn counter: it rises at the player Phase Start, so 0 before the first one.
var turn: int = 0

## Whose phase it is; [constant CombatFact.CombatSide.NONE] before the first Phase Start.
var phase_side: CombatFact.CombatSide = CombatFact.CombatSide.NONE

## Seats that have ended their turn in the current player phase.
var ended_seats: PackedInt32Array = []

## Rune instance ids in each seat's slots, copied in at battle start by the campaign bridge. A cast
## rune leaves its slot.
var rune_slots: Dictionary[int, PackedStringArray] = {}

var _units: Dictionary[String, CombatUnitState] = {}

# Roster order, then spawn order: the order of placement.
var _order: PackedStringArray = []

var _occupancy: Dictionary[Vector2i, String] = {}


func _init(map_grid: CombatGrid = null) -> void:
	grid = map_grid


## Places [param unit] on its tile, with Block 0 and its full Stance (its
## [constant CombatValue.Key.STANCE_MAX] in [param engine]), so a unit attacked before its side's
## first Phase Start still has Stance. Battle start, spawns, reinforcements and transfers all place
## units this way; the caller records any fact. Returns false, placing nothing, for a known id or a
## tile that is off the map or taken.
func place_unit(engine: EffectEngine, unit: CombatUnitState) -> bool:
	if unit == null or _units.has(unit.id) or unit.is_defeated:
		return false
	if unit.tile == CombatFact.NO_TILE or _occupancy.has(unit.tile):
		return false
	unit.block = 0
	unit.stance = engine.stats(unit.id).get_int(CombatValue.Key.STANCE_MAX)
	_units[unit.id] = unit
	_order.append(unit.id)
	_occupancy[unit.tile] = unit.id
	return true


## The state of [param id], defeated or not; null if unknown.
func unit(id: String) -> CombatUnitState:
	return _units.get(id, null)


## Units of [param side] on the map, in [method unit_ids] order.
func units_of(side: CombatFact.CombatSide) -> PackedStringArray:
	var ids: PackedStringArray = []
	for id: String in unit_ids():
		if _units[id].side == side:
			ids.append(id)
	return ids


## The unit or object standing on [param tile]; empty when none.
func occupant_at(tile: Vector2i) -> String:
	return _occupancy.get(tile, "")


## What stands in the way on [param tile]: [constant CombatGrid.Blocker.UNIT] for a unit,
## [constant CombatGrid.Blocker.PLAIN] for a map object kept here, otherwise the grid's answer.
func blocker_at(tile: Vector2i) -> CombatGrid.Blocker:
	var occupant: String = occupant_at(tile)
	if not occupant.is_empty():
		if _units[occupant].side == CombatFact.CombatSide.NONE:
			return CombatGrid.Blocker.PLAIN
		return CombatGrid.Blocker.UNIT
	return grid.blocker_at(tile)


## Moves [param id] to the free tile [param tile], updating occupancy. Records nothing: the action
## that moves it records [constant CombatFact.Kind.UNIT_MOVED].
func move_unit(id: String, tile: Vector2i) -> void:
	if not has_unit(id) or _occupancy.has(tile):
		return
	var moving: CombatUnitState = _units[id]
	_occupancy.erase(moving.tile)
	moving.tile = tile
	_occupancy[tile] = id


## Swaps the tiles of two units on the map (the Recall rune). Records nothing.
func swap_units(first_id: String, second_id: String) -> void:
	if not has_unit(first_id) or not has_unit(second_id):
		return
	var first: CombatUnitState = _units[first_id]
	var second: CombatUnitState = _units[second_id]
	var first_tile: Vector2i = first.tile
	first.tile = second.tile
	second.tile = first_tile
	_occupancy[first.tile] = first_id
	_occupancy[second.tile] = second_id


## Records [param id]'s defeat and takes it off the map: [constant CombatFact.Kind.DEFEATED],
## then [constant CombatFact.Kind.DEFEATED_AN_ENEMY] when [param by_id] is on the other side,
## then it leaves occupancy. Its effects react to its own defeat before they go dormant.
## [param by_id]: the unit that defeated it, or empty.
func defeat(engine: EffectEngine, id: String, by_id: String, source_effect_id: String = "") -> void:
	if not has_unit(id):
		return
	var defeated: CombatFact = CombatFact.new(CombatFact.Kind.DEFEATED, id, by_id)
	defeated.source_effect_id = source_effect_id
	engine.record(defeated)
	if engine.matches_side(side_of(by_id), id, EffectDefinition.UnitSide.ENEMY):
		var kill: CombatFact = CombatFact.new(CombatFact.Kind.DEFEATED_AN_ENEMY, by_id, id)
		kill.source_effect_id = source_effect_id
		engine.record(kill)
	var gone: CombatUnitState = _units[id]
	gone.is_defeated = true
	_occupancy.erase(gone.tile)


func copy_for_sandbox() -> SandboxState:
	var copy: CombatState = CombatState.new(grid)
	copy.turn = turn
	copy.phase_side = phase_side
	copy.ended_seats = ended_seats.duplicate()
	for seat: int in rune_slots:
		copy.rune_slots[seat] = rune_slots[seat].duplicate()
	for id: String in _order:
		copy._units[id] = _units[id].copy()
	copy._order = _order.duplicate()
	copy._occupancy = _occupancy.duplicate()
	return copy


func unit_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for id: String in _order:
		if not _units[id].is_defeated:
			ids.append(id)
	return ids


func has_unit(id: String) -> bool:
	return _units.has(id) and not _units[id].is_defeated


func side_of(id: String) -> CombatFact.CombatSide:
	return _units[id].side if _units.has(id) else CombatFact.CombatSide.NONE


func seat_of(id: String) -> int:
	return _units[id].seat if _units.has(id) else -1


func tile_of(id: String) -> Vector2i:
	return _units[id].tile if has_unit(id) else CombatFact.NO_TILE


## Steps [param from_id] could take to [param to_id]'s tile with its own movement type, through
## [method CombatGrid.walking_distance]; -1 when either is off the map or there is no path.
func walking_distance(from_id: String, to_id: String) -> int:
	if not has_unit(from_id) or not has_unit(to_id):
		return -1
	var walker: CombatUnitState = _units[from_id]
	return grid.walking_distance(walker.tile, _units[to_id].tile, walker.movement_type)


func get_hp(id: String) -> int:
	return _units[id].hp if _units.has(id) else 0


func get_block(id: String) -> int:
	return _units[id].block if _units.has(id) else 0


func get_stance(id: String) -> int:
	return _units[id].stance if _units.has(id) else 0


func tiles_moved(id: String) -> int:
	return _units[id].tiles_moved if _units.has(id) else 0


func darkness_layer(_id: String) -> int:
	# TODO(TOD-001): Answer from the darkness plan (P06).
	return WhileLayerCondition.Layer.DRY


func equipped_weapon_id(unit_id: String) -> String:
	return _units[unit_id].equipped_weapon_id if _units.has(unit_id) else ""


func set_hp(id: String, value: int) -> void:
	if _units.has(id):
		_units[id].hp = value


func set_block(id: String, value: int) -> void:
	if _units.has(id):
		_units[id].block = value


func set_stance(id: String, value: int) -> void:
	if _units.has(id):
		_units[id].stance = value


## The combat core's one splash rule, through [SplashResolver]; the engine's splash is
## [constant CombatFact.Source.SPLASH].
func deal_splash(
		engine: EffectEngine,
		source_id: String,
		target_id: String,
		amount: int,
		source_effect_id: String
) -> void:
	SplashResolver.deal(
			engine, self, source_id, target_id, amount, CombatFact.Source.SPLASH, source_effect_id
	)
