# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_use_resolver.gd
# Author:
# Created:  October 27, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name ItemUseResolver
extends RefCounted
## Using a Pouch item, on the user itself or an orthogonally adjacent ally: a potion's heal, a Guard
## Tonic's Block, the Elixir's full heal, a stat booster's permanent delta, an eaten ingredient
## (combat core plan, Staves, Pouch items, weapon swaps, runes).
##
## What an item does is data: its use effects ([method use_effects]) fire as a command, with the
## recipient as their command target, so their operations resolve through the engine's heal,
## Block-gain and stat paths. Their charges are the item's uses: combat-lane charges are per map
## and refill at the start of every battle; campaign-lane charges are total uses, and an item whose
## total uses are spent leaves the Pouch. Using an item is the unit's action. Pure and static;
## the caller starts the resolution step.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md


## Uses [param item_id] from [param user_id]'s Pouch on [param target_id]: its use effects fire,
## then Item used, then the drain resolves what they do. An illegal use records nothing.
static func resolve(
		engine: EffectEngine,
		state: CombatState,
		user_id: String,
		target_id: String,
		item_id: String
) -> Result:
	var result: Result = Result.new()
	result.reason = check(engine, state, user_id, target_id, item_id)
	if not result.reason.is_empty():
		return result
	result.is_legal = true
	var user: CombatUnitState = state.unit(user_id)
	user.has_acted = true
	var effects: Array[EffectInstance] = use_effects(engine, item_id)
	spend(engine, effects, target_id)
	var used: CombatFact = CombatFact.new(CombatFact.Kind.ITEM_USED, user_id, target_id)
	used.item_id = item_id
	engine.record(used)
	if _used_up(effects):
		user.pouch_item_id = ""
		state.load_bases(engine, user_id)
		result.is_consumed = true
	engine.drain()
	return result


## Why [param user_id] can't use [param item_id] on [param target_id] now; empty when it can.
static func check(
		engine: EffectEngine,
		state: CombatState,
		user_id: String,
		target_id: String,
		item_id: String
) -> String:
	if not state.has_unit(user_id) or not state.has_unit(target_id):
		return "not on the map"
	if item_id.is_empty() or state.unit(user_id).pouch_item_id != item_id:
		return "not in its Pouch"
	if target_id != user_id:
		if state.grid.distance(state.tile_of(user_id), state.tile_of(target_id)) != 1:
			return "not adjacent"
		var side: CombatFact.CombatSide = state.side_of(user_id)
		if not engine.matches_side(side, target_id, EffectTerms.UnitSide.ALLY):
			return "not an ally"
	var effects: Array[EffectInstance] = use_effects(engine, item_id)
	if effects.is_empty():
		return "nothing to use"
	if not has_uses(effects):
		return "no uses left"
	return ""


## The use effects of [param item_id], in instance id order: its registered effects with no
## trigger and no always-on modifier, which fire only when the item is used. Their charges are its
## uses.
static func use_effects(engine: EffectEngine, item_id: String) -> Array[EffectInstance]:
	var found: Array[EffectInstance] = []
	for instance: EffectInstance in engine.get_instances():
		if instance.owner.kind != EffectOwner.Kind.ITEM or instance.owner.owner_id != item_id:
			continue
		if instance.definition.trigger != EffectTerms.Trigger.ALWAYS:
			continue
		if _gives_modifiers(instance):
			continue
		found.append(instance)
	return found


## Whether every one of [param effects] has a use left.
static func has_uses(effects: Array[EffectInstance]) -> bool:
	for instance: EffectInstance in effects:
		if not instance.has_charge():
			return false
	return true


## Fires each of [param effects] as a command on [param target_id]: each spends a charge, records
## its activation and queues its operations for the next drain.
static func spend(engine: EffectEngine, effects: Array[EffectInstance], target_id: String) -> void:
	for instance: EffectInstance in effects:
		var ctx: EffectContext = EffectContext.new()
		ctx.command_target_id = target_id
		engine.activate(instance, ctx)


# Whether the item's total uses are spent: some effect counts campaign-lane uses and none is left.
static func _used_up(effects: Array[EffectInstance]) -> bool:
	var totals: bool = false
	for instance: EffectInstance in effects:
		if instance.definition.charges <= 0:
			return false
		if instance.definition.charge_lane != EffectTerms.Lane.CAMPAIGN:
			return false
		totals = true
		if instance.has_charge():
			return false
	return totals


static func _gives_modifiers(instance: EffectInstance) -> bool:
	for operation: EffectOperation in instance.definition.operations:
		if operation != null and operation.make_modifier(instance) != null:
			return true
	return false


## What an item use did, for its caller.
class Result:
	extends RefCounted

	## Whether the use was legal and resolved.
	var is_legal: bool = false
	## Why it wasn't; empty when it was.
	var reason: String = ""
	## Whether the item's total uses ran out and it left the Pouch.
	var is_consumed: bool = false
