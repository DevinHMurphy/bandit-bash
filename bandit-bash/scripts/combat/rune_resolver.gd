# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_resolver.gd
# Author:
# Created:  October 27, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name RuneResolver
extends RefCounted
## Casting a rune from a seat's slots on this map (combat core plan, Staves, Pouch items, weapon
## swaps, runes; items.md, Runes).
##
## Runes are run-wide, single use and outside the action economy. Most are ordinary effect
## operations with the cast's target as their command target (Mend, Aegis, Shatter, Clarity,
## Haste): [method cast] fires the rune's effect, the rune leaves its seat's slot, and
## [constant CombatFact.Kind.RUNE_USED] names it, its target, the target's tile and, in its amount,
## the casting seat. Recall is a combat core operation ([method recall]): two of the seat's units
## swap tiles, which is neither unit's move nor a shove. A rune cast on a map object (Spark on a
## powder keg) acts through the map's own rules instead of an effect ([method cast_on_object]).
## Pure and static; the caller starts the resolution step and checks that it is this map's player
## phase.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md


## Casts [param rune] from [param seat]'s slots on [param target_id]: its effect fires, the rune
## leaves the slot, Rune used, then the drain resolves what it does. An illegal cast records
## nothing. Returns why it was illegal; empty when it resolved.
static func cast(
		engine: EffectEngine,
		state: CombatState,
		seat: int,
		rune: EffectInstance,
		target_id: String
) -> String:
	if rune == null:
		return "no rune"
	var reason: String = _check_slot(state, seat, rune.owner.owner_id)
	if not reason.is_empty():
		return reason
	if not state.has_unit(target_id):
		return "no target on the map"
	var ctx: EffectContext = EffectContext.new()
	ctx.command_target_id = target_id
	if not engine.activate(rune, ctx):
		return "its effect can't fire"
	_record_used(engine, state, seat, rune.owner.owner_id, target_id)
	engine.drain()
	return ""


## Casts [param rune] from [param seat]'s slots on the map object [param object_id]: the map's
## rules act on it through [param operate], called as [code]operate.call(rune_id, object_id) ->
## bool[/code] ([constant CombatHooks.Hook.OBJECT_OPERATIONS]); then the rune leaves the slot,
## Rune used (with the object's tile, kept from before it acted), and the drain. When nothing acts
## on the object, nothing is recorded and the rune stays. Returns why the cast was illegal; empty
## when it resolved.
static func cast_on_object(
		engine: EffectEngine,
		state: CombatState,
		seat: int,
		rune: EffectInstance,
		object_id: String,
		operate: Callable
) -> String:
	if rune == null:
		return "no rune"
	var rune_id: String = rune.owner.owner_id
	var reason: String = _check_slot(state, seat, rune_id)
	if not reason.is_empty():
		return reason
	var target: MapState.ObjectState = state.map.object(object_id)
	if target == null or target.is_destroyed:
		return "no object on the map"
	var tile: Vector2i = target.tile
	var has_acted: bool = operate.call(rune_id, object_id)
	if not has_acted:
		return "it can't act on that object"
	_record_used(engine, state, seat, rune_id, object_id, tile)
	engine.drain()
	return ""


## Recall: [param seat]'s units [param first_id] and [param second_id] swap tiles, using the rune
## [param rune_id]. Legal only if each can stand on the other's tile. Records Unit moved for both,
## then Rune used (its target the first unit), then the drain. Returns why it was illegal; empty
## when it resolved.
static func recall(
		engine: EffectEngine,
		state: CombatState,
		seat: int,
		rune_id: String,
		first_id: String,
		second_id: String
) -> String:
	var reason: String = _check_slot(state, seat, rune_id)
	if not reason.is_empty():
		return reason
	for unit_id: String in [first_id, second_id]:
		if not state.has_unit(unit_id) or state.seat_of(unit_id) != seat:
			return "not two of the seat's units"
	if first_id == second_id:
		return "not two of the seat's units"
	var first: CombatUnitState = state.unit(first_id)
	var second: CombatUnitState = state.unit(second_id)
	if (
			not state.can_stand(second.tile, first.movement_type)
			or not state.can_stand(first.tile, second.movement_type)
	):
		return "a unit can't stand on the other's tile"
	state.swap_units(first_id, second_id)
	for unit_id: String in [first_id, second_id]:
		var moved: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, unit_id)
		moved.tile = state.tile_of(unit_id)
		engine.record(moved)
	_record_used(engine, state, seat, rune_id, first_id)
	engine.drain()
	return ""


static func _check_slot(state: CombatState, seat: int, rune_id: String) -> String:
	if not state.rune_slots.has(seat) or not state.rune_slots[seat].has(rune_id):
		return "not in the seat's rune slots"
	return ""


# Empties the slot and records Rune used: no actor (a rune has no owner), the casting seat in its
# amount, and tile, or the target's tile when tile is NO_TILE.
static func _record_used(
		engine: EffectEngine,
		state: CombatState,
		seat: int,
		rune_id: String,
		target_id: String,
		tile: Vector2i = CombatFact.NO_TILE
) -> void:
	var slots: PackedStringArray = state.rune_slots[seat]
	slots.remove_at(slots.find(rune_id))
	state.rune_slots[seat] = slots
	var used: CombatFact = CombatFact.new(CombatFact.Kind.RUNE_USED, "", target_id)
	used.item_id = rune_id
	used.amount = seat
	used.tile = state.tile_of(target_id) if tile == CombatFact.NO_TILE else tile
	engine.record(used)
