# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     staff_resolver.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name StaffResolver
extends RefCounted
## Using a Block or heal staff on an ally in range (combat core plan, Staves; weapons.md, Staves).
##
## The amount is the staff's [constant CombatValue.Key.STAFF_AMOUNT] plus Might (every staff
## scales with Might, game-vision.md). A Block staff gives it through the engine's Block-gain path
## (the Block gained window: Brittle Guard), a heal staff through the heal path (Healed an ally and
## Healed windows, healing received, capped at maximum HP with the overheal recorded); heal staves
## target only damaged allies, Block staves any ally. Healing never rolls to hit. A staff with
## limited uses spends one ([method ItemUseResolver.use_effects]), then
## [constant CombatFact.Kind.USED_STAFF_ON_ALLY] is recorded and the queue drains. Attack staves
## attack through [ExchangeResolver]. Using a staff is the unit's action. Pure and static; the
## caller starts the resolution step.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md
##
## @todo: TOD-001 - Area staves (Sanctuary, Everwall) give each ally in their area the amount.


## [param user_id] uses the staff in its Weapon slot on [param target_id]. An illegal use records
## nothing.
static func resolve(
		engine: EffectEngine, state: CombatState, user_id: String, target_id: String
) -> Result:
	var result: Result = Result.new()
	result.reason = check(engine, state, user_id, target_id)
	if not result.reason.is_empty():
		return result
	result.is_legal = true
	state.unit(user_id).has_acted = true
	var staff: CombatState.WeaponStats = state.equipped_weapon(user_id)
	var amount: float = staff_amount(engine, user_id)
	if staff.staff == CombatState.WeaponStats.Staff.BLOCK:
		result.amount = engine.gain_block(target_id, amount, user_id)
	else:
		result.amount = engine.heal(target_id, amount, user_id)
	ItemUseResolver.spend(engine, ItemUseResolver.use_effects(engine, staff.id), target_id)
	engine.record(CombatFact.new(CombatFact.Kind.USED_STAFF_ON_ALLY, user_id, target_id))
	engine.drain()
	return result


## Why [param user_id] can't use its staff on [param target_id] now; empty when it can.
static func check(
		engine: EffectEngine, state: CombatState, user_id: String, target_id: String
) -> String:
	if not state.has_unit(user_id) or not state.has_unit(target_id):
		return "not on the map"
	var staff: CombatState.WeaponStats = state.equipped_weapon(user_id)
	if (
			staff == null
			or staff.staff == CombatState.WeaponStats.Staff.NONE
			or staff.staff == CombatState.WeaponStats.Staff.ATTACK
	):
		return "no Block or heal staff"
	var side: CombatFact.CombatSide = state.side_of(user_id)
	if not engine.matches_side(side, target_id, EffectDefinition.UnitSide.ALLY):
		return "not an ally"
	var ctx: EffectContext = EffectContext.new()
	ctx.distance = state.grid.distance(state.tile_of(user_id), state.tile_of(target_id))
	if not ExchangeResolver.in_range(engine, user_id, ctx):
		return "out of range"
	if staff.staff == CombatState.WeaponStats.Staff.HEAL:
		var max_hp: int = engine.stats(target_id).get_int(CombatValue.Key.HP)
		if state.get_hp(target_id) >= max_hp:
			return "not damaged"
	if not ItemUseResolver.has_uses(ItemUseResolver.use_effects(engine, staff.id)):
		return "no uses left"
	return ""


## The amount [param user_id]'s staff gives: [constant CombatValue.Key.STAFF_AMOUNT] plus Might,
## exact.
static func staff_amount(engine: EffectEngine, user_id: String) -> float:
	var sheet: StatSheet = engine.stats(user_id)
	return (
			sheet.get_value(CombatValue.Key.STAFF_AMOUNT)
			+ DamagePipeline.SCALING_MODIFIER * sheet.get_value(CombatValue.Key.MGT)
	)


## What a staff use did, for its caller.
class Result:
	extends RefCounted

	## Whether the use was legal and resolved.
	var is_legal: bool = false
	## Why it wasn't; empty when it was.
	var reason: String = ""
	## Block gained or HP restored.
	var amount: int = 0
