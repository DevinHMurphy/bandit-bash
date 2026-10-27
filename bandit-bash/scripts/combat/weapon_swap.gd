# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     weapon_swap.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name WeaponSwap
extends RefCounted
## Swapping the Weapon slot with the weapon stowed in the Pouch (combat core plan, Staves, Pouch
## items, weapon swaps, runes; unit-roster.md, Stowed weapons and Sidearm).
##
## As an action the swap ends the unit's turn. With Sidearm
## ([constant CombatValue.Permission.FREE_WEAPON_SWAP]) it is free once per unit turn, before
## acting, so the attack that follows can use either weapon. Only the weapon in the Weapon slot
## counts: its numbers become the unit's bases ([method CombatState.load_bases]) and its effects
## wake while the stowed weapon's sleep, with nothing unregistered. Records
## [constant CombatFact.Kind.WEAPON_SWAPPED], naming the weapon now in the Weapon slot. Pure and
## static; the caller starts the resolution step.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md


## Swaps [param unit_id]'s weapons, as its action, or for free with Sidearm when
## [param is_free]. An illegal swap records nothing. Returns why it was illegal; empty when it
## resolved.
static func resolve(
		engine: EffectEngine, state: CombatState, unit_id: String, is_free: bool
) -> String:
	var reason: String = check(engine, state, unit_id, is_free)
	if not reason.is_empty():
		return reason
	var holder: CombatUnitState = state.unit(unit_id)
	var stowed: String = holder.stowed_weapon_id
	holder.stowed_weapon_id = holder.equipped_weapon_id
	holder.equipped_weapon_id = stowed
	if is_free:
		holder.has_used_sidearm = true
	else:
		holder.has_acted = true
	state.load_bases(engine, unit_id)
	var swapped: CombatFact = CombatFact.new(CombatFact.Kind.WEAPON_SWAPPED, unit_id)
	swapped.item_id = stowed
	engine.record(swapped)
	engine.drain()
	return ""


## Why [param unit_id] can't swap weapons now; empty when it can. Free only with Sidearm, once
## per unit turn and before acting.
static func check(
		engine: EffectEngine, state: CombatState, unit_id: String, is_free: bool
) -> String:
	if not state.has_unit(unit_id):
		return "not on the map"
	var holder: CombatUnitState = state.unit(unit_id)
	if holder.stowed_weapon_id.is_empty():
		return "no stowed weapon"
	if holder.has_acted:
		return "already acted"
	if not is_free:
		return ""
	if not engine.stats(unit_id).is_allowed(CombatValue.Permission.FREE_WEAPON_SWAP):
		return "no Sidearm"
	if holder.has_used_sidearm:
		return "Sidearm already used this turn"
	return ""
