# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fake_exchange.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

extends RefCounted
## A small stand-in for the combat core's turn loop, exchange and commands, for the effect engine's
## golden logs and odds tests.
##
## Test-only and deliberately simplified: it calls the engine at the points the combat core plan
## names (windows, boundaries, drains) so the engine's behavior can be checked, but its damage math
## is a placeholder. Hit is HIT minus AVOID; damage is (Attack stage - Mitigation stage) × CritX on
## a crit × Multipliers stage, rounded half up, never below 0; a crit needs an Exposed defender and
## rolls [constant CRIT_BASE] + CRIT_CHANCE. None of this is a combat rule.

# The harness's crit roll base, standing in for the combat core's.
const CRIT_BASE: int = 25

## The engine every call goes through.
var engine: EffectEngine = null

## The turn counter, raised at each player Phase Start.
var turn: int = 0


func _init(effect_engine: EffectEngine) -> void:
	engine = effect_engine


## Phase Start for [param side]: refresh, Phase Start, Unit Turn Start per unit, then the drain.
func phase_start(side: CombatFact.CombatSide) -> void:
	engine.begin_step()
	if side == CombatFact.CombatSide.PLAYER:
		turn += 1
	var units: PackedStringArray = _units_of(side)
	for unit_id: String in units:
		engine.state.set_block(unit_id, 0)
		engine.state.set_stance(unit_id, engine.stats(unit_id).get_int(CombatValue.Key.STANCE_MAX))
		engine.record(CombatFact.new(CombatFact.Kind.BLOCK_STANCE_REFRESHED, unit_id))
	var phase: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_START)
	phase.side = side
	phase.amount = turn
	engine.record(phase)
	for unit_id: String in units:
		engine.record(CombatFact.new(CombatFact.Kind.UNIT_TURN_START, unit_id))
	engine.drain()


## Phase End for [param side]: Phase End, Unit Turn End per unit, the drain, then the boundary.
func phase_end(side: CombatFact.CombatSide) -> void:
	engine.begin_step()
	var phase: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_END)
	phase.side = side
	engine.record(phase)
	for unit_id: String in _units_of(side):
		engine.record(CombatFact.new(CombatFact.Kind.UNIT_TURN_END, unit_id))
	engine.drain()
	engine.reach_boundary(EffectEngine.Boundary.PHASE_END)


## One exchange: Before Combat for both (then the drain), the attacks in [param order] ("a" for
## the attacker, "d" for the defender; a defender that may not counter skips its letters), After
## Combat for each survivor, the exchange boundary, then the drain. Stops at a defeat.
## [param matchup]: the attacker's triangle result.
func exchange(
		attacker: String,
		defender: String,
		order: String = "ad",
		matchup: WhileMatchupCondition.Matchup = WhileMatchupCondition.Matchup.STANDOFF,
		distance: int = 1
) -> void:
	engine.begin_step()
	var before: EffectContext = _context(attacker, defender, attacker, matchup, distance, -1)
	engine.record(CombatFact.new(CombatFact.Kind.BEFORE_COMBAT, attacker, defender), before)
	engine.record(CombatFact.new(CombatFact.Kind.BEFORE_COMBAT, defender, attacker), before)
	engine.drain()

	var counters: bool = engine.stats(defender).is_allowed(CombatValue.Permission.CAN_COUNTER)
	for index: int in order.length():
		var by_attacker: bool = order[index] == "a"
		if not by_attacker and not counters:
			continue
		var from: String = attacker if by_attacker else defender
		var to: String = defender if by_attacker else attacker
		var result: WhileMatchupCondition.Matchup = matchup if by_attacker else _mirror(matchup)
		if attack(_context(from, to, attacker, result, distance, index)):
			break

	var after: EffectContext = _context(attacker, defender, attacker, matchup, distance, -1)
	for unit_id: String in [attacker, defender]:
		if engine.state.has_unit(unit_id):
			var other: String = defender if unit_id == attacker else attacker
			engine.record(CombatFact.new(CombatFact.Kind.AFTER_COMBAT, unit_id, other), after)
	engine.reach_boundary(EffectEngine.Boundary.EXCHANGE_END)
	engine.drain()


## One attack with [param ctx]'s attacker and defender. Returns whether the defender was defeated.
func attack(ctx: EffectContext) -> bool:
	var a: String = ctx.attacker_id
	var d: String = ctx.defender_id
	var state: SandboxState = engine.state
	var made: CombatFact = CombatFact.new(CombatFact.Kind.ATTACK_MADE, a, d)
	engine.open_window(made, ctx)
	engine.record(made, ctx)

	var hit: int = (
			engine.stats(a).get_int(CombatValue.Key.HIT, ctx)
			- engine.stats(d).get_int(CombatValue.Key.AVOID, ctx)
	)
	if not engine.rolls.roll_hit_2rn(hit):
		engine.record(CombatFact.new(CombatFact.Kind.MISSED, a, d), ctx)
		engine.record(CombatFact.new(CombatFact.Kind.DODGED, d, a), ctx)
		engine.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, a)
		return false

	ctx.defender_was_exposed = state.get_stance(d) == 0
	if ctx.defender_was_exposed:
		var chance: int = CRIT_BASE + engine.stats(a).get_int(CombatValue.Key.CRIT_CHANCE, ctx)
		ctx.is_crit = engine.rolls.roll_percent(chance)
	var dealt: CombatFact = CombatFact.new(CombatFact.Kind.HIT_DEALT, a, d)
	var taken: CombatFact = CombatFact.new(CombatFact.Kind.HIT_TAKEN, d, a)
	var crits: Array[CombatFact] = []
	if ctx.is_crit:
		crits.append(CombatFact.new(CombatFact.Kind.CRIT_DEALT, a, d))
		crits.append(CombatFact.new(CombatFact.Kind.CRIT_TAKEN, d, a))
	for fact: CombatFact in [dealt, taken] + crits:
		engine.open_window(fact, ctx)

	var damage: int = _damage(ctx)
	for fact: CombatFact in [dealt, taken] + crits:
		fact.amount = damage
		engine.record(fact, ctx)
	if damage > 0:
		_apply_damage(ctx, damage)
	var defeated: bool = state.get_hp(d) == 0
	if defeated:
		engine.record(CombatFact.new(CombatFact.Kind.DEFEATED, d, a), ctx)
		engine.record(CombatFact.new(CombatFact.Kind.DEFEATED_AN_ENEMY, a, d), ctx)
		# Variant: the fake state has no class name; its units are marked defeated directly.
		var fake: Variant = state
		fake.unit(d).defeated = true
	engine.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, a)
	return defeated


## A staff's Block on [param target]: the Block-gain path, then Used a staff on an ally.
func staff_block(user: String, target: String, amount: float) -> void:
	engine.begin_step()
	engine.gain_block(target, amount, user)
	engine.record(CombatFact.new(CombatFact.Kind.USED_STAFF_ON_ALLY, user, target))
	engine.drain()


## A heal staff on [param target]: the heal path, then Used a staff on an ally.
func staff_heal(user: String, target: String, amount: float) -> void:
	engine.begin_step()
	engine.heal(target, amount, user)
	engine.record(CombatFact.new(CombatFact.Kind.USED_STAFF_ON_ALLY, user, target))
	engine.drain()


## A Pouch item: its effect fires as a command, then Item used, then the drain. Returns whether
## the effect fired (it may be out of charges).
func use_item(user: String, target: String, item: EffectInstance) -> bool:
	engine.begin_step()
	var ctx: EffectContext = EffectContext.new()
	ctx.command_target_id = target
	var fired: bool = engine.activate(item, ctx)
	if fired:
		var used: CombatFact = CombatFact.new(CombatFact.Kind.ITEM_USED, user, target)
		used.item_id = item.owner.owner_id
		engine.record(used)
	engine.drain()
	return fired


## A rune cast by [param seat] on [param target]: its effect fires, then Rune used, then the drain.
func cast_rune(seat: int, rune: EffectInstance, target: String) -> void:
	engine.begin_step()
	var ctx: EffectContext = EffectContext.new()
	ctx.command_target_id = target
	engine.activate(rune, ctx)
	var used: CombatFact = CombatFact.new(CombatFact.Kind.RUNE_USED, "", target)
	used.item_id = rune.owner.owner_id
	used.amount = seat
	engine.record(used)
	engine.drain()


## Darkness damage to [param unit_id]: the window (Lantern Oil), [param base] × the window's
## Multipliers modifiers, rounded down with a minimum of 1 (the darkness plan's rule), then the
## drain.
func darkness(unit_id: String, base: int) -> void:
	engine.begin_step()
	var ctx: EffectContext = EffectContext.new()
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_DAMAGE_TAKEN, unit_id)
	fact.source = CombatFact.Source.DARKNESS
	engine.open_window(fact, ctx)
	var multiplier: float = ValueBreakdown.compute(
			DamageStage.Key.MULTIPLIERS, 1.0, "", ctx.that_modifiers(DamageStage.Key.MULTIPLIERS)
	).total
	var damage: int = maxi(
			ValueBreakdown.round_to_int(base * multiplier, ValueBreakdown.Rounding.FLOOR), 1
	)
	var hp: int = engine.state.get_hp(unit_id)
	fact.amount = damage
	fact.hp_amount = mini(damage, hp)
	engine.state.set_hp(unit_id, hp - fact.hp_amount)
	engine.record(fact, ctx)
	engine.drain()


func _damage(ctx: EffectContext) -> int:
	var a: String = ctx.attacker_id
	var d: String = ctx.defender_id
	var attack_value: float = engine.stats(a).get_value(DamageStage.Key.ATTACK, ctx)
	var mitigation: float = 0.0
	if not ctx.has_flag(ModifyThat.Flag.SKIP_MITIGATION):
		mitigation = engine.stats(d).get_value(DamageStage.Key.MITIGATION, ctx)
	var crit: float = engine.stats(a).get_value(CombatValue.Key.CRIT_X, ctx) if ctx.is_crit else 1.0
	var multiplier: float = engine.stats(a).get_value(DamageStage.Key.MULTIPLIERS, ctx)
	var exact: float = maxf(attack_value - mitigation, 0.0) * crit * multiplier
	return maxi(ValueBreakdown.round_to_int(exact, ValueBreakdown.Rounding.HALF_UP), 0)


# Block absorbs, then HP; Damage dealt and taken; Stance -1 plus the hit's extra loss; lifesteal.
func _apply_damage(ctx: EffectContext, damage: int) -> void:
	var a: String = ctx.attacker_id
	var d: String = ctx.defender_id
	var state: SandboxState = engine.state
	var absorbed: int = mini(state.get_block(d), damage)
	var to_hp: int = mini(state.get_hp(d), damage - absorbed)
	state.set_block(d, state.get_block(d) - absorbed)
	state.set_hp(d, state.get_hp(d) - to_hp)
	for kind: CombatFact.Kind in [CombatFact.Kind.DAMAGE_DEALT, CombatFact.Kind.DAMAGE_TAKEN]:
		var dealt: bool = kind == CombatFact.Kind.DAMAGE_DEALT
		var fact: CombatFact = CombatFact.new(kind, a if dealt else d, d if dealt else a)
		fact.amount = damage
		fact.hp_amount = to_hp
		fact.block_amount = absorbed
		fact.source = CombatFact.Source.ATTACK
		engine.record(fact, ctx)
	engine.change_stance(d, -(1.0 + ctx.extra_stance_loss()), a)
	if ctx.has_flag(ModifyThat.Flag.LIFESTEAL) and to_hp > 0:
		engine.heal(a, to_hp)


func _context(
		attacker: String,
		defender: String,
		initiator: String,
		matchup: WhileMatchupCondition.Matchup,
		distance: int,
		index: int
) -> EffectContext:
	var ctx: EffectContext = EffectContext.new()
	ctx.attacker_id = attacker
	ctx.defender_id = defender
	ctx.initiator_id = initiator
	ctx.matchup = matchup
	ctx.distance = distance
	ctx.attack_index = index
	return ctx


func _units_of(side: CombatFact.CombatSide) -> PackedStringArray:
	var units: PackedStringArray = []
	for unit_id: String in engine.state.unit_ids():
		if engine.state.side_of(unit_id) == side:
			units.append(unit_id)
	return units


static func _mirror(matchup: WhileMatchupCondition.Matchup) -> WhileMatchupCondition.Matchup:
	match matchup:
		WhileMatchupCondition.Matchup.ADVANTAGE:
			return WhileMatchupCondition.Matchup.DISADVANTAGE
		WhileMatchupCondition.Matchup.DISADVANTAGE:
			return WhileMatchupCondition.Matchup.ADVANTAGE
	return WhileMatchupCondition.Matchup.STANDOFF
