# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     damage_pipeline.gd
# Author:
# Created:  October 27, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name DamagePipeline
extends RefCounted
## The eight damage stages of one hit (game-vision.md, Combat; combat core plan, The exchange).
##
## [method compute] runs stages 1 to 5: Attack (weapon damage, Might, flat bonuses, the triangle,
## effectiveness), Mitigation (which may go below 0), Critical, and Multipliers (the attacker's
## Multipliers times the defender's Incoming multipliers) stay exact, and stage 5 rounds once,
## halves up, never below 0 (question 5). [method apply] runs stages 6 to 8: Block absorbs, HP
## takes the rest, and only damage that got through costs Stance, extra loss from that hit's inline
## effects included (question 10), and pays lifesteal through the engine's heal path.[br]
## Every value is read through the engine with the hit's [EffectContext], so "that hit" modifiers
## from either side's inline windows apply. Pure and static; never instantiated.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## How much Might adds per point: every MVP weapon has a scaling modifier of 1 (game-vision.md,
## Weapons and equipment).
const SCALING_MODIFIER: float = 1.0

## Stance a hit costs when damage gets through, before extra loss (game-vision.md, stage 8).
const STANCE_LOSS: float = 1.0


## Stages 1 to 5 of the hit in [param ctx] (its attacker, defender, weapon, triangle result and
## crit set): the exact value of each stage and the damage, rounded once.
static func compute(engine: EffectEngine, state: CombatState, ctx: EffectContext) -> HitDamage:
	var attacker: String = ctx.attacker_id
	var defender: String = ctx.defender_id
	var hit: HitDamage = HitDamage.new()
	var weapon: CombatState.WeaponStats = state.weapon(ctx.weapon_id)
	var weapon_damage: float = 0.0 if weapon == null else float(weapon.damage)
	var sheet: StatSheet = engine.stats(attacker)

	hit.attack = sheet.get_value(DamageStage.Key.ATTACK, ctx)
	hit.attack += SCALING_MODIFIER * sheet.get_value(CombatValue.Key.MGT, ctx)
	hit.attack += WeaponTriangle.damage_change(ctx.matchup, weapon_damage)
	hit.is_effective = _is_effective(state, weapon, defender)
	if hit.is_effective:
		var times: float = sheet.get_value(CombatValue.Key.EFFECTIVE_MODIFIER, ctx)
		hit.attack += (times - 1.0) * weapon_damage

	hit.damage_type = sheet.get_int(CombatValue.Key.DAMAGE_TYPE, ctx) as CombatFact.DamageType
	var skips: bool = (
			hit.damage_type == CombatFact.DamageType.PURE
			or ctx.has_flag(ModifyThat.Flag.SKIP_MITIGATION)
			or (
					ctx.is_crit
					and sheet.is_allowed(CombatValue.Permission.SKIP_MITIGATION_ON_CRIT, ctx)
			)
	)
	if not skips:
		hit.mitigation = mitigation(engine, state, defender, hit.damage_type, ctx).total

	if ctx.is_crit:
		var crit_x: float = sheet.get_value(CombatValue.Key.CRIT_X, ctx)
		hit.critical = value_with_base(
				engine, attacker, DamageStage.Key.CRITICAL, crit_x, "CritX", ctx
		).total
	hit.outgoing = sheet.explain(DamageStage.Key.MULTIPLIERS, ctx)
	hit.incoming = engine.stats(defender).explain(DamageStage.Key.INCOMING_MULTIPLIERS, ctx)
	hit.multipliers = hit.outgoing.total * hit.incoming.total

	hit.exact = (hit.attack - hit.mitigation) * hit.critical * hit.multipliers
	hit.damage = maxi(ValueBreakdown.round_to_int(hit.exact, ValueBreakdown.Rounding.HALF_UP), 0)
	return hit


## Stage 2 for [param defender] against [param damage_type]: its stat for the type plus its tile's
## DEF or RES bonus (Split: half of each, both stat and terrain) as the base, and every Mitigation
## modifier ("take 5 less damage", "takes 2 more damage") on top, with no floor. Pure damage
## meets 0. A map object meets only its own DEF or RES: terrain bonuses are for a unit standing
## on the tile.
static func mitigation(
		engine: EffectEngine,
		state: CombatState,
		defender: String,
		damage_type: CombatFact.DamageType,
		ctx: EffectContext
) -> ValueBreakdown:
	var sheet: StatSheet = engine.stats(defender)
	var bonus: CombatGrid.TileBonus = CombatGrid.TileBonus.new()
	# ASSUMPTION: an object takes no terrain DEF or RES (the plan names only its own; Godot_FE gave
	# an entity its own terrain in place of the tile's).
	if state.side_of(defender) != CombatFact.CombatSide.NONE:
		bonus = state.grid.tile_bonus(state.tile_of(defender))
	var defense: float = sheet.get_value(CombatValue.Key.DEF, ctx) + bonus.defense
	var resistance: float = sheet.get_value(CombatValue.Key.RES, ctx) + bonus.resistance
	var base: float = defense
	var label: String = "DEF"
	match damage_type:
		CombatFact.DamageType.MAGIC:
			base = resistance
			label = "RES"
		CombatFact.DamageType.SPLIT:
			base = (defense + resistance) / 2.0
			label = "half DEF and RES"
		CombatFact.DamageType.PURE:
			base = 0.0
			label = "pure"
	return value_with_base(engine, defender, DamageStage.Key.MITIGATION, base, label, ctx)


## Stages 6 to 8 of a hit of [param damage] from [param ctx]'s attacker: Block absorbs, HP takes
## the rest, Damage dealt and Damage taken, then, if the defender survives, Stance -1 plus the hit's
## extra loss (Exposed at 0), and lifesteal for the damage that reached HP. A fully countered hit
## (0) records nothing and costs no Stance. The caller records a defeat. Returns the HP lost.
static func apply(
		engine: EffectEngine,
		state: CombatState,
		ctx: EffectContext,
		damage: int,
		damage_type: CombatFact.DamageType
) -> int:
	var attacker: String = ctx.attacker_id
	var defender: String = ctx.defender_id
	if damage <= 0 or not state.has_unit(defender):
		return 0
	var block: int = state.get_block(defender)
	var hp: int = state.get_hp(defender)
	var absorbed: int = mini(block, damage)
	var to_hp: int = mini(hp, damage - absorbed)
	state.set_block(defender, block - absorbed)
	state.set_hp(defender, hp - to_hp)
	for kind: CombatFact.Kind in [CombatFact.Kind.DAMAGE_DEALT, CombatFact.Kind.DAMAGE_TAKEN]:
		var dealt: bool = kind == CombatFact.Kind.DAMAGE_DEALT
		var fact: CombatFact = CombatFact.new(
				kind, attacker if dealt else defender, defender if dealt else attacker
		)
		fact.amount = absorbed + to_hp
		fact.hp_amount = to_hp
		fact.block_amount = absorbed
		fact.damage_type = damage_type
		fact.source = CombatFact.Source.ATTACK
		engine.record(fact, ctx)

	if state.get_hp(defender) > 0:
		engine.change_stance(defender, -(STANCE_LOSS + ctx.extra_stance_loss()), attacker)
	if ctx.has_flag(ModifyThat.Flag.LIFESTEAL) and to_hp > 0:
		engine.heal(attacker, to_hp)
	return to_hp


## [param key] for [param subject_id] with [param base] in place of its sheet's base, and every
## modifier the sheet and the engine's live part give it: a value whose base is a rule or the map
## (Attack Speed, avoid with terrain, mitigation), so every modifier mode still applies.
static func value_with_base(
		engine: EffectEngine,
		subject_id: String,
		key: int,
		base: float,
		label: String,
		ctx: EffectContext
) -> ValueBreakdown:
	var modifiers: Array[Modifier] = engine.stats(subject_id).get_modifiers(key)
	modifiers.append_array(engine.live_modifiers(subject_id, key, ctx))
	return ValueBreakdown.compute(key, base, label, modifiers)


static func _is_effective(
		state: CombatState, weapon: CombatState.WeaponStats, defender: String
) -> bool:
	if weapon == null or not state.has_unit(defender):
		return false
	for tag: String in state.unit(defender).tags:
		if weapon.effective_against.has(tag):
			return true
	return false


## Stages 1 to 5 of one hit, exact until [member damage].
class HitDamage:
	extends RefCounted

	## Stage 1: weapon damage, Might, flat bonuses, the triangle and effectiveness.
	var attack: float = 0.0
	## Stage 2: the defender's mitigation, subtracted; 0 when skipped. Below 0 it adds damage.
	var mitigation: float = 0.0
	## Stage 3: the crit multiplier; 1 without a crit.
	var critical: float = 1.0
	## Stage 4: [member outgoing] times [member incoming].
	var multipliers: float = 1.0
	## Stage 4's attacker side, one line per source: its Multipliers, with every "that hit"
	## modifier on the key from either side's inline windows.
	var outgoing: ValueBreakdown = null
	## Stage 4's defender side, one line per source: its Incoming multipliers.
	var incoming: ValueBreakdown = null
	## Stages 1 to 4 combined, before rounding.
	var exact: float = 0.0
	## Stage 5: rounded once, halves up, never below 0. 0 is fully countered.
	var damage: int = 0
	## The hit's damage type, after any override.
	var damage_type: CombatFact.DamageType = CombatFact.DamageType.PHYSICAL
	## Whether the weapon is effective against the defender.
	var is_effective: bool = false
