# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_world.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## A test map for the combat core's cases: a stub grid, a [CombatState] and an [EffectEngine] over
## it, with helpers to place units and read the fact log.
##
## Test-only. The engine runs in verify mode, so a stale cached stat sheet shows up in
## [member EffectEngine.diagnostics], which every case checks is empty.

# A preloaded script used as a type (gdscript.md, Naming): the stub has no class name.
const StubCombatGrid = preload("res://tests/combat/stub_combat_grid.gd")

## The map's terrain.
var grid: StubCombatGrid = null

## The map's combat state.
var state: CombatState = null

## The engine resolving on [member state].
var engine: EffectEngine = null


## [param rolls]: the roll source; [ForcedRolls] with no outcomes (every roll fails) when null.
func _init(rolls: RollSource = null, size: Vector2i = Vector2i(8, 8)) -> void:
	grid = StubCombatGrid.new(size)
	state = CombatState.new(grid)
	var source: RollSource = rolls if rolls != null else ForcedRolls.new(PackedInt32Array())
	engine = EffectEngine.new(state, source)
	engine.verify = true


## Places a unit with base stats [param bases] (value keys to numbers; HP 20 and Stance 2 unless
## given) at full HP. Returns its state for further setup, or null if it couldn't be placed.
func add_unit(
		id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i,
		bases: Dictionary = {}
) -> CombatUnitState:
	var all_bases: Dictionary[int, float] = {
		CombatValue.Key.HP: 20.0,
		CombatValue.Key.STANCE_MAX: 2.0,
	}
	# Untyped parameter: callers pass dictionary literals, which are untyped.
	for key: int in bases:
		all_bases[key] = float(bases[key])
	for key: int in all_bases:
		engine.set_base(id, key, all_bases[key])
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.side = side
	unit.seat = seat
	unit.tile = tile
	unit.hp = roundi(all_bases[CombatValue.Key.HP])
	if not state.place_unit(engine, unit):
		return null
	return unit


## Registers [param definition] as a trait of [param unit_id] (or, with [param item_id], as an
## effect of that item held by the unit) and returns the instance.
func add_effect(
		instance_id: String,
		definition: EffectDefinition,
		unit_id: String,
		kind: Modifier.SourceKind = Modifier.SourceKind.UNIT_TRAIT,
		item_id: String = ""
) -> EffectInstance:
	var side: CombatFact.CombatSide = state.side_of(unit_id)
	var seat: int = state.seat_of(unit_id)
	var owner: EffectOwner = EffectOwner.for_unit(unit_id, seat, side)
	if not item_id.is_empty():
		owner = EffectOwner.for_item(item_id, unit_id, seat, side)
	var instance: EffectInstance = EffectInstance.new(
			instance_id, definition, owner, kind, instance_id
	)
	engine.register(instance)
	return instance


## The fact log from index [param start] on, one [method CombatFact.to_log_line] per fact.
func log_lines(start: int = 0) -> Array[String]:
	var lines: Array[String] = []
	for i: int in range(start, engine.fact_log.size()):
		lines.append(engine.fact_log[i].to_log_line())
	return lines


## The kinds of the facts from index [param start] on, by name, joined by spaces.
func kinds(start: int = 0) -> String:
	var names: PackedStringArray = []
	for i: int in range(start, engine.fact_log.size()):
		names.append(String(CombatFact.Kind.find_key(engine.fact_log[i].kind)))
	return " ".join(names)
