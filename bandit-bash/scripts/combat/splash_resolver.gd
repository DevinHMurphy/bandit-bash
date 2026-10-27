# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     splash_resolver.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name SplashResolver
extends RefCounted
## The one splash rule, for every source of flat area damage: Cleave, Trample, powder kegs, bumps
## and spiked walls.
##
## Splash is not an attack: no hit roll, no Mitigation, no crit, no Stance loss. Block absorbs it,
## then HP takes the rest; it fires [constant CombatFact.Kind.DAMAGE_TAKEN], never Hit taken; it
## can defeat. A queued splash (Cleave) resolves at the next drain from the tile its source stood
## on when it was queued, even if that unit has been defeated since: the selector picks the
## targets ([Area]), this resolver deals the damage. Pure and static; never instantiated.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md


## Deals [param amount] splash damage to [param target_id] in [param state] and records it.
## [param source_id]: the unit or object dealing it, or empty; it is credited with the defeat even
## if it was defeated itself since. [param source]: [constant CombatFact.Source.SPLASH],
## [constant CombatFact.Source.BUMP] or [constant CombatFact.Source.SPIKE]. Nothing happens for an
## amount of 0 or less, or a target off the map.
static func deal(
		engine: EffectEngine,
		state: CombatState,
		source_id: String,
		target_id: String,
		amount: int,
		source: CombatFact.Source,
		source_effect_id: String = ""
) -> void:
	if amount <= 0 or not state.has_unit(target_id):
		return
	var block: int = state.get_block(target_id)
	var hp: int = state.get_hp(target_id)
	var absorbed: int = mini(block, amount)
	var to_hp: int = mini(hp, amount - absorbed)
	state.set_block(target_id, block - absorbed)
	state.set_hp(target_id, hp - to_hp)

	var taken: CombatFact = CombatFact.new(CombatFact.Kind.DAMAGE_TAKEN, target_id, source_id)
	taken.amount = absorbed + to_hp
	taken.hp_amount = to_hp
	taken.block_amount = absorbed
	taken.source = source
	taken.source_effect_id = source_effect_id
	engine.record(taken)
	if state.get_hp(target_id) == 0:
		state.defeat(engine, target_id, source_id, source_effect_id)
