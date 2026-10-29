# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     exchange_cases.gd
# Author:
# Created:  October 27, 2026
# Modified: October 29, 2026
# ==============================================================================

extends RefCounted
## The exchange's cases for tests/combat/run_all.gd: one golden fact log per fixture in the combat
## core plan's Verification list that the exchange covers, the two-sided damage stages (each side's
## multipliers, negative Mitigation, conditions on the attack in flight), the property tests, and
## the 2RN distribution test.
##
## Real resolution: every exchange rolls through [LiveRolls] over a seeded [RngStream]. A fixture
## that needs a sure outcome gets it from the numbers (Hit 100 always hits, Hit 0 always misses,
## crit chance 100 always crits), never from a forced roll. Every scenario also asserts that the
## engine reported no diagnostics.

# A preloaded script used as a type (gdscript.md, Naming): the test map has no class name.
const CombatWorld = preload("res://tests/combat/combat_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ADD: Modifier.Mode = Modifier.Mode.ADD
const ADVANTAGE: WhileMatchupCondition.Matchup = WhileMatchupCondition.Matchup.ADVANTAGE
const STANDOFF: WhileMatchupCondition.Matchup = WhileMatchupCondition.Matchup.STANDOFF
const DISADVANTAGE: WhileMatchupCondition.Matchup = WhileMatchupCondition.Matchup.DISADVANTAGE

# The seed of every fixture's stream.
const SEED: int = 20261027

# Draws per Hit value in the 2RN distribution test (combat core plan, Verification: 10^5).
const DISTRIBUTION_DRAWS: int = 100000

# Allowed gap between the observed and the analytic hit rate: above 4 standard deviations of
# 10^5 draws at the worst case (p = 0.5, sd 0.00158), so a correct roll fails about once in 15,000.
const DISTRIBUTION_TOLERANCE: float = 0.0065

# Base stats of every fixture unit: Might 3, Speed 5, Defense 2, Resistance 1, and Constitution 20,
# so no weapon slows anyone unless a case lowers it.
const UNIT_BASES: Dictionary = {
	CombatValue.Key.MGT: 3.0,
	CombatValue.Key.SPD: 5.0,
	CombatValue.Key.DEF: 2.0,
	CombatValue.Key.RES: 1.0,
	CombatValue.Key.CON: 20.0,
}

# Reviewed golden fact logs, one CombatFact.to_log_line() per fact, by fixture name.
const GOLDEN: Dictionary[String, Array] = {
	"two-sided multipliers": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 28 type magic",
		"s0#5 HIT_TAKEN e1 <- p1 amount 28 type magic",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 28 (hp 28, block 0) source attack type magic",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 28 (hp 28, block 0) source attack type magic",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE e1 -> p1",
		"s0#10 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#11 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#12 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#13 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#14 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#15 ATTACK_MADE e1 -> p1",
		"s0#16 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#17 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#18 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#19 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#20 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#21 EXPOSED p1 -> e1",
		"s0#22 AFTER_COMBAT p1 -> e1",
		"s0#23 AFTER_COMBAT e1 -> p1",
	],
	"plain exchange": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 MISSED p1 -> e1",
		"s0#5 DODGED e1 <- p1",
		"s0#6 ATTACK_MADE e1 -> p1",
		"s0#7 HIT_DEALT e1 -> p1 amount 6 type physical",
		"s0#8 HIT_TAKEN p1 <- e1 amount 6 type physical",
		"s0#9 DAMAGE_DEALT e1 -> p1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#10 DAMAGE_TAKEN p1 <- e1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#11 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#12 AFTER_COMBAT p1 -> e1",
		"s0#13 AFTER_COMBAT e1 -> p1",
	],
	"triangle advantage": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 10 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 10 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 10 (hp 10, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 10 (hp 10, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE e1 -> p1",
		"s0#10 MISSED e1 -> p1",
		"s0#11 DODGED p1 <- e1",
		"s0#12 AFTER_COMBAT p1 -> e1",
		"s0#13 AFTER_COMBAT e1 -> p1",
	],
	"effectiveness": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 19 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 19 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 19 (hp 19, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 19 (hp 19, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 AFTER_COMBAT p1 -> e1",
		"s0#10 AFTER_COMBAT e1 -> p1",
	],
	"bonus turn at a gap of 4": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE e1 -> p1",
		"s0#10 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#11 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#12 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#13 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#14 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#15 ATTACK_MADE p1 -> e1",
		"s0#16 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#17 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#18 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#19 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#20 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#21 EXPOSED e1 -> p1",
		"s0#22 AFTER_COMBAT p1 -> e1",
		"s0#23 AFTER_COMBAT e1 -> p1",
	],
	"bonus turns at a gap of 10": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE e1 -> p1",
		"s0#10 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#11 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#12 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#13 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#14 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#15 ATTACK_MADE p1 -> e1",
		"s0#16 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#17 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#18 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#19 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#20 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#21 EXPOSED e1 -> p1",
		"s0#22 ATTACK_MADE p1 -> e1",
		"s0#23 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#24 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#25 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#26 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#27 AFTER_COMBAT p1 -> e1",
		"s0#28 AFTER_COMBAT e1 -> p1",
	],
	"crit on an Exposed target": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 15 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 15 type physical",
		"s0#6 CRIT_DEALT p1 -> e1 amount 15 type physical",
		"s0#7 CRIT_TAKEN e1 <- p1 amount 15 type physical",
		"s0#8 DAMAGE_DEALT p1 -> e1 amount 15 (hp 15, block 0) source attack type physical",
		"s0#9 DAMAGE_TAKEN e1 <- p1 amount 15 (hp 15, block 0) source attack type physical",
		"s0#10 ATTACK_MADE e1 -> p1",
		"s0#11 HIT_DEALT e1 -> p1 amount 6 type physical",
		"s0#12 HIT_TAKEN p1 <- e1 amount 6 type physical",
		"s0#13 DAMAGE_DEALT e1 -> p1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#14 DAMAGE_TAKEN p1 <- e1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#15 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#16 AFTER_COMBAT p1 -> e1",
		"s0#17 AFTER_COMBAT e1 -> p1",
	],
	"parry cutting attacks": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE e1 -> p1",
		"s0#10 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#11 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#12 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#13 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#14 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#15 ATTACK_MADE e1 -> p1",
		"s0#16 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#17 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#18 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#19 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#20 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#21 EXPOSED p1 -> e1",
		"s0#22 AFTER_COMBAT p1 -> e1",
		"s0#23 AFTER_COMBAT e1 -> p1",
	],
	"full mitigation": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 type physical",
		"s0#6 ATTACK_MADE e1 -> p1",
		"s0#7 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#8 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#9 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#10 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#11 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#12 AFTER_COMBAT p1 -> e1",
		"s0#13 AFTER_COMBAT e1 -> p1",
	],
	"block absorbing": [
		"s0#2 BEFORE_COMBAT p1 -> e1",
		"s0#3 BEFORE_COMBAT e1 -> p1",
		"s0#4 ATTACK_MADE p1 -> e1",
		"s0#5 HIT_DEALT p1 -> e1 amount 5 type physical",
		"s0#6 HIT_TAKEN e1 <- p1 amount 5 type physical",
		"s0#7 DAMAGE_DEALT p1 -> e1 amount 5 (hp 1, block 4) source attack type physical",
		"s0#8 DAMAGE_TAKEN e1 <- p1 amount 5 (hp 1, block 4) source attack type physical",
		"s0#9 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#10 ATTACK_MADE e1 -> p1",
		"s0#11 HIT_DEALT e1 -> p1 amount 6 type physical",
		"s0#12 HIT_TAKEN p1 <- e1 amount 6 type physical",
		"s0#13 DAMAGE_DEALT e1 -> p1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#14 DAMAGE_TAKEN p1 <- e1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#15 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#16 AFTER_COMBAT p1 -> e1",
		"s0#17 AFTER_COMBAT e1 -> p1",
	],
	"defeat mid-exchange": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 4 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 4 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 4 (hp 4, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 4 (hp 4, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE p1 -> e1",
		"s0#10 HIT_DEALT p1 -> e1 amount 4 type physical",
		"s0#11 HIT_TAKEN e1 <- p1 amount 4 type physical",
		"s0#12 DAMAGE_DEALT p1 -> e1 amount 1 (hp 1, block 0) source attack type physical",
		"s0#13 DAMAGE_TAKEN e1 <- p1 amount 1 (hp 1, block 0) source attack type physical",
		"s0#14 DEFEATED e1 <- p1",
		"s0#15 DEFEATED_AN_ENEMY p1 -> e1",
		"s0#16 AFTER_COMBAT p1 -> e1",
	],
	"attacker defeated by the counter": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 MISSED p1 -> e1",
		"s0#5 DODGED e1 <- p1",
		"s0#6 ATTACK_MADE e1 -> p1",
		"s0#7 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#8 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#9 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#10 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#11 DEFEATED p1 <- e1",
		"s0#12 DEFEATED_AN_ENEMY e1 -> p1",
		"s0#13 AFTER_COMBAT e1 -> p1",
	],
	"bow can't counter at 1": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 MISSED p1 -> e1",
		"s0#5 DODGED e1 <- p1",
		"s0#6 AFTER_COMBAT p1 -> e1",
		"s0#7 AFTER_COMBAT e1 -> p1",
	],
	"staff holder can't counter": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 AFTER_COMBAT p1 -> e1",
		"s0#10 AFTER_COMBAT e1 -> p1",
	],
	"lifesteal": [
		"s0#2 BEFORE_COMBAT p1 -> e1",
		"s0#3 BEFORE_COMBAT e1 -> p1",
		"s0#4 ATTACK_MADE p1 -> e1",
		"s0#5 EFFECT_ACTIVATED p1 effect effect:iron_heart",
		"s0#6 HIT_DEALT p1 -> e1 amount 5 type physical",
		"s0#7 HIT_TAKEN e1 <- p1 amount 5 type physical",
		"s0#8 DAMAGE_DEALT p1 -> e1 amount 5 (hp 3, block 2) source attack type physical",
		"s0#9 DAMAGE_TAKEN e1 <- p1 amount 5 (hp 3, block 2) source attack type physical",
		"s0#10 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#11 HEALED p1 amount 3 (hp 3, block 0)",
		"s0#12 AFTER_COMBAT p1 -> e1",
		"s0#13 AFTER_COMBAT e1 -> p1",
	],
	"enemy attacked before its first Phase Start": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 3 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 3 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE e1 -> p1",
		"s0#10 HIT_DEALT e1 -> p1 amount 6 type physical",
		"s0#11 HIT_TAKEN p1 <- e1 amount 6 type physical",
		"s0#12 DAMAGE_DEALT e1 -> p1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#13 DAMAGE_TAKEN p1 <- e1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#14 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#15 AFTER_COMBAT p1 -> e1",
		"s0#16 AFTER_COMBAT e1 -> p1",
	],
	"breaker on a fully countered hit": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 type physical",
		"s0#5 COUNTER_CHANGED p1 lane 0 amount 1 effect effect:breaker",
		"s0#6 EFFECT_ACTIVATED p1 effect effect:breaker",
		"s0#7 HIT_TAKEN e1 <- p1 type physical",
		"s0#8 ATTACK_MADE e1 -> p1",
		"s0#9 HIT_DEALT e1 -> p1 amount 6 type physical",
		"s0#10 HIT_TAKEN p1 <- e1 amount 6 type physical",
		"s0#11 DAMAGE_DEALT e1 -> p1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#12 DAMAGE_TAKEN p1 <- e1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#13 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#14 AFTER_COMBAT p1 -> e1",
		"s0#15 AFTER_COMBAT e1 -> p1",
	],
	"momentum and cleave at After Combat": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 MISSED p1 -> e1",
		"s0#5 EFFECT_ACTIVATED p1 effect effect:momentum",
		"s0#6 DODGED e1 <- p1",
		"s0#7 ATTACK_MADE e1 -> p1",
		"s0#8 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#9 EFFECT_ACTIVATED e1 effect effect:cleave",
		"s0#10 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#11 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#12 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#13 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#14 ATTACK_MADE e1 -> p1",
		"s0#15 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#16 EFFECT_ACTIVATED e1 effect effect:cleave",
		"s0#17 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#18 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#19 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#20 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#21 EXPOSED p1 -> e1",
		"s0#22 AFTER_COMBAT p1 -> e1",
		"s0#23 AFTER_COMBAT e1 -> p1",
		"s0#24 MODIFIER_GAINED p1 effect effect:momentum",
		"s0#25 DAMAGE_TAKEN p1 <- e1 amount 2 (hp 2, block 0) source splash effect effect:cleave",
		"s0#26 DAMAGE_TAKEN p2 <- e1 amount 2 (hp 2, block 0) source splash effect effect:cleave",
		"s0#27 DAMAGE_TAKEN p1 <- e1 amount 2 (hp 2, block 0) source splash effect effect:cleave",
		"s0#28 DAMAGE_TAKEN p2 <- e1 amount 2 (hp 2, block 0) source splash effect effect:cleave",
	],
	"cleave queued, then its brute defeated": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 6 type physical",
		"s0#5 HIT_TAKEN e1 <- p1 amount 6 type physical",
		"s0#6 DAMAGE_DEALT p1 -> e1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#7 DAMAGE_TAKEN e1 <- p1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#8 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#9 ATTACK_MADE e1 -> p1",
		"s0#10 HIT_DEALT e1 -> p1 amount 3 type physical",
		"s0#11 EFFECT_ACTIVATED e1 effect effect:cleave",
		"s0#12 HIT_TAKEN p1 <- e1 amount 3 type physical",
		"s0#13 DAMAGE_DEALT e1 -> p1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#14 DAMAGE_TAKEN p1 <- e1 amount 3 (hp 3, block 0) source attack type physical",
		"s0#15 STANCE_CHANGED p1 -> e1 amount -1",
		"s0#16 ATTACK_MADE p1 -> e1",
		"s0#17 HIT_DEALT p1 -> e1 amount 6 type physical",
		"s0#18 HIT_TAKEN e1 <- p1 amount 6 type physical",
		"s0#19 DAMAGE_DEALT p1 -> e1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#20 DAMAGE_TAKEN e1 <- p1 amount 6 (hp 6, block 0) source attack type physical",
		"s0#21 DEFEATED e1 <- p1",
		"s0#22 DEFEATED_AN_ENEMY p1 -> e1",
		"s0#23 AFTER_COMBAT p1 -> e1",
		"s0#24 DAMAGE_TAKEN p1 <- e1 amount 2 (hp 2, block 0) source splash effect effect:cleave",
		"s0#25 DAMAGE_TAKEN p2 <- e1 amount 2 (hp 2, block 0) source splash effect effect:cleave",
	],
}

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_plain_exchange()
	_test_triangle_advantage()
	_test_effectiveness()
	_test_bonus_turn_at_four()
	_test_bonus_turns_at_ten()
	_test_crit_on_exposed()
	_test_parry_cuts_attacks()
	_test_full_mitigation()
	_test_block_absorbs()
	_test_defeat_mid_exchange()
	_test_attacker_defeated_by_counter()
	_test_bow_cannot_counter_at_one()
	_test_staff_holder_cannot_counter()
	_test_lifesteal()
	_test_turn_one_full_stance()
	_test_breaker_on_full_counter()
	_test_heavy_pack()
	_test_cleave_and_momentum_after_combat()
	_test_magic_and_terrain()
	_test_multiplier_against_tag()
	_test_incoming_from_magic()
	_test_incoming_while_adjacent()
	_test_more_damage_from_bows()
	_test_two_sided_multipliers()
	_test_illegal_exchanges()
	_test_determinism()
	_test_property_damage_never_negative()
	_test_property_exchanges()
	_test_property_bonus_turns_never_fall()
	_test_property_triangle_mirror()
	_test_2rn_distribution()


func _test_plain_exchange() -> void:
	var world: CombatWorld = _duel("sword", "sword")
	var result: ExchangeResolver.Result = _exchange(world)
	_ok(
			"plain: legal, countered, two turns",
			result.is_legal and result.can_counter and result.turns == 2
	)
	var hit: DamagePipeline.HitDamage = _hit(world, "p1", "e1")
	_ok("plain: 5 + 3 Might - 2 DEF = 6", hit.damage == 6 and hit.attack == 8.0)
	_same("plain: both Hit 80", _shown_rolls(world), "80,80")
	_golden("plain exchange", world)


func _test_triangle_advantage() -> void:
	var world: CombatWorld = _duel("lance", "sword")
	var ctx: EffectContext = _context(world, "p1", "e1", "p1", 0)
	_ok("triangle: a lance has Advantage over a sword", ctx.matchup == ADVANTAGE)
	_ok("triangle: +15 Hit", ExchangeResolver.hit_chance(world.engine, world.state, ctx) == 95)
	_ok("triangle: +round(7 / 4) = +2 damage", _hit(world, "p1", "e1").damage == 7 + 3 + 2 - 2)
	var back: EffectContext = _context(world, "e1", "p1", "p1", 1)
	_ok(
			"triangle: -15 Hit back",
			ExchangeResolver.hit_chance(world.engine, world.state, back) == 65
	)
	_ok("triangle: -round(5 / 4) = -1 damage back", _hit(world, "e1", "p1").damage == 5 + 3 - 1 - 2)
	_exchange(world)
	_same("triangle: rolls shown", _shown_rolls(world), "95,65")
	_golden("triangle advantage", world)


func _test_effectiveness() -> void:
	var world: CombatWorld = _duel("bow", "sword", 2)
	world.state.unit("e1").tags = PackedStringArray(["Flier"])
	var hit: DamagePipeline.HitDamage = _hit(world, "p1", "e1")
	_ok("effective: a bow against a flier", hit.is_effective)
	_ok("effective: weapon damage counts 3 times", hit.damage == 3 * 6 + 3 - 2)
	var result: ExchangeResolver.Result = _exchange(world)
	_ok("effective: a sword can't reach 2 tiles", not result.can_counter and result.turns == 1)
	_ok("effective: 19 damage", world.state.get_hp("e1") == 1)
	world.state.unit("e1").tags = PackedStringArray()
	_ok("effective: not without the tag", _hit(world, "p1", "e1").damage == 6 + 3 - 2)
	_golden("effectiveness", world)


func _test_bonus_turn_at_four() -> void:
	var world: CombatWorld = _duel("dagger", "dagger", 1, {CombatValue.Key.SPD: 9.0})
	var order: PackedStringArray = _order(world)
	_same("bonus: a gap of exactly 4 gives one", ",".join(order), "p1,e1,p1")
	_exchange(world)
	_golden("bonus turn at a gap of 4", world)

	var three: CombatWorld = _duel("dagger", "dagger", 1, {CombatValue.Key.SPD: 8.0})
	_same(
			"bonus: a gap of 3 gives none",
			",".join(ExchangeResolver.turn_order(three.engine, three.state, "p1", "e1")),
			"p1,e1"
	)
	var slower: CombatWorld = _duel("dagger", "dagger", 1, {}, {CombatValue.Key.SPD: 9.0})
	_same(
			"bonus: the faster defender gets it",
			",".join(ExchangeResolver.turn_order(slower.engine, slower.state, "p1", "e1")),
			"p1,e1,e1"
	)


func _test_bonus_turns_at_ten() -> void:
	var world: CombatWorld = _duel("dagger", "dagger", 1, {CombatValue.Key.SPD: 15.0})
	var order: PackedStringArray = _order(world)
	_same("bonus: a gap of exactly 10 gives two", ",".join(order), "p1,e1,p1,p1")
	world.state.set_hp("e1", 40)
	world.engine.set_base("e1", CombatValue.Key.HP, 40.0)
	_exchange(world)
	_golden("bonus turns at a gap of 10", world)
	var nine: CombatWorld = _duel("dagger", "dagger", 1, {CombatValue.Key.SPD: 14.0})
	_ok(
			"bonus: a gap of 9 gives one",
			ExchangeResolver.turn_order(nine.engine, nine.state, "p1", "e1").size() == 3
	)


func _test_crit_on_exposed() -> void:
	var world: CombatWorld = _duel("dagger", "sword", 1)
	world.state.weapon("w:p1").crit = 75
	world.state.load_bases(world.engine, "p1")
	world.state.set_stance("e1", 0)
	var result: ExchangeResolver.Result = _exchange(world)
	_ok("crit: legal", result.is_legal)
	_same("crit: 25 + 75 is a sure crit", _shown_rolls(world), "100,100,80")
	_ok("crit: (2 + 3 - 2) x CritX 5 = 15", world.state.get_hp("e1") == 5)
	_golden("crit on an Exposed target", world)

	var guarded: CombatWorld = _duel("dagger", "sword", 1)
	guarded.state.weapon("w:p1").crit = 75
	guarded.state.load_bases(guarded.engine, "p1")
	_exchange(guarded)
	_ok("crit: never against a unit with Stance", _count(guarded, CombatFact.Kind.CRIT_DEALT) == 0)
	_quiet(guarded)


func _test_parry_cuts_attacks() -> void:
	var world: CombatWorld = _duel("gauntlets", "gauntlets")
	_ok(
			"parry: AtkX 2 makes two attacks",
			ExchangeResolver.attacks_per_turn(world.engine, world.state, "p1", "e1", "p1") == 2
	)
	world.add_effect("effect:shield", _always(CombatValue.Key.PARRY, 1.0), "e1")
	_ok(
			"parry: Parry 1 cuts it to one",
			ExchangeResolver.attacks_per_turn(world.engine, world.state, "p1", "e1", "p1") == 1
	)
	world.add_effect("effect:wall", _always(CombatValue.Key.PARRY, 3.0), "e1")
	_ok(
			"parry: never below one",
			ExchangeResolver.attacks_per_turn(world.engine, world.state, "p1", "e1", "p1") == 1
	)
	_exchange(world)
	_ok("parry: three attacks in the exchange", _count(world, CombatFact.Kind.ATTACK_MADE) == 3)
	_golden("parry cutting attacks", world)


func _test_full_mitigation() -> void:
	var world: CombatWorld = _duel("dagger", "dagger", 1, {}, {CombatValue.Key.DEF: 20.0})
	_exchange(world)
	_ok("countered: no damage", world.state.get_hp("e1") == 20)
	_ok("countered: no Stance lost", world.state.get_stance("e1") == 2)
	_ok("countered: no Damage dealt", _count(world, CombatFact.Kind.DAMAGE_DEALT) == 1)
	_golden("full mitigation", world)


func _test_block_absorbs() -> void:
	var world: CombatWorld = _duel("dagger", "sword", 1, {CombatValue.Key.MGT: 5.0})
	world.engine.gain_block("e1", 4.0)
	var start: int = world.engine.fact_log.size()
	_exchange(world)
	_ok("block: 5 damage, 4 absorbed", world.state.get_block("e1") == 0)
	_ok("block: 1 to HP", world.state.get_hp("e1") == 19)
	_ok("block: damage to Block still costs Stance", world.state.get_stance("e1") == 1)
	_golden("block absorbing", world, start)


func _test_defeat_mid_exchange() -> void:
	var world: CombatWorld = _duel("gauntlets", "sword", 1, {CombatValue.Key.MGT: 4.0})
	world.state.set_hp("e1", 5)
	var result: ExchangeResolver.Result = _exchange(world)
	_ok("defeat: the defender falls", result.defender_defeated and not world.state.has_unit("e1"))
	_ok("defeat: on the second attack, no counter", result.attacks == 2)
	_ok("defeat: one After Combat", _count(world, CombatFact.Kind.AFTER_COMBAT) == 1)
	_golden("defeat mid-exchange", world)


func _test_attacker_defeated_by_counter() -> void:
	var world: CombatWorld = _duel("sword", "dagger", 1, {}, {CombatValue.Key.SPD: 9.0})
	world.state.weapon("w:p1").hit = 0
	world.state.load_bases(world.engine, "p1")
	world.state.set_hp("p1", 3)
	var result: ExchangeResolver.Result = _exchange(world)
	_ok("counter kill: the attacker falls", result.attacker_defeated)
	_ok("counter kill: the bonus turn never comes", result.attacks == 2 and result.turns == 3)
	_golden("attacker defeated by the counter", world)


func _test_bow_cannot_counter_at_one() -> void:
	var world: CombatWorld = _duel("sword", "bow")
	var result: ExchangeResolver.Result = _exchange(world)
	_ok("bow: can't counter at 1", not result.can_counter and result.turns == 1)
	_golden("bow can't counter at 1", world)


func _test_staff_holder_cannot_counter() -> void:
	var world: CombatWorld = _duel("dagger", "harm", 1)
	var result: ExchangeResolver.Result = _exchange(world)
	_ok("staff: an attack staff in range still can't counter", not result.can_counter)
	var shelter: CombatWorld = _duel("dagger", "shelter", 1)
	_ok("staff: nor a Block staff", not _exchange(shelter).can_counter)
	_golden("staff holder can't counter", world)
	_quiet(shelter)


func _test_lifesteal() -> void:
	# A bow can't counter at 1, so only p1's attack touches p1's HP.
	var world: CombatWorld = _duel("dagger", "bow", 1, {CombatValue.Key.MGT: 5.0})
	world.state.set_hp("p1", 10)
	var lifesteal: ModifyThat = ModifyThat.new()
	lifesteal.what = ModifyThat.What.FLAG
	lifesteal.flag = ModifyThat.Flag.LIFESTEAL
	var made: EffectTerms.Trigger = EffectTerms.Trigger.ATTACK_MADE
	world.add_effect("effect:iron_heart", _triggered(made, [], [lifesteal]), "p1")
	world.engine.gain_block("e1", 2.0)
	var start: int = world.engine.fact_log.size()
	_exchange(world)
	_ok("lifesteal: heals what reached HP, not Block", world.state.get_hp("p1") == 13)
	_golden("lifesteal", world, start)


func _test_turn_one_full_stance() -> void:
	var world: CombatWorld = _duel("dagger", "sword", 1, {}, {CombatValue.Key.STANCE_MAX: 3.0})
	world.state.weapon("w:p1").crit = 75
	world.state.load_bases(world.engine, "p1")
	_ok("turn 1: placed with full Stance", world.state.get_stance("e1") == 3)
	_exchange(world)
	_ok("turn 1: one hit costs one", world.state.get_stance("e1") == 2)
	_ok("turn 1: no crit", _count(world, CombatFact.Kind.CRIT_DEALT) == 0)
	_golden("enemy attacked before its first Phase Start", world)


func _test_breaker_on_full_counter() -> void:
	var world: CombatWorld = _duel("dagger", "sword", 1, {}, {CombatValue.Key.DEF: 20.0})
	world.add_effect("effect:breaker", _breaker(), "p1")
	_exchange(world)
	_ok("breaker: a fully countered hit costs no Stance", world.state.get_stance("e1") == 2)
	_golden("breaker on a fully countered hit", world)

	var through: CombatWorld = _duel("dagger", "sword", 1)
	through.add_effect("effect:breaker", _breaker(), "p1")
	_exchange(through)
	_ok("breaker: a hit that gets through costs 2", through.state.get_stance("e1") == 0)
	_quiet(through)


func _test_heavy_pack() -> void:
	# A dagger weighs 3: Constitution 3 carries it, so only the Pouch can slow p1.
	var bases: Dictionary = {CombatValue.Key.SPD: 9.0, CombatValue.Key.CON: 3.0}
	var light: CombatWorld = _duel("dagger", "dagger", 1, bases)
	var ctx: EffectContext = ExchangeResolver.context(
			light.engine, light.state, "p1", "e1", "p1", -1
	)
	_ok("pack: Attack Speed 9 with an empty Pouch", _speed(light, "p1", ctx) == 9)
	var heavy: CombatWorld = _duel("dagger", "dagger", 1, bases)
	var holder: CombatUnitState = heavy.state.unit("p1")
	holder.pouch_item_id = "item:potion"
	holder.pouch_item_weight = 2
	heavy.state.load_bases(heavy.engine, "p1")
	_ok("pack: Heavy Pack's potion weighs 2", _speed(heavy, "p1", ctx) == 7)
	_same(
			"pack: and costs the bonus turn",
			",".join(ExchangeResolver.turn_order(heavy.engine, heavy.state, "p1", "e1")),
			"p1,e1"
	)
	holder.pouch_item_weight = 0
	heavy.state.load_bases(heavy.engine, "p1")
	_ok("pack: weightless without the curse", _speed(heavy, "p1", ctx) == 9)
	_quiet(light)
	_quiet(heavy)


func _test_cleave_and_momentum_after_combat() -> void:
	# p1 always misses (Momentum); the faster Brute e1 hits it twice (Cleave, twice); p2 stands
	# next to e1 and only the splash reaches it.
	var world: CombatWorld = _duel("sword", "dagger", 1, {}, {CombatValue.Key.SPD: 9.0})
	world.add_unit("p2", PLAYER, 0, Vector2i(2, 2), UNIT_BASES)
	world.state.weapon("w:p1").hit = 0
	world.state.load_bases(world.engine, "p1")
	world.add_effect("effect:momentum", _momentum(), "p1")
	world.add_effect("effect:cleave", _cleave(), "e1")
	_exchange(world)
	_golden("momentum and cleave at After Combat", world)
	_ok("after combat: Momentum landed", world.engine.get_timed_modifiers("p1").size() == 1)
	_ok("after combat: both splashes reached p2", world.state.get_hp("p2") == 16)
	var start: int = world.engine.rolls.records.size()
	_exchange(world)
	_ok(
			"after combat: Momentum reaches the next exchange's first attack",
			world.engine.rolls.records[start].value == 15
	)

	# p1 is faster: p1 hits, the Brute counters (Cleave queued), p1's bonus turn defeats it.
	var later: CombatWorld = _duel("sword", "dagger", 1, {CombatValue.Key.SPD: 9.0})
	later.add_unit("p2", PLAYER, 0, Vector2i(2, 2), UNIT_BASES)
	later.add_effect("effect:cleave", _cleave(), "e1")
	later.state.set_hp("e1", 12)
	later.state.weapon("w:p1").hit = 100
	later.state.load_bases(later.engine, "p1")
	_exchange(later)
	_golden("cleave queued, then its brute defeated", later)
	_ok("after combat: the Brute fell to the bonus turn", not later.state.has_unit("e1"))
	_ok("after combat: its splash still hit p2 from its tile", later.state.get_hp("p2") == 18)


func _test_magic_and_terrain() -> void:
	var world: CombatWorld = _duel("fire", "sword", 1, {}, {CombatValue.Key.RES: 1.0})
	var forest: CombatGrid.TileBonus = CombatGrid.TileBonus.new()
	forest.avoid = 20
	forest.defense = 1
	forest.resistance = 2
	world.grid.set_bonus(Vector2i(2, 1), forest)
	var hit: DamagePipeline.HitDamage = _hit(world, "p1", "e1")
	_ok(
			"magic: 5 + 3 Might + 1 Advantage - (1 RES + 2 tile RES)",
			hit.mitigation == 3.0 and hit.damage == 6
	)
	_ok("magic: a magic hit", hit.damage_type == CombatFact.DamageType.MAGIC)
	var ctx: EffectContext = ExchangeResolver.context(
			world.engine, world.state, "p1", "e1", "p1", 0
	)
	_ok(
			"terrain: 80 Hit + 15 Advantage - 20 forest avoid",
			ExchangeResolver.hit_chance(world.engine, world.state, ctx) == 75
	)
	world.state.weapon("w:p1").damage_type = CombatFact.DamageType.SPLIT
	world.state.load_bases(world.engine, "p1")
	_ok(
			"split: half of DEF and RES, terrain too",
			_hit(world, "p1", "e1").mitigation == (2.0 + 1.0 + 1.0 + 2.0) / 2.0
	)
	world.state.weapon("w:p1").damage_type = CombatFact.DamageType.PURE
	world.state.load_bases(world.engine, "p1")
	_ok("pure: no mitigation", _hit(world, "p1", "e1").mitigation == 0.0)
	_quiet(world)


# "Deals ×2 damage to Beasts": the attacker's Multipliers, only against a Beast, only while it
# attacks; its own counter target isn't a Beast here, and outside an attack nothing changes.
func _test_multiplier_against_tag() -> void:
	var world: CombatWorld = _duel("sword", "gauntlets")
	world.add_effect("effect:bane", _beast_bane(), "p1")
	_ok("beasts: 1 outside an attack", _multipliers(world, "p1") == 1.0)
	_ok("beasts: not a Beast, 6", _hit(world, "p1", "e1").damage == 6)
	world.state.unit("e1").tags = PackedStringArray(["Beast"])
	var hit: DamagePipeline.HitDamage = _hit(world, "p1", "e1")
	_ok("beasts: ×2 against a Beast, 12", hit.damage == 12 and hit.multipliers == 2.0)
	_same("beasts: its source", hit.outgoing.to_text(), "1 rule ×2 effect:bane = 2")
	_ok("beasts: not when attacked", _hit(world, "e1", "p1").multipliers == 1.0)
	_ok("beasts: still 1 outside an attack", _multipliers(world, "p1") == 1.0)
	_quiet(world)


# "Takes ×2 damage from magic": the defender's Incoming multipliers, magic only.
func _test_incoming_from_magic() -> void:
	var world: CombatWorld = _duel("fire", "gauntlets")
	world.add_effect("effect:frail", _magic_frailty(), "e1")
	var hit: DamagePipeline.HitDamage = _hit(world, "p1", "e1")
	_ok("magic: 5 + 3 - 1 RES = 7, ×2 = 14", hit.damage == 14)
	_same("magic: its source", hit.incoming.to_text(), "1 rule ×2 effect:frail = 2")
	_ok("magic: the attacker's side untouched", hit.outgoing.total == 1.0)
	world.add_weapon("w:sword", "sword")
	world.arm("p1", "w:sword")
	_ok("magic: not from a sword", _hit(world, "p1", "e1").damage == 6)
	_quiet(world)


# "Takes 50% less damage while adjacent to an ally": a position condition on Incoming multipliers,
# so moving the ally away changes the next hit with no cached sheet left behind.
func _test_incoming_while_adjacent() -> void:
	var world: CombatWorld = _duel("sword", "gauntlets")
	world.add_unit("e2", ENEMY, -1, Vector2i(2, 2), UNIT_BASES)
	var half: ModifyValue = _times(DamageStage.Key.INCOMING_MULTIPLIERS, 0.5)
	var beside: WhilePositionCondition = WhilePositionCondition.new()
	beside.kind = WhilePositionCondition.Kind.ADJACENT_TO
	beside.side = EffectTerms.UnitSide.ALLY
	var wall: EffectDefinition = _triggered(EffectTerms.Trigger.ALWAYS, [beside], [half])
	world.add_effect("effect:shield_wall", wall, "e1")
	_ok("adjacent: 6 halved to 3", _hit(world, "p1", "e1").damage == 3)
	world.state.move_unit("e2", Vector2i(6, 6))
	_ok("adjacent: alone, 6 again", _hit(world, "p1", "e1").damage == 6)
	world.state.move_unit("e2", Vector2i(2, 2))
	_ok("adjacent: back beside it, 3", _hit(world, "p1", "e1").damage == 3)
	_quiet(world)


# "Takes 2 more damage from bows": Mitigation -2, which goes below 0 when DEF can't cover it.
func _test_more_damage_from_bows() -> void:
	var world: CombatWorld = _duel("bow", "gauntlets", 2)
	world.state.weapon("w:p1").weapon_type = "Bow"
	var more: ModifyValue = _times(DamageStage.Key.MITIGATION, -2.0)
	more.mode = ADD
	var bows: WhileAttackCondition = _attack_condition(
			WhileAttackCondition.Role.ATTACKED, WhileAttackCondition.Kind.WEAPON_TYPE, "Bow"
	)
	world.add_effect(
			"effect:soft", _triggered(EffectTerms.Trigger.ALWAYS, [bows], [more]), "e1"
	)
	var hit: DamagePipeline.HitDamage = _hit(world, "p1", "e1")
	_ok("bows: 6 + 3 - (2 - 2) = 9", hit.damage == 9 and hit.mitigation == 0.0)
	world.engine.set_base("e1", CombatValue.Key.DEF, 0.0)
	hit = _hit(world, "p1", "e1")
	_ok("bows: Mitigation -2 adds 2, 11", hit.mitigation == -2.0 and hit.damage == 11)
	world.state.weapon("w:p1").weapon_type = "Sword"
	_ok("bows: not from another weapon type, 9", _hit(world, "p1", "e1").damage == 9)
	_quiet(world)


# The attacker's ×2 against Beasts, the defender's ×2 from magic and a ×1.5 "that hit" modifier
# multiply on one hit, each in its breakdown; then the exchange's log, with verify mode on.
func _test_two_sided_multipliers() -> void:
	var world: CombatWorld = _duel("fire", "gauntlets", 1, {}, {CombatValue.Key.HP: 40.0})
	world.state.weapon("w:p1").hit = 100
	world.arm("p1", "w:p1")
	world.state.unit("e1").tags = PackedStringArray(["Beast"])
	world.state.set_hp("e1", 40)
	world.add_effect("effect:bane", _beast_bane(), "p1")
	world.add_effect("effect:frail", _magic_frailty(), "e1")
	var ctx: EffectContext = _context(world, "p1", "e1", "p1", 0)
	var hit: DamagePipeline.HitDamage = DamagePipeline.compute(world.engine, world.state, ctx)
	_ok("stacking: 7 × 2 × 2 = 28", hit.damage == 28 and hit.multipliers == 4.0)
	ctx.add_that_modifier(Modifier.new(
			DamageStage.Key.MULTIPLIERS, Modifier.Mode.MULTIPLY, 1.5,
			Modifier.SourceKind.UNIT_TRAIT, "effect:fury", "Fury"
	))
	hit = DamagePipeline.compute(world.engine, world.state, ctx)
	_ok("stacking: that hit's ×1.5 too, 42", hit.damage == 42 and hit.multipliers == 6.0)
	_same(
			"stacking: attacker's sources",
			hit.outgoing.to_text(),
			"1 rule ×2 effect:bane ×1.5 Fury = 3"
	)
	_same("stacking: defender's sources", hit.incoming.to_text(), "1 rule ×2 effect:frail = 2")
	_ok(
			"stacking: sheets cached outside the attack stay at 1",
			_multipliers(world, "p1") == 1.0
			and world.engine.stats("e1").get_value(DamageStage.Key.INCOMING_MULTIPLIERS) == 1.0
	)
	_exchange(world)
	_ok("stacking: 28 in the exchange", world.state.get_hp("e1") == 12)
	_golden("two-sided multipliers", world)


func _test_illegal_exchanges() -> void:
	var world: CombatWorld = _duel("sword", "sword", 3)
	_same("illegal: out of range", _exchange(world).reason, "out of range")
	var shelter: CombatWorld = _duel("shelter", "sword")
	_same(
			"illegal: a Block staff can't attack",
			_exchange(shelter).reason,
			"a support staff can't attack"
	)
	var ally: CombatWorld = _duel("sword", "sword")
	ally.add_unit("p2", PLAYER, 0, Vector2i(1, 2), UNIT_BASES)
	ally.arm("p2", ally.add_weapon("w:p2", "sword").id)
	_same(
			"illegal: not an enemy",
			ExchangeResolver.check(ally.engine, ally.state, "p1", "p2"),
			"not an enemy"
	)
	_ok(
			"illegal: nothing recorded",
			world.engine.fact_log.is_empty() and shelter.engine.fact_log.is_empty()
	)
	_ok("illegal: no action spent", not world.state.unit("p1").has_acted)


func _test_determinism() -> void:
	var first: CombatWorld = _duel("axe", "lance")
	var second: CombatWorld = _duel("axe", "lance")
	_exchange(first)
	_exchange(second)
	_ok("determinism: same seed, same log", first.log_lines() == second.log_lines())
	var other: CombatWorld = _duel("axe", "lance", 1, {}, {}, SEED + 1)
	_exchange(other)
	_ok("determinism: the stream is the only randomness", other.engine.rolls.records.size() > 0)


func _test_property_damage_never_negative() -> void:
	var world: CombatWorld = _duel("sword", "sword")
	var stream: RngStream = RngStream.new(SEED)
	var lowest: int = 0
	for i: int in 300:
		world.engine.set_base("p1", CombatValue.Key.MGT, stream.randi_range(-10, 10))
		world.engine.set_base("e1", CombatValue.Key.DEF, stream.randi_range(0, 30))
		world.engine.set_base("p1", DamageStage.Key.MULTIPLIERS, stream.randi_range(0, 4) / 2.0)
		var ctx: EffectContext = _context(world, "p1", "e1", "p1", 0)
		ctx.is_crit = stream.randi_range(0, 1) == 1
		lowest = mini(lowest, DamagePipeline.compute(world.engine, world.state, ctx).damage)
	_ok("property: damage is never negative", lowest >= 0)


func _test_property_exchanges() -> void:
	var hp_ok: bool = true
	var stops_ok: bool = true
	var defeats: int = 0
	var weapons: PackedStringArray = ["sword", "axe", "lance", "gauntlets", "dagger", "fire"]
	for i: int in 200:
		var stream: RngStream = RngStream.new(SEED + i)
		var own: String = weapons[stream.randi_range(0, weapons.size() - 1)]
		var theirs: String = weapons[stream.randi_range(0, weapons.size() - 1)]
		var world: CombatWorld = _duel(
				own, theirs, 1,
				{CombatValue.Key.SPD: float(stream.randi_range(0, 20))},
				{CombatValue.Key.SPD: float(stream.randi_range(0, 20))},
				SEED + 1000 + i
		)
		world.state.set_hp("p1", stream.randi_range(1, 20))
		world.state.set_hp("e1", stream.randi_range(1, 20))
		_exchange(world)
		for unit_id: String in ["p1", "e1"]:
			hp_ok = hp_ok and world.state.get_hp(unit_id) >= 0
		stops_ok = stops_ok and _stops_at_defeat(world)
		if not world.state.has_unit("p1") or not world.state.has_unit("e1"):
			defeats += 1
	_ok("property: HP never below 0", hp_ok)
	_ok("property: the exchange stops at the first defeat", stops_ok)
	_ok("property: the sample includes defeats", defeats > 20, str(defeats))


func _test_property_bonus_turns_never_fall() -> void:
	var never_falls: bool = true
	var previous: int = 0
	for gap: int in range(-5, 201):
		var turns: int = BonusTurns.count(gap)
		never_falls = never_falls and turns >= previous
		previous = turns
	_ok("property: bonus turns never fall as the gap grows", never_falls)
	_same(
			"bonus: thresholds 4, 10, 18, 28, 40, 54",
			"%d,%d,%d,%d,%d,%d" % [
				BonusTurns.threshold_for(1), BonusTurns.threshold_for(2),
				BonusTurns.threshold_for(3), BonusTurns.threshold_for(4),
				BonusTurns.threshold_for(5), BonusTurns.threshold_for(6),
			],
			"4,10,18,28,40,54"
	)
	# Gap to bonus turns, from game-vision.md's table and its "and so on".
	var table: Dictionary[int, int] = {
		3: 0, 4: 1, 9: 1, 10: 2, 17: 2, 18: 3, 27: 3, 28: 4, 39: 4, 40: 5, 53: 5, 54: 6,
	}
	var table_ok: bool = true
	for gap: int in table:
		table_ok = table_ok and BonusTurns.count(gap) == table[gap]
	_ok("bonus: the vision's table, no cap", table_ok)


func _test_property_triangle_mirror() -> void:
	var mirrored: bool = true
	var profiles: Array = WeaponTriangle.Profile.values()
	for own: int in profiles:
		for theirs: int in profiles:
			var forward: WhileMatchupCondition.Matchup = WeaponTriangle.matchup(own, theirs)
			var backward: WhileMatchupCondition.Matchup = WeaponTriangle.matchup(theirs, own)
			mirrored = mirrored and forward == WeaponTriangle.mirror(backward)
			mirrored = mirrored and (
					WeaponTriangle.hit_change(forward) == -WeaponTriangle.hit_change(backward)
			)
			for damage: int in range(0, 21):
				mirrored = mirrored and (
						WeaponTriangle.damage_change(forward, damage)
						== -WeaponTriangle.damage_change(backward, damage)
				)
	_ok("property: Advantage and Disadvantage are mirror images", mirrored)
	_ok(
			"triangle: the three wins",
			WeaponTriangle.matchup(WeaponTriangle.Profile.BALANCE, WeaponTriangle.Profile.NIMBLE)
			== ADVANTAGE
			and WeaponTriangle.matchup(WeaponTriangle.Profile.POWER, WeaponTriangle.Profile.BALANCE)
			== ADVANTAGE
			and WeaponTriangle.matchup(WeaponTriangle.Profile.NIMBLE, WeaponTriangle.Profile.POWER)
			== ADVANTAGE
	)
	_ok(
			"triangle: profile None never takes part",
			WeaponTriangle.matchup(WeaponTriangle.Profile.NONE, WeaponTriangle.Profile.POWER)
			== STANDOFF
			and WeaponTriangle.matchup(WeaponTriangle.Profile.NIMBLE, WeaponTriangle.Profile.NONE)
			== STANDOFF
	)
	_ok(
			"triangle: damage change at least 1, halves up",
			WeaponTriangle.damage_change(ADVANTAGE, 2) == 1
			and WeaponTriangle.damage_change(ADVANTAGE, 6) == 2
			and WeaponTriangle.damage_change(DISADVANTAGE, 10) == -3
	)


func _test_2rn_distribution() -> void:
	var matches: bool = true
	var details: PackedStringArray = []
	for hit: int in [0, 1, 25, 50, 75, 99, 100]:
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(SEED + hit))
		var hits: int = 0
		for i: int in DISTRIBUTION_DRAWS:
			if rolls.roll_hit_2rn(hit):
				hits += 1
		var observed: float = hits / float(DISTRIBUTION_DRAWS)
		var expected: float = _two_roll_odds(hit)
		matches = matches and absf(observed - expected) <= DISTRIBUTION_TOLERANCE
		details.append("%d: %.4f vs %.4f" % [hit, observed, expected])
	_ok("2RN: 10^5 draws per Hit match the analytic two-roll curve", matches, ", ".join(details))
	_ok(
			"2RN: Hit 25 lands 12.75% of the time, not 25% (Godot_FE 07, section 10: about 12.5%)",
			is_equal_approx(_two_roll_odds(25), 0.1275)
	)
	_ok(
			"2RN: the reported odds are the two-roll odds",
			is_equal_approx(RollSource.hit_2rn_probability(25), _two_roll_odds(25))
	)


# A duel on an open map: p1 (seat 0) at (1, 1) holding w:p1, e1 at distance tiles to its right
# holding w:e1, both with UNIT_BASES plus the given changes, rolling LiveRolls over a seeded stream.
func _duel(
		own: String,
		theirs: String,
		distance: int = 1,
		own_bases: Dictionary = {},
		their_bases: Dictionary = {},
		stream_seed: int = SEED
) -> CombatWorld:
	var world: CombatWorld = CombatWorld.new(LiveRolls.new(RngStream.new(stream_seed)))
	var p1_bases: Dictionary = UNIT_BASES.duplicate()
	p1_bases.merge(own_bases, true)
	var e1_bases: Dictionary = UNIT_BASES.duplicate()
	e1_bases.merge(their_bases, true)
	world.add_unit("p1", PLAYER, 0, Vector2i(1, 1), p1_bases)
	world.add_unit("e1", ENEMY, -1, Vector2i(1 + distance, 1), e1_bases)
	world.add_weapon("w:p1", own)
	world.add_weapon("w:e1", theirs)
	world.arm("p1", "w:p1")
	world.arm("e1", "w:e1")
	return world


func _exchange(
		world: CombatWorld, attacker: String = "p1", defender: String = "e1"
) -> ExchangeResolver.Result:
	world.engine.begin_step()
	return ExchangeResolver.resolve(world.engine, world.state, attacker, defender)


# Stages 1 to 5 of attacker's hit on defender, outside an exchange (no facts).
func _hit(world: CombatWorld, attacker: String, defender: String) -> DamagePipeline.HitDamage:
	var ctx: EffectContext = _context(world, attacker, defender, attacker, 0)
	return DamagePipeline.compute(world.engine, world.state, ctx)


func _speed(world: CombatWorld, unit_id: String, ctx: EffectContext) -> int:
	return ExchangeResolver.attack_speed(world.engine, unit_id, ctx).get_int()


# The displayed Hit or chance of every roll made, in order.
func _shown_rolls(world: CombatWorld) -> String:
	var shown: PackedStringArray = []
	var rolls: RollSource = world.engine.rolls
	for record: RollRecord in rolls.records:
		shown.append(str(record.value))
	return ",".join(shown)


func _count(world: CombatWorld, kind: CombatFact.Kind) -> int:
	var found: int = 0
	var engine: EffectEngine = world.engine
	for fact: CombatFact in engine.fact_log:
		if fact.kind == kind:
			found += 1
	return found


# Whether nothing but After Combat (and what its drain resolves) follows a defeat in the attacks.
func _stops_at_defeat(world: CombatWorld) -> bool:
	var engine: EffectEngine = world.engine
	var defeated: bool = false
	for fact: CombatFact in engine.fact_log:
		if fact.kind == CombatFact.Kind.DEFEATED:
			defeated = true
		elif defeated and fact.kind == CombatFact.Kind.ATTACK_MADE:
			return false
	return true


# The exact two-roll odds, counted independently of RollSource: pairs of d100 (0 to 99) whose
# integer average is below hit, over 10,000.
func _two_roll_odds(hit: int) -> float:
	var pairs: int = 0
	for first: int in 100:
		for second: int in 100:
			# Integer division on purpose: Godot_FE's rule averages the two rolls as integers.
			@warning_ignore("integer_division")
			if (first + second) / 2 < hit:
				pairs += 1
	return pairs / 10000.0


func _always(key: int, value: float) -> EffectDefinition:
	var modify: ModifyValue = ModifyValue.new()
	modify.key = key
	modify.mode = ADD
	modify.value = value
	return _triggered(EffectTerms.Trigger.ALWAYS, [], [modify])


func _triggered(
		trigger: EffectTerms.Trigger, conditions: Array, operations: Array
) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = trigger
	definition.conditions.assign(conditions)
	definition.operations.assign(operations)
	return definition


# The attacker's Multipliers outside any attack.
func _multipliers(world: CombatWorld, unit_id: String) -> float:
	return world.engine.stats(unit_id).get_value(DamageStage.Key.MULTIPLIERS)


func _times(key: int, value: float) -> ModifyValue:
	var modify: ModifyValue = ModifyValue.new()
	modify.key = key
	modify.mode = Modifier.Mode.MULTIPLY
	modify.value = value
	return modify


func _attack_condition(
		role: WhileAttackCondition.Role, kind: WhileAttackCondition.Kind, type_name: String = ""
) -> WhileAttackCondition:
	var condition: WhileAttackCondition = WhileAttackCondition.new()
	condition.role = role
	condition.kind = kind
	condition.type_name = type_name
	return condition


# Deals ×2 damage to Beasts.
func _beast_bane() -> EffectDefinition:
	var against: WhileAttackCondition = _attack_condition(
			WhileAttackCondition.Role.ATTACKING, WhileAttackCondition.Kind.OPPONENT_TAG, "Beast"
	)
	var times: ModifyValue = _times(DamageStage.Key.MULTIPLIERS, 2.0)
	return _triggered(EffectTerms.Trigger.ALWAYS, [against], [times])


# Takes ×2 damage from magic.
func _magic_frailty() -> EffectDefinition:
	var magic: WhileAttackCondition = _attack_condition(
			WhileAttackCondition.Role.ATTACKED, WhileAttackCondition.Kind.DAMAGE_TYPE
	)
	var times: ModifyValue = _times(DamageStage.Key.INCOMING_MULTIPLIERS, 2.0)
	return _triggered(EffectTerms.Trigger.ALWAYS, [magic], [times])


# Momentum (Fighter): Missed: +15 Hit on the next attack this combat.
func _momentum() -> EffectDefinition:
	var bonus: AddTimedModifier = AddTimedModifier.new()
	bonus.key = CombatValue.Key.HIT
	bonus.mode = ADD
	bonus.value = 15.0
	bonus.end = AddTimedModifier.End.THIS_COMBAT
	bonus.uses = 1
	return _triggered(EffectTerms.Trigger.MISSED, [], [bonus])


# Cleave (Brute): Hit dealt: deal 2 splash damage to adjacent units, friend or foe.
func _cleave() -> EffectDefinition:
	var area: Area = Area.new()
	area.center = Area.Center.OWNER
	area.radius = 1
	area.side = EffectTerms.UnitSide.ANY
	var amount: Constant = Constant.new()
	amount.value = 2.0
	var splash: DealSplash = DealSplash.new()
	splash.target = area
	splash.amount = amount
	return _triggered(EffectTerms.Trigger.HIT_DEALT, [], [splash])


# Breaker (Brawler): the first Hit dealt each combat: the target loses 1 extra Stance.
func _breaker() -> EffectDefinition:
	var first: CounterCondition = CounterCondition.new()
	first.mode = CounterCondition.Mode.FIRST
	var extra: ModifyThat = ModifyThat.new()
	extra.what = ModifyThat.What.EXTRA_STANCE_LOSS
	extra.value = 1.0
	return _triggered(EffectTerms.Trigger.HIT_DEALT, [first], [extra])


# Compares the log from start on with GOLDEN[name]; on a mismatch prints the actual log as a
# GDScript array for review. Also checks the engine reported no diagnostics.
func _golden(name: String, world: CombatWorld, start: int = 0) -> void:
	var lines: Array[String] = world.log_lines(start)
	var expected: Array = GOLDEN.get(name, [])
	var same: bool = lines.size() == expected.size()
	for i: int in mini(lines.size(), expected.size()):
		same = same and lines[i] == expected[i]
	if not same:
		var listing: PackedStringArray = []
		for line: String in lines:
			listing.append("\t\t\"%s\"," % [line])
		print("GOLDEN \"%s\": [\n%s\n\t]," % [name, "\n".join(listing)])
	_ok("golden: %s" % [name], same)
	_quiet(world)


func _quiet(world: CombatWorld) -> void:
	var engine: EffectEngine = world.engine
	_ok("diagnostics: none", engine.diagnostics.is_empty(), str(engine.diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])


func _context(
		world: CombatWorld, attacker: String, defender: String, initiator: String, index: int
) -> EffectContext:
	return ExchangeResolver.context(world.engine, world.state, attacker, defender, initiator, index)


func _order(world: CombatWorld) -> PackedStringArray:
	return ExchangeResolver.turn_order(world.engine, world.state, "p1", "e1")
