# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_text_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tests/effects/effects_case_base.gd"
## The effect text grammar's cases for tests/effects/run_all.gd (effect-triggers.md, Reading
## effect text): [member EffectDefinition.written_text] winning when set and ignored when empty;
## a carrier's lead-in; every value key's player-facing name in [constant EffectTerms.KEY_TEXT]
## and the singular forms; each trigger head by scope and counter; an always-on effect with no
## head; the sentence, list and charge helpers; and alike permanent changes said once.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "effects"

# Each value key's text for +2 (and -1 where a singular form differs), as items, heirlooms and
# curses read them.
const KEY_CASES: Array[Array] = [
	[CombatValue.Key.NET_WEIGHT, 2.0, "+2 Weight"],
	[CombatValue.Key.ATK_X, 1.0, "+1 AtkX"],
	[CombatValue.Key.CRIT_CHANCE, 10.0, "+10 Crit"],
	[CombatValue.Key.CRIT_X, -1.0, "-1 CritX"],
	[CombatValue.Key.STANCE_MAX, 1.0, "+1 max Stance"],
	[CombatValue.Key.SHOVE_DISTANCE, 1.0, "+1 Shove distance"],
	[CombatValue.Key.RANGE_MIN, 1.0, "+1 min Range"],
	[CombatValue.Key.RANGE_MAX, 1.0, "+1 max Range"],
	[CombatValue.Key.EFFECTIVE_MODIFIER, 1.0, "+1 effectiveness"],
	[CombatValue.Key.STAFF_AMOUNT, 2.0, "+2 staff amount"],
	[CombatValue.Key.MOVEMENT, 1.0, "+1 Movement"],
	[CombatValue.Key.SPD, -2.0, "-2 SPD"],
	[CampaignValue.Key.COMBAT_GOLD, 8.0, "+8 Gold per won combat"],
	[CampaignValue.Key.GRADE_BONUS_PERCENT, 25.0, "+25% grade bonus"],
	[CampaignValue.Key.SHARED_XP_PERCENT, 20.0, "+20% shared XP"],
	[CampaignValue.Key.UNIT_XP_PERCENT, 25.0, "+25% XP"],
	[CampaignValue.Key.SCRAP_PERCENT, 20.0, "+20% of the price when scrapping"],
	[CampaignValue.Key.ARMORY_STOCK, 2.0, "+2 Armory items"],
	[CampaignValue.Key.ARMORY_STOCK, 1.0, "+1 Armory item"],
	[CampaignValue.Key.GUILDHALL_RECRUITS, 1.0, "+1 Guildhall recruit"],
	[CampaignValue.Key.PRICE_PERCENT, -20.0, "-20% shop prices"],
	[CampaignValue.Key.FREE_REROLLS, 2.0, "+2 free rerolls"],
	[CampaignValue.Key.FREE_REROLLS, 1.0, "+1 free reroll"],
	[CampaignValue.Key.MAX_ARMY_SIZE, 1.0, "+1 max army size"],
	[CampaignValue.Key.EXTRA_ENEMIES, 1.0, "+1 enemy per combat"],
	[CampaignValue.Key.EXTRA_ENEMIES, 2.0, "+2 enemies per combat"],
	[CampaignValue.Key.HEALING_RECEIVED_PERCENT, 20.0, "+20% healing received"],
	[CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS, 1.0, "+1 stat point per level-up"],
	[CampaignValue.Key.LEVEL_UP_RANDOM_GAINS, 1.0, "+1 random stat point per level-up"],
	[CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET, -1.0, "-1 turn before the darkness arrives"],
	[CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET, 2.0, "+2 turns before the darkness arrives"],
	[CampaignValue.Key.POUCH_ITEM_WEIGHT, 2.0, "+2 weight per Pouch item"],
	[DamageStage.Key.ATTACK, 2.0, "+2 Attack"],
]

# Each trigger head: trigger, scope, count word, lane, the head.
const HEAD_CASES: Array[Array] = [
	[EffectTerms.Trigger.ALWAYS, EffectTerms.Scope.THIS_UNIT, "", 0, ""],
	[EffectTerms.Trigger.PHASE_START, EffectTerms.Scope.THIS_UNIT, "", 0, "At Phase Start"],
	[EffectTerms.Trigger.PHASE_END, EffectTerms.Scope.YOUR_UNIT, "", 0, "At Phase End"],
	[
		EffectTerms.Trigger.PHASE_START, EffectTerms.Scope.ANY_ALLY_UNIT, "", 0,
		"At each allied Phase Start",
	],
	[EffectTerms.Trigger.PHASE_START, EffectTerms.Scope.ANY_UNIT, "", 0, "At every Phase Start"],
	[
		EffectTerms.Trigger.PHASE_START, EffectTerms.Scope.YOUR_UNIT, "first", 0,
		"At the first Phase Start each combat",
	],
	[
		EffectTerms.Trigger.PHASE_START, EffectTerms.Scope.THIS_UNIT, "3rd", 1,
		"At every 3rd Phase Start this run",
	],
	[EffectTerms.Trigger.BEFORE_COMBAT, EffectTerms.Scope.THIS_UNIT, "", 0, "Before each exchange"],
	[EffectTerms.Trigger.AFTER_COMBAT, EffectTerms.Scope.THIS_UNIT, "", 0, "After each exchange"],
	[
		EffectTerms.Trigger.BEFORE_COMBAT, EffectTerms.Scope.YOUR_UNIT, "", 0,
		"Whenever one of your units enters an exchange",
	],
	[
		EffectTerms.Trigger.UNIT_TURN_START, EffectTerms.Scope.THIS_UNIT, "", 0,
		"At the start of this unit's turn",
	],
	[
		EffectTerms.Trigger.UNIT_TURN_END, EffectTerms.Scope.ANY_ALLY_UNIT, "", 0,
		"Whenever an ally ends its turn",
	],
	[
		EffectTerms.Trigger.HIT_DEALT, EffectTerms.Scope.THIS_UNIT, "", 0,
		"Whenever this unit lands a hit",
	],
	[
		EffectTerms.Trigger.DEFEATED, EffectTerms.Scope.THIS_UNIT, "", 0,
		"When this unit is defeated",
	],
	[
		EffectTerms.Trigger.DEFEATED, EffectTerms.Scope.YOUR_UNIT, "", 0,
		"Whenever one of your units is defeated",
	],
	[
		EffectTerms.Trigger.DAMAGE_TAKEN, EffectTerms.Scope.ANY_UNIT, "", 0,
		"Whenever any unit takes damage",
	],
	[
		EffectTerms.Trigger.HIT_TAKEN, EffectTerms.Scope.THIS_UNIT, "first", 0,
		"The first time this unit is hit each combat",
	],
	[
		EffectTerms.Trigger.ATTACK_MADE, EffectTerms.Scope.YOUR_UNIT, "10th", 1,
		"Every 10th time one of your units attacks this run",
	],
	[EffectTerms.Trigger.GAINED, EffectTerms.Scope.YOUR_UNIT, "", 0, "Upon pickup"],
	[
		EffectTerms.Trigger.COMBAT_ENDED, EffectTerms.Scope.YOUR_UNIT, "", 0,
		"At the end of each combat",
	],
	[
		EffectTerms.Trigger.COMBAT_ENDED, EffectTerms.Scope.YOUR_UNIT, "3rd", 1,
		"At the end of every 3rd combat",
	],
	[
		EffectTerms.Trigger.LEVELED_UP, EffectTerms.Scope.YOUR_UNIT, "", 0,
		"Whenever one of your units levels up",
	],
]


func run() -> void:
	_test_written_text()
	_test_lead_in()
	_test_key_names()
	_test_heads()
	_test_sentences()
	_test_permanent_runs()


# The written text replaces the built text, its lead-in and charges included; empty, the built
# text shows.
func _test_written_text() -> void:
	var gain: GainResource = GainResource.new()
	gain.amount = _constant(1.0)
	var effect: EffectDefinition = EffectDefinition.new()
	effect.trigger = EffectTerms.Trigger.BEFORE_COMBAT
	effect.operations.assign([gain])
	effect.charges = 1
	_snapshot("written text: empty, the built text", effect.describe(), (
			"Before each exchange, gain 1 Block (once per combat)."
	))
	effect.written_text = "Once per combat, guard."
	_snapshot("written text: set, it wins", effect.describe(), "Once per combat, guard.")
	_snapshot(
			"written text: set, a lead-in leaves it as written",
			effect.describe("When eaten"),
			"Once per combat, guard."
	)
	var opener: EffectDefinition = EffectDefinition.new()
	_snapshot("written text: an opener without it has no text", opener.describe(), "")
	var carrier: EffectCarrierDefinition = EffectCarrierDefinition.new()
	carrier.effects.assign([opener, effect])
	_check(
			"written text: a carrier gives no line for an effect with no text",
			carrier.describe() == PackedStringArray(["Once per combat, guard."]),
			str(carrier.describe())
	)


# A lead-in opens the sentence before the head and conditions; an ingredient's is "When eaten".
func _test_lead_in() -> void:
	var heal: GainResource = _gain(GainResource.Pool.HP, CommandTarget.new(), _constant(5.0))
	var eat: EffectDefinition = EffectDefinition.new()
	eat.operations.assign([heal])
	_snapshot("lead-in: none, the action alone", eat.describe(), "Heal the target for 5 HP.")
	_snapshot("lead-in: given", eat.describe("When eaten"), (
			"When eaten, heal the target for 5 HP."
	))
	var ingredient: ConsumableDefinition = ConsumableDefinition.new()
	ingredient.use_kind = ConsumableDefinition.INGREDIENT_USE_KIND
	ingredient.effects.assign([eat])
	_check(
			"lead-in: an ingredient's text opens When eaten",
			ingredient.describe() == PackedStringArray(["When eaten, heal the target for 5 HP."]),
			str(ingredient.describe())
	)
	ingredient.use_kind = "heal"
	_check(
			"lead-in: a potion's text is its action",
			ingredient.describe() == PackedStringArray(["Heal the target for 5 HP."]),
			str(ingredient.describe())
	)
	var bonus: EffectDefinition = EffectDefinition.new()
	bonus.operations.assign([_modify_value(CombatValue.Key.DEF, ADD, 2.0)])
	_snapshot("lead-in: an always-on effect has no head", bonus.describe(), "+2 DEF.")
	_check(
			"lead-in: no text says Always",
			not (bonus.describe() + eat.describe()).contains("Always"),
			bonus.describe()
	)


func _test_key_names() -> void:
	for row: Array in KEY_CASES:
		var key: int = row[0]
		var value: float = row[1]
		var expected: String = row[2]
		_snapshot(
				"key text: %s %s" % [EffectTerms.key_name(key), EffectTerms.format_number(value)],
				EffectTerms.describe_modifier(key, ADD, value),
				expected
		)
	_snapshot(
			"key text: a per-stat level-up gain names its stat",
			EffectTerms.describe_modifier(
					CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS, ADD, 1.0, CombatValue.Stat.MGT
			),
			"+1 MGT per level-up"
	)
	_snapshot(
			"key text: a damage type reads as the attacks'",
			EffectTerms.describe_modifier(
					CombatValue.Key.DAMAGE_TYPE, REPLACE_BASE, CombatFact.DamageType.MAGIC
			),
			"attacks deal Magic damage"
	)
	_snapshot(
			"key text: the inspector keeps the key's own name",
			EffectTerms.key_name(CampaignValue.Key.UNIT_XP_PERCENT),
			"Unit Xp Percent"
	)
	var unnamed: PackedStringArray = []
	for keys: Dictionary in [CombatValue.Key, CampaignValue.Key]:
		for key_name: String in keys:
			var key: int = keys[key_name]
			var shown: String = EffectTerms.text_name(key)
			if shown.contains("Percent") or shown.contains("Xp") or shown.contains("Level Up"):
				unnamed.append(shown)
	_check(
			"key text: no key reads as its code name",
			unnamed.is_empty(),
			", ".join(unnamed)
	)


func _test_heads() -> void:
	for row: Array in HEAD_CASES:
		var trigger: int = row[0]
		var scope: int = row[1]
		var count: String = row[2]
		var lane: int = row[3]
		var expected: String = row[4]
		_snapshot(
				"head: %s, %s%s" % [
					EffectTerms.TRIGGER_TEXT[trigger], EffectTerms.SCOPE_TEXT[scope],
					"" if count.is_empty() else ", " + count,
				],
				EffectTerms.trigger_head(trigger, scope, count, lane),
				expected
		)
	_snapshot(
			"head: the ready line's clause",
			EffectTerms.trigger_clause(
					EffectTerms.Trigger.ATTACK_MADE, EffectTerms.Scope.YOUR_UNIT
			),
			"one of your units attacks"
	)


func _test_sentences() -> void:
	_snapshot("sentence: capital and period", EffectTerms.sentence("gain 1 Block"), (
			"Gain 1 Block."
	))
	_snapshot("sentence: a period kept", EffectTerms.sentence("Open a door."), "Open a door.")
	_snapshot("sentence: empty stays empty", EffectTerms.sentence("  "), "")
	_snapshot("list: one", EffectTerms.join_list(PackedStringArray(["a"])), "a")
	_snapshot("list: two", EffectTerms.join_list(PackedStringArray(["a", "b"])), "a and b")
	_snapshot("list: three", EffectTerms.join_list(PackedStringArray(["a", "b", "c"])), (
			"a, b and c"
	))
	_snapshot("charges: once", EffectTerms.describe_charges(1, 0), "(once per combat)")
	_snapshot("charges: twice", EffectTerms.describe_charges(2, 1), "(twice per run)")
	_snapshot("charges: more", EffectTerms.describe_charges(3, 0), "(3 times per combat)")


# Permanent stat changes given to one target share one "permanently give"; a growth change, or
# a change to another target, keeps its own.
func _test_permanent_runs() -> void:
	var operations: Array[EffectOperation] = []
	for key: int in [CombatValue.Key.MGT, CombatValue.Key.SPD, CombatValue.Key.DEF]:
		var change: ChangeBaseStat = ChangeBaseStat.new()
		change.target = CommandTarget.new()
		change.key = key
		change.value = 1.0
		operations.append(change)
	var growth: ChangeBaseStat = ChangeBaseStat.new()
	growth.target = CommandTarget.new()
	growth.key = CombatValue.Key.RES
	growth.mode = ChangeBaseStat.Mode.GROWTH
	growth.value = 5.0
	operations.append(growth)
	var effect: EffectDefinition = EffectDefinition.new()
	effect.operations.assign(operations)
	_snapshot("permanent run: alike changes said once", effect.describe(), (
			"Permanently give the target +1 MGT, +1 SPD and +1 DEF and permanently give the"
			+ " target +5% RES growth."
	))
	var own: ChangeBaseStat = ChangeBaseStat.new()
	own.key = CombatValue.Key.HP
	own.value = 3.0
	_snapshot("permanent run: on the owner", own.describe(), "permanently gain +3 HP")


func _modify_value(key: int, mode: Modifier.Mode, value: float) -> ModifyValue:
	var operation: ModifyValue = ModifyValue.new()
	operation.key = key
	operation.mode = mode
	operation.value = value
	return operation


func _gain(pool: GainResource.Pool, target: TargetSelector, amount: ValueSource) -> GainResource:
	var operation: GainResource = GainResource.new()
	operation.pool = pool
	operation.target = target
	operation.amount = amount
	return operation


func _constant(value: float) -> Constant:
	var constant: Constant = Constant.new()
	constant.value = value
	return constant
