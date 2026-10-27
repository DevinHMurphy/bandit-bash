# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fake_state.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

extends SandboxState
## A minimal map for the effect engine's tests: units and objects with a tile, HP, Block and Stance.
##
## Test-only, standing in for the combat core's [code]CombatState[/code]. Walking distance is the
## tile distance plus the walker's [member FakeUnit.detour] (a wall in its way, so "movable tiles"
## can differ from grid tiles), and splash follows the combat core's rule closely enough for the
## engine's tests: Block absorbs, then HP; Damage taken; a unit at 0 HP is defeated. A defeated
## unit leaves the map: it has no tile any more, as when the combat core clears its occupancy.

# This script, preloaded as a type for its copy (gdscript.md, Naming): it has no class name.
const FakeState = preload("res://tests/effects/harness/fake_state.gd")

## Weapon type by weapon instance id, for conditions that test it.
var weapon_types: Dictionary[String, String] = {}

var _units: Dictionary[String, FakeUnit] = {}
var _order: PackedStringArray = []


## Adds a unit (or, with side NONE, an object) and returns it for further setup.
func add(
		id: String, side: CombatFact.CombatSide, seat: int, tile: Vector2i, hp: int = 20
) -> FakeUnit:
	var unit: FakeUnit = FakeUnit.new()
	unit.id = id
	unit.side = side
	unit.seat = seat
	unit.tile = tile
	unit.hp = hp
	_units[id] = unit
	_order.append(id)
	return unit


## The unit [param id], defeated or not; null if unknown.
func unit(id: String) -> FakeUnit:
	return _units.get(id, null)


## A one-line summary of every unit, for comparing states: id hp/block/stance.
func summary() -> String:
	var parts: PackedStringArray = []
	for id: String in _order:
		var u: FakeUnit = _units[id]
		parts.append("%s %d/%d/%d%s" % [id, u.hp, u.block, u.stance, " x" if u.defeated else ""])
	return ", ".join(parts)


func copy_for_sandbox() -> SandboxState:
	var copy: FakeState = FakeState.new()
	copy.weapon_types = weapon_types.duplicate()
	for id: String in _order:
		var original: FakeUnit = _units[id]
		var unit_copy: FakeUnit = copy.add(id, original.side, original.seat, original.tile)
		unit_copy.hp = original.hp
		unit_copy.block = original.block
		unit_copy.stance = original.stance
		unit_copy.moved = original.moved
		unit_copy.layer = original.layer
		unit_copy.weapon = original.weapon
		unit_copy.growth = original.growth.duplicate()
		unit_copy.tags = original.tags
		unit_copy.unit_type = original.unit_type
		unit_copy.detour = original.detour
		unit_copy.defeated = original.defeated
	return copy


func unit_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for id: String in _order:
		if not _units[id].defeated:
			ids.append(id)
	return ids


func has_unit(id: String) -> bool:
	return _units.has(id) and not _units[id].defeated


func side_of(id: String) -> CombatFact.CombatSide:
	return _units[id].side if _units.has(id) else CombatFact.CombatSide.NONE


func seat_of(id: String) -> int:
	return _units[id].seat if _units.has(id) else -1


func tile_of(id: String) -> Vector2i:
	return _units[id].tile if has_unit(id) else CombatFact.NO_TILE


func walking_distance(from_id: String, to_id: String) -> int:
	if not has_unit(from_id) or not has_unit(to_id):
		return -1
	var delta: Vector2i = _units[from_id].tile - _units[to_id].tile
	return absi(delta.x) + absi(delta.y) + _units[from_id].detour


func get_hp(id: String) -> int:
	return _units[id].hp if _units.has(id) else 0


func get_block(id: String) -> int:
	return _units[id].block if _units.has(id) else 0


func get_stance(id: String) -> int:
	return _units[id].stance if _units.has(id) else 0


func tiles_moved(id: String) -> int:
	return _units[id].moved if _units.has(id) else 0


func darkness_layer(id: String) -> int:
	return _units[id].layer if _units.has(id) else 0


func equipped_weapon_id(unit_id: String) -> String:
	return _units[unit_id].weapon if _units.has(unit_id) else ""


func tags_of(id: String) -> PackedStringArray:
	return _units[id].tags if _units.has(id) else PackedStringArray()


func unit_type_of(id: String) -> String:
	return _units[id].unit_type if _units.has(id) else ""


func weapon_type_of(weapon_id: String) -> String:
	return weapon_types.get(weapon_id, "")


func set_hp(id: String, value: int) -> void:
	_units[id].hp = value


func set_block(id: String, value: int) -> void:
	_units[id].block = value


func set_stance(id: String, value: int) -> void:
	_units[id].stance = value


func add_growth(id: String, stat: int, points: int) -> void:
	if _units.has(id):
		_units[id].growth[stat] = _units[id].growth.get(stat, 0) + points


func deal_splash(
		engine: EffectEngine,
		source_id: String,
		target_id: String,
		amount: int,
		source_effect_id: String
) -> void:
	if amount <= 0 or not has_unit(target_id):
		return
	var target: FakeUnit = _units[target_id]
	var absorbed: int = mini(target.block, amount)
	var to_hp: int = mini(target.hp, amount - absorbed)
	target.block -= absorbed
	target.hp -= to_hp
	var taken: CombatFact = CombatFact.new(CombatFact.Kind.DAMAGE_TAKEN, target_id, source_id)
	taken.amount = absorbed + to_hp
	taken.hp_amount = to_hp
	taken.block_amount = absorbed
	taken.source = CombatFact.Source.SPLASH
	taken.source_effect_id = source_effect_id
	engine.record(taken)
	if target.hp > 0:
		return
	engine.record(_defeat_fact(CombatFact.Kind.DEFEATED, target_id, source_id, source_effect_id))
	if has_unit(source_id) and engine.matches_side(
			side_of(source_id), target_id, EffectDefinition.UnitSide.ENEMY
	):
		engine.record(_defeat_fact(
				CombatFact.Kind.DEFEATED_AN_ENEMY, source_id, target_id, source_effect_id
		))
	target.defeated = true


static func _defeat_fact(
		kind: CombatFact.Kind, actor_id: String, target_id: String, effect_id: String
) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor_id, target_id)
	fact.source_effect_id = effect_id
	return fact



## A unit or object on the fake map.
class FakeUnit:
	extends RefCounted

	## Instance id.
	var id: String = ""
	## Its side; NONE for an object.
	var side: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
	## Controlling seat; -1 for enemies and objects.
	var seat: int = -1
	## Where it stands.
	var tile: Vector2i = Vector2i.ZERO
	## Current HP.
	var hp: int = 20
	## Current Block.
	var block: int = 0
	## Current Stance.
	var stance: int = 2
	## Tiles moved this turn.
	var moved: int = 0
	## Darkness layer of its tile.
	var layer: int = 0
	## Instance id of the weapon in its Weapon slot; empty for none.
	var weapon: String = ""
	## Growth changes, in percentage points by stat.
	var growth: Dictionary[int, int] = {}
	## Its tags, such as "Beast".
	var tags: PackedStringArray = []
	## Its unit type.
	var unit_type: String = ""
	## Extra steps every walk from this unit takes, as if a wall were in its way.
	var detour: int = 0
	## Whether it was defeated (kept, so its side and seat stay readable).
	var defeated: bool = false

	## A copy.
	func copy() -> FakeUnit:
		var unit: FakeUnit = FakeUnit.new()
		unit.id = id
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.hp = hp
		unit.block = block
		unit.stance = stance
		unit.moved = moved
		unit.layer = layer
		unit.weapon = weapon
		unit.growth = growth.duplicate()
		unit.tags = tags
		unit.unit_type = unit_type
		unit.detour = detour
		unit.defeated = defeated
		return unit
