# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_content_cases.gd
# Author:
# Created:  November 14, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The heirloom and curse cases for tests/content/run_all.gd, over the real
## [code]res://data/[/code]: each heirloom's tier, kind, scope, unique tag and co-op mark and each
## curse's tier against heirlooms.md and events.md, each folder holding exactly the listed files,
## effect text snapshots, a battle case for every combat-side effect (loaded through [Loadout] as
## an army's carriers, the way a campaign registers them), how copies stack, and golden fact logs
## for a profile, a behavior, an economy and army value, and a curse; Tactician's Manual doubling
## your units' triangle both ways (Hit and damage, through the forecast) and leaving enemies'
## alone. Reports each case through the check callable it is given.
##
## The expected values are transcribed from the design docs, never read from the data, so a
## changed .tres fails here until the doc and this file agree.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "content"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const SHOVE: UnitTurnCommand.Action = UnitTurnCommand.Action.SHOVE

const HEIRLOOM_DIR: String = "res://data/heirlooms/"
const CURSE_DIR: String = "res://data/curses/"

# The Commander Heirloom already in heirlooms/, outside the pool (CT13's Drengr).
const COMMANDER_HEIRLOOMS: PackedStringArray = ["iron_heart"]

# The seven starting heirlooms in heirlooms/, outside the pool (heirlooms.md, Starting heirlooms).
const STARTING_HEIRLOOMS: PackedStringArray = [
	"abundance", "ancestral_weapon", "family_relic", "mercenary_contract", "tacticians_manual",
	"veteran_company", "war_chest",
]

# Any fixed seed; the cases that need a hit force it with _sure_hit().
const SEED: int = 0xC7_0009

# A Hakkapel's 36 HP, Simple Lance (7 damage, weight 12) and 2 Stance (unit-roster.md).
const HAKKAPEL_HP: int = 36
const LANCE_WEIGHT: int = 12

# A locked chest on the first object spot, as in item_content_cases.gd.
const CHEST_TILE: Vector2i = Vector2i(1, 0)
const CHEST_ID: String = "object:0"

# heirlooms.md's four tables. Columns: tier, kind (empty for Shop), co-op only.
const HEIRLOOMS: Dictionary[String, Array] = {
	"grandfathers_whetstone": ["common", "profile", false],
	"dueling_manual": ["common", "profile", false],
	"drillmasters_baton": ["common", "profile", false],
	"fletchers_kit": ["common", "profile", false],
	"hammerhead_charm": ["common", "behavior", false],
	"horsebane_charm": ["common", "behavior", false],
	"bloodied_banner": ["common", "behavior", false],
	"iron_rations": ["common", "behavior", false],
	"hunters_horn": ["common", "behavior", false],
	"shoving_pole": ["common", "behavior", false],
	"sappers_fuse": ["common", "behavior", false],
	"lantern_oil": ["common", "behavior", false],
	"bounty_ledger": ["common", "economy", false],
	"scrappers_tongs": ["common", "economy", false],
	"executioners_brand": ["uncommon", "behavior", false],
	"breakers_maul": ["uncommon", "behavior", false],
	"war_ledger": ["uncommon", "behavior", false],
	"overflowing_cup": ["uncommon", "behavior", false],
	"tactical_map": ["uncommon", "behavior", false],
	"grave_candle": ["uncommon", "behavior", false],
	"warlords_spoils": ["uncommon", "behavior", false],
	"burglars_roll": ["uncommon", "economy", false],
	"veterans_medal": ["uncommon", "economy", false],
	"brothers_in_arms": ["uncommon", "behavior", true],
	"muster_roll": ["rare", "army", false],
	"warhorse_lineage": ["rare", "behavior", false],
	"ancestral_mail": ["rare", "behavior", false],
	"bloodhounds_collar": ["rare", "behavior", false],
	"champions_belt": ["rare", "behavior", false],
	"commanders_standard": ["rare", "behavior", false],
	"gilded_purse": ["rare", "economy", false],
	"merchants_ledger": ["shop", "", false],
	"guild_charter": ["shop", "", false],
	"membership_seal": ["shop", "", false],
	"tinkers_token": ["shop", "", false],
}

# heirlooms.md's tier sizes: Common (14), Uncommon (10), Rare (7), Shop (4).
const TIER_SIZES: Dictionary[String, int] = {"common": 14, "uncommon": 10, "rare": 7, "shop": 4}

# events.md's Curses table: tier.
const CURSES: Dictionary[String, String] = {
	"haunted": "minor",
	"short_wick": "minor",
	"shaken_footing": "minor",
	"heavy_pack": "minor",
	"leaden_boots": "major",
	"brittle_guard": "major",
	"clouded_sight": "major",
	"ill_omen": "major",
	"hunted": "severe",
	"cursed_blood": "severe",
}

# Reviewed effect text, one line per effect.
const TEXT: Dictionary[String, Array] = {
	# "+2 damage" is +2 at the Attack stage; the profile is the held weapon's.
	"grandfathers_whetstone": ["While holding a Power weapon, +2 Attack."],
	"dueling_manual": ["While holding a Nimble weapon, +2 Attack Speed."],
	"drillmasters_baton": ["While holding a Balance weapon, +1 Attack and +1 DEF."],
	"fletchers_kit": ["While at range 2 or more, +1 Attack."],
	"hammerhead_charm": ["Against Armored units, +3 Attack."],
	"horsebane_charm": ["Against Mounted units, +3 Attack."],
	"bloodied_banner": [
		"Whenever one of your units defeats an enemy, give that unit +3 Attack on its next attack"
		+ " this combat.",
	],
	"iron_rations": ["At the first Phase Start each combat, give your units 3 Block."],
	# +5 Hit for that exchange only.
	"hunters_horn": [
		"Whenever one of your units enters an exchange, while it is the initiator, give that unit"
		+ " +5 Hit this exchange.",
	],
	"shoving_pole": ["Whenever one of your units shoves a unit, give that unit 2 Block."],
	"sappers_fuse": ["Whenever one of your units uses an object, give that unit 3 Block."],
	"lantern_oil": [
		"Whenever one of your units takes darkness damage, ×0.5 to that darkness damage.",
	],
	"bounty_ledger": ["+8 Gold per won combat."],
	# Percents add points to their base: 20 + 20 is the 40% scrap rate.
	"scrappers_tongs": ["+20% of the price when scrapping."],
	"executioners_brand": ["While the opponent is Exposed, +3 Attack."],
	"breakers_maul": [
		"Every 5th time one of your units lands a hit each combat, the target loses 1 extra"
		+ " Stance.",
	],
	"war_ledger": [
		"Every 10th time one of your units attacks this run, ×2 damage for that attack.",
	],
	"overflowing_cup": [
		"Whenever one of your units is healed, give that unit Block equal to 100% of that"
		+ " overheal.",
	],
	"tactical_map": [
		"At the first Phase Start each combat, give your units +1 Movement until Phase End.",
	],
	# The defeated unit is off the map when the Block is given, so "every other one" holds.
	"grave_candle": ["Whenever one of your units is defeated, give your units 4 Block."],
	"warlords_spoils": ["Whenever one of your units defeats an enemy, heal that unit for 3 HP."],
	# An opener with no operations, like the Key, so its text is written: MapObjects reads its
	# charge.
	"burglars_roll": [
		"Once per combat, one of your units can open a chest or door without a Key or Lockpick"
		+ " (still its action).",
	],
	"veterans_medal": ["+20% shared XP."],
	"brothers_in_arms": [
		"At each allied Phase Start, give every ally adjacent to a unit of another player 2 Block.",
	],
	# The ceiling of 8 is the recruiting step's rule, not this value's.
	"muster_roll": ["+1 max army size."],
	"warhorse_lineage": ["+1 Movement."],
	"ancestral_mail": ["+1 max Stance."],
	"bloodhounds_collar": [
		"Whenever one of your units defeats an enemy, that unit may move after acting until Phase"
		+ " End.",
	],
	"champions_belt": [
		"Whenever one of your units defeats an enemy, give that unit +1 Attack this combat.",
	],
	# The commander counts: it is 0 tiles from itself.
	"commanders_standard": [
		"At Phase Start, give your commander and allies within 2 tiles of your commander 2 Block.",
	],
	"gilded_purse": ["+25% grade bonus."],
	"merchants_ledger": ["+1 Armory item."],
	"guild_charter": ["+1 Guildhall recruit."],
	"membership_seal": ["-20% shop prices."],
	"tinkers_token": ["+1 free reroll."],
	# Resolves first, so the ban is in place before Phase Start's Block gains.
	"haunted": [
		"At Phase Start, a random one of your units can't gain Block until the end of the next"
		+ " phase.",
	],
	"short_wick": ["-1 turn before the darkness arrives."],
	# A Stance loss at the army's first Phase Start, so it lasts until its next refresh.
	"shaken_footing": ["At the first Phase Start each combat, remove 1 Stance from your units."],
	"heavy_pack": ["+2 weight per Pouch item."],
	"leaden_boots": ["-1 SPD."],
	"brittle_guard": ["Whenever one of your units gains Block, -1 to that Block gain."],
	"clouded_sight": ["Enemy intents are hidden."],
	"ill_omen": ["While it is the commander, -1 max Stance."],
	"hunted": ["+1 enemy per combat."],
	# It multiplies, so two copies leave a quarter.
	"cursed_blood": ["×0.5 healing received."],
}

# Reviewed golden fact logs, one CombatFact.to_log_line() per fact, keyed by the name _golden()
# is given. A scenario missing here expects no facts.
const GOLDEN: Dictionary[String, Array] = {
	# A Fighter (Simple Axe, Power) hits a Lancer for 18, the whetstone's +2 included (the
	# forecast case isolates it); the Lancer counters.
	"Grandfather's Whetstone": [
		"s0#6 BEFORE_COMBAT unit:2 -> enemy:5",
		"s0#7 BEFORE_COMBAT enemy:5 -> unit:2",
		"s0#8 ATTACK_MADE unit:2 -> enemy:5",
		"s0#9 HIT_DEALT unit:2 -> enemy:5 amount 18 type physical",
		"s0#10 HIT_TAKEN enemy:5 <- unit:2 amount 18 type physical",
		"s0#11 DAMAGE_DEALT unit:2 -> enemy:5 amount 18 (hp 18, block 0) source attack"
		+ " type physical",
		"s0#12 DAMAGE_TAKEN enemy:5 <- unit:2 amount 18 (hp 18, block 0) source attack"
		+ " type physical",
		"s0#13 STANCE_CHANGED enemy:5 -> unit:2 amount -1",
		"s0#14 ATTACK_MADE enemy:5 -> unit:2",
		"s0#15 HIT_DEALT enemy:5 -> unit:2 amount 5 type physical",
		"s0#16 HIT_TAKEN unit:2 <- enemy:5 amount 5 type physical",
		"s0#17 DAMAGE_DEALT enemy:5 -> unit:2 amount 5 (hp 5, block 0) source attack"
		+ " type physical",
		"s0#18 DAMAGE_TAKEN unit:2 <- enemy:5 amount 5 (hp 5, block 0) source attack"
		+ " type physical",
		"s0#19 STANCE_CHANGED unit:2 -> enemy:5 amount -1",
		"s0#20 AFTER_COMBAT unit:2 -> enemy:5",
		"s0#21 AFTER_COMBAT enemy:5 -> unit:2",
	],
	# The kill fires the army's effect; its timed +3 lands after the exchange, as a queued
	# reaction.
	"Bloodied Banner (the kill)": [
		"s0#8 BEFORE_COMBAT unit:2 -> enemy:5",
		"s0#9 BEFORE_COMBAT enemy:5 -> unit:2",
		"s0#10 ATTACK_MADE unit:2 -> enemy:5",
		"s0#11 HIT_DEALT unit:2 -> enemy:5 amount 7 type physical",
		"s0#12 HIT_TAKEN enemy:5 <- unit:2 amount 7 type physical",
		"s0#13 DAMAGE_DEALT unit:2 -> enemy:5 amount 1 (hp 1, block 0) source attack"
		+ " type physical",
		"s0#14 DAMAGE_TAKEN enemy:5 <- unit:2 amount 1 (hp 1, block 0) source attack"
		+ " type physical",
		"s0#15 DEFEATED enemy:5 <- unit:2",
		"s0#16 DEFEATED_AN_ENEMY unit:2 -> enemy:5",
		"s0#17 EFFECT_ACTIVATED seat:0 effect effect:1",
		"s0#18 AFTER_COMBAT unit:2 -> enemy:5",
		"s0#19 MODIFIER_GAINED unit:2 effect effect:1",
	],
	# The curse (effect:1) resolves first, ahead of Iron Rations (effect:2): its pick, the Lancer,
	# gets neither Iron Rations' Block nor its own Unit Turn Start Block (effect:8), and neither
	# banned gain is recorded.
	"Haunted with Iron Rations": [
		"s0#6 PHASE_START side player amount 1",
		"s0#7 EFFECT_ACTIVATED seat:0 effect effect:1",
		"s0#8 COUNTER_CHANGED seat:0 lane 0 amount 1 effect effect:2",
		"s0#9 EFFECT_ACTIVATED seat:0 effect effect:2",
		"s0#10 UNIT_TURN_START unit:3 tile (0, 0)",
		"s0#11 UNIT_TURN_START unit:6 tile (1, 0)",
		"s0#12 EFFECT_ACTIVATED unit:6 effect effect:8",
		"s0#13 MODIFIER_GAINED unit:6 effect effect:1",
		"s0#14 BLOCK_GAINED unit:3 amount 3 (hp 0, block 3) source effect effect effect:2",
	],
	# Economy and army heirlooms produce no facts: their golden output is the seat's breakdown.
	"Bounty Ledger and Muster Roll": [
		"0 base +8 Bounty Ledger = 8",
		"0 base +1 Muster Roll = 1",
	],
}

# Each seat value heirloom and curse, its key, and the value with one copy and with two: flat
# values add, percents add points to their base, Cursed Blood multiplies (CT9's stacking rule).
const SEAT_VALUES: Array[Array] = [
	["bounty_ledger", CampaignValue.Key.COMBAT_GOLD, 8, 16],
	["scrappers_tongs", CampaignValue.Key.SCRAP_PERCENT, 40, 60],
	["veterans_medal", CampaignValue.Key.SHARED_XP_PERCENT, 120, 140],
	["gilded_purse", CampaignValue.Key.GRADE_BONUS_PERCENT, 50, 75],
	["muster_roll", CampaignValue.Key.MAX_ARMY_SIZE, 1, 2],
	["merchants_ledger", CampaignValue.Key.ARMORY_STOCK, 1, 2],
	["guild_charter", CampaignValue.Key.GUILDHALL_RECRUITS, 1, 2],
	["membership_seal", CampaignValue.Key.PRICE_PERCENT, 80, 60],
	["tinkers_token", CampaignValue.Key.FREE_REROLLS, 1, 2],
	["short_wick", CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET, -1, -2],
	["heavy_pack", CampaignValue.Key.POUCH_ITEM_WEIGHT, 2, 4],
	["hunted", CampaignValue.Key.EXTRA_ENEMIES, 1, 2],
	["cursed_blood", CampaignValue.Key.HEALING_RECEIVED_PERCENT, 50, 25],
]

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_test_pool()
	_test_curses()
	_test_folders()
	_test_text_snapshots()
	_test_profiles()
	_test_fletchers_kit()
	_test_charms()
	_test_bloodied_banner()
	_test_iron_rations_and_brittle_guard()
	_test_hunters_horn()
	_test_shoving_pole()
	_test_sappers_fuse_and_burglars_roll()
	_test_lantern_oil()
	_test_executioners_brand()
	_test_breakers_maul()
	_test_war_ledger()
	_test_overflowing_cup_and_cursed_blood()
	_test_tactical_map()
	_test_grave_candle()
	_test_warlords_spoils()
	_test_brothers_in_arms()
	_test_always_on()
	_test_bloodhounds_collar()
	_test_champions_belt()
	_test_commander_and_pouch()
	_test_haunted()
	_test_shaken_footing()
	_test_seat_values()
	_test_tacticians_manual()
	_test_value_readers()


# Each pool heirloom's tier, kind and co-op mark; every effect scoped Your Unit or wider, and
# tagged unique exactly when it reaches other players' units; each tier the size heirlooms.md says.
func _test_pool() -> void:
	var sizes: Dictionary[String, int] = {}
	for heirloom_id: String in HEIRLOOMS:
		var heirloom: HeirloomDefinition = _catalog.heirloom(heirloom_id)
		if heirloom == null or heirloom is CurseDefinition:
			_ok("%s: an heirloom in the catalog" % [heirloom_id], false)
			continue
		var row: Array = HEIRLOOMS[heirloom_id]
		_same("%s: heirlooms.md's tier, kind and co-op mark" % [heirloom_id], str([
			heirloom.tier, heirloom.kind, heirloom.is_coop_only,
		]), str(row))
		sizes[heirloom.tier] = sizes.get(heirloom.tier, 0) + 1
		var problems: PackedStringArray = []
		for effect: EffectDefinition in heirloom.effects:
			var reaches_others: bool = effect.scope >= EffectTerms.Scope.ANY_ALLY_UNIT
			if effect.scope == EffectTerms.Scope.THIS_UNIT:
				problems.append("%s is scoped This unit" % [effect.id])
			if reaches_others != effect.has_tag(EffectDefinition.Tag.UNIQUE):
				problems.append("%s: unique tag %s" % [effect.id, not reaches_others])
			if effect.has_tag(EffectDefinition.Tag.CURSE):
				problems.append("%s is tagged a curse" % [effect.id])
		_ok("%s: Your Unit or wider, unique when it reaches others" % [heirloom_id], (
				not heirloom.effects.is_empty() and problems.is_empty()
		), str(problems))
	_same("pool: tier sizes", str(sizes), str(TIER_SIZES))


# Each curse's tier, no kind, never sold, every effect tagged a curse and scoped Your Unit; four
# Minor, four Major and two Severe (events.md).
func _test_curses() -> void:
	var sizes: Dictionary[String, int] = {}
	for curse_id: String in CURSES:
		var curse: CurseDefinition = _catalog.curse(curse_id)
		if curse == null:
			_ok("%s: a curse in the catalog" % [curse_id], false)
			continue
		sizes[curse.tier] = sizes.get(curse.tier, 0) + 1
		var tagged: bool = not curse.effects.is_empty()
		for effect: EffectDefinition in curse.effects:
			tagged = (
					tagged
					and effect.has_tag(EffectDefinition.Tag.CURSE)
					and not effect.has_tag(EffectDefinition.Tag.UNIQUE)
					and effect.scope == EffectTerms.Scope.YOUR_UNIT
			)
		_ok("%s: events.md's tier, no kind, unpriced, curse-tagged Your Unit effects" % [
			curse_id,
		], (
				curse.tier == CURSES[curse_id]
				and curse.kind.is_empty()
				and not curse.is_coop_only
				and Prices.heirloom_price(curse.tier) == Prices.NO_PRICE
				and tagged
		))
	_same("curses: tier sizes", str(sizes), str({"minor": 4, "major": 4, "severe": 2}))


# Every file in the two folders is listed, so none goes untested.
func _test_folders() -> void:
	var listed: Dictionary[String, PackedStringArray] = {
		HEIRLOOM_DIR: (
				PackedStringArray(HEIRLOOMS.keys()) + COMMANDER_HEIRLOOMS + STARTING_HEIRLOOMS
		),
		CURSE_DIR: PackedStringArray(CURSES.keys()),
	}
	for folder: String in listed:
		var found: PackedStringArray = []
		for file: String in DirAccess.get_files_at(folder):
			if file.get_extension() == "tres":
				found.append(file.get_basename())
		found.sort()
		var expected: PackedStringArray = listed[folder]
		expected.sort()
		_same("%s: holds exactly the listed files" % [folder], ", ".join(found), (
				", ".join(expected)
		))


# Generated text is canonical (content catalog plan, Approach); these are its reviewed snapshots.
func _test_text_snapshots() -> void:
	var ids: PackedStringArray = PackedStringArray(HEIRLOOMS.keys()) + PackedStringArray(
			CURSES.keys()
	)
	for heirloom_id: String in ids:
		var heirloom: HeirloomDefinition = _catalog.heirloom(heirloom_id)
		if heirloom == null:
			_ok("text %s: in the catalog" % [heirloom_id], false)
			continue
		var expected: PackedStringArray = PackedStringArray(TEXT.get(heirloom_id, []) as Array)
		_same("text %s" % [heirloom_id], " | ".join(heirloom.describe()), " | ".join(expected))


# Each profile heirloom on a Fighter (Simple Axe, Power), a Sellsword (Simple Sword, Nimble), a
# Lancer (Simple Lance, Balance) and an Archer (Simple Bow, no profile): the change to Attack,
# Attack Speed and DEF against the same unit without it, so only the matching profile gains.
func _test_profiles() -> void:
	var units: PackedStringArray = ["fighter", "sellsword", "lancer", "archer"]
	var keys: Array[int] = [
		DamageStage.Key.ATTACK, CombatValue.Key.ATTACK_SPEED, CombatValue.Key.DEF,
	]
	var bare: Dictionary[String, Array] = {}
	var session: CombatSession = _session()
	for index: int in units.size():
		var unit_id: String = _place(session, units[index], PLAYER, 0, Vector2i(index, 0))
		bare[units[index]] = _values(session, unit_id, keys)
	var rows: Dictionary[String, String] = {
		"grandfathers_whetstone": "fighter +2 +0 +0, sellsword +0 +0 +0, lancer +0 +0 +0,"
				+ " archer +0 +0 +0",
		"dueling_manual": "fighter +0 +0 +0, sellsword +0 +2 +0, lancer +0 +0 +0, archer +0 +0 +0",
		"drillmasters_baton": "fighter +0 +0 +0, sellsword +0 +0 +0, lancer +1 +0 +1,"
				+ " archer +0 +0 +0",
	}
	for heirloom_id: String in rows:
		var owned: CombatSession = _session()
		_own(owned, heirloom_id)
		var changes: PackedStringArray = []
		for index: int in units.size():
			var unit_id: String = _place(owned, units[index], PLAYER, 0, Vector2i(index, 0))
			var values: Array = _values(owned, unit_id, keys)
			var deltas: PackedStringArray = []
			for key_index: int in keys.size():
				deltas.append("%+d" % [values[key_index] - bare[units[index]][key_index]])
			changes.append("%s %s" % [units[index], " ".join(deltas)])
		_same("%s: Attack, Attack Speed, DEF by profile" % [heirloom_id], ", ".join(changes), (
				rows[heirloom_id]
		))
	# The profile is read live from the Weapon slot: a Fighter's whetstone damage in a real
	# exchange, through the forecast.
	var dealt: PackedStringArray = []
	for heirloom_id: String in ["", "grandfathers_whetstone"]:
		dealt.append(str(_forecast_damage(heirloom_id, "fighter", "lancer", 1)))
	_same("grandfathers_whetstone: a Fighter's forecast damage, without and with", (
			" ".join(dealt)
	), "%d %d" % [dealt[0].to_int(), dealt[0].to_int() + 2])
	_golden_whetstone()


# An Archer at range 2 gains 1 damage; a Hakkapel at range 1 gains nothing (as the Simple Quiver).
func _test_fletchers_kit() -> void:
	var rows: PackedStringArray = []
	for row: Array in [["archer", 2], ["hakkapel", 1]]:
		var type_id: String = row[0]
		var distance: int = row[1]
		var plain: int = _forecast_damage("", type_id, type_id, distance)
		var kit: int = _forecast_damage("fletchers_kit", type_id, type_id, distance)
		rows.append("%s at %d %+d" % [type_id, distance, kit - plain])
	_same("fletchers_kit: damage gained by range", ", ".join(rows), (
			"archer at 2 +1, hakkapel at 1 +0"
	))


# A Hakkapel's damage against a Lance Armor (Armored), a Hakkapel (Mounted) and a Lancer (neither).
func _test_charms() -> void:
	var expected: Dictionary[String, String] = {
		"hammerhead_charm": "+3 +0 +0",
		"horsebane_charm": "+0 +3 +0",
	}
	for charm: String in expected:
		var gains: PackedStringArray = []
		for target: String in ["lance_armor", "hakkapel", "lancer"]:
			var plain: int = _forecast_damage("", "hakkapel", target, 1)
			gains.append("%+d" % [_forecast_damage(charm, "hakkapel", target, 1) - plain])
		_same("%s: against Armored, Mounted, neither" % [charm], " ".join(gains), expected[charm])


# A kill gives the killer +3 damage on its next attack this combat, spent by that attack. The
# second and third attacks are a test shortcut: the unit's action is refreshed, never a rule.
func _test_bloodied_banner() -> void:
	var session: CombatSession = _session()
	_own(session, "bloodied_banner")
	var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(1, 0))
	var first: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(0, 0))
	var second: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(2, 0))
	var third: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 1))
	if who.is_empty() or first.is_empty() or session.open_battle().is_rejected():
		_ok("bloodied banner: the battle loads", false)
		return
	_sure_hit(session, who)
	var before: int = _damage(session, who, second)
	session.state.set_hp(first, 1)
	var start: int = session.engine.fact_log.size()
	var kill: CombatSession.FactBatch = _attack(session, who, first)
	_golden("Bloodied Banner (the kill)", session.engine, start)
	var after_kill: int = _damage(session, who, second)
	session.state.set_hp(second, 99)
	_attack(session, who, second)
	_same("bloodied banner: next attack +3, then spent", "%s %+d %+d" % [
		kill.rejected_reason if kill.is_rejected() else "killed",
		after_kill - before,
		_damage(session, who, third) - before,
	], "killed +3 +0")


# First Phase Start this combat: each of Your Units gains 3 Block, once (the next player Phase
# Start adds none). Brittle Guard takes 1 from each gain; two copies take 2.
func _test_iron_rations_and_brittle_guard() -> void:
	var rows: PackedStringArray = []
	for guards: int in 3:
		var session: CombatSession = _session()
		_own(session, "iron_rations")
		_own(session, "brittle_guard", 0, guards)
		var units: PackedStringArray = [
			_place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0)),
			_place(session, "hakkapel", PLAYER, 0, Vector2i(3, 0)),
		]
		_place(session, "hakkapel", ENEMY, -1, Vector2i(8, 0))
		session.open_battle()
		var blocks: PackedStringArray = []
		for unit_id: String in units:
			blocks.append(str(session.state.get_block(unit_id)))
		rows.append("%d guards: %s" % [guards, " ".join(blocks)])
		if guards > 0:
			continue
		session.submit(EndTurnCommand.new(0))
		session.resolve_next()
		var phase_starts: int = 0
		var gains: int = 0
		for fact: CombatFact in session.engine.fact_log:
			if fact.kind == CombatFact.Kind.PHASE_START and fact.side == PLAYER:
				phase_starts += 1
			elif fact.kind == CombatFact.Kind.BLOCK_GAINED and fact.amount == 3:
				gains += 1
		_same("iron rations: two player Phase Starts, one gain per unit", "%d %d" % [
			phase_starts, gains,
		], "2 2")
	_same("iron rations: Block with 0, 1 and 2 Brittle Guards", " | ".join(rows), (
			"0 guards: 3 3 | 1 guards: 2 2 | 2 guards: 1 1"
	))


# +5 Hit for the exchange Your Unit starts; the enemy it attacks gains nothing.
func _test_hunters_horn() -> void:
	var hits: PackedStringArray = []
	for heirloom_id: String in ["", "hunters_horn"]:
		var session: CombatSession = _session()
		_own(session, heirloom_id)
		var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
		var foe: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 0))
		session.open_battle()
		var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
				session.engine, UnitTurnCommand.new(0, who, ATTACK, foe)
		)
		hits.append("%d/%d" % [forecast.attacker.hit, forecast.defender.hit])
	var plain: PackedStringArray = hits[0].split("/")
	_same("hunters_horn: initiator and defender Hit, without and with", " ".join(hits), (
			"%s %d/%s" % [hits[0], plain[0].to_int() + 5, plain[1]]
	))


# The shover gains 2 Block; the unit shoved gains none.
func _test_shoving_pole() -> void:
	var session: CombatSession = _session()
	_own(session, "shoving_pole")
	var shover: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var pushed: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 0))
	session.open_battle()
	session.state.set_stance(pushed, 0)
	session.submit(UnitTurnCommand.new(0, shover, SHOVE, pushed))
	var shove: CombatSession.FactBatch = session.resolve_next()
	_same("shoving_pole: the shover's and the pushed unit's Block", "%s %d %d" % [
		shove.rejected_reason if shove.is_rejected() else "shoved",
		session.state.get_block(shover),
		session.state.get_block(pushed),
	], "shoved 2 0")


# A Hakkapel on a locked chest with nothing in its Pouch: refused without Burglar's Roll; with one
# copy it opens once per combat (still its action; Sapper's Fuse then gives 3 Block), and a mirror
# spends the same charge; two copies open twice.
func _test_sappers_fuse_and_burglars_roll() -> void:
	var refused: CombatSession = _chest_session()
	var plain: String = _place(refused, "hakkapel", PLAYER, 0, CHEST_TILE)
	refused.open_battle()
	_same("burglars_roll: without it, a lock needs an item", MapObjects.check_use(
			refused.engine, refused.state, plain, CHEST_ID
	), "needs a key or a lockpick")

	var host: CombatSession = _chest_session()
	var mirror: CombatSession = _chest_session()
	var who: String = ""
	for session: CombatSession in [host, mirror]:
		_own(session, "burglars_roll")
		_own(session, "sappers_fuse")
		who = _place(session, "hakkapel", PLAYER, 0, CHEST_TILE)
		session.open_battle()
	var opened: CombatSession.FactBatch = _open_chest(host, who)
	_same("burglars_roll: opens it as its action; Sapper's Fuse gives 3 Block", "%s %s %s %d" % [
		opened.rejected_reason if opened.is_rejected() else "opened",
		host.state.map.object(CHEST_ID).is_used,
		host.state.unit(who).has_acted,
		host.state.get_block(who),
	], "opened true true 3")
	mirror.apply_batch(opened)
	_same("burglars_roll: spent once this combat, on the host and its mirror", "%s %s %s" % [
		_open_chest(host, who).rejected_reason,
		_burglar_charges(host),
		_burglar_charges(mirror),
	], "needs a key or a lockpick 0 0")

	var doubled: CombatSession = _chest_session()
	_own(doubled, "burglars_roll", 0, 2)
	var thief: String = _place(doubled, "hakkapel", PLAYER, 0, CHEST_TILE)
	doubled.open_battle()
	var results: PackedStringArray = []
	for _attempt: int in 3:
		var batch: CombatSession.FactBatch = _open_chest(doubled, thief)
		results.append(batch.rejected_reason if batch.is_rejected() else "opened")
	_same("burglars_roll: two copies open twice", ", ".join(results), (
			"opened, opened, needs a key or a lockpick"
	))


# Darkness damage at Gloom on a Hakkapel: 25% of its HP, rounded down; Lantern Oil halves it
# before rounding, so 12.5%, rounded down. The HP is read from the unit's stats, so tuning the
# Hakkapel's HP leaves this case alone.
func _test_lantern_oil() -> void:
	var taken: PackedStringArray = []
	var full_hp: int = 0
	for heirloom_id: String in ["", "lantern_oil"]:
		var session: CombatSession = _session()
		_own(session, heirloom_id)
		var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
		full_hp = session.stats(who).get_int(CombatValue.Key.HP)
		session.state.map.darkness.layers[Vector2i(0, 0)] = WhileLayerCondition.Layer.GLOOM
		taken.append(str(Darkness.damage_at(session.engine, who, Vector2i(0, 0))))
	_same("lantern_oil: Gloom damage without and with", " ".join(taken), "%d %d" % [
		floori(full_hp * 0.25), floori(full_hp * 0.125),
	])


# +3 damage against an Exposed target only.
func _test_executioners_brand() -> void:
	var gains: PackedStringArray = []
	for stance: int in [2, 0]:
		var dealt: Array[int] = []
		for heirloom_id: String in ["", "executioners_brand"]:
			var session: CombatSession = _session()
			_own(session, heirloom_id)
			var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
			var foe: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 0))
			session.open_battle()
			session.state.set_stance(foe, stance)
			dealt.append(_damage(session, who, foe))
		gains.append("stance %d %+d" % [stance, dealt[1] - dealt[0]])
	_same("executioners_brand: damage gained by the target's Stance", ", ".join(gains), (
			"stance 2 +0, stance 0 +3"
	))


# Every 5th hit Your Unit deals this combat takes 1 extra Stance. The defender's Stance, HP and
# both units' action are reset between exchanges: a test shortcut, never a rule.
func _test_breakers_maul() -> void:
	var session: CombatSession = _session()
	_own(session, "breakers_maul")
	var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var foe: String = _place(session, "lance_armor", ENEMY, -1, Vector2i(1, 0))
	session.open_battle()
	_sure_hit(session, who)
	var losses: PackedStringArray = []
	var exchanges: int = 0
	while losses.size() < 6 and exchanges < 12:
		exchanges += 1
		session.state.set_stance(foe, 9)
		session.state.set_stance(who, 9)
		session.state.set_hp(foe, 99)
		session.state.set_hp(who, HAKKAPEL_HP)
		var batch: CombatSession.FactBatch = _attack(session, who, foe)
		if batch.is_rejected():
			losses.append(batch.rejected_reason)
		var last_hit_by_us: bool = false
		for fact: CombatFact in batch.facts:
			if fact.kind == CombatFact.Kind.HIT_DEALT:
				last_hit_by_us = fact.actor_id == who
			elif fact.kind == CombatFact.Kind.STANCE_CHANGED and fact.actor_id == foe:
				if last_hit_by_us:
					losses.append(str(fact.amount))
	_same("breakers_maul: Stance lost to each of Your Unit's hits", " ".join(losses.slice(0, 6)), (
			"-1 -1 -1 -1 -2 -1"
	))


# Every 10th attack this campaign deals double damage: with the campaign counter at 9 the next
# attack is the 10th.
func _test_war_ledger() -> void:
	var dealt: PackedStringArray = []
	for count: int in [0, 9]:
		var session: CombatSession = _session()
		var ledger: Array[EffectInstance] = _own(session, "war_ledger")
		ledger[0].set_counter(EffectTerms.Lane.CAMPAIGN, count)
		var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
		var foe: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 0))
		session.open_battle()
		dealt.append(str(_damage(session, who, foe)))
	_same("war_ledger: damage at counts 0 and 9", " ".join(dealt), "%s %d" % [
		dealt[0], dealt[0].to_int() * 2,
	])


# A Potion (8) on a Hakkapel 2 HP below full restores 2: Overflowing Cup turns the other 6 into
# Block. Cursed Blood halves a Potion on a Hakkapel at 10 HP to 4; two copies quarter it to 2. Full
# HP is read from the unit's stats, so tuning the Hakkapel's HP leaves this case alone.
func _test_overflowing_cup_and_cursed_blood() -> void:
	var cup: CombatSession = _session()
	_own(cup, "overflowing_cup")
	var drinker: String = _place(cup, "hakkapel", PLAYER, 0, Vector2i(0, 0), "", "potion")
	cup.open_battle()
	var full_hp: int = cup.stats(drinker).get_int(CombatValue.Key.HP)
	cup.state.set_hp(drinker, full_hp - 2)
	_drink(cup, drinker)
	_same("overflowing_cup: HP and Block after an 8 heal 2 below full", "%d %d" % [
		cup.state.get_hp(drinker), cup.state.get_block(drinker),
	], "%d 6" % [full_hp])

	var healed: PackedStringArray = []
	for curses: int in 3:
		var session: CombatSession = _session()
		_own(session, "cursed_blood", 0, curses)
		var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0), "", "potion")
		session.open_battle()
		session.state.set_hp(who, 10)
		_drink(session, who)
		healed.append(str(session.state.get_hp(who) - 10))
	_same("cursed_blood: a Potion's heal with 0, 1 and 2 copies", " ".join(healed), "8 4 2")


# First Phase Start this combat: Your Units gain +1 Movement until Phase End.
func _test_tactical_map() -> void:
	var bare: CombatSession = _session()
	var plain: String = _place(bare, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var base: int = bare.engine.stats(plain).get_int(CombatValue.Key.MOVEMENT)
	var session: CombatSession = _session()
	_own(session, "tactical_map")
	var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	_place(session, "hakkapel", ENEMY, -1, Vector2i(8, 0))
	session.open_battle()
	var during: int = session.engine.stats(who).get_int(CombatValue.Key.MOVEMENT)
	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	var later: int = session.engine.stats(who).get_int(CombatValue.Key.MOVEMENT)
	_same("tactical_map: Movement on turn 1, then on turn 2", "%+d %+d" % [
		during - base, later - base,
	], "+1 +0")


# A Hakkapel at 1 HP falls to the enemy's counter: the other one of Your Units gains 4 Block.
func _test_grave_candle() -> void:
	var session: CombatSession = _session()
	_own(session, "grave_candle")
	var falls: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var mourns: String = _place(session, "lancer", PLAYER, 0, Vector2i(4, 0))
	var foe: String = _place(session, "lance_armor", ENEMY, -1, Vector2i(1, 0))
	session.open_battle()
	session.state.set_hp(falls, 1)
	session.state.set_hp(foe, 99)
	_sure_hit(session, foe)
	_attack(session, falls, foe)
	_same("grave_candle: the fallen unit is gone, the other gains 4 Block", "%s %d" % [
		session.state.has_unit(falls), session.state.get_block(mourns),
	], "false 4")


# The killer heals 3 HP.
func _test_warlords_spoils() -> void:
	var session: CombatSession = _session()
	_own(session, "warlords_spoils")
	var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var foe: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 0))
	session.open_battle()
	_sure_hit(session, who)
	session.state.set_hp(who, 10)
	session.state.set_hp(foe, 1)
	_attack(session, who, foe)
	_same("warlords_spoils: the killer's HP after a kill at 10", "%s %d" % [
		session.state.has_unit(foe), session.state.get_hp(who),
	], "false 13")


# Two seats on one map, seat 0 owning it: at Phase Start each friendly unit next to another
# player's unit gains 2 Block, whichever seat it belongs to; a unit beside only its own seat's
# units gains none. In solo it never fires.
func _test_brothers_in_arms() -> void:
	var session: CombatSession = _session(9, PackedInt32Array([0, 1]))
	_own(session, "brothers_in_arms")
	var units: PackedStringArray = [
		_place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0)),
		_place(session, "hakkapel", PLAYER, 1, Vector2i(1, 0)),
		_place(session, "hakkapel", PLAYER, 0, Vector2i(4, 0)),
		_place(session, "hakkapel", PLAYER, 0, Vector2i(5, 0)),
	]
	_place(session, "hakkapel", ENEMY, -1, Vector2i(8, 0))
	session.open_battle()
	var blocks: PackedStringArray = []
	for unit_id: String in units:
		blocks.append(str(session.state.get_block(unit_id)))
	_same("brothers_in_arms: Block beside a partner, a partner, own seat only", " ".join(blocks), (
			"2 2 0 0"
	))
	var solo: CombatSession = _session()
	_own(solo, "brothers_in_arms")
	var alone: String = _place(solo, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	_place(solo, "hakkapel", PLAYER, 0, Vector2i(1, 0))
	solo.open_battle()
	_same("brothers_in_arms: nothing in solo", str(solo.state.get_block(alone)), "0")


# The always-on stat heirlooms and curses, against a bare Hakkapel: Warhorse Lineage +1 Movement,
# Ancestral Mail +1 Stance (it also starts with it), Leaden Boots -1 SPD per copy.
func _test_always_on() -> void:
	var bare: CombatSession = _session()
	var plain: String = _place(bare, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var rows: Array[Array] = [
		["warhorse_lineage", 1, CombatValue.Key.MOVEMENT, "+1"],
		["ancestral_mail", 1, CombatValue.Key.STANCE_MAX, "+1"],
		["leaden_boots", 1, CombatValue.Key.SPD, "-1"],
		["leaden_boots", 2, CombatValue.Key.SPD, "-2"],
	]
	for row: Array in rows:
		var heirloom_id: String = row[0]
		var copies: int = row[1]
		var key: int = row[2]
		var wanted: String = row[3]
		var session: CombatSession = _session()
		_own(session, heirloom_id, 0, copies)
		var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
		var change: int = (
				session.engine.stats(who).get_int(key) - bare.engine.stats(plain).get_int(key)
		)
		_same("%s x%d: %s change" % [heirloom_id, copies, EffectTerms.key_name(key)], (
				"%+d" % [change]
		), wanted)
		if heirloom_id == "ancestral_mail":
			var placed: int = session.state.get_stance(who)
			_same("ancestral_mail: placed with the extra Stance", str(placed), (
					str(bare.state.get_stance(plain) + 1)
			))


# After a kill the killer may move again with its movement left, this phase.
func _test_bloodhounds_collar() -> void:
	var pending: PackedStringArray = []
	for heirloom_id: String in ["", "bloodhounds_collar"]:
		var session: CombatSession = _session()
		_own(session, heirloom_id)
		var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
		var foe: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 0))
		_place(session, "hakkapel", ENEMY, -1, Vector2i(8, 0))
		session.open_battle()
		_sure_hit(session, who)
		session.state.set_hp(foe, 1)
		_attack(session, who, foe)
		pending.append(str(session.state.unit(who).is_second_move_pending))
	_same("bloodhounds_collar: a move pending after a kill, without and with", " ".join(pending), (
			"false true"
	))


# Each kill adds +1 damage for the rest of this combat: two kills, +2 against a third enemy. The
# second kill is a test shortcut: the unit's action is refreshed, never a rule.
func _test_champions_belt() -> void:
	var session: CombatSession = _session()
	_own(session, "champions_belt")
	var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(1, 0))
	var foes: PackedStringArray = [
		_place(session, "hakkapel", ENEMY, -1, Vector2i(0, 0)),
		_place(session, "hakkapel", ENEMY, -1, Vector2i(2, 0)),
		_place(session, "hakkapel", ENEMY, -1, Vector2i(1, 1)),
	]
	session.open_battle()
	_sure_hit(session, who)
	var before: int = _damage(session, who, foes[2])
	var gains: PackedStringArray = []
	for index: int in 2:
		session.state.set_hp(foes[index], 1)
		_attack(session, who, foes[index])
		gains.append("%+d" % [_damage(session, who, foes[2]) - before])
	_same("champions_belt: damage after one kill, then two", " ".join(gains), "+1 +2")


# Deployment as a campaign does it ([method CombatSession.deploy]), with the army's carriers
# registered first: Ill Omen takes 1 Stance from the commander alone, from placement on; Heavy
# Pack makes a Hakkapel's Potion weigh 2; Commander's Standard gives 2 Block at Phase Start to the
# commander and Your Units within 2 tiles of it. The commander's 4 is the Standard's 2 and
# Vanguard's 2 (2 × level 1).
func _test_commander_and_pouch() -> void:
	var results: Dictionary[String, String] = {}
	for cursed: bool in [false, true]:
		var session: CombatSession = _deploy_session()
		if cursed:
			_own(session, "ill_omen")
			_own(session, "heavy_pack")
		_own(session, "commanders_standard")
		var army: Array[Loadout.LoadedUnit] = [
			_load(session, "drengr", ""),
			_load(session, "hakkapel", "potion"),
			_load(session, "lancer", ""),
		]
		var units: Array[CombatUnitState] = []
		var bases: Dictionary[String, Dictionary] = {}
		for loaded: Loadout.LoadedUnit in army:
			units.append(loaded.state)
			bases[loaded.state.id] = loaded.bases
		session.deploy(units, bases, units[0].id)
		var ids: PackedStringArray = [units[0].id, units[1].id, units[2].id]
		var sheets: PackedStringArray = []
		for unit_id: String in ids:
			sheets.append("%d/%d" % [
				session.engine.stats(unit_id).get_int(CombatValue.Key.STANCE_MAX),
				session.state.get_stance(unit_id),
			])
		results["stance %s" % [cursed]] = " ".join(sheets)
		results["weight %s" % [cursed]] = str(
				session.engine.stats(ids[1]).get_int(CombatValue.Key.NET_WEIGHT)
		)
		session.state.move_unit(ids[0], Vector2i(2, 0))
		session.state.move_unit(ids[1], Vector2i(0, 0))
		session.state.move_unit(ids[2], Vector2i(5, 0))
		_place(session, "hakkapel", ENEMY, -1, Vector2i(8, 0))
		session.open_battle()
		results["block %s" % [cursed]] = "%d %d %d" % [
			session.state.get_block(ids[0]),
			session.state.get_block(ids[1]),
			session.state.get_block(ids[2]),
		]
	var plain: PackedStringArray = results["stance false"].split(" ")
	var commander: PackedStringArray = plain[0].split("/")
	_same("ill_omen: Stance Max/Stance of commander, Hakkapel, Lancer", results["stance true"], (
			"%d/%d %s %s" % [
				commander[0].to_int() - 1, commander[1].to_int() - 1, plain[1], plain[2],
			]
	))
	_same("heavy_pack: a Hakkapel with a Potion, without and with", "%s %s" % [
		results["weight false"], results["weight true"],
	], "%d %d" % [LANCE_WEIGHT, LANCE_WEIGHT + 2])
	_same("commanders_standard: commander, 2 tiles away, 3 tiles away", results["block false"], (
			"4 2 0"
	))


# Haunted with Iron Rations: the golden log, its random pick through the roll source. The ban
# resolves first, so the picked unit gets none of Iron Rations' Block, nor any later gain that
# turn (nothing recorded); it ends at the enemy Phase End, and the next Phase Start picks again.
# Two copies pick twice.
func _test_haunted() -> void:
	var session: CombatSession = _session()
	var curse: String = _own(session, "haunted")[0].instance_id
	_own(session, "iron_rations")
	var hakkapel: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var lancer: String = _place(session, "lancer", PLAYER, 0, Vector2i(1, 0))
	_place(session, "hakkapel", ENEMY, -1, Vector2i(8, 0))
	var start: int = session.engine.fact_log.size()
	session.open_battle()
	_golden("Haunted with Iron Rations", session.engine, _first_phase_start(session, start))
	var picked: String = _haunted_pick(session.engine, curse, start)
	var spared: String = hakkapel if picked == lancer else lancer
	var block: String = "%d %d" % [
		session.state.get_block(picked), session.state.get_block(spared),
	]
	var before: int = session.engine.fact_log.size()
	var gains: String = "%d %d" % [
		session.engine.gain_block(picked, 2.0), session.engine.gain_block(spared, 2.0),
	]
	_same("haunted: Block of the picked unit and the other, then a gain of 2 to each", (
			"%s | %s" % [block, gains]
	), "0 3 | 0 2")
	_ok("haunted: a banned gain records nothing", (
			session.engine.fact_log.size() == before + 1
			and session.engine.fact_log[before].actor_id == spared
	))

	var ended_at: int = session.engine.fact_log.size()
	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	var expired: int = -1
	var next_start: int = -1
	for index: int in range(ended_at, session.engine.fact_log.size()):
		var fact: CombatFact = session.engine.fact_log[index]
		if fact.kind == CombatFact.Kind.MODIFIER_EXPIRED and fact.actor_id == picked:
			expired = index
		elif fact.kind == CombatFact.Kind.PHASE_START and fact.side == PLAYER:
			next_start = index
	_ok("haunted: the ban ends before the next Phase Start, which picks again", (
			expired >= 0
			and next_start > expired
			and not _haunted_pick(session.engine, curse, next_start).is_empty()
	))

	var picks: PackedStringArray = []
	for copies: int in [1, 2]:
		var haunted: CombatSession = _session()
		var instances: Array[EffectInstance] = _own(haunted, "haunted", 0, copies)
		_place(haunted, "hakkapel", PLAYER, 0, Vector2i(0, 0))
		_place(haunted, "hakkapel", ENEMY, -1, Vector2i(8, 0))
		haunted.open_battle()
		var fired: int = 0
		var banned: int = 0
		for fact: CombatFact in haunted.engine.fact_log:
			for instance: EffectInstance in instances:
				if fact.source_effect_id != instance.instance_id:
					continue
				if fact.kind == CombatFact.Kind.EFFECT_ACTIVATED:
					fired += 1
				elif fact.kind == CombatFact.Kind.MODIFIER_GAINED:
					banned += 1
		picks.append("%d copies: %d fired, %d banned" % [copies, fired, banned])
	_same("haunted: copies each fire and pick", ", ".join(picks), (
			"1 copies: 1 fired, 1 banned, 2 copies: 2 fired, 2 banned"
	))


# The first unit the curse instance curse_id banned from start on; empty when none.
func _haunted_pick(engine: EffectEngine, curse_id: String, start: int) -> String:
	for index: int in range(start, engine.fact_log.size()):
		var fact: CombatFact = engine.fact_log[index]
		if fact.kind == CombatFact.Kind.MODIFIER_GAINED and fact.source_effect_id == curse_id:
			return fact.actor_id
	return ""


# On turn 1 Your Units start with 1 Stance less (a Thief's 1 leaves it Exposed); turn 2's refresh
# restores it.
func _test_shaken_footing() -> void:
	var session: CombatSession = _session()
	_own(session, "shaken_footing")
	var hakkapel: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var thief: String = _place(session, "thief", PLAYER, 0, Vector2i(1, 0))
	_place(session, "hakkapel", ENEMY, -1, Vector2i(8, 0))
	session.open_battle()
	var first: String = "%d %d" % [
		session.state.get_stance(hakkapel), session.state.get_stance(thief),
	]
	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	_same("shaken_footing: Hakkapel and Thief Stance on turn 1, then turn 2", "%s | %d %d" % [
		first, session.state.get_stance(hakkapel), session.state.get_stance(thief),
	], "1 0 | 2 1")


# Each seat value heirloom and curse on the seat's sheet, one copy and two; Clouded Sight's
# permission, which a second copy doesn't change.
func _test_seat_values() -> void:
	for row: Array in SEAT_VALUES:
		var heirloom_id: String = row[0]
		var key: int = row[1]
		var values: PackedStringArray = []
		for copies: int in [1, 2]:
			var session: CombatSession = _session()
			_own(session, heirloom_id, 0, copies)
			values.append(str(_seat(session).get_int(key)))
		_same("%s: seat value with one copy and two" % [heirloom_id], " ".join(values), "%d %d" % [
			row[2], row[3],
		])
	var hidden: PackedStringArray = []
	for copies: int in [0, 1, 2]:
		var session: CombatSession = _session()
		_own(session, "clouded_sight", 0, copies)
		hidden.append(str(_seat(session).is_allowed(CampaignValue.Permission.INTENTS_HIDDEN)))
	_same("clouded_sight: intents hidden with 0, 1 and 2 copies", " ".join(hidden), (
			"false true true"
	))


# The readers that exist already: Scrapper's Tongs through Prices (a Common trinket, 30 gold, at
# 40%), Short Wick through the darkness's arrival; and the golden breakdowns of an economy and an
# army value.
func _test_value_readers() -> void:
	var tongs: CombatSession = _session()
	_own(tongs, "scrappers_tongs")
	var percent: float = _seat(tongs).get_value(CampaignValue.Key.SCRAP_PERCENT)
	_same("scrappers_tongs: a Common trinket scraps for 12 instead of 6", "%d %d" % [
		Prices.scrap_value("trinket", ItemDefinition.Rarity.COMMON, Prices.default_scrap_percent()),
		Prices.scrap_value("trinket", ItemDefinition.Rarity.COMMON, percent),
	], "6 12")
	var wick: CombatSession = _session()
	_own(wick, "short_wick")
	_place(wick, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var offset: int = DarknessSetup.arrival_offset(wick)
	_same("short_wick: the darkness arrives a turn early", str(offset), "-1")
	var ledger: CombatSession = _session()
	_own(ledger, "bounty_ledger")
	_own(ledger, "muster_roll")
	var lines: PackedStringArray = [
		_seat(ledger).explain(CampaignValue.Key.COMBAT_GOLD).to_text(),
		_seat(ledger).explain(CampaignValue.Key.MAX_ARMY_SIZE).to_text(),
	]
	_same("golden Bounty Ledger and Muster Roll breakdowns", " || ".join(lines), " || ".join(
			PackedStringArray(GOLDEN.get("Bounty Ledger and Muster Roll", []) as Array)
	))


# A Fighter with the whetstone hits a Lancer that survives: the exchange's facts.
func _golden_whetstone() -> void:
	var session: CombatSession = _session()
	_own(session, "grandfathers_whetstone")
	var who: String = _place(session, "fighter", PLAYER, 0, Vector2i(0, 0))
	var foe: String = _place(session, "lancer", ENEMY, -1, Vector2i(1, 0))
	session.open_battle()
	_sure_hit(session, who)
	session.state.set_hp(foe, 99)
	var start: int = session.engine.fact_log.size()
	_attack(session, who, foe)
	_golden("Grandfather's Whetstone", session.engine, start)


# The damage [param attacker_type] would deal per hit to [param defender_type] at
# [param distance], owning [param heirloom_id] (empty for none), by the forecast.
# Tactician's Manual (heirlooms.md, Starting heirlooms): a Fighter's Simple Axe (Power, 10) has
# Advantage on a Lance Armor's Simple Lance (Balance; it survives, so it counters): +15 Hit more
# and its change of 3 again; a Lancer's Simple Lance (7) attacking the Fighter loses 15 Hit more
# and its change of 2 again. The enemy's counter keeps the normal triangle either way, and a
# Standoff changes nothing.
func _test_tacticians_manual() -> void:
	var rows: PackedStringArray = []
	for row: Array in [["fighter", "lance_armor"], ["lancer", "fighter"], ["fighter", "fighter"]]:
		var attacker: String = row[0]
		var defender: String = row[1]
		var plain: PackedInt32Array = _exchange_numbers("", attacker, defender)
		var manual: PackedInt32Array = _exchange_numbers("tacticians_manual", attacker, defender)
		var deltas: PackedStringArray = []
		for index: int in plain.size():
			deltas.append("%+d" % [manual[index] - plain[index]])
		rows.append("%s on %s: %s" % [attacker, defender, " ".join(deltas)])
	_same("tacticians_manual: attacker damage and Hit, defender damage and Hit", ", ".join(rows), (
			"fighter on lance_armor: +3 +15 +0 +0, lancer on fighter: -2 -15 +0 +0,"
			+ " fighter on fighter: +0 +0 +0 +0"
	))


# The forecast of a player unit of attacker_type attacking an adjacent enemy of defender_type,
# seat 0 owning heirloom_id (empty: none): attacker damage and Hit, then the counter's.
func _exchange_numbers(
		heirloom_id: String, attacker_type: String, defender_type: String
) -> PackedInt32Array:
	var session: CombatSession = _session()
	_own(session, heirloom_id)
	var who: String = _place(session, attacker_type, PLAYER, 0, Vector2i(0, 0))
	var foe: String = _place(session, defender_type, ENEMY, -1, Vector2i(1, 0))
	if who.is_empty() or foe.is_empty() or session.open_battle().is_rejected():
		_ok("%s: the battle loads" % [heirloom_id], false)
		return PackedInt32Array([0, 0, 0, 0])
	session.state.unit(who).has_acted = false
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			session.engine, UnitTurnCommand.new(0, who, ATTACK, foe)
	)
	return PackedInt32Array([
		forecast.attacker.damage, forecast.attacker.hit,
		forecast.defender.damage, forecast.defender.hit,
	])


func _forecast_damage(
		heirloom_id: String, attacker_type: String, defender_type: String, distance: int
) -> int:
	var session: CombatSession = _session()
	_own(session, heirloom_id)
	var who: String = _place(session, attacker_type, PLAYER, 0, Vector2i(0, 0))
	var foe: String = _place(session, defender_type, ENEMY, -1, Vector2i(distance, 0))
	if who.is_empty() or foe.is_empty() or session.open_battle().is_rejected():
		_ok("%s: the battle loads" % [heirloom_id], false)
		return -1
	return _damage(session, who, foe)


# The forecast's damage per hit from attacker_id to defender_id now, its action refreshed first
# (a test shortcut, never a rule); -1 when illegal.
func _damage(session: CombatSession, attacker_id: String, defender_id: String) -> int:
	session.state.unit(attacker_id).has_acted = false
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			session.engine, UnitTurnCommand.new(0, attacker_id, ATTACK, defender_id)
	)
	if not forecast.is_legal:
		_ok("forecast %s -> %s: legal" % [attacker_id, defender_id], false, forecast.reason)
		return -1
	return forecast.attacker.damage


# Attacks as attacker_id's action, refreshed first so one unit can attack again: a test shortcut,
# never a rule.
func _attack(
		session: CombatSession, attacker_id: String, defender_id: String
) -> CombatSession.FactBatch:
	session.state.unit(attacker_id).has_acted = false
	session.submit(UnitTurnCommand.new(0, attacker_id, ATTACK, defender_id))
	return session.resolve_next()


# Uses unit_id's Pouch item on itself as its action.
func _drink(session: CombatSession, unit_id: String) -> void:
	var use: UnitTurnCommand = UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.ITEM, unit_id)
	use.item_id = session.state.unit(unit_id).pouch_item_id
	session.submit(use)
	var batch: CombatSession.FactBatch = session.resolve_next()
	if batch.is_rejected():
		_ok("%s drinks its Potion" % [unit_id], false, batch.rejected_reason)


# Uses the chest under unit_id with no item, as its action; the chest is closed and the action
# refreshed first, so one unit can try again: a test shortcut, never a rule.
func _open_chest(session: CombatSession, unit_id: String) -> CombatSession.FactBatch:
	session.state.map.object(CHEST_ID).is_used = false
	session.state.unit(unit_id).has_acted = false
	session.submit(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.USE_OBJECT, CHEST_ID))
	return session.resolve_next()


# The Burglar's Roll charges left on session, over every copy.
func _burglar_charges(session: CombatSession) -> int:
	var left: int = 0
	for instance: EffectInstance in session.engine.get_instances():
		if instance.definition.id == MapObjects.BURGLAR_EFFECT_ID:
			left += instance.charges_left
	return left


# Registers copies of heirloom_id's effects on session's engine, owned by seat's army, as a
# campaign does for every heirloom it holds; none for an empty id. Returns them.
func _own(
		session: CombatSession, heirloom_id: String, seat: int = 0, copies: int = 1
) -> Array[EffectInstance]:
	var registered: Array[EffectInstance] = []
	if heirloom_id.is_empty():
		return registered
	for _copy: int in copies:
		var instances: Array[EffectInstance] = Loadout.heirloom_effects(
				_catalog, heirloom_id, seat, session.ids
		)
		if instances.is_empty():
			_ok("%s: loads as carriers" % [heirloom_id], false)
		for instance: EffectInstance in instances:
			session.engine.register(instance)
			registered.append(instance)
	return registered


# The values of keys on unit_id's sheet, in order.
func _values(session: CombatSession, unit_id: String, keys: Array[int]) -> Array:
	var values: Array = []
	for key: int in keys:
		values.append(session.engine.stats(unit_id).get_int(key))
	return values


func _seat(session: CombatSession, seat: int = 0) -> StatSheet:
	return session.engine.stats(InstanceIdAllocator.seat_subject_id(seat))


# Makes every attack of unit_id hit, as a test delta: the cases are about what the hit does.
func _sure_hit(session: CombatSession, unit_id: String) -> void:
	session.engine.add_delta(unit_id, Modifier.new(
			CombatValue.Key.HIT,
			Modifier.Mode.ADD,
			200.0,
			Modifier.SourceKind.UNIT_TRAIT,
			"",
			"test"
	))


# The index of the first PHASE_START at or after start in session's fact log.
func _first_phase_start(session: CombatSession, start: int) -> int:
	for index: int in range(start, session.engine.fact_log.size()):
		if session.engine.fact_log[index].kind == CombatFact.Kind.PHASE_START:
			return index
	return start


func _golden(name: String, engine: EffectEngine, start: int = 0) -> void:
	var lines: PackedStringArray = []
	for index: int in range(start, engine.fact_log.size()):
		lines.append(engine.fact_log[index].to_log_line())
	var wanted: PackedStringArray = PackedStringArray(GOLDEN.get(name, []) as Array)
	_ok("golden %s" % [name], lines == wanted, "\n\t" + "\n\t".join(lines))
	_ok("%s: no diagnostics" % [name], engine.diagnostics.is_empty(), str(engine.diagnostics))


func _session(
		width: int = 9, seats: PackedInt32Array = PackedInt32Array([0])
) -> CombatSession:
	return _session_on(_plain_layout(width), seats)


# A plain row with a locked chest at CHEST_TILE, holding a common item.
func _chest_session() -> CombatSession:
	var layout: MapLayout = _plain_layout(5)
	layout.add_marker(MapLayout.MarkerKind.OBJECT_SPOT, CHEST_TILE, MapLayout.ObjectKind.CHEST)
	layout.index_markers()
	var session: CombatSession = _session_on(layout, PackedInt32Array([0]))
	MapObjects.place(session)
	session.state.map.contents[0] = {"kind": "item", "rarity": "common"}
	return session


# A plain row whose first four tiles are deployment tiles.
func _deploy_session() -> CombatSession:
	var layout: MapLayout = _plain_layout(9)
	for x: int in 4:
		layout.add_marker(MapLayout.MarkerKind.DEPLOYMENT, Vector2i(x, 0))
	layout.index_markers()
	return _session_on(layout, PackedInt32Array([0]))


func _session_on(layout: MapLayout, seats: PackedInt32Array) -> CombatSession:
	return CombatSession.new(
			0, seats, MapGrid.new(layout), LiveRolls.new(RngStream.new(SEED)),
			InstanceIdAllocator.new()
	)


# Loads a new seat-0 unit of type_id with its starting weapon and pouch_id in its Pouch, its
# weapons and effects added to session, not yet placed.
func _load(session: CombatSession, type_id: String, pouch_id: String) -> Loadout.LoadedUnit:
	var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
	var ids: InstanceIdAllocator = session.ids
	var unit: UnitInstance = UnitInstance.new(ids.next_unit_id(type_id), type_id)
	var items: Dictionary[String, ItemInstance] = {}
	unit.weapon_id = _add_item(items, ids, unit_type.starting_weapon_id)
	unit.pouch_id = _add_item(items, ids, pouch_id)
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(_catalog, unit, items, PLAYER, 0, ids)
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		_ok("%s: loads" % [type_id], false, str(loaded.problems))
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	return loaded


# Loads a new unit of type_id with its type's starting weapon, equipment_id in its Equipment slot
# and pouch_id in its Pouch (empty for none), and places it on tile; its id, or empty when it
# didn't load.
func _place(
		session: CombatSession,
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i,
		equipment_id: String = "",
		pouch_id: String = ""
) -> String:
	var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
	if unit_type == null:
		_ok("%s: a unit type in the catalog" % [type_id], false)
		return ""
	var ids: InstanceIdAllocator = session.ids
	var unit_id: String = (
			ids.next_unit_id(type_id) if side == PLAYER else ids.next_enemy_id(type_id)
	)
	var unit: UnitInstance = UnitInstance.new(unit_id, type_id)
	var items: Dictionary[String, ItemInstance] = {}
	unit.weapon_id = _add_item(items, ids, unit_type.starting_weapon_id)
	unit.equipment_id = _add_item(items, ids, equipment_id)
	unit.pouch_id = _add_item(items, ids, pouch_id)
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(_catalog, unit, items, side, seat, ids)
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		_ok("%s: loads" % [type_id], false, str(loaded.problems))
		return ""
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = tile
	return unit_id if session.add_unit(loaded.state, loaded.bases) else ""


func _add_item(
		items: Dictionary[String, ItemInstance], ids: InstanceIdAllocator, definition_id: String
) -> String:
	if definition_id.is_empty():
		return ""
	var item: ItemInstance = ItemInstance.new(ids.next_item_id(definition_id), definition_id)
	items[item.instance_id] = item
	return item.instance_id


# A plain field width tiles across and two deep, so units can stand beside and behind each other.
func _plain_layout(width: int) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "heirloom_content"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for y: int in 2:
		for x: int in width:
			layout.set_terrain(Vector2i(x, y), plain)
	return layout


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
