# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     exchange_resolver.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name ExchangeResolver
extends RefCounted
## One combat exchange, from Before Combat to After Combat (combat core plan, The exchange).
##
## The attacker attacks with the weapon in its Weapon slot from the tile it stands on. Before
## Combat fires for both units and the reaction queue drains, so Before Combat Block lands before
## the first attack. The attacker takes the first turn, the defender the second if it can counter,
## then the faster unit its [BonusTurns]. Each turn makes [code]max(1, AtkX - Parry)[/code]
## attacks; each attack rolls Hit with 2RN, a hit on an Exposed defender rolls one d100 for a crit,
## and [DamagePipeline] resolves the damage. The exchange stops at the first defeat. After Combat
## fires for the survivors, "this exchange" modifiers expire, and the queue drains again: reactions
## to anything inside the exchange (Cleave's splash, Momentum) land there, never between attacks,
## and a reaction queued by a unit defeated later still resolves.[br]
## Pure and static: the same code runs for real resolution, a forecast and an AI branch, with the
## engine's roll source deciding. The caller starts the resolution step
## ([method EffectEngine.begin_step]).
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## The crit chance against an Exposed defender before bonuses: [code]ExposureConstant[/code]
## (game-vision.md, Stance and Exposure).
const CRIT_BASE: int = 25


## Resolves an exchange of [param attacker_id] on [param defender_id]. An illegal exchange records
## nothing; see [member Result.reason]. A legal one marks the attacker as having acted, and an
## attack staff spends a use first ([method ItemUseResolver.use_effects]).
static func resolve(
		engine: EffectEngine, state: CombatState, attacker_id: String, defender_id: String
) -> Result:
	var result: Result = Result.new()
	result.reason = check(engine, state, attacker_id, defender_id)
	if not result.reason.is_empty():
		return result
	result.is_legal = true
	state.unit(attacker_id).has_acted = true
	var weapon: CombatState.WeaponStats = state.equipped_weapon(attacker_id)
	if weapon.staff == CombatState.WeaponStats.Staff.ATTACK:
		ItemUseResolver.spend(
				engine, ItemUseResolver.use_effects(engine, weapon.id), defender_id
		)

	var before: EffectContext = context(engine, state, attacker_id, defender_id, attacker_id, -1)
	engine.record(CombatFact.new(CombatFact.Kind.BEFORE_COMBAT, attacker_id, defender_id), before)
	engine.record(CombatFact.new(CombatFact.Kind.BEFORE_COMBAT, defender_id, attacker_id), before)
	engine.drain()

	result.can_counter = can_counter(engine, state, defender_id, attacker_id)
	var order: PackedStringArray = turn_order(engine, state, attacker_id, defender_id)
	result.turns = order.size()
	var index: int = 0
	for turn_unit: String in order:
		var target: String = defender_id if turn_unit == attacker_id else attacker_id
		if not state.has_unit(turn_unit) or not state.has_unit(target):
			break
		var count: int = attacks_per_turn(engine, state, turn_unit, target, attacker_id)
		for i: int in count:
			var ctx: EffectContext = context(
					engine, state, turn_unit, target, attacker_id, index
			)
			index += 1
			if attack(engine, state, ctx):
				break
		if not state.has_unit(turn_unit) or not state.has_unit(target):
			break
	result.attacks = index
	result.attacker_defeated = not state.has_unit(attacker_id)
	result.defender_defeated = not state.has_unit(defender_id)

	var after: EffectContext = context(engine, state, attacker_id, defender_id, attacker_id, -1)
	for unit_id: String in [attacker_id, defender_id]:
		if state.has_unit(unit_id):
			var other: String = defender_id if unit_id == attacker_id else attacker_id
			engine.record(CombatFact.new(CombatFact.Kind.AFTER_COMBAT, unit_id, other), after)
	engine.reach_boundary(EffectEngine.Boundary.EXCHANGE_END)
	engine.drain()
	return result


## Why [param attacker_id] can't attack [param defender_id] now; empty when it can. Legal: both on
## the map and on opposing sides, the attacker holds a weapon that isn't a Block or heal staff (an
## attack staff needs a use left), and its range covers the distance.
static func check(
		engine: EffectEngine, state: CombatState, attacker_id: String, defender_id: String
) -> String:
	if not state.has_unit(attacker_id) or not state.has_unit(defender_id):
		return "not on the map"
	if not engine.matches_side(
			state.side_of(attacker_id), defender_id, EffectDefinition.UnitSide.ENEMY
	):
		return "not an enemy"
	var weapon: CombatState.WeaponStats = state.equipped_weapon(attacker_id)
	if weapon == null:
		return "no weapon"
	if weapon.is_staff() and weapon.staff != CombatState.WeaponStats.Staff.ATTACK:
		return "a support staff can't attack"
	if not ItemUseResolver.has_uses(ItemUseResolver.use_effects(engine, weapon.id)):
		return "no uses left"
	var ctx: EffectContext = context(engine, state, attacker_id, defender_id, attacker_id, -1)
	if not in_range(engine, attacker_id, ctx):
		return "out of range"
	return ""


## Whether [param defender_id] can counter [param attacker_id]: it holds a weapon that isn't a
## staff, its range covers the distance, and nothing denies
## [constant CombatValue.Permission.CAN_COUNTER].
static func can_counter(
		engine: EffectEngine, state: CombatState, defender_id: String, attacker_id: String
) -> bool:
	var weapon: CombatState.WeaponStats = state.equipped_weapon(defender_id)
	if weapon == null or weapon.is_staff():
		return false
	var ctx: EffectContext = context(engine, state, defender_id, attacker_id, attacker_id, -1)
	if not in_range(engine, defender_id, ctx):
		return false
	return engine.stats(defender_id).is_allowed(CombatValue.Permission.CAN_COUNTER, ctx)


## The units taking each turn, in order: the attacker, the defender if it can counter, then the
## faster unit's bonus turns from the Attack Speed gap. A unit that can't counter gets no turns.
static func turn_order(
		engine: EffectEngine, state: CombatState, attacker_id: String, defender_id: String
) -> PackedStringArray:
	var order: PackedStringArray = [attacker_id]
	var counters: bool = can_counter(engine, state, defender_id, attacker_id)
	if counters:
		order.append(defender_id)
	var ctx: EffectContext = context(engine, state, attacker_id, defender_id, attacker_id, -1)
	var gap: int = (
			attack_speed(engine, attacker_id, ctx).get_int()
			- attack_speed(engine, defender_id, ctx).get_int()
	)
	var faster: String = attacker_id if gap > 0 else defender_id
	if faster == defender_id and not counters:
		return order
	for i: int in BonusTurns.count(absi(gap)):
		order.append(faster)
	return order


## Attack Speed of [param unit_id]: [code]SPD - max(0, NET_WEIGHT - CON)[/code] as the base, with
## every Attack Speed modifier on top.
static func attack_speed(
		engine: EffectEngine, unit_id: String, ctx: EffectContext
) -> ValueBreakdown:
	var sheet: StatSheet = engine.stats(unit_id)
	var burden: float = maxf(
			sheet.get_value(CombatValue.Key.NET_WEIGHT, ctx)
			- sheet.get_value(CombatValue.Key.CON, ctx),
			0.0
	)
	var base: float = sheet.get_value(CombatValue.Key.SPD, ctx) - burden
	return DamagePipeline.value_with_base(
			engine, unit_id, CombatValue.Key.ATTACK_SPEED, base, "SPD - weight", ctx
	)


## Attacks [param unit_id] makes in one turn against [param target_id]:
## [code]max(1, AtkX - the target's Parry)[/code].
static func attacks_per_turn(
		engine: EffectEngine,
		state: CombatState,
		unit_id: String,
		target_id: String,
		initiator_id: String
) -> int:
	var ctx: EffectContext = context(engine, state, unit_id, target_id, initiator_id, -1)
	var atk_x: int = engine.stats(unit_id).get_int(CombatValue.Key.ATK_X, ctx)
	var parry: int = engine.stats(target_id).get_int(CombatValue.Key.PARRY, ctx)
	return maxi(1, atk_x - parry)


## [param ctx]'s attacker's Hit against its defender: weapon Hit and effects, plus or minus 15 for
## the triangle, minus the defender's avoid (terrain plus effects), clamped to 0 to 100.
static func hit_chance(engine: EffectEngine, state: CombatState, ctx: EffectContext) -> int:
	var hit: float = engine.stats(ctx.attacker_id).get_value(CombatValue.Key.HIT, ctx)
	hit += WeaponTriangle.hit_change(ctx.matchup)
	var terrain: int = state.grid.tile_bonus(state.tile_of(ctx.defender_id)).avoid
	var avoid: ValueBreakdown = DamagePipeline.value_with_base(
			engine, ctx.defender_id, CombatValue.Key.AVOID, terrain, "terrain", ctx
	)
	var chance: float = hit - avoid.total
	return clampi(ValueBreakdown.round_to_int(chance, ValueBreakdown.Rounding.HALF_UP), 0, 100)


## One attack in [param ctx]: Attack made (its inline window first), the 2RN hit roll, then on a
## hit Hit dealt and Hit taken (windows through stage 8), the crit roll against an Exposed
## defender, Crit dealt and Crit taken, the damage stages, and a defeat. Spends one use of the
## attacker's "next attack" modifiers. Returns whether the defender was defeated.
static func attack(engine: EffectEngine, state: CombatState, ctx: EffectContext) -> bool:
	var a: String = ctx.attacker_id
	var d: String = ctx.defender_id
	var made: CombatFact = CombatFact.new(CombatFact.Kind.ATTACK_MADE, a, d)
	engine.open_window(made, ctx)
	engine.record(made, ctx)

	if not engine.rolls.roll_hit_2rn(hit_chance(engine, state, ctx)):
		engine.record(CombatFact.new(CombatFact.Kind.MISSED, a, d), ctx)
		engine.record(CombatFact.new(CombatFact.Kind.DODGED, d, a), ctx)
		engine.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, a)
		return false

	ctx.defender_was_exposed = state.get_stance(d) == 0
	var facts: Array[CombatFact] = [
		CombatFact.new(CombatFact.Kind.HIT_DEALT, a, d),
		CombatFact.new(CombatFact.Kind.HIT_TAKEN, d, a),
	]
	for fact: CombatFact in facts:
		engine.open_window(fact, ctx)
	if ctx.defender_was_exposed:
		var chance: int = CRIT_BASE + engine.stats(a).get_int(CombatValue.Key.CRIT_CHANCE, ctx)
		ctx.is_crit = engine.rolls.roll_percent(chance)
	if ctx.is_crit:
		var crits: Array[CombatFact] = [
			CombatFact.new(CombatFact.Kind.CRIT_DEALT, a, d),
			CombatFact.new(CombatFact.Kind.CRIT_TAKEN, d, a),
		]
		for fact: CombatFact in crits:
			engine.open_window(fact, ctx)
		facts.append_array(crits)

	var hit: DamagePipeline.HitDamage = DamagePipeline.compute(engine, state, ctx)
	for fact: CombatFact in facts:
		fact.amount = hit.damage
		fact.damage_type = hit.damage_type
		engine.record(fact, ctx)
	DamagePipeline.apply(engine, state, ctx, hit.damage, hit.damage_type)
	var defeated: bool = state.get_hp(d) == 0
	if defeated:
		state.defeat(engine, d, a)
	engine.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, a)
	return defeated


## A context for [param attacker_id]'s attack on [param defender_id] in the exchange
## [param initiator_id] started: weapon, origin tile, distance and triangle result filled in.
## [param index]: the attack's position in the exchange, or -1 outside an attack.
static func context(
		engine: EffectEngine,
		state: CombatState,
		attacker_id: String,
		defender_id: String,
		initiator_id: String,
		index: int
) -> EffectContext:
	var ctx: EffectContext = EffectContext.new()
	ctx.engine = engine
	ctx.attacker_id = attacker_id
	ctx.defender_id = defender_id
	ctx.initiator_id = initiator_id
	ctx.weapon_id = state.equipped_weapon_id(attacker_id)
	ctx.origin_tile = state.tile_of(attacker_id)
	ctx.distance = state.grid.distance(ctx.origin_tile, state.tile_of(defender_id))
	ctx.attack_index = index
	var own: CombatState.WeaponStats = state.equipped_weapon(attacker_id)
	var theirs: CombatState.WeaponStats = state.equipped_weapon(defender_id)
	if own != null and theirs != null:
		ctx.matchup = WeaponTriangle.matchup(own.profile, theirs.profile)
	return ctx


## Whether [param ctx]'s distance is within [param unit_id]'s range, read with [param ctx].
static func in_range(engine: EffectEngine, unit_id: String, ctx: EffectContext) -> bool:
	var sheet: StatSheet = engine.stats(unit_id)
	return (
			ctx.distance >= sheet.get_int(CombatValue.Key.RANGE_MIN, ctx)
			and ctx.distance <= sheet.get_int(CombatValue.Key.RANGE_MAX, ctx)
	)


## What an exchange did, for its caller (the command, the forecast, the AI).
class Result:
	extends RefCounted

	## Whether the exchange was legal and resolved.
	var is_legal: bool = false
	## Why it wasn't; empty when it was.
	var reason: String = ""
	## Whether the defender could counter.
	var can_counter: bool = false
	## Turns in the order, bonus turns included, whether or not all were reached.
	var turns: int = 0
	## Attacks made.
	var attacks: int = 0
	## Whether the attacker was defeated.
	var attacker_defeated: bool = false
	## Whether the defender was defeated.
	var defender_defeated: bool = false
