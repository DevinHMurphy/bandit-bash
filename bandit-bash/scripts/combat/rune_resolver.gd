# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_resolver.gd
# Author:
# Created:  October 27, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name RuneResolver
extends RefCounted
## Casting a rune from a seat's slots on this map (combat core plan, Staves, Pouch items, weapon
## swaps, runes; items.md, Runes).
##
## Runes are run-wide, single use and outside the action economy. A rune's [RuneDefinition] says
## what it may be cast on ([method target_reason]). A [code]unit[/code] rune (Mend, Aegis, Shatter,
## Clarity, Haste) fires its effect with the unit as the command target ([method cast]); Recall
## swaps two of the seat's units ([method recall]); Spark acts on the object on a tile through the
## map's rules ([method cast_on_object]). Each empties the slot and records
## [constant CombatFact.Kind.RUNE_USED]: the rune, its target, the target's tile and, in its amount,
## the casting seat. [method discard] empties the slot unused. Pure and static; the caller starts
## the resolution step and checks that it is this map's player phase.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

# What each target kind is cast on, for refusals.
const _AIMED_AT: Dictionary[String, String] = {
	ContentIds.RUNE_UNIT: "one unit",
	ContentIds.RUNE_PAIR: "two of your units",
	ContentIds.RUNE_OBJECT: "a map object",
}


## The effect instance the rune [param rune_id] owns in [param engine]; null when it has none.
static func effect_of(engine: EffectEngine, rune_id: String) -> EffectInstance:
	for instance: EffectInstance in engine.get_instances():
		if instance.owner.kind == EffectOwner.Kind.RUNE and instance.owner.owner_id == rune_id:
			return instance
	return null


## The catalog's rune whose effect the rune [param rune_id] owns in [param engine]: combat holds
## only instance ids, so the effect is the link. Null when it owns none, or an effect no rune in
## the catalog carries. Reads [EffectCatalog], so it runs on the main thread.
static func definition_of(engine: EffectEngine, rune_id: String) -> RuneDefinition:
	var instance: EffectInstance = effect_of(engine, rune_id)
	if instance == null:
		return null
	for resource: Resource in EffectCatalog.all_of(EffectCatalog.Kind.RUNE):
		var rune: RuneDefinition = resource as RuneDefinition
		if rune != null and rune.effects.has(instance.definition):
			return rune
	return null


## Why [param rune] can't be cast on the unit [param target_id]; empty when it can. A
## [code]unit[/code] rune takes one unit of its [member RuneDefinition.target_side] (never a
## breakable), one that hasn't acted when [member RuneDefinition.needs_unacted_target] says so.
## Any seat's unit of that side will do: a rune may help a teammate's unit.
static func target_reason(state: CombatState, rune: RuneDefinition, target_id: String) -> String:
	if rune == null:
		return "no rune"
	if rune.target_kind != ContentIds.RUNE_UNIT:
		return _kind_reason(rune)
	if not state.has_unit(target_id):
		return "no target on the map"
	var side: CombatFact.CombatSide = state.side_of(target_id)
	var wanted: CombatFact.CombatSide = (
			CombatFact.CombatSide.ENEMY
			if rune.target_side == ContentIds.RUNE_SIDE_ENEMY
			else CombatFact.CombatSide.PLAYER
	)
	if side != wanted:
		return "%s isn't on the %s side" % [target_id, rune.target_side]
	if rune.needs_unacted_target and state.unit(target_id).has_acted:
		return "%s has acted" % [target_id]
	return ""


## Casts the [code]unit[/code] rune [param rune] (its effect instance) from [param seat]'s slots
## on [param target_id]: its effect fires, the rune leaves the slot, Rune used, then the drain
## resolves what it does. An illegal cast records nothing. Returns why it was illegal; empty when
## it resolved.
static func cast(
		engine: EffectEngine,
		state: CombatState,
		seat: int,
		rune: EffectInstance,
		target_id: String
) -> String:
	if rune == null:
		return "no rune"
	var rune_id: String = rune.owner.owner_id
	var reason: String = _check_slot(state, seat, rune_id)
	if reason.is_empty():
		reason = target_reason(state, definition_of(engine, rune_id), target_id)
	if not reason.is_empty():
		return reason
	var ctx: EffectContext = EffectContext.new()
	ctx.command_target_id = target_id
	if not engine.activate(rune, ctx):
		return "its effect can't fire"
	_record_used(engine, state, seat, rune_id, target_id)
	engine.drain()
	return ""


## Casts the [code]object[/code] rune [param rune_id] from [param seat]'s slots on the map object
## standing on [param tile]: the map's rules act on it through [param operate], called as
## [code]operate.call(rune_id, object_id) -> bool[/code]
## ([constant CombatHooks.Hook.OBJECT_OPERATIONS]); then the rune leaves the slot, Rune used (with
## the tile), and the drain. When nothing acts on the object, nothing is recorded and the rune
## stays. Returns why the cast was illegal; empty when it resolved.
static func cast_on_object(
		engine: EffectEngine,
		state: CombatState,
		seat: int,
		rune_id: String,
		tile: Vector2i,
		operate: Callable
) -> String:
	var reason: String = _check_kind(engine, state, seat, rune_id, ContentIds.RUNE_OBJECT)
	if not reason.is_empty():
		return reason
	var here: Array[MapState.ObjectState] = state.map.objects_at(tile)
	if here.is_empty():
		return "no object on %s" % [tile]
	var object_id: String = here[0].id
	var has_acted: bool = operate.call(rune_id, object_id)
	if not has_acted:
		return "it can't act on that object"
	_record_used(engine, state, seat, rune_id, object_id, tile)
	engine.drain()
	return ""


## Recall: [param seat]'s units [param first_id] and [param second_id] swap tiles, using the
## [code]pair[/code] rune [param rune_id]. Legal only if each can stand on the other's tile.
## Records Unit moved for both, then Rune used (its target the first unit), then the drain; it is
## neither unit's move nor a shove. Returns why it was illegal; empty when it resolved.
static func recall(
		engine: EffectEngine,
		state: CombatState,
		seat: int,
		rune_id: String,
		first_id: String,
		second_id: String
) -> String:
	var reason: String = _check_kind(engine, state, seat, rune_id, ContentIds.RUNE_PAIR)
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


## Takes the rune [param rune_id] out of [param seat]'s slots unused: its effect never fires, and
## [constant CombatFact.Kind.RUNE_DISCARDED] is recorded with the rune and, in its amount, the seat.
## Returns why it can't be discarded (it isn't in the seat's slots), recording nothing then; empty
## when it was.
static func discard(
		engine: EffectEngine, state: CombatState, seat: int, rune_id: String
) -> String:
	var reason: String = _check_slot(state, seat, rune_id)
	if not reason.is_empty():
		return reason
	var slots: PackedStringArray = state.rune_slots[seat]
	slots.remove_at(slots.find(rune_id))
	state.rune_slots[seat] = slots
	var discarded: CombatFact = CombatFact.new(CombatFact.Kind.RUNE_DISCARDED)
	discarded.item_id = rune_id
	discarded.amount = seat
	engine.record(discarded)
	return ""


static func _check_slot(state: CombatState, seat: int, rune_id: String) -> String:
	if not state.rune_slots.has(seat) or not state.rune_slots[seat].has(rune_id):
		return "not in the seat's rune slots"
	return ""


# Why rune_id can't be cast by seat as a rune of target_kind: not in its slots, no definition, or
# another kind. Empty when it can.
static func _check_kind(
		engine: EffectEngine, state: CombatState, seat: int, rune_id: String, target_kind: String
) -> String:
	var reason: String = _check_slot(state, seat, rune_id)
	if not reason.is_empty():
		return reason
	var rune: RuneDefinition = definition_of(engine, rune_id)
	if rune == null:
		return "no rune"
	if rune.target_kind != target_kind:
		return _kind_reason(rune)
	return ""


# The refusal of a cast that doesn't fit rune's kind: what the rune is cast on.
static func _kind_reason(rune: RuneDefinition) -> String:
	return "%s is cast on %s" % [rune.id, _AIMED_AT.get(rune.target_kind, rune.target_kind)]


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
