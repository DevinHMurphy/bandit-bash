# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reward_cases.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Reward cases for tests/campaign/run_all.gd: the rules data holds the vision's tables; grades
## and gold (both grades, under par strictly, Survive and Defend, sent units, Gilded Purse, Bounty
## Ledger added flat); XP (shared, personal and its cap, a killing blow, the Standout and its
## ties, Family Ring and Veteran's Medal); level-ups (growths, several at once, current HP,
## Training Weights, Royal Crest, the Resonant Ore, Feast gains, seeded); the item pick (the
## rarity tables and the offset, its fallbacks, never Basic, Legendary or Unique, per seat and
## seeded, pinned offers, its save shape); the pick and leave commands; a fallen commander's return; a Boss win;
## and a real M1 battle paid end to end. Touches no save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const M1_ID: String = "m1_greybox"
const RUN_SEED: int = 0x3F9A12C077E1A
const MERCENARY: String = "mercenary"

# Fixture unit types: no growths, every growth at 100, and a sword user for the weapon pick.
const STILL: String = "test_still"
const GROWER: String = "test_grower"
const SWORDSMAN: String = "test_swordsman"

const STANDARD: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.STANDARD
const KEY: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.KEY
const BOSS: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.BOSS
const COMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.COMMON
const UNCOMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.UNCOMMON
const RARE: ItemDefinition.Rarity = ItemDefinition.Rarity.RARE

const HP: CombatValue.Stat = CombatValue.Stat.HP
const MGT: CombatValue.Stat = CombatValue.Stat.MGT
const SPD: CombatValue.Stat = CombatValue.Stat.SPD
const DEF: CombatValue.Stat = CombatValue.Stat.DEF
const RES: CombatValue.Stat = CombatValue.Stat.RES

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# Draws for the statistical cases, picks for the slot shares, and how far a share may stray from
# its chance.
const DRAWS: int = 6000
const PICKS: int = 2000
const TOLERANCE: float = 0.025

var _report: Callable
var _rules: CombatRewardRules = null
var _map_rules: CampaignMapRules = null
var _catalog: EffectCatalog.Index = null
var _fixtures: EffectCatalog.Index = null
var _pools: CombatMapPools = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_rules = CombatRewardRules.load_default()
	_map_rules = load(RULES_PATH) as CampaignMapRules
	_catalog = EffectCatalog.index()
	_pools = CombatMapPools.load_default()
	_check("rewards: the reward rules, map rules, catalog and pools load", (
			_rules != null and _map_rules != null and _catalog != null and _pools != null
	))
	if _rules == null or _map_rules == null or _catalog == null or _pools == null:
		return
	_fixtures = _catalog_with_fixtures()
	_test_rules_tables()
	_test_grades()
	_test_xp()
	_test_standout()
	_test_level_ups()
	_test_level_up_items()
	_test_rarity_weights()
	_test_pick_rarity_shares()
	_test_pick_fallbacks()
	_test_pick_real_catalog()
	_test_pick_per_seat_and_saved()
	_test_pick_golden()
	_test_commands()
	_test_apply_rewards()
	_test_fallen_commander()
	_test_real_battle()


func _test_rules_tables() -> void:
	_check("rules: gold per combat is 30 / 60 / 0, each grade +8 / +15 / 0", (
			_rules.gold_for(STANDARD) == 30
			and _rules.gold_for(KEY) == 60
			and _rules.gold_for(BOSS) == 0
			and _grade(STANDARD, true, false).bonus_per_grade == 8
			and _grade(KEY, true, false).bonus_per_grade == 15
			and _grade(BOSS, true, true).gold == 0
	))
	_check("rules: shared XP is 40 / 70 / 100; personal +2 / +5 / +3 / +3 / +5, capped at 15", (
			_rules.shared_xp_for(STANDARD) == 40
			and _rules.shared_xp_for(KEY) == 70
			and _rules.shared_xp_for(BOSS) == 100
			and _rules.personal_xp_for(BattleTally.Action.HIT) == 2
			and _rules.personal_xp_for(BattleTally.Action.DEFEAT) == 5
			and _rules.personal_xp_for(BattleTally.Action.HEAL) == 3
			and _rules.personal_xp_for(BattleTally.Action.BLOCK) == 3
			and _rules.personal_xp_for(BattleTally.Action.NON_COMBAT) == 5
			and _rules.personal_xp_cap == 15
	))
	_check("rules: the Standout +5, 100 XP per level, a fallen commander back at 10%", (
			_rules.standout_xp == 5
			and _rules.xp_per_level == 100
			and _rules.fallen_commander_hp_percent == 10
	))
	_check("rules: three offers; slots Weapon 3 / Equipment 2 / Pouch 3; usable weapons 75%", (
			_rules.offer_count == 3
			and _rules.slot_weights() == PackedInt32Array([3, 2, 3])
			and _rules.usable_weapon_chance == 75
	))
	_check("rules: rarity Standard 60 / 30 / 10, Key 50 / 33 / 17; offset +1 from -5 to +40", (
			_rules.rarity_table(STANDARD) == PackedInt32Array([60, 30, 10])
			and _rules.rarity_table(KEY) == PackedInt32Array([50, 33, 17])
			and _rules.rare_offset_step == 1
			and SeatRun.RARE_OFFSET_START == -5
			and SeatRun.RARE_OFFSET_CAP == 40
	))


func _test_grades() -> void:
	var table: Dictionary[String, int] = {
		"Standard, no grade": _grade(STANDARD, false, false).gold,
		"Standard, under par": _grade(STANDARD, true, false).gold,
		"Standard, no losses": _grade(STANDARD, false, true).gold,
		"Standard, both": _grade(STANDARD, true, true).gold,
		"Key, no grade": _grade(KEY, false, false).gold,
		"Key, one grade": _grade(KEY, false, true).gold,
		"Key, both": _grade(KEY, true, true).gold,
		"Boss, both": _grade(BOSS, true, true).gold,
	}
	var expected: Dictionary[String, int] = {
		"Standard, no grade": 30, "Standard, under par": 38, "Standard, no losses": 38,
		"Standard, both": 46, "Key, no grade": 60, "Key, one grade": 75, "Key, both": 90,
		"Boss, both": 0,
	}
	_check("grades: the vision's gold table (30 +8 per grade, 60 +15, Boss 0)", (
			table == expected
	), str(table))

	var ledger: CampaignSession.SeatOutcome = _outcome(STANDARD, true, false)
	ledger.combat_gold = 8
	var with_ledger: CombatGrades = CombatGrades.grade(ledger, _rules)
	_check("grades: Bounty Ledger adds 8 flat after one grade: 30 + 8 + 8 = 46", (
			with_ledger.gold == 46
			and with_ledger.bonus_per_grade == 8
			and with_ledger.extra_gold == 8
			and with_ledger.grade_count() == 1
	), str(with_ledger.capture()))
	var purse: CampaignSession.SeatOutcome = _outcome(STANDARD, true, true)
	purse.grade_bonus_percent = 50
	_check("grades: Gilded Purse's +25 points make each grade 50%: 30 + 15 + 15", (
			CombatGrades.grade(purse, _rules).gold == 60
	))

	var on_par: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	on_par.turn_par = 5
	on_par.turn = 5
	var below: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	below.turn_par = 5
	below.turn = 4
	var no_par: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	no_par.turn = 1
	var sent: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	sent.turn_par = 5
	sent.turn = 2
	sent.has_received_units = true
	_check("grades: under par is a turn below par; on par, no par, or sent units earn none", (
			CombatGrades.is_under_par_for(below)
			and not CombatGrades.is_under_par_for(on_par)
			and not CombatGrades.is_under_par_for(no_par)
			and not CombatGrades.is_under_par_for(sent)
	))
	var survive: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	survive.objective = CombatMapDefinition.Objective.SURVIVE
	survive.turns_early = 2
	var defend: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	defend.objective = CombatMapDefinition.Objective.DEFEND
	_check("grades: Survive earns it by ending early; Defend held to the end doesn't", (
			CombatGrades.is_under_par_for(survive) and not CombatGrades.is_under_par_for(defend)
	))
	var lost: CampaignSession.SeatOutcome = _outcome(KEY, true, true)
	lost.is_won = false
	_check("grades: a lost map earns no grade and no gold", (
			CombatGrades.grade(lost, _rules).gold == 0
			and CombatGrades.grade(lost, _rules).grade_count() == 0
	))


func _test_xp() -> void:
	var units: Array[UnitInstance] = [_unit("unit:1", STILL), _unit("unit:2", STILL)]
	var tally: BattleTally = BattleTally.new()
	# unit:1: two hits and a killing blow (hit and defeat): 2 + 2 + 2 + 5 = 11.
	_record(tally, "unit:1", BattleTally.Action.HIT, 3)
	_record(tally, "unit:1", BattleTally.Action.DEFEAT, 1)
	# unit:2: two heals, two Block and two non-combat actions: 6 + 6 + 10 = 22, capped at 15.
	_record(tally, "unit:2", BattleTally.Action.HEAL, 2)
	_record(tally, "unit:2", BattleTally.Action.BLOCK, 2)
	_record(tally, "unit:2", BattleTally.Action.NON_COMBAT, 2)
	var no_percents: Dictionary[String, int] = {}
	var awards: Array[XpAward] = XpAward.award(
			units, tally, _outcome(STANDARD, false, false), no_percents, _rules
	)
	_check("xp: shared 40; personal from actions, a killing blow +7; capped at 15", (
			awards.size() == 2
			and awards[0].shared == 40
			and awards[0].personal == 11
			and XpAward.personal_xp(tally, "unit:2", _rules) == 22
			and awards[1].personal == 15
	), "%s / %s" % [awards[0].capture(), awards[1].capture()])
	_check("xp: the Standout (most actions) gets +5 on top of the cap", (
			awards[1].is_standout
			and awards[1].standout == 5
			and awards[1].total == 40 + 15 + 5
			and not awards[0].is_standout
			and awards[0].total == 40 + 11
	), "%d / %d" % [awards[0].total, awards[1].total])
	var key_awards: Array[XpAward] = XpAward.award(
			units, tally, _outcome(KEY, false, false), no_percents, _rules
	)
	var boss_awards: Array[XpAward] = XpAward.award(
			units, tally, _outcome(BOSS, false, false), no_percents, _rules
	)
	_check("xp: Key shares 70, Boss 100", (
			key_awards[0].shared == 70 and boss_awards[0].shared == 100
	))
	var ring: Dictionary[String, int] = {"unit:1": 125}
	var medal: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	medal.shared_xp_percent = 120
	var boosted: Array[XpAward] = XpAward.award(units, tally, medal, ring, _rules)
	_check("xp: Veteran's Medal raises shared XP; Family Ring all a unit's XP, halves up", (
			boosted[0].shared == 48
			and boosted[0].percent == 125
			and boosted[0].total == 74
			and boosted[1].total == 48 + 15 + 5
	), "%d / %d" % [boosted[0].total, boosted[1].total])
	var lost: CampaignSession.SeatOutcome = _outcome(STANDARD, false, false)
	lost.is_won = false
	_check("xp: a lost map pays no XP and names no Standout", (
			XpAward.award(units, tally, lost, no_percents, _rules).is_empty()
	))


func _test_standout() -> void:
	var low: UnitInstance = _unit("unit:1", STILL)
	var high: UnitInstance = _unit("unit:2", STILL)
	high.level = 3
	var tally: BattleTally = BattleTally.new()
	_record(tally, "unit:1", BattleTally.Action.HIT, 2)
	_record(tally, "unit:2", BattleTally.Action.HIT, 2)
	var by_level: String = XpAward.standout_of([high, low], tally, _rules)
	var level_a: UnitInstance = _unit("unit:3", STILL)
	var level_b: UnitInstance = _unit("unit:4", STILL)
	var tied: BattleTally = BattleTally.new()
	# Two actions each: two hits (4 XP), or a hit and a defeat (7 XP).
	_record(tied, "unit:3", BattleTally.Action.HIT, 2)
	_record(tied, "unit:4", BattleTally.Action.HIT, 1)
	_record(tied, "unit:4", BattleTally.Action.DEFEAT, 1)
	var by_personal: String = XpAward.standout_of([level_a, level_b], tied, _rules)
	var even: BattleTally = BattleTally.new()
	_record(even, "unit:3", BattleTally.Action.HIT, 1)
	_record(even, "unit:4", BattleTally.Action.HIT, 1)
	var by_roster: String = XpAward.standout_of([level_b, level_a], even, _rules)
	_check("standout: a tie goes to the lower level, then more personal XP, then roster order", (
			by_level == "unit:1" and by_personal == "unit:4" and by_roster == "unit:4"
	), "%s, %s, %s" % [by_level, by_personal, by_roster])
	_check("standout: none when no unit acted", (
			XpAward.standout_of([low, high], BattleTally.new(), _rules).is_empty()
	))


func _test_level_ups() -> void:
	var grower: UnitInstance = _unit("unit:1", GROWER)
	grower.hp = 10
	var reached: Array[LevelUp] = LevelUp.gain_xp(
			grower, 215, null, RngStream.new(1), _fixtures, _rules
	)
	var gains: Dictionary[int, int] = {HP: 2, MGT: 2, SPD: 2, DEF: 2, RES: 2}
	_check("level-ups: 215 XP is two level-ups with 15 left; 100% growths raise every stat", (
			reached.size() == 2
			and grower.level == 3
			and grower.xp == 15
			and reached[0].level == 2
			and reached[1].level == 3
			and _deltas(grower) == gains
	), "%d levels, %d XP, %s" % [reached.size(), grower.xp, _deltas(grower)])
	_check("level-ups: HP gained raises a hurt unit's current HP; a full unit stays full", (
			grower.hp == 12 and _level(_unit("unit:9", GROWER)).hp == UnitInstance.FULL_HP
	), str(grower.hp))
	_check("level-ups: their deltas are one per stat, sourced Level-ups", (
			grower.stat_deltas.size() == 5
			and grower.stat_deltas[0].source_id == LevelUp.SOURCE_ID
			and grower.stat_deltas[0].label == LevelUp.SOURCE_LABEL
	))
	var none: Array[LevelUp] = LevelUp.gain_xp(
			_unit("unit:2", STILL), 99, null, RngStream.new(1), _fixtures, _rules
	)
	_check("level-ups: 99 XP is none", none.is_empty())

	# Growth 150: one point always, a second on the d100 half of the time; seeded.
	var half: Dictionary[int, int] = {}
	for draw: int in DRAWS:
		var unit: UnitInstance = _unit("unit:3", STILL)
		unit.growth_deltas.append(ItemInstance.StatDelta.new(MGT, 150.0, "", ""))
		var mgt: int = LevelUp.level_up(unit, null, RngStream.new(draw), _fixtures).gains[MGT]
		half[mgt] = half.get(mgt, 0) + 1
	_check("level-ups: a growth over 100 is a point per 100 and a roll of the rest", (
			half.keys().size() == 2
			and _near((half.get(2, 0) as int), 0.5)
			and _near((half.get(1, 0) as int), 0.5)
	), str(half))
	var first: UnitInstance = _unit("unit:4", STILL)
	var second: UnitInstance = _unit("unit:4", STILL)
	for unit: UnitInstance in [first, second]:
		unit.growth_deltas.append(ItemInstance.StatDelta.new(DEF, 45.0, "", ""))
		LevelUp.gain_xp(unit, 500, null, RngStream.new(77), _fixtures, _rules)
	_check("level-ups: the same stream gives the same gains", (
			_deltas(first) == _deltas(second) and first.level == 6
	))


func _test_level_up_items() -> void:
	var weights: LevelUp.Values = LevelUp.Values.new()
	weights.guaranteed[MGT] = 1
	weights.denied.append(SPD)
	var trained: LevelUp = LevelUp.level_up(
			_unit("unit:1", GROWER), weights, RngStream.new(3), _fixtures
	)
	_check("level-up: Training Weights adds +1 MGT and Speed doesn't grow", (
			trained.gains == {HP: 1, MGT: 2, DEF: 1, RES: 1}
	), str(trained.gains))

	var ore: LevelUp.Values = LevelUp.Values.new()
	ore.random_gains = 1
	var raised: Dictionary[int, int] = {}
	var is_single: bool = true
	for draw: int in 400:
		var gained: LevelUp = LevelUp.level_up(
				_unit("unit:2", STILL), ore, RngStream.new(draw), _fixtures
		)
		is_single = is_single and gained.gains.size() == 1 and gained.gains.values() == [1]
		for stat: int in gained.gains:
			raised[stat] = raised.get(stat, 0) + 1
	_check("level-up: the Resonant Ore adds +1 to one random stat, never Speed", (
			is_single and raised.keys().size() == 4 and not raised.has(SPD)
	), str(raised))
	var ore_weights: LevelUp.Values = LevelUp.Values.new()
	ore_weights.random_gains = 1
	ore_weights.denied.assign([SPD, HP, MGT, DEF])
	var only_res: LevelUp = LevelUp.level_up(
			_unit("unit:3", STILL), ore_weights, RngStream.new(5), _fixtures
	)
	_check("level-up: the Ore's random stat is one still allowed to grow", (
			only_res.gains == {RES: 1}
	), str(only_res.gains))

	var crest: LevelUp.Values = LevelUp.Values.new()
	crest.min_stats = 3
	var three: LevelUp = LevelUp.level_up(
			_unit("unit:4", STILL), crest, RngStream.new(9), _fixtures
	)
	var crest_and_weights: LevelUp.Values = LevelUp.Values.new()
	crest_and_weights.min_stats = 3
	crest_and_weights.guaranteed[MGT] = 1
	crest_and_weights.denied.append(SPD)
	var with_weights: LevelUp = LevelUp.level_up(
			_unit("unit:5", STILL), crest_and_weights, RngStream.new(9), _fixtures
	)
	_check("level-up: Royal Crest raises 3 stats, the guaranteed gain counting as one", (
			three.gains.size() == 3
			and three.gains.values() == [1, 1, 1]
			and with_weights.gains.size() == 3
			and (with_weights.gains.get(MGT, 0) as int) == 1
			and not with_weights.gains.has(SPD)
	), "%s / %s" % [three.gains, with_weights.gains])

	var feast: UnitInstance = _unit("unit:6", STILL)
	var sap: UnitInstance.PendingGain = UnitInstance.PendingGain.new()
	sap.stat = MGT
	sap.amount = 1
	sap.remaining = 2
	feast.pending_gains.append(sap)
	var once: LevelUp = _level_up(feast)
	var remaining_after_one: int = feast.pending_gains[0].remaining
	var twice: LevelUp = _level_up(feast)
	var thrice: LevelUp = _level_up(feast)
	_check("level-up: a Feast's pending gain adds once per level-up until spent", (
			once.gains == {MGT: 1}
			and remaining_after_one == 1
			and twice.gains == {MGT: 1}
			and feast.pending_gains.is_empty()
			and thrice.gains.is_empty()
	))


func _test_rarity_weights() -> void:
	var standard: PackedInt32Array = _rules.rarity_table(STANDARD)
	var key: PackedInt32Array = _rules.rarity_table(KEY)
	_check("rarity: the offset adds to Rare, taken from Common (-5, 0, +40)", (
			ItemPick.rarity_weights(standard, -5) == PackedInt32Array([65, 30, 5])
			and ItemPick.rarity_weights(standard, 0) == PackedInt32Array([60, 30, 10])
			and ItemPick.rarity_weights(standard, 40) == PackedInt32Array([20, 30, 50])
			and ItemPick.rarity_weights(key, 40) == PackedInt32Array([10, 33, 57])
	))
	_check("rarity: once Common is used up, the offset takes from Uncommon; none below 0", (
			ItemPick.rarity_weights(PackedInt32Array([5, 30, 10]), 20)
					== PackedInt32Array([0, 15, 30])
			and ItemPick.rarity_weights(PackedInt32Array([60, 30, 3]), -5)
					== PackedInt32Array([63, 30, 0])
	))
	_check("rarity: a Common shown raises the offset by 1 to +40; a Rare resets it to -5", (
			ItemPick.next_offset(-5, COMMON, _rules) == -4
			and ItemPick.next_offset(40, COMMON, _rules) == 40
			and ItemPick.next_offset(12, UNCOMMON, _rules) == 12
			and ItemPick.next_offset(12, RARE, _rules) == -5
	))


# One-offer Equipment picks with the offset held at 0 show the tables' shares (a Rare resets the
# offset, so a second offer would roll with -5); with it moving, the offset after a pick follows
# its offers' rarities.
func _test_pick_rarity_shares() -> void:
	for combat_type: CombatMapDefinition.CombatType in [STANDARD, KEY]:
		var rules: CombatRewardRules = _equipment_rules()
		rules.rare_offset_step = 0
		rules.offer_count = 1
		var counts: Dictionary[int, int] = {}
		var seat_run: SeatRun = _seat_run(STILL)
		var stream: RngStream = RngStream.new(41)
		var shown: int = 0
		while shown < DRAWS:
			seat_run.rare_offset = 0
			var pick: ItemPick = ItemPick.roll(
					stream, combat_type, seat_run, rules, _catalog, InstanceIdAllocator.new()
			)
			for offer: ItemPick.Offer in pick.offers:
				var rarity: int = _catalog.item(offer.definition_id).rarity
				counts[rarity] = counts.get(rarity, 0) + 1
				shown += 1
		var table: PackedInt32Array = rules.rarity_table(combat_type)
		_check("pick: %s offers show Common %d / Uncommon %d / Rare %d" % [
			CombatMapDefinition.CombatType.find_key(combat_type), table[0], table[1], table[2],
		], (
				_near_share((counts.get(COMMON, 0) as int), shown, table[0])
				and _near_share((counts.get(UNCOMMON, 0) as int), shown, table[1])
				and _near_share((counts.get(RARE, 0) as int), shown, table[2])
		), str(counts))

	var moving: SeatRun = _seat_run(STILL)
	var pick: ItemPick = ItemPick.roll(
			RngStream.new(8), STANDARD, moving, _equipment_rules(), _catalog,
			InstanceIdAllocator.new()
	)
	var expected: int = SeatRun.RARE_OFFSET_START
	for offer: ItemPick.Offer in pick.offers:
		expected = ItemPick.next_offset(expected, _catalog.item(offer.definition_id).rarity, _rules)
	_check("pick: the seat's offset moves by each offer's rarity in turn", (
			pick.offers.size() == 3 and moving.rare_offset == expected
	), "%d, expected %d" % [moving.rare_offset, expected])


func _test_pick_fallbacks() -> void:
	var rules: CombatRewardRules = _rules.duplicate() as CombatRewardRules
	rules.weapon_pick_weight = 1
	rules.equipment_pick_weight = 0
	rules.pouch_pick_weight = 0
	rules.usable_weapon_chance = 100
	rules.rare_offset_step = 0
	var weapons: EffectCatalog.Index = _weapon_fixtures(true)
	rules.standard_common = 100
	rules.standard_uncommon = 0
	rules.standard_rare = 0
	var seat_run: SeatRun = _seat_run(SWORDSMAN)
	seat_run.rare_offset = 0
	var commons: ItemPick = ItemPick.roll(
			RngStream.new(2), STANDARD, seat_run, rules, weapons, InstanceIdAllocator.new()
	)
	_check("pick fallback: a usable type first, then any type, then the next higher rarity", (
			_offered(commons) == PackedStringArray(["test_sword_c", "test_bow_c", "test_axe_u"])
	), str(_offered(commons)))
	# Every offer rolls Uncommon, and there is none: the lower rarity comes before the higher.
	rules.standard_common = 0
	rules.standard_uncommon = 100
	seat_run.rare_offset = 0
	var uncommons: ItemPick = ItemPick.roll(
			RngStream.new(2), STANDARD, seat_run, rules, _weapon_fixtures(false),
			InstanceIdAllocator.new()
	)
	_check("pick fallback: an empty rarity falls to the next lower one before the higher", (
			_offered(uncommons)
					== PackedStringArray(["test_sword_c", "test_bow_c", "test_lance_r"])
	), str(_offered(uncommons)))
	rules.standard_common = 100
	rules.standard_uncommon = 0
	rules.offer_count = 5
	seat_run.rare_offset = 0
	var short: ItemPick = ItemPick.roll(
			RngStream.new(2), STANDARD, seat_run, rules, weapons, InstanceIdAllocator.new()
	)
	_check("pick fallback: a kind that runs short offers fewer, all different", (
			short.offers.size() == 4 and _is_distinct(short)
	), str(_offered(short)))


func _test_pick_real_catalog() -> void:
	var weapon_rules: CombatRewardRules = _rules.duplicate() as CombatRewardRules
	weapon_rules.weapon_pick_weight = 1
	weapon_rules.equipment_pick_weight = 0
	weapon_rules.pouch_pick_weight = 0
	var weapon_pick: ItemPick = ItemPick.roll(
			RngStream.new(4), STANDARD, _seat_run(STILL), weapon_rules, _catalog,
			InstanceIdAllocator.new()
	)
	var is_never_basic: bool = not weapon_pick.offers.is_empty()
	for offer: ItemPick.Offer in weapon_pick.offers:
		if _catalog.item(offer.definition_id).rarity == ItemDefinition.Rarity.BASIC:
			is_never_basic = false
	_check("pick: a real weapon pick offers weapons, none of them Basic", (
			weapon_pick.slot == ItemPick.Slot.WEAPON and is_never_basic
	), str(_offered(weapon_pick)))
	var rarities: Dictionary[int, int] = {}
	var kinds: Dictionary[int, int] = {}
	var is_one_kind: bool = true
	var is_distinct: bool = true
	var seat_run: SeatRun = _seat_run(STILL)
	var stream: RngStream = RngStream.new(19)
	for draw: int in PICKS:
		var pick: ItemPick = ItemPick.roll(
				stream, KEY, seat_run, _rules, _catalog, InstanceIdAllocator.new()
		)
		kinds[pick.slot] = kinds.get(pick.slot, 0) + 1
		is_distinct = is_distinct and _is_distinct(pick)
		for offer: ItemPick.Offer in pick.offers:
			var item: ItemDefinition = _catalog.item(offer.definition_id)
			rarities[item.rarity] = rarities.get(item.rarity, 0) + 1
			is_one_kind = is_one_kind and ItemPick.items_for(pick.slot, _catalog).has(item)
	_check("pick: offers are Common, Uncommon or Rare only, never Legendary or Unique", (
			rarities.keys().size() == 3
			and not rarities.has(ItemDefinition.Rarity.BASIC)
			and not rarities.has(ItemDefinition.Rarity.LEGENDARY)
			and not rarities.has(ItemDefinition.Rarity.UNIQUE)
	), str(rarities))
	_check("pick: one slot kind per pick, Weapon 3 / Equipment 2 / Pouch 3; offers differ", (
			is_one_kind
			and is_distinct
			and _near_share((kinds.get(ItemPick.Slot.WEAPON, 0) as int), PICKS, 37.5)
			and _near_share((kinds.get(ItemPick.Slot.EQUIPMENT, 0) as int), PICKS, 25.0)
			and _near_share((kinds.get(ItemPick.Slot.POUCH, 0) as int), PICKS, 37.5)
	), str(kinds))
	_check("pick: a Boss combat offers none", (
			ItemPick.roll(
					RngStream.new(4), BOSS, _seat_run(STILL), _rules, _catalog,
					InstanceIdAllocator.new()
			) == null
	))


# Three picks each on streams 1 to 40, Standard and Key, for an Archer's army, on today's catalog:
# slot, offers and the offset after each. Pinned before the pick drew through ItemPools, so the
# move changed no seed's offers; a new item of a pick's kind changes it, and it is re-recorded.
func _test_pick_golden() -> void:
	var lines: PackedStringArray = []
	for combat_type: CombatMapDefinition.CombatType in [STANDARD, KEY]:
		for stream_seed: int in range(1, 41):
			var seat_run: SeatRun = SeatRun.new(0)
			seat_run.army.append(_unit("unit:1", "archer"))
			var stream: RngStream = RngStream.new(stream_seed)
			for pick_number: int in 3:
				var pick: ItemPick = ItemPick.roll(
						stream, combat_type, seat_run, _rules, _catalog, InstanceIdAllocator.new()
				)
				lines.append("%d:%d:%d:%s:%d" % [
					combat_type, stream_seed, pick.slot, ",".join(_offered(pick)),
					seat_run.rare_offset,
				])
	_check("pick: 240 seeded picks are pinned", (
			"\n".join(lines).sha256_text()
			== "79098ea9af968222eb805543c2f011a9b9f4314f8042fb01578a5f248e6c3a33"
	), lines[0])


func _test_pick_per_seat_and_saved() -> void:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	var result: CampaignSession.BattleResult = CampaignSession.BattleResult.new()
	result.floor_number = 2
	result.node = 7
	var rolls: CampaignSession.RewardRolls = session.reward_rolls(result)
	_check("per seat: each seat's reward and level-up streams are its own, on the node's keys", (
			rolls.reward[0] != rolls.reward[1]
			and rolls.level_ups[0] != rolls.level_ups[1]
			and rolls.reward[1] == session.rng.stream(
					RngKey.new(RngKey.RngPurpose.REWARD, 2, 7, 1)
			)
			and rolls.level_ups[0] == session.rng.stream(
					RngKey.new(RngKey.RngPurpose.LEVEL_UPS, 2, 7, 0)
			)
	))
	var texts: PackedStringArray = []
	for seat: int in [0, 1, 0]:
		var streams: RngStreams = RngStreams.new(RUN_SEED)
		var key: RngKey = RngKey.new(RngKey.RngPurpose.REWARD, 2, 7, seat)
		var picks: Array = []
		for node_pick: int in 4:
			picks.append(ItemPick.roll(
					streams.stream(key), STANDARD, _seat_run(STILL), _rules, _catalog,
					InstanceIdAllocator.new()
			).capture())
		texts.append(JSON.stringify(picks))
	_check("per seat: a seat's picks repeat on its seed; another seat's differ", (
			texts[0] == texts[2] and texts[0] != texts[1]
	))
	var pick: ItemPick = ItemPick.roll(
			RngStream.new(6), KEY, _seat_run(STILL), _rules, _catalog, InstanceIdAllocator.new()
	)
	var seat_run: SeatRun = _seat_run(STILL)
	pick.store(seat_run)
	var json: Variant = JSON.parse_string(JSON.stringify(seat_run.capture_economy()))
	var reloaded: SeatRun = SeatRun.new(0)
	var restored: Error = reloaded.restore_economy(json as Dictionary)
	var back: ItemPick = ItemPick.pending(reloaded)
	_check("saved pick: it round-trips through the economy section's JSON", (
			restored == OK
			and back != null
			and JSON.stringify(back.capture()) == JSON.stringify(pick.capture())
			and not back.is_resolved
			and back.taken == ItemPick.NOT_TAKEN
	))
	print("    (errors about unusable item picks follow)")
	var bad: Dictionary[String, Dictionary] = {
		"an unknown slot": {"slot": "hat", "offers": [], "is_resolved": false, "taken": -1},
		"an offer without ids": {
			"slot": "pouch", "offers": [{"definition_id": "x"}], "is_resolved": false,
			"taken": -1,
		},
		"a taken index past the offers": {
			"slot": "pouch", "offers": [], "is_resolved": true, "taken": 2.0,
		},
	}
	for case_name: String in bad:
		var holder: SeatRun = SeatRun.new(0)
		holder.pending_offers[ItemPick.OFFER_KEY] = bad[case_name]
		_check("saved pick: %s reads as no pick" % [case_name], ItemPick.pending(holder) == null)


func _test_commands() -> void:
	var session: CampaignSession = _session()
	var run: CampaignRunState = session.run
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var seat_run: SeatRun = run.seat_run(0)
	var pick: ItemPick = ItemPick.roll(
			RngStream.new(10), STANDARD, seat_run, _equipment_rules(), _catalog, session.ids
	)
	pick.store(seat_run)
	seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {"grades": {}}
	var too_early: CampaignBatch = session.submit(ItemPickCommand.new(0, 0))
	run.flow.stage = RunFlow.Stage.RESULTS
	var no_offer: CampaignBatch = session.submit(ItemPickCommand.new(0, 7))
	var leave_open: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	print("    (an error about a run that isn't inside a node's battle follows)")
	var no_battle: CampaignSession.BattleRequest = run.battle_request(_pools, _catalog)
	_check("commands: no pick outside results, nor of a missing offer; no leaving it open", (
			too_early.is_rejected()
			and no_offer.is_rejected()
			and leave_open.is_rejected()
			and no_battle == null
			and not run.is_on_map()
	), "%s / %s / %s" % [
		too_early.rejected_reason, no_offer.rejected_reason, leave_open.rejected_reason,
	])
	var convoy_before: int = seat_run.convoy.size()
	var took: CampaignBatch = session.submit(ItemPickCommand.new(0, 1))
	var again: CampaignBatch = session.submit(ItemPickCommand.new(0, 0))
	var taken: ItemPick.Offer = pick.offers[1]
	_check("commands: taking an offer puts it at the end of the convoy, with its rolled id", (
			not took.is_rejected()
			and took.facts.size() == 1
			and took.facts[0].kind == CampaignFact.Kind.GAINED
			and took.facts[0].actor_id == taken.instance_id
			and took.facts[0].definition_id == taken.definition_id
			and seat_run.convoy.size() == convoy_before + 1
			and seat_run.convoy[seat_run.convoy.size() - 1] == taken.instance_id
			and seat_run.items[taken.instance_id].definition_id == taken.definition_id
			and SeatRun.new(0).restore_roster(seat_run.capture_roster()) == OK
	), took.rejected_reason)
	_check("commands: a pick is taken once", (
			again.is_rejected()
			and ItemPick.pending(seat_run).is_resolved
			and ItemPick.pending(seat_run).taken == 1
	))
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("commands: once resolved, leaving goes to the map and clears the report and pick", (
			not left.is_rejected()
			and run.is_on_map()
			and not seat_run.pending_offers.has(ItemPick.OFFER_KEY)
			and not seat_run.pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
	), left.rejected_reason)

	session.submit(ChooseNodeCommand.new(0, run.graph.children_of(run.node)[0]))
	ItemPick.roll(
			RngStream.new(11), STANDARD, seat_run, _equipment_rules(), _catalog, session.ids
	).store(seat_run)
	run.flow.stage = RunFlow.Stage.RESULTS
	var items_before: int = seat_run.items.size()
	var skipped: CampaignBatch = session.submit(ItemPickCommand.new(0, ItemPickCommand.SKIP))
	var after_skip: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("commands: skipping gives nothing and lets the team leave", (
			not skipped.is_rejected()
			and skipped.facts.is_empty()
			and seat_run.items.size() == items_before
			and not after_skip.is_rejected()
	), skipped.rejected_reason)


# Fixture results applied to a run: a won Standard map pays gold, XP, the Standout and level-ups,
# rolls a pick and moves to results; a Boss win pays XP and level-ups but no pick; a lost map
# pays nothing.
func _test_apply_rewards() -> void:
	var session: CampaignSession = _session()
	var run: CampaignRunState = session.run
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var army: Array[UnitInstance] = run.seat_run(0).army
	army[1].xp = 90
	var result: CampaignSession.BattleResult = _won_result(run, STANDARD)
	_record(result.tally, army[1].instance_id, BattleTally.Action.HIT, 2)
	var start_gold: int = run.seat_run(0).gold
	var start_offset: int = run.seat_run(0).rare_offset
	var next: CampaignRunState = run.apply_battle(
			result, session.ids, session.reward_rolls(result), _rules, _catalog
	)
	var after: SeatRun = next.seat_run(0)
	var report: Dictionary = after.pending_offers.get(CampaignRunState.COMBAT_REPORT_KEY, {})
	var xp: Array = report.get("xp", [])
	var level_ups: Array = report.get("level_ups", [])
	_check("apply: a won Standard map with no losses pays 38 and moves to results", (
			after.gold == start_gold + 38
			and next.flow.stage == RunFlow.Stage.RESULTS
			and not next.is_on_map()
			and ((report.get("grades", {}) as Dictionary).get("gold") as int) == 38
	), "%d gold, stage %s" % [after.gold, next.flow.stage_id(next.flow.stage)])
	_check("apply: each standing unit gets shared XP; the Standout +5; a level-up at 100", (
			xp.size() == 4
			and ((xp[0] as Dictionary).get("total") as int) == 40
			and ((xp[1] as Dictionary).get("total") as int) == 40 + 4 + 5
			and ((xp[1] as Dictionary).get("standout") as bool)
			and after.army[1].level == 2
			and after.army[1].xp == 90 + 49 - 100
			and level_ups.size() == 1
			and str((level_ups[0] as Dictionary).get("unit_id")) == army[1].instance_id
			and after.army[0].xp == 40
	), "%s / %s" % [xp, level_ups])
	var leveled: Array[CampaignFact] = []
	for fact: CampaignFact in next.fact_log.slice(run.fact_log.size()):
		if fact.kind == CampaignFact.Kind.LEVELED_UP:
			leveled.append(fact)
	var pick: ItemPick = ItemPick.pending(after)
	_check("apply: the level-up is recorded; the pick is rolled and saved", (
			leveled.size() == 1
			and leveled[0].actor_id == army[1].instance_id
			and leveled[0].amount == 2
			and pick != null
			and not pick.offers.is_empty()
			and not pick.is_resolved
	))
	_check("apply: the run itself is unchanged", (
			run.seat_run(0).gold == start_gold
			and run.seat_run(0).rare_offset == start_offset
			and not run.seat_run(0).pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
			and run.flow.stage == RunFlow.Stage.NODE
	))

	var boss: CampaignSession.BattleResult = _won_result(run, BOSS)
	var after_boss: CampaignRunState = run.apply_battle(
			boss, session.ids, session.reward_rolls(boss), _rules, _catalog
	)
	var boss_seat: SeatRun = after_boss.seat_run(0)
	_check("apply: a Boss win pays 100 shared XP and no gold, and offers no pick", (
			boss_seat.gold == start_gold
			and boss_seat.army[0].xp == 0
			and boss_seat.army[0].level == 2
			and not boss_seat.pending_offers.has(ItemPick.OFFER_KEY)
			and boss_seat.pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
			and after_boss.flow.stage == RunFlow.Stage.RESULTS
	), "%d gold, XP %d, level %d" % [
		boss_seat.gold, boss_seat.army[0].xp, boss_seat.army[0].level,
	])

	var lost: CampaignSession.BattleResult = _won_result(run, STANDARD)
	lost.is_won = false
	lost.seats[0].is_won = false
	var after_loss: CampaignRunState = run.apply_battle(
			lost, session.ids, session.reward_rolls(lost), _rules, _catalog
	)
	_check("apply: a lost map pays nothing and stays in the node", (
			after_loss.seat_run(0).gold == start_gold
			and after_loss.seat_run(0).pending_offers.is_empty()
			and after_loss.seat_run(0).army[0].xp == 0
			and after_loss.flow.stage == RunFlow.Stage.NODE
	))
	print("    (an error about missing reward rules follows)")
	_check("apply: no rules, no result applied", (
			run.apply_battle(result, session.ids, session.reward_rolls(result), null) == null
	))


func _test_fallen_commander() -> void:
	var session: CampaignSession = _session()
	var run: CampaignRunState = session.run
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var commander_id: String = run.seat_run(0).commander_id
	var hp_by_max: Dictionary[int, int] = {}
	for max_hp: int in [23, 25, 4]:
		var result: CampaignSession.BattleResult = _won_result(run, STANDARD)
		result.is_won = false
		result.seats[0].is_won = false
		result.units[commander_id] = _unit_outcome(0, true)
		result.units[commander_id].max_hp = max_hp
		var next: CampaignRunState = run.apply_battle(
				result, session.ids, session.reward_rolls(result), _rules, _catalog
		)
		var seat_run: SeatRun = next.seat_run(0)
		var commander: UnitInstance = seat_run.unit(commander_id)
		hp_by_max[max_hp] = commander.hp
		_check("fallen commander (max HP %d): stays in the army, the commander still" % [max_hp], (
				seat_run.commander_id == commander_id
				and seat_run.army.has(commander)
				and seat_run.fallen.is_empty()
				and SeatRun.new(0).restore_roster(seat_run.capture_roster()) == OK
		))
	_check("fallen commander: back at 10% of its battle max HP, halves up, at least 1", (
			hp_by_max == {23: 2, 25: 3, 4: 1}
	), str(hp_by_max))


# A real M1 battle with a turn par, run end to end: a Bounty Ledger on the seat, a Family Ring,
# Training Weights and the Resonant Ore on units; a killing blow, a unit fallen, the map won on
# turn 1. Run twice, the same seed pays the same.
func _test_real_battle() -> void:
	var first: Dictionary = _play_real_battle()
	var second: Dictionary = _play_real_battle()
	if first.is_empty():
		_check("real battle: the battle begins and ends", false)
		return
	var gold: int = first["gold"]
	var xp: Array = first["xp"]
	var weights: String = first["weights"]
	var ore: int = first["ore"]
	var ore_speed: int = first["ore_speed"]
	var base_speed: int = first["base_speed"]
	var trained_level: int = first["trained_level"]
	var trained_gains: Dictionary = first["trained_gains"]
	var first_text: String = first["text"]
	var second_text: String = second.get("text", "")
	_check("real battle: under par with a unit fallen and a Bounty Ledger: 30 + 8 + 8", (
			gold == 46
	), str(gold))
	_check("real battle: XP from the tally; the killing blow's unit is the Standout", (
			xp == [40, 40 + 11 + 5, 53]
	), str(xp))
	_check("real battle: Training Weights and the Resonant Ore are read as the battle ends", (
			weights == "MGT 1, SPD denied" and ore == 1 and ore_speed == base_speed - 2
	), "%s; ore %d, SPD %d of %d" % [weights, ore, ore_speed, base_speed])
	_check("real battle: the Weights' unit levels up with +1 MGT and no Speed", (
			trained_level == 2
			and (trained_gains.get(MGT, 0) as int) >= 1
			and not trained_gains.has(SPD)
	), str(trained_gains))
	_check("real battle: the same seed pays the same, pick and level-ups included", (
			first_text == second_text
	))


# The real battle of _test_real_battle(); empty when it couldn't be played.
func _play_real_battle() -> Dictionary:
	var session: CampaignSession = _session()
	var run: CampaignRunState = session.run
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var seat_run: SeatRun = run.seat_run(0)
	var army: Array[UnitInstance] = seat_run.army
	var start_gold: int = seat_run.gold
	_hold(session, seat_run, army[0], "resonant_ore", false)
	_hold(session, seat_run, army[2], "family_ring", false)
	_hold(session, seat_run, army[1], "training_weights", true)
	army[1].xp = 60
	var ledger: EffectDefinition = EffectDefinition.new()
	ledger.id = "test_bounty_ledger"
	var gold: ModifyValue = ModifyValue.new()
	gold.key = CampaignValue.Key.COMBAT_GOLD
	gold.value = 8.0
	ledger.operations.append(gold)
	session.add_carrier(EffectInstance.new(
			session.ids.next_effect_id("Bounty Ledger"),
			ledger,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.HEIRLOOM
	))
	var request: CampaignSession.BattleRequest = run.battle_request(_pools, _catalog)
	var with_par: CombatMapDefinition = request.pool[0].duplicate() as CombatMapDefinition
	with_par.turn_par = 5
	request.pool = [with_par]
	request.opening_swap[0] = false
	var battle: CombatEncounter = session.begin_battle(request)
	if battle == null:
		return {}
	var map: CombatSession = battle.get_session(0)
	var enemies: PackedStringArray = map.state.units_of(ENEMY)
	if enemies.is_empty():
		session.close()
		return {}
	var striker: String = army[1].instance_id
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, striker, enemies[0]))
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, striker, enemies[0]))
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, striker, enemies[0]))
	map.state.defeat(map.engine, enemies[0], striker)
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, army[2].instance_id, enemies[0]))
	map.state.defeat(map.engine, army[3].instance_id, enemies[0])
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	map.engine.record(ended)
	var base_speed: int = army[0].stats(_catalog).get_int(CombatValue.Key.SPD)
	var ore_speed: int = map.stats(army[0].instance_id).get_int(CombatValue.Key.SPD)
	var result: CampaignSession.BattleResult = session.collect_battle()
	var next: CampaignRunState = run.apply_battle(
			result, session.ids, session.reward_rolls(result), _rules, _catalog
	)
	session.end_battle()
	var after: SeatRun = next.seat_run(0)
	var xp: Array[int] = []
	for entry: Variant in after.pending_offers[CampaignRunState.COMBAT_REPORT_KEY]["xp"]:
		xp.append((entry as Dictionary).get("total") as int)
	var trained: UnitInstance = after.unit(striker)
	var trained_gains: Dictionary[int, int] = _deltas(trained)
	var weights: LevelUp.Values = result.units[striker].level_up
	var played: Dictionary = {
		"gold": after.gold - start_gold,
		"xp": xp,
		"weights": "MGT %d, %s" % [
			weights.guaranteed.get(MGT, 0), "SPD denied" if not weights.can_grow(SPD) else "",
		],
		"ore": result.units[army[0].instance_id].level_up.random_gains,
		"ore_speed": ore_speed,
		"base_speed": base_speed,
		"trained_level": trained.level,
		"trained_gains": trained_gains,
		"text": _run_text(next),
	}
	session.close()
	return played


# The seat's unit holds a new item of definition_id, in its Equipment slot or its Pouch; whatever
# was there moves to the convoy.
func _hold(
		session: CampaignSession,
		seat_run: SeatRun,
		unit: UnitInstance,
		definition_id: String,
		is_equipment: bool
) -> void:
	var item_id: String = session.ids.next_item_id(definition_id)
	seat_run.items[item_id] = ItemInstance.new(item_id, definition_id)
	var old: String = unit.equipment_id if is_equipment else unit.pouch_id
	if not old.is_empty():
		seat_run.convoy.append(old)
	if is_equipment:
		unit.equipment_id = item_id
	else:
		unit.pouch_id = item_id


func _session() -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			_map_rules,
			session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog,
			factions,
			session.ids
	)
	session.run = start.run
	return session


# A won result for the run's current node: every army unit standing at full HP, the seat's map won
# on turn 1 with no par, the seat's values at their bases.
func _won_result(
		run: CampaignRunState, combat_type: CombatMapDefinition.CombatType
) -> CampaignSession.BattleResult:
	var result: CampaignSession.BattleResult = CampaignSession.BattleResult.new()
	result.floor_number = run.floor_number
	result.node = run.node
	result.map_id = M1_ID
	result.pool_ids = PackedStringArray([M1_ID])
	result.is_finished = true
	result.is_won = true
	for unit: UnitInstance in run.seat_run(0).army:
		result.units[unit.instance_id] = _unit_outcome(UnitInstance.FULL_HP, false)
	var outcome: CampaignSession.SeatOutcome = _outcome(combat_type, false, true)
	outcome.seat = 0
	outcome.turn = 1
	result.seats[0] = outcome
	return result


func _unit_outcome(hp: int, is_fallen: bool) -> CampaignSession.UnitOutcome:
	var outcome: CampaignSession.UnitOutcome = CampaignSession.UnitOutcome.new()
	outcome.seat = 0
	outcome.hp = hp
	outcome.is_fallen = is_fallen
	return outcome


# A won map's outcome, under par or not and with or without losses, at the bases' percents.
func _outcome(
		combat_type: CombatMapDefinition.CombatType, is_under_par: bool, is_without_losses: bool
) -> CampaignSession.SeatOutcome:
	var outcome: CampaignSession.SeatOutcome = CampaignSession.SeatOutcome.new()
	outcome.is_won = true
	outcome.combat_type = combat_type
	outcome.grade_bonus_percent = 25
	outcome.shared_xp_percent = 100
	outcome.units_lost = 0 if is_without_losses else 1
	if is_under_par:
		outcome.turn_par = 5
		outcome.turn = 3
	return outcome


func _grade(
		combat_type: CombatMapDefinition.CombatType, is_under_par: bool, is_without_losses: bool
) -> CombatGrades:
	return CombatGrades.grade(_outcome(combat_type, is_under_par, is_without_losses), _rules)


func _unit(id: String, unit_type: String) -> UnitInstance:
	return UnitInstance.new(id, unit_type)


func _level(unit: UnitInstance) -> UnitInstance:
	LevelUp.level_up(unit, null, RngStream.new(1), _fixtures)
	return unit


func _level_up(unit: UnitInstance) -> LevelUp:
	return LevelUp.level_up(unit, null, RngStream.new(1), _fixtures)


# A seat whose army is one unit of unit_type.
func _seat_run(unit_type: String) -> SeatRun:
	var seat_run: SeatRun = SeatRun.new(0)
	seat_run.army.append(_unit("unit:1", unit_type))
	return seat_run


# The reward rules with every pick an Equipment pick.
func _equipment_rules() -> CombatRewardRules:
	var rules: CombatRewardRules = _rules.duplicate() as CombatRewardRules
	rules.weapon_pick_weight = 0
	rules.equipment_pick_weight = 1
	rules.pouch_pick_weight = 0
	return rules


# The unit's level-up deltas, stat to points.
func _deltas(unit: UnitInstance) -> Dictionary[int, int]:
	var gains: Dictionary[int, int] = {}
	for delta: ItemInstance.StatDelta in unit.stat_deltas:
		if delta.source_id != LevelUp.SOURCE_ID:
			continue
		var stat: Variant = CombatValue.STAT_KEYS.find_key(delta.key)
		if stat != null:
			gains[stat as int] = gains.get(stat as int, 0) + roundi(delta.amount)
	return gains


func _offered(pick: ItemPick) -> PackedStringArray:
	var ids: PackedStringArray = []
	for offer: ItemPick.Offer in pick.offers:
		ids.append(offer.definition_id)
	return ids


func _is_distinct(pick: ItemPick) -> bool:
	var seen: Dictionary[String, bool] = {}
	for offer: ItemPick.Offer in pick.offers:
		if seen.has(offer.definition_id):
			return false
		seen[offer.definition_id] = true
	return true


func _record(tally: BattleTally, unit_id: String, action: BattleTally.Action, times: int) -> void:
	var counts: Dictionary = tally.capture().get("units", {})
	var entry: Dictionary = counts.get(unit_id, {})
	for each: BattleTally.Action in BattleTally.ACTION_IDS:
		var name: String = BattleTally.ACTION_IDS[each]
		entry[name] = (entry.get(name, 0) as int) + (times if each == action else 0)
	counts[unit_id] = entry
	tally.restore({"units": counts})


# Whether count of DRAWS is near share (0 to 1).
func _near(count: int, share: float) -> bool:
	return absf(float(count) / DRAWS - share) <= TOLERANCE


# Whether count of total is near percent.
func _near_share(count: int, total: int, percent: float) -> bool:
	return total > 0 and absf(float(count) / total - percent / 100.0) <= TOLERANCE


# The real catalog with the fixture unit types added.
func _catalog_with_fixtures() -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.Index.new()
	for id: String in _catalog.ids():
		index.add(_catalog.path_of(id), _catalog.definition(id))
	_add_fixture_types(index)
	index.finish()
	return index


# Only fixture weapons and unit types: a Common sword and bow, a Rare lance, and with has_axe an
# Uncommon axe.
func _weapon_fixtures(has_axe: bool) -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.Index.new()
	var rows: Array[Array] = [
		["test_sword_c", "sword", COMMON],
		["test_bow_c", "bow", COMMON],
		["test_lance_r", "lance", RARE],
	]
	if has_axe:
		rows.append(["test_axe_u", "axe", UNCOMMON])
	for row: Array in rows:
		var weapon: WeaponDefinition = WeaponDefinition.new()
		weapon.id = row[0]
		weapon.display_name = row[0]
		weapon.weapon_type = row[1]
		weapon.rarity = row[2]
		index.add("res://tests/campaign/%s.tres" % [row[0]], weapon)
	_add_fixture_types(index)
	index.finish()
	return index


func _add_fixture_types(index: EffectCatalog.Index) -> void:
	var growths: Dictionary[CombatValue.Stat, int] = {}
	for stat: CombatValue.Stat in LevelUp.GROWTH_STATS:
		growths[stat] = 100
	var rows: Array[Array] = [
		[STILL, {}, PackedStringArray()],
		[GROWER, growths, PackedStringArray()],
		[SWORDSMAN, {}, PackedStringArray(["sword"])],
	]
	for row: Array in rows:
		var unit_type: UnitTypeDefinition = UnitTypeDefinition.new()
		unit_type.id = row[0]
		unit_type.display_name = row[0]
		unit_type.growths.assign(row[1] as Dictionary)
		unit_type.weapon_types = row[2]
		index.add("res://tests/campaign/%s.tres" % [row[0]], unit_type)


static func _run_text(run: CampaignRunState) -> String:
	var parts: Array = [run.capture_map(), run.flow.capture()]
	for seat: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat)
		parts.append_array([seat_run.capture_roster(), seat_run.capture_economy()])
	return JSON.stringify(parts)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
