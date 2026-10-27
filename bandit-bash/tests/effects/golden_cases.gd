# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     golden_cases.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

extends "res://tests/effects/engine_cases.gd"
## The effect engine's lifecycle cases and golden fact logs, for tests/effects/run_all.gd.
##
## One golden log per coverage fixture in the event bus plan (Coverage check against real
## content), each played through the test-only fake_exchange.gd harness, plus the inline windows
## per trigger, the reaction caps, lanes and charges, timed-modifier ends and uses, observers, and
## the single Block-gain and heal paths. Every scenario also asserts that the engine reported no
## diagnostics. Shares the helpers of engine_cases.gd.

# A preloaded script used as a type (gdscript.md, Naming): the harness has no class name.
const FakeExchange = preload("res://tests/effects/harness/fake_exchange.gd")

const ENEMY_SIDE: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const HEIRLOOM: Modifier.SourceKind = Modifier.SourceKind.HEIRLOOM
const CURSE: Modifier.SourceKind = Modifier.SourceKind.CURSE
const ADVANTAGE: WhileMatchupCondition.Matchup = WhileMatchupCondition.Matchup.ADVANTAGE
const POUCH: Modifier.SourceKind = Modifier.SourceKind.POUCH_ITEM

# Reviewed golden fact logs, one CombatFact.to_log_line() per fact, keyed by the name _golden() is
# given. A scenario missing here expects no facts.
const GOLDEN: Dictionary[String, Array] = {
	"Iron Heart (7th attack)": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 COUNTER_CHANGED seat:0 lane 0 effect effect:ih",
		"s0#5 EFFECT_ACTIVATED seat:0 effect effect:ih",
		"s0#6 HIT_DEALT p1 -> e1 amount 4",
		"s0#7 HIT_TAKEN e1 <- p1 amount 4",
		"s0#8 DAMAGE_DEALT p1 -> e1 amount 4 (hp 4, block 0) source attack",
		"s0#9 DAMAGE_TAKEN e1 <- p1 amount 4 (hp 4, block 0) source attack",
		"s0#10 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#11 HEALED p1 amount 4 (hp 4, block 0)",
		"s0#12 AFTER_COMBAT p1 -> e1",
		"s0#13 AFTER_COMBAT e1 -> p1",
	],
	"Overflowing Cup": [
		"s0#1 HEALED_AN_ALLY p2 -> p1 amount 5 (hp 2, block 0)",
		"s0#2 HEALED p1 <- p2 amount 5 (hp 2, block 0)",
		"s0#3 EFFECT_ACTIVATED seat:0 effect effect:oc",
		"s0#4 USED_STAFF_ON_ALLY p2 -> p1",
		"s0#5 BLOCK_GAINED p1 amount 3 (hp 0, block 3) source effect effect effect:oc",
	],
	"Brittle Guard (3 -> 2, 1 -> 0)": [
		"s0#1 BLOCK_GAINED p1 <- p2 amount 2 (hp 0, block 2)",
		"s0#2 EFFECT_ACTIVATED seat:0 effect effect:bg",
		"s0#3 USED_STAFF_ON_ALLY p2 -> p1",
		"s0#4 BLOCK_GAINED p1 <- p2",
		"s0#5 EFFECT_ACTIVATED seat:0 effect effect:bg",
		"s0#6 USED_STAFF_ON_ALLY p2 -> p1",
	],
	"Vanguard": [
		"s0#1 BLOCK_STANCE_REFRESHED p1",
		"s0#2 BLOCK_STANCE_REFRESHED p2",
		"s0#3 PHASE_START side player amount 1",
		"s0#4 EFFECT_ACTIVATED p2 effect effect:v2",
		"s0#5 UNIT_TURN_START p1",
		"s0#6 UNIT_TURN_START p2",
		"s0#7 BLOCK_GAINED p2 amount 3 (hp 0, block 3) source effect effect effect:v2",
	],
	"Momentum": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 MISSED p1 -> e1",
		"s0#5 EFFECT_ACTIVATED p1 effect effect:mo",
		"s0#6 DODGED e1 <- p1",
		"s0#7 ATTACK_MADE p1 -> e1",
		"s0#8 HIT_DEALT p1 -> e1 amount 4",
		"s0#9 HIT_TAKEN e1 <- p1 amount 4",
		"s0#10 DAMAGE_DEALT p1 -> e1 amount 4 (hp 4, block 0) source attack",
		"s0#11 DAMAGE_TAKEN e1 <- p1 amount 4 (hp 4, block 0) source attack",
		"s0#12 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#13 AFTER_COMBAT p1 -> e1",
		"s0#14 AFTER_COMBAT e1 -> p1",
		"s0#15 MODIFIER_GAINED p1 effect effect:mo",
		"s0#16 BEFORE_COMBAT p1 -> e1",
		"s0#17 BEFORE_COMBAT e1 -> p1",
		"s0#18 ATTACK_MADE p1 -> e1",
		"s0#19 HIT_DEALT p1 -> e1 amount 4",
		"s0#20 HIT_TAKEN e1 <- p1 amount 4",
		"s0#21 DAMAGE_DEALT p1 -> e1 amount 4 (hp 4, block 0) source attack",
		"s0#22 DAMAGE_TAKEN e1 <- p1 amount 4 (hp 4, block 0) source attack",
		"s0#23 STANCE_CHANGED e1 -> p1 amount -1",
		"s0#24 EXPOSED e1 -> p1",
		"s0#25 MODIFIER_EXPIRED p1 effect effect:mo",
		"s0#26 AFTER_COMBAT p1 -> e1",
		"s0#27 AFTER_COMBAT e1 -> p1",
	],
	"Phalanx": [
		"s0#1 BLOCK_STANCE_REFRESHED p1",
		"s0#2 BLOCK_STANCE_REFRESHED p2",
		"s0#3 BLOCK_STANCE_REFRESHED q1",
		"s0#4 PHASE_START side player amount 1",
		"s0#5 UNIT_TURN_START p1",
		"s0#6 EFFECT_ACTIVATED p1 effect effect:ph",
		"s0#7 UNIT_TURN_START p2",
		"s0#8 UNIT_TURN_START q1",
		"s0#9 BLOCK_GAINED p1 amount 2 (hp 0, block 2) source effect effect effect:ph",
	],
	"Cleave": [
		"s0#1 BEFORE_COMBAT e1 -> p2",
		"s0#2 BEFORE_COMBAT p2 -> e1",
		"s0#3 ATTACK_MADE e1 -> p2",
		"s0#4 HIT_DEALT e1 -> p2 amount 4",
		"s0#5 EFFECT_ACTIVATED e1 effect effect:cl",
		"s0#6 HIT_TAKEN p2 <- e1 amount 4",
		"s0#7 DAMAGE_DEALT e1 -> p2 amount 4 (hp 4, block 0) source attack",
		"s0#8 DAMAGE_TAKEN p2 <- e1 amount 4 (hp 4, block 0) source attack",
		"s0#9 STANCE_CHANGED p2 -> e1 amount -1",
		"s0#10 AFTER_COMBAT e1 -> p2",
		"s0#11 AFTER_COMBAT p2 -> e1",
		"s0#12 DAMAGE_TAKEN p2 <- e1 amount 2 (hp 2, block 0) source splash effect effect:cl",
	],
	"War Horn (from the second Phase Start)": [
		"s0#10 BLOCK_STANCE_REFRESHED e1",
		"s0#11 BLOCK_STANCE_REFRESHED e2",
		"s0#12 PHASE_START side enemy",
		"s0#13 COUNTER_CHANGED e1 lane 0 effect effect:wh",
		"s0#14 EFFECT_ACTIVATED e1 effect effect:wh",
		"s0#15 UNIT_TURN_START e1",
		"s0#16 UNIT_TURN_START e2",
		"s0#17 MODIFIER_GAINED p1 effect effect:wh",
		"s0#18 MODIFIER_GAINED p2 effect effect:wh",
		"s0#19 MODIFIER_GAINED e1 effect effect:wh",
		"s0#20 MODIFIER_GAINED e2 effect effect:wh",
		"s0#21 PHASE_END side enemy",
		"s0#22 UNIT_TURN_END e1",
		"s0#23 UNIT_TURN_END e2",
		"s0#24 BLOCK_STANCE_REFRESHED p1",
		"s0#25 BLOCK_STANCE_REFRESHED p2",
		"s0#26 BLOCK_STANCE_REFRESHED q1",
		"s0#27 PHASE_START side player amount 1",
		"s0#28 UNIT_TURN_START p1",
		"s0#29 UNIT_TURN_START p2",
		"s0#30 UNIT_TURN_START q1",
		"s0#31 PHASE_END side player",
		"s0#32 UNIT_TURN_END p1",
		"s0#33 UNIT_TURN_END p2",
		"s0#34 UNIT_TURN_END q1",
		"s0#35 MODIFIER_EXPIRED p1 effect effect:wh",
		"s0#36 MODIFIER_EXPIRED p2 effect effect:wh",
		"s0#37 MODIFIER_EXPIRED e1 effect effect:wh",
		"s0#38 MODIFIER_EXPIRED e2 effect effect:wh",
	],
	"Lantern Oil": [
		"s0#1 DARKNESS_DAMAGE_TAKEN p1 amount 2 (hp 2, block 0) source darkness",
		"s0#2 EFFECT_ACTIVATED seat:0 effect effect:lo",
	],
	"Haunted after Iron Rations (curses act on the finished result)": [
		"s0#1 BLOCK_STANCE_REFRESHED p1",
		"s0#2 BLOCK_STANCE_REFRESHED p2",
		"s0#3 PHASE_START side player amount 1",
		"s0#4 COUNTER_CHANGED seat:0 lane 0 amount 1 effect effect:ir",
		"s0#5 EFFECT_ACTIVATED seat:0 effect effect:ir",
		"s0#6 EFFECT_ACTIVATED seat:0 effect effect:ha",
		"s0#7 UNIT_TURN_START p1",
		"s0#8 UNIT_TURN_START p2",
		"s0#9 BLOCK_GAINED p1 amount 3 (hp 0, block 3) source effect effect effect:ir",
		"s0#10 BLOCK_GAINED p2 amount 3 (hp 0, block 3) source effect effect effect:ir",
		"s0#11 BLOCK_LOST p2 amount 2 (hp 0, block 2) source effect effect effect:ha",
	],
	"Mend": [
		"s0#1 EFFECT_ACTIVATED effect effect:me",
		"s0#2 RUNE_USED -> p2 item rune:1",
		"s0#3 HEALED p2 amount 10 (hp 10, block 0) source effect effect effect:me",
	],
	"Breaker (first hit only)": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 BEFORE_COMBAT e1 -> p1",
		"s0#3 ATTACK_MADE p1 -> e1",
		"s0#4 HIT_DEALT p1 -> e1 amount 4",
		"s0#5 COUNTER_CHANGED p1 lane 0 amount 1 effect effect:br",
		"s0#6 EFFECT_ACTIVATED p1 effect effect:br",
		"s0#7 HIT_TAKEN e1 <- p1 amount 4",
		"s0#8 DAMAGE_DEALT p1 -> e1 amount 4 (hp 4, block 0) source attack",
		"s0#9 DAMAGE_TAKEN e1 <- p1 amount 4 (hp 4, block 0) source attack",
		"s0#10 STANCE_CHANGED e1 -> p1 amount -2",
		"s0#11 EXPOSED e1 -> p1",
		"s0#12 ATTACK_MADE p1 -> e1",
		"s0#13 HIT_DEALT p1 -> e1 amount 4",
		"s0#14 HIT_TAKEN e1 <- p1 amount 4",
		"s0#15 DAMAGE_DEALT p1 -> e1 amount 4 (hp 4, block 0) source attack",
		"s0#16 DAMAGE_TAKEN e1 <- p1 amount 4 (hp 4, block 0) source attack",
		"s0#17 AFTER_COMBAT p1 -> e1",
		"s0#18 AFTER_COMBAT e1 -> p1",
	],
	"Professional (Advantage only)": [
		"s0#1 BEFORE_COMBAT p1 -> e1",
		"s0#2 EFFECT_ACTIVATED p1 effect effect:pr1",
		"s0#3 BEFORE_COMBAT e1 -> p1",
		"s0#4 BLOCK_GAINED p1 amount 3 (hp 0, block 3) source effect effect effect:pr1",
		"s0#5 ATTACK_MADE p1 -> e1",
		"s0#6 MISSED p1 -> e1",
		"s0#7 DODGED e1 <- p1",
		"s0#8 AFTER_COMBAT p1 -> e1",
		"s0#9 AFTER_COMBAT e1 -> p1",
	],
	"STAT_CHANGED from a stat booster": [
		"s0#1 EFFECT_ACTIVATED p1 effect effect:mt",
		"s0#2 ITEM_USED p1 -> p1 item item:mt",
		"s0#3 STAT_CHANGED p1 stat 1 amount 1 source effect effect effect:mt",
	],
	"GROWTH_CHANGED from an eaten ingredient": [
		"s0#1 EFFECT_ACTIVATED p1 effect effect:carrot",
		"s0#2 ITEM_USED p1 -> p1 item item:carrot",
		"s0#3 GROWTH_CHANGED p1 stat 4 amount 5 source effect effect effect:carrot",
	],
}


func run() -> void:
	_test_golden_vanguard()
	_test_golden_iron_heart()
	_test_golden_momentum()
	_test_golden_phalanx()
	_test_golden_cleave()
	_test_golden_war_horn()
	_test_golden_overflowing_cup()
	_test_golden_lantern_oil()
	_test_golden_bounty_ledger()
	_test_golden_training_weights()
	_test_golden_brittle_guard()
	_test_golden_haunted()
	_test_golden_mend()
	_test_golden_breaker()
	_test_golden_professional()
	_test_inline_window_per_trigger()
	_test_momentum_stacks()
	_test_next_attack_uses()
	_test_timed_ends()
	_test_per_map_charges()
	_test_block_gain_path()
	_test_heal_path()
	_test_flags_in_any_order()
	_test_observers()
	_test_iron_rations()
	_test_vanguard_without_enemies()
	_test_this_unit_without_a_unit()
	_test_stat_changed()
	_test_deepest_chain()
	_test_queued_reaction_outlives_its_owner()
	_test_depth_cap()
	_test_step_cap()
	_test_keg_chain()
	_test_worst_legitimate_step()
	_test_shuffled_registration()


func _test_golden_vanguard() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	var vanguard: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START,
			[_position(WhilePositionCondition.Kind.NO_ALLY_CLOSER_TO_ENEMY)],
			[_block(3.0)]
	)
	engine.register(_instance("effect:v1", vanguard, _owner("p1"), TRAIT, "Vanguard"))
	engine.register(_instance("effect:v2", vanguard, _owner("p2"), TRAIT, "Vanguard"))
	_harness(engine).phase_start(PLAYER)
	_golden("Vanguard", engine)


func _test_golden_iron_heart() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"], [1])
	var seventh: CounterCondition = CounterCondition.new()
	seventh.count = 7
	var lifesteal: ModifyThat = _lifesteal()
	var iron_heart: EffectDefinition = _definition(
			EffectDefinition.Trigger.ATTACK_MADE, [seventh], [lifesteal]
	)
	iron_heart.scope = YOUR_UNIT
	var instance: EffectInstance = _instance(
			"effect:ih", iron_heart, _army(), HEIRLOOM, "Iron Heart"
	)
	engine.register(instance)
	instance.set_counter(EffectDefinition.Lane.COMBAT, 6)
	_fake(engine).unit("p1").hp = 10
	_harness(engine).exchange("p1", "e1", "a")
	_golden("Iron Heart (7th attack)", engine)


func _test_golden_momentum() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"], [0, 1, 1])
	engine.register(_instance("effect:mo", _momentum(), _owner("p1"), TRAIT, "Momentum"))
	var harness: FakeExchange = _harness(engine)
	harness.exchange("p1", "e1", "aa")
	harness.exchange("p1", "e1", "a")
	_golden("Momentum", engine)
	_same(
			"Momentum: the follow-up has no bonus, the next exchange's attack has it",
			_shown_rolls(engine),
			"80,80,95"
	)


func _test_golden_phalanx() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "q1", "e1"])
	var count: CountOf = CountOf.new()
	count.selector = _area(Area.Center.OWNER, 1, EffectDefinition.UnitSide.ALLY, false)
	var phalanx: EffectDefinition = _definition(
			EffectDefinition.Trigger.UNIT_TURN_START,
			[],
			[_gain(GainResource.Pool.BLOCK, null, count)]
	)
	engine.register(_instance("effect:ph", phalanx, _owner("p1"), TRAIT, "Phalanx"))
	_harness(engine).phase_start(PLAYER)
	_golden("Phalanx", engine)


func _test_golden_cleave() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"], [1])
	engine.register(_instance("effect:cl", _cleave(), _owner("e1"), TRAIT, "Cleave"))
	_harness(engine).exchange("e1", "p2", "a")
	_golden("Cleave", engine)


func _test_golden_war_horn() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "q1", "e1", "e2"])
	var second: CounterCondition = CounterCondition.new()
	second.count = 2
	var horn: AddTimedModifier = AddTimedModifier.new()
	horn.target = _area(Area.Center.OWNER, 2, EffectDefinition.UnitSide.ANY, true)
	horn.key = DamageStage.Key.ATTACK
	horn.value = 2.0
	horn.end = AddTimedModifier.End.END_OF_NEXT_PHASE
	var war_horn: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START, [second], [horn]
	)
	engine.register(_instance("effect:wh", war_horn, _owner("e1"), TRAIT, "War Horn"))
	var harness: FakeExchange = _harness(engine)
	harness.phase_start(ENEMY_SIDE)
	harness.phase_end(ENEMY_SIDE)
	var second_start: int = engine.fact_log.size()
	harness.phase_start(ENEMY_SIDE)
	harness.phase_end(ENEMY_SIDE)
	_ok(
			"War Horn: kept through the enemy's own Phase End",
			engine.stats("p1").get_value(DamageStage.Key.ATTACK) == 7.0
	)
	harness.phase_start(PLAYER)
	harness.phase_end(PLAYER)
	_ok(
			"War Horn: gone after the next phase (the players')",
			engine.stats("p1").get_value(DamageStage.Key.ATTACK) == 5.0
	)
	_golden("War Horn (from the second Phase Start)", engine, second_start)


func _test_golden_overflowing_cup() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	engine.register(
			_instance("effect:oc", _overflowing_cup(), _army(), HEIRLOOM, "Overflowing Cup")
	)
	_fake(engine).unit("p1").hp = 18
	_harness(engine).staff_heal("p2", "p1", 5.0)
	_golden("Overflowing Cup", engine)


func _test_golden_lantern_oil() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var halve: ModifyThat = _modify_that(
			ModifyThat.What.VALUE, MULTIPLY, 0.5, DamageStage.Key.MULTIPLIERS
	)
	var lantern: EffectDefinition = _definition(
			EffectDefinition.Trigger.DARKNESS_DAMAGE_TAKEN, [], [halve]
	)
	lantern.scope = YOUR_UNIT
	engine.register(_instance("effect:lo", lantern, _army(), HEIRLOOM, "Lantern Oil"))
	_harness(engine).darkness("p1", 5)
	_golden("Lantern Oil", engine)


func _test_golden_bounty_ledger() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var ledger: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS,
			[],
			[_modify_value(CampaignValue.Key.COMBAT_GOLD, ADD, 8.0)]
	)
	ledger.scope = YOUR_UNIT
	engine.register(_instance("effect:bl", ledger, _army(), HEIRLOOM, "Bounty Ledger"))
	_same(
			"golden Bounty Ledger: breakdown",
			engine.stats("seat:0").explain(CampaignValue.Key.COMBAT_GOLD).to_text(),
			"0 base +8 Bounty Ledger = 8"
	)
	_golden("Bounty Ledger (no facts)", engine)


func _test_golden_training_weights() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var slower: ModifyValue = _modify_value(CombatValue.Key.SPD, ADD, -2.0)
	var no_speed: SetPermission = SetPermission.new()
	no_speed.permission = CampaignValue.Permission.STAT_CAN_GROW
	no_speed.allow = false
	no_speed.stat = CombatValue.Stat.SPD
	var might: ModifyValue = _modify_value(CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS, ADD, 1.0)
	might.stat = CombatValue.Stat.MGT
	var weights: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS, [], [slower, no_speed, might]
	)
	engine.set_base("p1", CombatValue.Key.SPD, 6.0, "Fighter base")
	var equipped: EffectOwner = _p1_item("item:tw")
	engine.register(_instance(
			"effect:tw", weights, equipped, Modifier.SourceKind.EQUIPMENT, "Training Weights"
	))
	var sheet: StatSheet = engine.stats("p1")
	var grow: int = CampaignValue.Permission.STAT_CAN_GROW
	var gains: int = CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS
	var lines: PackedStringArray = [
		sheet.explain(CombatValue.Key.SPD).to_text(),
		sheet.explain_permission(grow, null, CombatValue.Stat.SPD).to_text(),
		sheet.explain(gains, null, CombatValue.Stat.MGT).to_text(),
	]
	_same(
			"golden Training Weights: breakdowns",
			" | ".join(lines),
			"6 Fighter base -2 Training Weights = 4 | denied by Training Weights = denied"
			+ " | 0 base +1 Training Weights = 1"
	)
	_golden("Training Weights (no facts)", engine)


func _test_golden_brittle_guard() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	engine.register(_instance("effect:bg", _brittle_guard(), _army(), CURSE, "Brittle Guard"))
	var harness: FakeExchange = _harness(engine)
	harness.staff_block("p2", "p1", 3.0)
	harness.staff_block("p2", "p1", 1.0)
	_golden("Brittle Guard (3 -> 2, 1 -> 0)", engine)


func _test_golden_haunted() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"], [1])
	engine.register(_instance("effect:ha", _haunted(), _army(), CURSE, "Haunted"))
	engine.register(_instance("effect:ir", _iron_rations(), _army(), HEIRLOOM, "Iron Rations"))
	_harness(engine).phase_start(PLAYER)
	_golden("Haunted after Iron Rations (curses act on the finished result)", engine)


func _test_golden_mend() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	var mend: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS,
			[],
			[_gain(GainResource.Pool.HP, CommandTarget.new(), _constant(10.0))]
	)
	var rune: EffectInstance = _instance(
			"effect:me", mend, EffectOwner.for_rune("rune:1", 0), Modifier.SourceKind.RUNE, "Mend"
	)
	engine.register(rune)
	_fake(engine).unit("p2").hp = 5
	_harness(engine).cast_rune(0, rune, "p2")
	_golden("Mend", engine)


func _test_golden_breaker() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"], [1, 1, 0])
	var first: CounterCondition = CounterCondition.new()
	first.mode = CounterCondition.Mode.FIRST
	var breaker: EffectDefinition = _definition(
			EffectDefinition.Trigger.HIT_DEALT,
			[first],
			[_modify_that(ModifyThat.What.EXTRA_STANCE_LOSS, ADD, 1.0)]
	)
	engine.register(_instance("effect:br", breaker, _owner("p1"), TRAIT, "Breaker"))
	_harness(engine).exchange("p1", "e1", "aa")
	_golden("Breaker (first hit only)", engine)


func _test_golden_professional() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"], [0])
	var professional: EffectDefinition = _definition(
			EffectDefinition.Trigger.BEFORE_COMBAT,
			[WhileMatchupCondition.new()],
			[_block(3.0)]
	)
	engine.register(_instance("effect:pr1", professional, _owner("p1"), TRAIT, "Professional"))
	engine.register(_instance("effect:pr2", professional, _owner("e1"), TRAIT, "Professional"))
	_harness(engine).exchange("p1", "e1", "a", ADVANTAGE)
	_golden("Professional (Advantage only)", engine)


func _test_inline_window_per_trigger() -> void:
	var opened: PackedStringArray = []
	for trigger: int in EffectEngine.INLINE_TRIGGERS:
		var engine: EffectEngine = _battle(["p1", "e1"])
		var flag: ModifyThat = _lifesteal()
		var definition: EffectDefinition = _definition(
				trigger as EffectDefinition.Trigger, [], [flag]
		)
		engine.register(_instance("effect:w", definition, _owner("p1"), TRAIT))
		var ctx: EffectContext = EffectContext.new()
		engine.open_window(CombatFact.new(_kind_of(trigger), "p1", "e1"), ctx)
		if ctx.has_flag(ModifyThat.Flag.LIFESTEAL) and engine.diagnostics.is_empty():
			opened.append(EffectDefinition.TRIGGER_TEXT[trigger])
	_ok(
			"windows: every inline trigger changes the action before it is recorded",
			opened.size() == 9,
			", ".join(opened)
	)


func _test_momentum_stacks() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"], [0, 0, 1])
	engine.register(_instance("effect:mo", _momentum(), _owner("p1"), TRAIT, "Momentum"))
	var harness: FakeExchange = _harness(engine)
	harness.exchange("p1", "e1", "aa")
	_ok("momentum: two misses give two modifiers", engine.get_timed_modifiers("p1").size() == 2)
	harness.exchange("p1", "e1", "a")
	_same(
			"momentum: they stack (+30) on the next exchange's attack",
			_shown_rolls(engine), "80,80,100"
	)
	_ok("momentum: that attack spends both", engine.get_timed_modifiers("p1").is_empty())
	_clean("momentum stacks", engine)


func _test_next_attack_uses() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"], [0, 1, 1])
	var harness: FakeExchange = _harness(engine)
	engine.add_timed_modifier("p1", _hit_bonus("miss"), AddTimedModifier.End.THIS_COMBAT, 1)
	engine.add_timed_modifier("e1", _hit_bonus("counter"), AddTimedModifier.End.THIS_COMBAT, 1)
	harness.exchange("p1", "e1", "ad")
	_ok(
			"uses: spent by a miss and by a counter",
			engine.get_timed_modifiers("p1").is_empty()
			and engine.get_timed_modifiers("e1").is_empty()
	)

	var under_way: EffectEngine = _battle(["p1", "e1"])
	var made: CombatFact = CombatFact.new(CombatFact.Kind.ATTACK_MADE, "p1", "e1")
	under_way.record(made)
	under_way.add_timed_modifier("p1", _hit_bonus("late"), AddTimedModifier.End.THIS_COMBAT, 1)
	under_way.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, "p1")
	_ok(
			"uses: an attack under way doesn't spend it",
			under_way.get_timed_modifiers("p1").size() == 1
	)
	under_way.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, "p1", "e1"))
	under_way.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, "p1")
	_ok("uses: the next one does", under_way.get_timed_modifiers("p1").is_empty())
	_clean("next attack uses", engine)


func _test_timed_ends() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var harness: FakeExchange = _harness(engine)
	var end: Dictionary[String, AddTimedModifier.End] = {
		"wall": AddTimedModifier.End.UNTIL_PHASE_END,
		"horn": AddTimedModifier.End.END_OF_NEXT_PHASE,
		"exchange": AddTimedModifier.End.THIS_EXCHANGE,
		"combat": AddTimedModifier.End.THIS_COMBAT,
	}
	harness.phase_start(ENEMY_SIDE)
	for name: String in end:
		engine.add_timed_modifier("p1", _hit_bonus(name), end[name], 0)
	engine.reach_boundary(EffectEngine.Boundary.EXCHANGE_END)
	_same("ends: this exchange ends at the exchange", _held(engine), "wall,horn,combat")
	harness.phase_end(ENEMY_SIDE)
	_same("ends: Iron Wall ends at its own Phase End", _held(engine), "horn,combat")
	harness.phase_start(PLAYER)
	harness.phase_end(PLAYER)
	_same("ends: War Horn ends at the next phase's end", _held(engine), "combat")
	var next_phase: AddTimedModifier.End = AddTimedModifier.End.END_OF_NEXT_PHASE
	engine.add_timed_modifier("p1", _hit_bonus("between"), next_phase, 0)
	harness.phase_start(ENEMY_SIDE)
	harness.phase_end(ENEMY_SIDE)
	_same(
			"ends: one added between phases belongs to the next phase",
			_held(engine), "combat,between"
	)
	harness.phase_start(PLAYER)
	harness.phase_end(PLAYER)
	_same("ends: ... and ends after the phase after it", _held(engine), "combat")
	engine.reach_boundary(EffectEngine.Boundary.COMBAT_END)
	_same("ends: this combat ends with the battle", _held(engine), "")
	_clean("timed ends", engine)


func _test_per_map_charges() -> void:
	var tonic: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS, [], [_block_to_target(3.0)]
	)
	tonic.charges = 1
	var elixir: EffectDefinition = tonic.duplicate()
	elixir.charge_lane = EffectDefinition.Lane.CAMPAIGN
	var item: EffectInstance = _instance(
			"effect:gt", tonic, _p1_item("item:gt"), POUCH, "Guard Tonic"
	)
	var lasting: EffectInstance = _instance(
			"effect:el", elixir, _p1_item("item:el"), POUCH, "Elixir"
	)

	var first: EffectEngine = _battle(["p1", "e1"])
	first.register(item)
	first.register(lasting)
	var harness: FakeExchange = _harness(first)
	_ok(
			"charges: one use each this combat",
			harness.use_item("p1", "p1", item) and not harness.use_item("p1", "p1", item)
			and harness.use_item("p1", "p1", lasting)
	)
	first.unregister("effect:gt")
	first.unregister("effect:el")

	var second: EffectEngine = _battle(["p1", "e1"])
	second.register(item)
	second.register(lasting)
	var next_combat: FakeExchange = _harness(second)
	_ok(
			"charges: a per-map charge is full in the next combat",
			next_combat.use_item("p1", "p1", item)
	)
	_ok("charges: a campaign charge stays spent", not next_combat.use_item("p1", "p1", lasting))
	_clean("charges", second)


func _test_block_gain_path() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	engine.register(_instance("effect:bg", _brittle_guard(), _army(), CURSE, "Brittle Guard"))
	var tonic: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS, [], [_block_to_target(3.0)]
	)
	var item: EffectInstance = _instance(
			"effect:gt", tonic, _p1_item("item:gt"), POUCH, "Guard Tonic"
	)
	engine.register(item)
	var phase: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START, [], [_block(3.0)]
	)
	engine.register(_instance("effect:ps", phase, _owner("p2"), TRAIT, "Vanguard"))
	var harness: FakeExchange = _harness(engine)
	harness.phase_start(PLAYER)
	harness.staff_block("p1", "p2", 3.0)
	harness.use_item("p1", "p1", item)
	var gains: PackedStringArray = []
	for fact: CombatFact in engine.fact_log:
		if fact.kind == CombatFact.Kind.BLOCK_GAINED:
			gains.append("%s %d" % [fact.actor_id, fact.amount])
	_same(
			"block path: Phase Start, staff and Guard Tonic gains all open the window",
			", ".join(gains),
			"p2 2, p2 2, p1 2"
	)
	_clean("block path", engine)


func _test_heal_path() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	var halved: ModifyValue = _modify_value(
			CampaignValue.Key.HEALING_RECEIVED_PERCENT, MULTIPLY, 0.5
	)
	var cursed_blood: EffectDefinition = _definition(EffectDefinition.Trigger.ALWAYS, [], [halved])
	cursed_blood.scope = YOUR_UNIT
	engine.register(_instance("effect:cb", cursed_blood, _army(), CURSE, "Cursed Blood"))
	_fake(engine).unit("p1").hp = 1
	_ok("heal: received percent halves, then rounds half up (5 -> 3)", engine.heal("p1", 5.0) == 3)
	var plus_one: EffectDefinition = _definition(
			EffectDefinition.Trigger.HEALED, [], [_modify_that(ModifyThat.What.AMOUNT, ADD, 1.0)]
	)
	engine.register(_instance("effect:plus", plus_one, _owner("p1"), TRAIT, "Goblet"))
	_ok(
			"heal: the window shapes the amount before the percent ((5 + 1) / 2)",
			engine.heal("p1", 5.0) == 3
	)
	var minus: EffectDefinition = _definition(
			EffectDefinition.Trigger.HEALED, [], [_modify_that(ModifyThat.What.AMOUNT, ADD, -10.0)]
	)
	engine.register(_instance("effect:minus", minus, _owner("p2"), TRAIT, "Wound"))
	_fake(engine).unit("p2").hp = 1
	_ok("heal: never below 0", engine.heal("p2", 5.0) == 0 and _fake(engine).unit("p2").hp == 1)
	_ok(
			"heal: the percent starts at 100",
			engine.stats("e1").get_value(CampaignValue.Key.HEALING_RECEIVED_PERCENT) == 100.0
	)
	_clean("heal path", engine)


func _test_flags_in_any_order() -> void:
	var logs: PackedStringArray = []
	for reversed: bool in [false, true]:
		var engine: EffectEngine = _battle(["p1", "e1"], [1])
		_fake(engine).unit("p1").hp = 10
		var lifesteal: EffectDefinition = _definition(
				EffectDefinition.Trigger.ATTACK_MADE, [], [_lifesteal()]
		)
		var pierce: ModifyThat = _lifesteal()
		pierce.flag = ModifyThat.Flag.SKIP_MITIGATION
		var skip: EffectDefinition = _definition(EffectDefinition.Trigger.HIT_DEALT, [], [pierce])
		var instances: Array[EffectInstance] = [
			_instance("effect:a", lifesteal, _owner("p1"), TRAIT),
			_instance("effect:b", skip, _owner("p1"), TRAIT),
		]
		if reversed:
			instances.reverse()
		for instance: EffectInstance in instances:
			engine.register(instance)
		_harness(engine).exchange("p1", "e1", "a")
		logs.append(_log_tail(engine, 0))
	_ok("flags: set in any order, the same hit", logs[0] == logs[1], logs[0])
	_ok(
			"flags: skip Mitigation and lifesteal both applied (5 damage, healed 5)",
			logs[0].contains("HIT_DEALT p1 -> e1 amount 5")
			and logs[0].contains("HEALED p1 amount 5")
	)


func _test_observers() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"], [1])
	var seen: Array[CombatFact] = []
	engine.add_observer(func(fact: CombatFact) -> void: seen.append(fact))
	engine.register(_instance("effect:cl", _cleave(), _owner("p1"), TRAIT, "Cleave"))
	_harness(engine).exchange("p1", "e1", "a")
	_ok(
			"observers: every fact, in order, as recorded",
			seen.size() == engine.fact_log.size() and seen == engine.fact_log
	)


func _test_iron_rations() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "q1", "e1"])
	engine.register(_instance("effect:ir", _iron_rations(), _army(), HEIRLOOM, "Iron Rations"))
	var harness: FakeExchange = _harness(engine)
	harness.phase_start(PLAYER)
	var fake: FakeState = _fake(engine)
	var after_first: String = "%d,%d,%d" % [
		fake.unit("p1").block, fake.unit("p2").block, fake.unit("q1").block
	]
	harness.phase_end(PLAYER)
	harness.phase_start(PLAYER)
	_same("Iron Rations: your units gain 3 Block, a partner's don't", after_first, "3,3,0")
	_ok("Iron Rations: once per combat", _count(engine, CombatFact.Kind.BLOCK_GAINED) == 2)
	_clean("Iron Rations", engine)


func _test_vanguard_without_enemies() -> void:
	var engine: EffectEngine = _battle(["p1", "p2"])
	var vanguard: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START,
			[_position(WhilePositionCondition.Kind.NO_ALLY_CLOSER_TO_ENEMY)],
			[_block(3.0)]
	)
	engine.register(_instance("effect:v", vanguard, _owner("p1"), TRAIT, "Vanguard"))
	_harness(engine).phase_start(PLAYER)
	_ok(
			"Vanguard: with no enemy on the map, no ally is closer",
			_fake(engine).unit("p1").block == 3
	)
	_clean("Vanguard without enemies", engine)


func _test_this_unit_without_a_unit() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var exposed: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START, [WhileStateCondition.new()], [_block(1.0)]
	)
	exposed.scope = YOUR_UNIT
	engine.register(_instance("effect:x", exposed, _army(), HEIRLOOM))
	_harness(engine).phase_start(PLAYER)
	_ok(
			"this unit: an army effect testing \"this unit\" on a phase fact is a content error",
			engine.diagnostics.size() == 1 and engine.diagnostics[0].contains("no unit")
			and _count(engine, CombatFact.Kind.BLOCK_GAINED) == 0
	)


func _test_stat_changed() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var booster: ChangeBaseStat = ChangeBaseStat.new()
	booster.key = CombatValue.Key.MGT
	booster.value = 1.0
	var tonic: EffectDefinition = _definition(EffectDefinition.Trigger.ALWAYS, [], [booster])
	var item: EffectInstance = _instance(
			"effect:mt", tonic, _p1_item("item:mt"), POUCH, "Might Tonic"
	)
	engine.register(item)
	_harness(engine).use_item("p1", "p1", item)
	_golden("STAT_CHANGED from a stat booster", engine)
	var wrong: ChangeBaseStat = ChangeBaseStat.new()
	wrong.key = CombatValue.Key.HIT
	wrong.value = 1.0
	wrong.apply(_context(engine, item))
	_ok("STAT_CHANGED: a key that isn't a base stat is reported", engine.diagnostics.size() == 1)

	var growth_engine: EffectEngine = _battle(["p1", "e1"])
	var growth: ChangeBaseStat = ChangeBaseStat.new()
	growth.key = CombatValue.Key.RES
	growth.mode = ChangeBaseStat.Mode.GROWTH
	growth.value = 5.0
	var carrot: EffectInstance = _instance(
			"effect:carrot",
			_definition(EffectDefinition.Trigger.ALWAYS, [], [growth]),
			_p1_item("item:carrot"),
			POUCH,
			"Cave Carrot"
	)
	growth_engine.register(carrot)
	_harness(growth_engine).use_item("p1", "p1", carrot)
	_golden("GROWTH_CHANGED from an eaten ingredient", growth_engine)
	_ok(
			"GROWTH_CHANGED: no stat changes in battle",
			growth_engine.stats("p1").get_int(CombatValue.Key.RES) == 0
			and growth_engine.get_deltas("p1", CombatValue.Key.RES).is_empty()
	)
	_ok(
			"GROWTH_CHANGED: kept on the unit's state",
			_fake(growth_engine).unit("p1").growth == {CombatValue.Stat.RES: 5}
	)


func _test_deepest_chain() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"], [1])
	engine.register(_instance("effect:cl", _cleave(), _owner("e1"), TRAIT, "Cleave"))
	var others: AllOfScope = AllOfScope.new()
	var candle_gain: GainResource = _gain(GainResource.Pool.BLOCK, others, _constant(4.0))
	var candle: EffectDefinition = _definition(EffectDefinition.Trigger.DEFEATED, [], [candle_gain])
	candle.scope = YOUR_UNIT
	engine.register(_instance("effect:gc", candle, _army(), HEIRLOOM, "Grave Candle"))
	_fake(engine).unit("p2").hp = 5
	_harness(engine).exchange("e1", "p2", "a")
	_ok(
			"chain: Brute hit -> Cleave -> Defeated -> Grave Candle resolves",
			_fake(engine).unit("p1").block == 4 and _fake(engine).unit("p2").defeated,
			_log_tail(engine, 0)
	)
	_clean("deepest chain", engine)


# A Brute defeated by the counter still splashes, from the tile it stood on: its queued reaction
# keeps the context it was queued with; the defeat only stops later triggers.
func _test_queued_reaction_outlives_its_owner() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"], [1, 1])
	engine.register(_instance("effect:cl", _cleave(), _owner("e1"), TRAIT, "Cleave"))
	_fake(engine).unit("e1").hp = 3
	_harness(engine).exchange("e1", "p2", "ad")
	var splash: CombatFact = _last_of(engine, CombatFact.Kind.DAMAGE_TAKEN)
	_ok(
			"queued: a Brute defeated by the counter still splashes from its old tile",
			_fake(engine).unit("e1").defeated and engine.state.tile_of("e1") == CombatFact.NO_TILE
			and splash.source == CombatFact.Source.SPLASH
			and splash.actor_id == "p2" and splash.source_effect_id == "effect:cl"
	)
	var activations: int = _count(engine, CombatFact.Kind.EFFECT_ACTIVATED)
	engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, "e1", "p2"))
	_ok(
			"queued: a defeated owner's effect no longer triggers",
			_count(engine, CombatFact.Kind.EFFECT_ACTIVATED) == activations
			and engine.pending_reactions() == 0
	)
	_clean("queued reaction outlives its owner", engine)


func _test_depth_cap() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var echo: EffectDefinition = _definition(
			EffectDefinition.Trigger.BLOCK_GAINED, [], [_block(1.0)]
	)
	engine.register(_instance("effect:loop", echo, _owner("p1"), TRAIT, "Echo"))
	engine.begin_step()
	engine.gain_block("p1", 1.0)
	engine.drain()
	_ok(
			"cap: a loop stops after 16 generations",
			_count(engine, CombatFact.Kind.BLOCK_GAINED) == 17 and engine.diagnostics.size() == 1
			and engine.diagnostics[0].contains("depth 16"),
			str(engine.diagnostics)
	)


func _test_step_cap() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "q1", "e1"])
	var fan: EffectDefinition = _definition(
			EffectDefinition.Trigger.BLOCK_GAINED, [], [_block(1.0)]
	)
	fan.scope = ANY_ALLY_UNIT
	for unit_id: String in ["p1", "p2", "q1"]:
		engine.register(_instance("effect:fan-" + unit_id, fan, _owner(unit_id), TRAIT, "Fan"))
	engine.begin_step()
	engine.gain_block("p1", 1.0)
	engine.drain()
	_ok(
			"cap: a step stops at 256 reactions, keeping what resolved",
			_count(engine, CombatFact.Kind.BLOCK_GAINED) == 257
			and engine.diagnostics[0].contains("256"),
			"%d gains, %d diagnostics" % [
				_count(engine, CombatFact.Kind.BLOCK_GAINED), engine.diagnostics.size()
			]
	)


func _test_keg_chain() -> void:
	var fake: FakeState = FakeState.new()
	var engine: EffectEngine = EffectEngine.new(fake, ForcedRolls.new())
	var blast: DealSplash = DealSplash.new()
	blast.target = _area(Area.Center.OWNER, 1, EffectDefinition.UnitSide.ANY, false)
	blast.amount = _constant(1.0)
	var keg: EffectDefinition = _definition(EffectDefinition.Trigger.DAMAGE_TAKEN, [], [blast])
	for i: int in 20:
		var id: String = "keg:%d" % [i]
		fake.add(id, OBJECT_SIDE, -1, Vector2i(i, 0), 1)
		engine.register(
				_instance("effect:" + id, keg, EffectOwner.for_object(id), TRAIT, "Powder Keg")
		)
	fake.add("p1", PLAYER, 0, Vector2i(20, 0))
	engine.set_base("p1", CombatValue.Key.HP, 20.0)
	var brace: EffectDefinition = _definition(
			EffectDefinition.Trigger.DAMAGE_TAKEN, [], [_block(2.0)]
	)
	engine.register(_instance("effect:brace", brace, _owner("p1"), TRAIT, "Brace"))
	engine.begin_step()
	engine.deal_splash("", "keg:0", 1.0)
	engine.drain()
	_ok(
			"keg chain: 20 kegs break, the unit at the end reacts, nothing is cut",
			_count(engine, CombatFact.Kind.DEFEATED) == 20 and fake.unit("p1").block == 2
			and fake.unit("p1").hp == 19,
			str(engine.diagnostics)
	)
	_clean("keg chain", engine)


func _test_worst_legitimate_step() -> void:
	# Every roll succeeds (hits and crits), the most reactions an exchange can cause.
	var all_hit: Array = []
	all_hit.resize(64)
	all_hit.fill(1)
	var engine: EffectEngine = _battle(["p1", "p2", "q1", "e1", "e2"], all_hit)
	var army: EffectOwner = _army()
	var seventh: CounterCondition = CounterCondition.new()
	seventh.count = 7
	var iron_heart: EffectDefinition = _definition(
			EffectDefinition.Trigger.ATTACK_MADE, [seventh], [_lifesteal()]
	)
	iron_heart.scope = YOUR_UNIT
	var regimental: Array[EffectInstance] = [
		_instance("effect:cl-e1", _cleave(), _owner("e1"), TRAIT, "Cleave"),
		_instance("effect:cl-p1", _cleave(), _owner("p1"), TRAIT, "Cleave"),
		_instance("effect:mo-p1", _momentum(), _owner("p1"), TRAIT, "Momentum"),
		_instance("effect:mo-e1", _momentum(), _owner("e1"), TRAIT, "Momentum"),
		_instance("effect:ih", iron_heart, army, HEIRLOOM, "Iron Heart"),
		_instance("effect:oc", _overflowing_cup(), army, HEIRLOOM, "Overflowing Cup"),
		_instance("effect:bg", _brittle_guard(), army, CURSE, "Brittle Guard"),
		_instance("effect:ha", _haunted(), army, CURSE, "Haunted"),
	]
	for instance: EffectInstance in regimental:
		engine.register(instance)
	for unit_id: String in ["p1", "e1"]:
		engine.set_base(unit_id, CombatValue.Key.HP, 200.0)
		_fake(engine).unit(unit_id).hp = 200
	# Maximum bonus turns with AtkX 2 on both sides: eight attacks, then four counters.
	_harness(engine).exchange("p1", "e1", "aaaaaaaadddd")
	_ok(
			"worst step: stays under 256 reactions with no cap hit",
			engine.diagnostics.is_empty()
			and engine.reactions_this_step() < ReactionQueue.MAX_PER_STEP,
			"%d reactions, %s" % [engine.reactions_this_step(), engine.diagnostics]
	)


func _test_shuffled_registration() -> void:
	var logs: PackedStringArray = []
	for variant: int in 3:
		var engine: EffectEngine = _battle(["p1", "p2", "q1", "e1", "e2"], [1, 0, 1, 1, 1, 0, 1])
		var army: EffectOwner = _army()
		var instances: Array[EffectInstance] = [
			_instance("effect:cl", _cleave(), _owner("e1"), TRAIT, "Cleave"),
			_instance("effect:mo", _momentum(), _owner("p1"), TRAIT, "Momentum"),
			_instance("effect:oc", _overflowing_cup(), army, HEIRLOOM, "Overflowing Cup"),
			_instance("effect:ir", _iron_rations(), army, HEIRLOOM, "Iron Rations"),
			_instance("effect:bg", _brittle_guard(), army, CURSE, "Brittle Guard"),
			_instance("effect:ha", _haunted(), army, CURSE, "Haunted"),
		]
		_shuffle(instances, variant)
		for instance: EffectInstance in instances:
			engine.register(instance)
		var harness: FakeExchange = _harness(engine)
		harness.phase_start(PLAYER)
		harness.exchange("p2", "e1", "aad")
		harness.exchange("p1", "e2", "ad")
		harness.phase_end(PLAYER)
		logs.append(_log_tail(engine, 0))
	_ok(
			"determinism: shuffled registration gives the same log",
			logs[0] == logs[1] and logs[1] == logs[2]
	)


# --- Fixtures ------------------------------------------------------------------------------------


func _momentum() -> EffectDefinition:
	var bonus: AddTimedModifier = AddTimedModifier.new()
	bonus.key = CombatValue.Key.HIT
	bonus.value = 15.0
	bonus.end = AddTimedModifier.End.THIS_COMBAT
	bonus.uses = 1
	return _definition(EffectDefinition.Trigger.MISSED, [], [bonus])


func _cleave() -> EffectDefinition:
	var splash: DealSplash = DealSplash.new()
	splash.target = _area(Area.Center.OWNER, 1, EffectDefinition.UnitSide.ANY, false)
	splash.amount = _constant(2.0)
	return _definition(EffectDefinition.Trigger.HIT_DEALT, [], [splash])


func _overflowing_cup() -> EffectDefinition:
	var overheal: PercentOfFact = PercentOfFact.new()
	overheal.field = PercentOfFact.Field.OVERHEAL
	var cup: EffectDefinition = _definition(
			EffectDefinition.Trigger.HEALED,
			[],
			[_gain(GainResource.Pool.BLOCK, FactActor.new(), overheal)]
	)
	cup.scope = YOUR_UNIT
	return cup


# Brittle Guard's minimum is its own (events.md: "minimum 0"); the engine's floor is a backstop.
func _brittle_guard() -> EffectDefinition:
	var guard: EffectDefinition = _definition(
			EffectDefinition.Trigger.BLOCK_GAINED,
			[],
			[
				_modify_that(ModifyThat.What.AMOUNT, ADD, -1.0),
				_modify_that(ModifyThat.What.AMOUNT, Modifier.Mode.FLOOR, 0.0),
			]
	)
	guard.scope = YOUR_UNIT
	guard.tags = EffectDefinition.Tag.CURSE
	return guard


func _haunted() -> EffectDefinition:
	var pick: RandomOf = RandomOf.new()
	pick.from = AllOfScope.new()
	var haunted: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START,
			[],
			[_gain(GainResource.Pool.BLOCK, pick, _constant(-2.0))]
	)
	haunted.scope = YOUR_UNIT
	haunted.tags = EffectDefinition.Tag.CURSE
	return haunted


func _iron_rations() -> EffectDefinition:
	var first: CounterCondition = CounterCondition.new()
	first.mode = CounterCondition.Mode.FIRST
	var rations: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START,
			[first],
			[_gain(GainResource.Pool.BLOCK, AllOfScope.new(), _constant(3.0))]
	)
	rations.scope = YOUR_UNIT
	return rations


# --- Helpers -------------------------------------------------------------------------------------


# The standard map with only `ids` on it, and the harness's placeholder combat bases: Hit 80,
# Attack stage 5, Mitigation stage 1, Multipliers stage 1, CritX 3.
func _battle(ids: Array, outcomes: Array = []) -> EffectEngine:
	var engine: EffectEngine = _world(PackedInt32Array(outcomes))
	var fake: FakeState = _fake(engine)
	for id: String in ["p1", "p2", "q1", "e1", "e2", "keg"]:
		if not ids.has(id):
			fake.unit(id).defeated = true
	for id: String in ids:
		engine.set_base(id, CombatValue.Key.HIT, 80.0)
		engine.set_base(id, DamageStage.Key.ATTACK, 5.0)
		engine.set_base(id, DamageStage.Key.MITIGATION, 1.0)
		engine.set_base(id, DamageStage.Key.MULTIPLIERS, 1.0)
		engine.set_base(id, CombatValue.Key.CRIT_X, 3.0)
	return engine


func _harness(engine: EffectEngine) -> FakeExchange:
	return FakeExchange.new(engine)


func _hit_bonus(label: String) -> Modifier:
	return Modifier.new(CombatValue.Key.HIT, ADD, 15.0, TRAIT, "effect:" + label, label)


# The labels of p1's timed modifiers, in the order gained.
func _held(engine: EffectEngine) -> String:
	var labels: PackedStringArray = []
	for timed: TimedModifier in engine.get_timed_modifiers("p1"):
		labels.append(timed.modifier.label)
	return ",".join(labels)


# The displayed value of every hit roll, in order.
func _shown_rolls(engine: EffectEngine) -> String:
	var shown: PackedStringArray = []
	for record: RollRecord in engine.rolls.records:
		if record.kind == RollRecord.Kind.HIT_2RN:
			shown.append(str(record.value))
	return ",".join(shown)


func _count(engine: EffectEngine, kind: CombatFact.Kind) -> int:
	var total: int = 0
	for fact: CombatFact in engine.fact_log:
		if fact.kind == kind:
			total += 1
	return total


# The combat fact kind whose trigger is `trigger`.
func _kind_of(trigger: int) -> CombatFact.Kind:
	for kind: int in CombatFact.Kind.values():
		var name: String = CombatFact.Kind.find_key(kind)
		if EffectDefinition.Trigger.get(name, -1) == trigger:
			return kind as CombatFact.Kind
	return CombatFact.Kind.PHASE_START


# Checks the log from index `start` against GOLDEN[name], one line per fact, and that the engine
# reported nothing. On a mismatch the detail prints the whole actual log.
func _golden(name: String, engine: EffectEngine, start: int = 0) -> void:
	var lines: PackedStringArray = []
	for i: int in range(start, engine.fact_log.size()):
		lines.append(engine.fact_log[i].to_log_line())
	var wanted: PackedStringArray = PackedStringArray(GOLDEN.get(name, []) as Array)
	_ok("golden %s" % [name], lines == wanted, "\n\t" + "\n\t".join(lines))
	_clean(name, engine)


func _clean(name: String, engine: EffectEngine) -> void:
	_ok("%s: no diagnostics" % [name], engine.diagnostics.is_empty(), str(engine.diagnostics))


func _army() -> EffectOwner:
	return EffectOwner.for_army("seat:0", 0)


func _p1_item(item_id: String) -> EffectOwner:
	return EffectOwner.for_item(item_id, "p1", 0, PLAYER)


# "Gain <amount> Block" for the command's target (a Guard Tonic).
func _block_to_target(amount: float) -> GainResource:
	return _gain(GainResource.Pool.BLOCK, CommandTarget.new(), _constant(amount))


func _lifesteal() -> ModifyThat:
	return _modify_that(ModifyThat.What.FLAG, ADD, 0.0)
