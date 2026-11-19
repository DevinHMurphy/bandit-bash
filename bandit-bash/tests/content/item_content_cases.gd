# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_content_cases.gd
# Author:
# Created:  November 12, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The equipment, trinket, consumable and rune cases for tests/content/run_all.gd, over the real
## [code]res://data/[/code]: each item's category, rarity, weight, uses and cooked gains and each
## rune's target rules against items.md, each folder holding exactly the listed items and runes,
## effect text snapshots, and battles
## loaded from the data: Training Weights' Speed cost and level-up rules, Spirit Coating's hits
## mitigated by Resistance, the Elixir healing to full and being used up, the Simple Quiver's
## damage at range, the Sunshard Band's rounded heal, Tungsten Ooze's Armored tag, a Hit booster's
## permanent Hit on host and mirror, the Elixir's last use leaving a mirror's Pouch with the
## host's hash, the Key opening a locked chest twice and being used up, and
## the Lockpick opening it only for a lock picker and being kept. Reports each case through the
## check callable it is given.
##
## The expected values are transcribed from items.md, never read from the data, so a changed .tres
## fails here until the doc and this file agree.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK

const COMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.COMMON
const UNCOMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.UNCOMMON
const RARE: ItemDefinition.Rarity = ItemDefinition.Rarity.RARE
const LEGENDARY: ItemDefinition.Rarity = ItemDefinition.Rarity.LEGENDARY
const UNIQUE: ItemDefinition.Rarity = ItemDefinition.Rarity.UNIQUE

const PER_MAP: EffectTerms.Lane = EffectTerms.Lane.COMBAT
const TOTAL: EffectTerms.Lane = EffectTerms.Lane.CAMPAIGN

const EQUIPMENT_DIR: String = "res://data/items/equipment/"
const TRINKET_DIR: String = "res://data/items/trinkets/"
const CONSUMABLE_DIR: String = "res://data/items/consumables/"
const RUNE_DIR: String = "res://data/runes/"

# items.md's seven runes: target kind, target side (unit runes only), whether the unit must not
# have acted, and the reviewed effect text.
const RUNES: Dictionary[String, Array] = {
	"mend": ["unit", "player", false, "Heal an ally for 10"],
	"aegis": ["unit", "player", false, "Give an ally 6 Block"],
	"shatter": ["unit", "enemy", false, "Remove 2 Stance from an enemy"],
	"clarity": ["unit", "player", false, (
			"Give an ally +20 Hit and +2 Attack on its next attack until Phase End"
	)],
	"haste": ["unit", "player", true, "Give an ally that hasn't acted +2 Movement until Phase End"],
	"spark": ["object", "", false, "A powder keg anywhere on the map explodes"],
	"recall": ["pair", "", false, "Two of your units swap positions"],
}

# Any fixed seed: the forecasts draw nothing from it, and no item use rolls.
const SEED: int = 0xC7_0005

# The locked chest of the Key and Lockpick cases: the first object placed.
const CHEST_TILE: Vector2i = Vector2i(1, 0)
const CHEST_ID: String = "object:0"

# items.md's Equipment and Shields tables. Columns: category, rarity, weight.
const EQUIPMENT: Dictionary[String, Array] = {
	"vitality_cloak": ["cloak", COMMON, 1],
	"enshrouding_sash": ["cloak", UNCOMMON, 0],
	"fancy_cloak": ["cloak", RARE, 1],
	"magi_robes": ["armor", UNCOMMON, 2],
	"tungsten_ooze": ["armor", RARE, 5],
	"old_soldiers_band": ["band", COMMON, 1],
	"power_band": ["band", UNCOMMON, 1],
	"training_weights": ["band", UNCOMMON, 0],
	"sunshard_band": ["band", RARE, 1],
	"quick_soles": ["band", RARE, 0],
	"simple_quiver": ["quiver", COMMON, 1],
	"short_quiver": ["quiver", UNCOMMON, 1],
	"simple_coating": ["coating", COMMON, 0],
	"spirit_coating": ["coating", UNCOMMON, 0],
	"iron_shield": ["shield", COMMON, 4],
	"iron_greatshield": ["shield", COMMON, 6],
	"buckler": ["shield", UNCOMMON, 4],
	"steel_shield": ["shield", UNCOMMON, 5],
	"steel_greatshield": ["shield", UNCOMMON, 9],
	"knight_shield": ["shield", RARE, 7],
	"silver_greatshield": ["shield", RARE, 8],
	"silver_shield": ["shield", RARE, 10],
	"eye_shield": ["shield", LEGENDARY, 12],
}

# items.md's Trinkets table: rarity.
const TRINKETS: Dictionary[String, ItemDefinition.Rarity] = {
	"lucky_coin": COMMON,
	"mystifying_incense": COMMON,
	"old_pendant": COMMON,
	"travelers_ring": COMMON,
	"scholars_optics": COMMON,
	"family_ring": COMMON,
	"band_of_fortune": UNCOMMON,
	"knights_token": UNCOMMON,
	"loaded_die": RARE,
	"null_sigil": RARE,
	"jester_mask": RARE,
	"royal_crest": RARE,
	"ring_of_favor": LEGENDARY,
	"oak_wood_charm": UNIQUE,
	"cleansed_goblet": UNIQUE,
	"heavy_brick": UNIQUE,
	"resonant_ore": UNIQUE,
}

# items.md's Consumables, Stat boosters and Ingredients tables, and the Key and Lockpick of P03
# decisions 5 and 11. Columns: use kind, amount, uses (0: never used up), when they refill,
# rarity. Stat boosters and ingredients are single-use.
const CONSUMABLES: Dictionary[String, Array] = {
	"key": ["key", 0, 2, TOTAL, COMMON],
	"lockpick": ["lockpick", 0, 0, TOTAL, COMMON],
	"large_potion": ["heal", 8, 2, PER_MAP, COMMON],
	"potion_plus": ["heal", 12, 1, PER_MAP, UNCOMMON],
	"large_potion_plus": ["heal", 12, 2, PER_MAP, UNCOMMON],
	"elixir": ["full_heal", 0, 1, TOTAL, RARE],
	"guard_tonic_plus": ["block", 10, 1, PER_MAP, UNCOMMON],
	"emberglass_vial": ["heal", 12, 2, PER_MAP, UNIQUE],
	"vermillion_tonic": ["stat_booster", 0, 1, TOTAL, RARE],
	"godseed_oil": ["stat_booster", 0, 1, TOTAL, RARE],
	"bulls_draught": ["stat_booster", 0, 1, TOTAL, RARE],
	"giants_brew": ["stat_booster", 0, 1, TOTAL, RARE],
	"spirit_ink": ["stat_booster", 0, 1, TOTAL, RARE],
	"soul_dust": ["stat_booster", 0, 1, TOTAL, RARE],
	"tempo_tonic": ["stat_booster", 0, 1, TOTAL, RARE],
	"wyvern_wingdust": ["stat_booster", 0, 1, TOTAL, RARE],
	"infused_obsidian": ["stat_booster", 0, 1, TOTAL, RARE],
	"stonedragon_tail": ["stat_booster", 0, 1, TOTAL, RARE],
	"warding_worm": ["stat_booster", 0, 1, TOTAL, RARE],
	"ancient_anchor": ["stat_booster", 0, 1, TOTAL, RARE],
	"adept_anchovy": ["stat_booster", 0, 1, TOTAL, RARE],
	"martial_scroll": ["stat_booster", 0, 1, TOTAL, RARE],
	"boost_bread": ["stat_booster", 0, 1, TOTAL, LEGENDARY],
	"heartbeet": ["ingredient", 5, 1, TOTAL, COMMON],
	"titan_trout": ["ingredient", 10, 1, TOTAL, UNCOMMON],
	"century_cheese": ["ingredient", 10, 1, TOTAL, RARE],
	"brutvine_sap": ["ingredient", 5, 1, TOTAL, COMMON],
	"runewart": ["ingredient", 5, 1, TOTAL, COMMON],
	"wisdom_wine": ["ingredient", 5, 1, TOTAL, UNCOMMON],
	"brawn_prawn": ["ingredient", 10, 1, TOTAL, UNCOMMON],
	"brutvine_heartroot": ["ingredient", 10, 1, TOTAL, RARE],
	"moonclam_pearl": ["ingredient", 10, 1, TOTAL, RARE],
	"rushraddish": ["ingredient", 5, 1, TOTAL, COMMON],
	"swift_shellfish": ["ingredient", 10, 1, TOTAL, UNCOMMON],
	"hastehawk_feather": ["ingredient", 10, 1, TOTAL, RARE],
	"stonebark_blossom": ["ingredient", 5, 1, TOTAL, COMMON],
	"bastion_crab": ["ingredient", 5, 1, TOTAL, UNCOMMON],
	"stonebark_essence": ["ingredient", 10, 1, TOTAL, RARE],
	"cave_carrot": ["ingredient", 5, 1, TOTAL, COMMON],
	"sanctuary_shell": ["ingredient", 5, 1, TOTAL, UNCOMMON],
	"sanctree_branch": ["ingredient", 10, 1, TOTAL, RARE],
	"hawkweed": ["ingredient", 5, 1, TOTAL, COMMON],
	"precise_pepper": ["ingredient", 5, 1, TOTAL, UNCOMMON],
	"finesse_filet": ["ingredient", 10, 1, TOTAL, RARE],
}

# items.md's Ingredients table, the Cooked column for the Hit ingredients: Hit every unit gains at
# once.
const COOKED_HIT: Dictionary[String, int] = {
	"hawkweed": 5,
	"precise_pepper": 5,
	"finesse_filet": 10,
}

# items.md's Ingredients table, the Cooked column: the stat every unit's next level-up gains, and
# how much.
const COOKED: Dictionary[String, Array] = {
	"heartbeet": [CombatValue.Stat.HP, 2],
	"titan_trout": [CombatValue.Stat.HP, 4],
	"century_cheese": [CombatValue.Stat.HP, 4],
	"brutvine_sap": [CombatValue.Stat.MGT, 1],
	"runewart": [CombatValue.Stat.MGT, 1],
	"wisdom_wine": [CombatValue.Stat.MGT, 1],
	"brawn_prawn": [CombatValue.Stat.MGT, 2],
	"brutvine_heartroot": [CombatValue.Stat.MGT, 2],
	"moonclam_pearl": [CombatValue.Stat.MGT, 2],
	"rushraddish": [CombatValue.Stat.SPD, 1],
	"swift_shellfish": [CombatValue.Stat.SPD, 2],
	"hastehawk_feather": [CombatValue.Stat.SPD, 2],
	"stonebark_blossom": [CombatValue.Stat.DEF, 1],
	"bastion_crab": [CombatValue.Stat.DEF, 1],
	"stonebark_essence": [CombatValue.Stat.DEF, 2],
	"cave_carrot": [CombatValue.Stat.RES, 1],
	"sanctuary_shell": [CombatValue.Stat.RES, 1],
	"sanctree_branch": [CombatValue.Stat.RES, 2],
}

# The consumables CT3 entered for M1, checked by m1_content_cases.gd; listed so the folder check
# accounts for them.
const M1_CONSUMABLES: PackedStringArray = ["potion", "guard_tonic"]

# Reviewed effect text, one line per effect, in each item's order.
# NOTE: stat boosters and ingredients read "Always:" because the text generator recognises a
# used-on-target effect only when every operation is a heal or Block gain, and the Key and
# Lockpick read "Always: " because their use effects have no operations; Tungsten Ooze's Armored
# tag isn't in its text (reported with CT5, for P07).
const TEXT: Dictionary[String, Array] = {
	"vitality_cloak": ["Always: +4 HP", "Phase Start: heal 1"],
	"enshrouding_sash": ["Always: +20 Avoid, +1 SPD, -1 DEF"],
	"fancy_cloak": ["Always: +6 HP"],
	"magi_robes": ["Always: +2 MGT, +1 RES"],
	"tungsten_ooze": ["Always: +4 DEF, -1 Movement"],
	"old_soldiers_band": ["Always: +1 MGT, +1 DEF, +10 Hit"],
	# "+2 damage" is +2 at the Attack stage, as the Archer's Volley reads it.
	"power_band": ["Always: +2 Attack"],
	"training_weights": [
		"Always: -2 SPD, SPD can't grow, +1 Level Up Guaranteed Gains (MGT)",
	],
	"sunshard_band": ["Always: +4 HP", "Phase End: heal for 10% of this unit's HP"],
	"quick_soles": ["Always: +1 Movement"],
	"simple_quiver": ["While at range 2 or more: +1 Attack"],
	# Every bow reaches 1-2, the Short Bow and the Dragonslayer Bow included.
	"short_quiver": [
		"While holding a bow: Range becomes 1-2",
	],
	"simple_coating": ["While the opponent is Exposed: +2 Attack"],
	# It replaces the damage type's base, so a fixed damage type still wins.
	"spirit_coating": ["Always: Damage Type becomes Magic"],
	# A shield's Before Combat Block comes in every exchange, attacking or defending.
	"iron_shield": ["Always: +2 DEF", "Before Combat: gain 1 Block"],
	"iron_greatshield": ["Always: +2 DEF, +1 Stance Max"],
	"buckler": ["Always: +1 DEF, +1 RES", "Before Combat: gain 1 Block"],
	"steel_shield": ["Always: +3 DEF", "Before Combat: gain 1 Block"],
	"steel_greatshield": ["Always: +3 DEF, +1 Stance Max"],
	"knight_shield": ["Always: +2 DEF, +2 RES", "Before Combat: gain 1 Block"],
	"silver_greatshield": ["Always: +4 DEF, +1 RES, +1 Stance Max"],
	"silver_shield": ["Always: +4 DEF", "Before Combat: gain 2 Block"],
	"eye_shield": ["Always: +4 HP, -3 SPD, +4 DEF, +2 RES, +1 Parry"],
	"lucky_coin": ["Always: +10 Crit Chance"],
	"mystifying_incense": ["Always: +5 Avoid"],
	"old_pendant": ["Always: +1 RES"],
	"travelers_ring": ["Always: +2 SPD, -1 DEF"],
	"scholars_optics": ["Always: +10 Hit"],
	# "+25% XP" and "+20% healing received" add points to their 100% bases.
	"family_ring": ["Always: +25 Unit Xp Percent"],
	"band_of_fortune": ["Always: +5 Crit Chance, +5 Hit"],
	"knights_token": ["Always: +1 MGT, +1 DEF, -1 SPD"],
	"loaded_die": ["Always: +30 Crit Chance, -1 Crit X"],
	"null_sigil": ["Always: +1 Stance Max"],
	# "Crits ignore the target's Defense" is Kukri's permission, which skips the whole
	# Mitigation stage (Resistance against magic too).
	"jester_mask": ["Always: crits skip Mitigation"],
	"royal_crest": ["Always: Level Up Min Stats at least 3"],
	"ring_of_favor": ["Always: +2 HP, +1 DEF, +1 RES"],
	"oak_wood_charm": ["Always: +10 Avoid"],
	"cleansed_goblet": ["Always: +20 Healing Received Percent"],
	"heavy_brick": ["Always: +2 CON"],
	"key": ["Always: "],
	"lockpick": ["Always: "],
	"large_potion": ["Heal the target for 8"],
	"potion_plus": ["Heal the target for 12"],
	"large_potion_plus": ["Heal the target for 12"],
	# "Heal to full" heals the target's maximum HP, so healing received below 100%
	# (Cursed Blood) leaves it short of full.
	"elixir": ["Heal the target for HP equal to the target's HP"],
	"guard_tonic_plus": ["Give the target 10 Block"],
	"emberglass_vial": ["Heal the target for 12"],
	"vermillion_tonic": ["Always: permanently give the target +3 HP"],
	"godseed_oil": ["Always: permanently give the target +7 HP"],
	"bulls_draught": ["Always: permanently give the target +1 MGT"],
	"giants_brew": ["Always: permanently give the target +2 MGT"],
	"spirit_ink": ["Always: permanently give the target +1 MGT"],
	"soul_dust": ["Always: permanently give the target +2 MGT"],
	"tempo_tonic": ["Always: permanently give the target +1 SPD"],
	"wyvern_wingdust": ["Always: permanently give the target +2 SPD"],
	"infused_obsidian": ["Always: permanently give the target +1 DEF"],
	"stonedragon_tail": ["Always: permanently give the target +2 DEF"],
	"warding_worm": ["Always: permanently give the target +1 RES"],
	"ancient_anchor": ["Always: permanently give the target +2 RES"],
	"adept_anchovy": ["Always: permanently give the target +5 Hit"],
	"martial_scroll": ["Always: permanently give the target +10 Hit"],
	"boost_bread": [
		"Always: permanently give the target +1 MGT, permanently give the target +1 SPD,"
		+ " permanently give the target +1 DEF, permanently give the target +1 RES",
	],
	"heartbeet": ["Always: heal the target for 5, permanently give the target +5% HP growth"],
	"titan_trout": ["Always: heal the target for 10, permanently give the target +10% HP growth"],
	"century_cheese": [
		"Always: heal the target for 10, permanently give the target +10% HP growth",
	],
	"brutvine_sap": ["Always: heal the target for 5, permanently give the target +5% MGT growth"],
	"runewart": ["Always: heal the target for 5, permanently give the target +5% MGT growth"],
	"wisdom_wine": ["Always: heal the target for 5, permanently give the target +5% MGT growth"],
	"brawn_prawn": [
		"Always: heal the target for 10, permanently give the target +10% MGT growth",
	],
	"brutvine_heartroot": [
		"Always: heal the target for 10, permanently give the target +10% MGT growth",
	],
	"moonclam_pearl": [
		"Always: heal the target for 10, permanently give the target +10% MGT growth",
	],
	"rushraddish": ["Always: heal the target for 5, permanently give the target +5% SPD growth"],
	"swift_shellfish": [
		"Always: heal the target for 10, permanently give the target +10% SPD growth",
	],
	"hastehawk_feather": [
		"Always: heal the target for 10, permanently give the target +10% SPD growth",
	],
	"stonebark_blossom": [
		"Always: heal the target for 5, permanently give the target +5% DEF growth",
	],
	"bastion_crab": ["Always: heal the target for 5, permanently give the target +5% DEF growth"],
	"stonebark_essence": [
		"Always: heal the target for 10, permanently give the target +10% DEF growth",
	],
	"cave_carrot": ["Always: heal the target for 5, permanently give the target +5% RES growth"],
	"sanctuary_shell": [
		"Always: heal the target for 5, permanently give the target +5% RES growth",
	],
	"sanctree_branch": [
		"Always: heal the target for 10, permanently give the target +10% RES growth",
	],
	"hawkweed": ["Always: heal the target for 5, permanently give the target +3 Hit"],
	"precise_pepper": ["Always: heal the target for 5, permanently give the target +3 Hit"],
	"finesse_filet": ["Always: heal the target for 10, permanently give the target +5 Hit"],
}

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_test_equipment()
	_test_trinkets()
	_test_consumables()
	_test_cooked_gains()
	_test_folders()
	_test_text_snapshots()
	_test_runes()
	_test_training_weights()
	_test_spirit_coating()
	_test_elixir()
	_test_simple_quiver()
	_test_sunshard_band()
	_test_tungsten_ooze()
	_test_hit_booster()
	_test_elixir_mirror()
	_test_key()
	_test_lockpick()


func _test_equipment() -> void:
	for item_id: String in EQUIPMENT:
		var equipment: EquipmentDefinition = _catalog.equipment(item_id)
		if equipment == null:
			_ok("%s: equipment in the catalog" % [item_id], false)
			continue
		var actual: Array = [equipment.category, equipment.rarity, equipment.weight]
		_same("%s: items.md's category, rarity and weight" % [item_id], str(actual), (
				str(EQUIPMENT[item_id])
		))


func _test_trinkets() -> void:
	for item_id: String in TRINKETS:
		var trinket: TrinketDefinition = _catalog.trinket(item_id)
		if trinket == null:
			_ok("%s: a trinket in the catalog" % [item_id], false)
			continue
		_ok("%s: items.md's rarity, weightless, one always-on effect" % [item_id], (
				trinket.rarity == TRINKETS[item_id]
				and trinket.weight == 0
				and trinket.effects.size() == 1
				and trinket.effects[0].trigger == EffectTerms.Trigger.ALWAYS
				and trinket.effects[0].charges == 0
		))


# Each consumable's numbers, and one use effect that counts nothing: the loadout counts its uses
# from the fields (ConsumableDefinition.uses).
func _test_consumables() -> void:
	for item_id: String in CONSUMABLES:
		var consumable: ConsumableDefinition = _catalog.consumable(item_id)
		if consumable == null:
			_ok("%s: a consumable in the catalog" % [item_id], false)
			continue
		var actual: Array = [
			consumable.use_kind,
			consumable.amount,
			consumable.uses,
			consumable.uses_lane,
			consumable.rarity,
		]
		_same("%s: items.md's numbers" % [item_id], str(actual), str(CONSUMABLES[item_id]))
		var use: EffectDefinition = (
				consumable.effects[0] if consumable.effects.size() == 1 else null
		)
		_ok("%s: one use effect counting nothing, weightless" % [item_id], (
				use != null
				and use.trigger == EffectTerms.Trigger.ALWAYS
				and use.charges == 0
				and consumable.weight == 0
		))


func _test_cooked_gains() -> void:
	for item_id: String in CONSUMABLES:
		var consumable: ConsumableDefinition = _catalog.consumable(item_id)
		if consumable == null:
			continue
		var expected: Dictionary[CombatValue.Stat, int] = {}
		if COOKED.has(item_id):
			var row: Array = COOKED[item_id]
			expected[row[0] as CombatValue.Stat] = row[1]
		_same("%s: cooked gains" % [item_id], "%s %d" % [
			consumable.cooked_gains, consumable.cooked_hit,
		], "%s %d" % [expected, COOKED_HIT.get(item_id, 0)])


# Every file in the three folders is a listed item, so no item goes untested.
func _test_folders() -> void:
	var listed: Dictionary[String, PackedStringArray] = {
		EQUIPMENT_DIR: PackedStringArray(EQUIPMENT.keys()),
		TRINKET_DIR: PackedStringArray(TRINKETS.keys()),
		CONSUMABLE_DIR: PackedStringArray(CONSUMABLES.keys()) + M1_CONSUMABLES,
	}
	for folder: String in listed:
		var found: PackedStringArray = []
		for file: String in DirAccess.get_files_at(folder):
			if file.get_extension() == "tres":
				found.append(file.get_basename())
		found.sort()
		var expected: PackedStringArray = listed[folder]
		expected.sort()
		_same("%s: holds exactly the listed items" % [folder], ", ".join(found), (
				", ".join(expected)
		))


# Generated text is canonical (content catalog plan, Approach); these are its reviewed snapshots.
func _test_text_snapshots() -> void:
	for item_id: String in TEXT:
		var item: ItemDefinition = _catalog.item(item_id)
		if item == null:
			_ok("text %s: in the catalog" % [item_id], false)
			continue
		var expected: PackedStringArray = PackedStringArray(TEXT[item_id])
		_same("text %s" % [item_id], " | ".join(item.describe()), " | ".join(expected))


# The seven runes against items.md: the folder holds exactly them, each with its target rules and
# one effect, whose text is the reviewed snapshot.
func _test_runes() -> void:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(RUNE_DIR):
		if file.get_extension() == "tres":
			found.append(file.get_basename())
	found.sort()
	var expected: PackedStringArray = PackedStringArray(RUNES.keys())
	expected.sort()
	_same("runes: data/runes/ holds exactly the seven", ", ".join(found), ", ".join(expected))
	for rune_id: String in RUNES:
		var rune: RuneDefinition = _catalog.rune(rune_id)
		if rune == null:
			_ok("rune %s: in the catalog" % [rune_id], false)
			continue
		var row: Array = RUNES[rune_id]
		var rules: String = "%s %s %s" % [
			rune.target_kind, rune.target_side, rune.needs_unacted_target,
		]
		_same("rune %s: target rules" % [rune_id], rules, "%s %s %s" % [row[0], row[1], row[2]])
		var text: String = row[3]
		_same("rune %s: one effect, its text" % [rune_id], " | ".join(rune.describe()), text)


# An Archer (SPD 8) wearing Training Weights: -2 SPD in battle, its Speed can't grow while every
# other stat can, every level-up guarantees +1 MGT and nothing else, and it adds no weight
# (items.md: "its Speed cost is the weight").
func _test_training_weights() -> void:
	var session: CombatSession = _session()
	var plain: String = _place(session, "archer", PLAYER, 0, Vector2i(0, 0), "")
	var worn: String = _place(session, "archer", PLAYER, 0, Vector2i(1, 0), "training_weights")
	if plain.is_empty() or worn.is_empty():
		_ok("training weights: both archers load", false)
		return
	var sheet: StatSheet = session.engine.stats(worn)
	var grow: int = CampaignValue.Permission.STAT_CAN_GROW
	var gains: int = CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS
	_same("training weights: SPD 8 - 2", str(sheet.get_int(CombatValue.Key.SPD)), "6")
	_ok("training weights: Speed can't grow; Might, HP and Defense can", (
			not sheet.is_allowed(grow, null, CombatValue.Stat.SPD)
			and sheet.is_allowed(grow, null, CombatValue.Stat.MGT)
			and sheet.is_allowed(grow, null, CombatValue.Stat.HP)
			and sheet.is_allowed(grow, null, CombatValue.Stat.DEF)
	))
	_same("training weights: level-up guaranteed gains MGT, SPD, HP", "%d %d %d" % [
		sheet.get_int(gains, null, CombatValue.Stat.MGT),
		sheet.get_int(gains, null, CombatValue.Stat.SPD),
		sheet.get_int(gains, null, CombatValue.Stat.HP),
	], "1 0 0")
	_same("training weights: no weight beyond the bow's", "%d %d" % [
		sheet.get_int(CombatValue.Key.NET_WEIGHT),
		session.engine.stats(plain).get_int(CombatValue.Key.NET_WEIGHT),
	], "5 5")


# A Hakkapel's Simple Lance (7 + 4 MGT, Balance against Balance: no triangle change) against an
# adjacent enemy Hakkapel (DEF 4, RES 0) on Plain: 11 - 4 DEF = 7 physical; with Spirit Coating
# the hit is Magic, so 11 - 0 RES = 11. The enemy's counter is unchanged.
func _test_spirit_coating() -> void:
	var results: PackedStringArray = []
	for coating: String in ["", "spirit_coating"]:
		var session: CombatSession = _session()
		var attacker: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0), coating)
		var defender: String = _place(session, "hakkapel", ENEMY, -1, Vector2i(1, 0), "")
		if attacker.is_empty() or defender.is_empty() or session.open_battle().is_rejected():
			_ok("spirit coating: the battle loads", false)
			return
		var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
				session.engine, UnitTurnCommand.new(0, attacker, ATTACK, defender)
		)
		if not forecast.is_legal:
			_ok("spirit coating: the attack is legal", false, forecast.reason)
			return
		results.append("%d/%d" % [forecast.attacker.damage, forecast.defender.damage])
	_same("spirit coating: damage dealt/taken, without and with", " ".join(results), "7/7 11/7")


# The real Elixir in a Hakkapel's Pouch at 3 HP: used on itself it heals to its full HP, and its
# one total use spends it, so it leaves the Pouch (items.md: "1, then it's used up"). Full HP is
# read from the unit's stats, so tuning the Hakkapel's HP leaves this case alone.
func _test_elixir() -> void:
	var session: CombatSession = _session()
	var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0), "", "elixir")
	if who.is_empty() or session.open_battle().is_rejected():
		_ok("elixir: the battle loads", false)
		return
	var full_hp: int = session.stats(who).get_int(CombatValue.Key.HP)
	var elixir: String = session.state.unit(who).pouch_item_id
	session.state.set_hp(who, 3)
	session.engine.begin_step()
	var used: ItemUseResolver.Result = ItemUseResolver.resolve(
			session.engine, session.state, who, who, elixir
	)
	_ok("elixir: heals 3 to full HP, then leaves the Pouch", (
			used.is_legal
			and used.is_consumed
			and session.state.get_hp(who) == full_hp
			and session.state.unit(who).pouch_item_id.is_empty()
	), "%s %d of %d" % [used.reason, session.state.get_hp(who), full_hp])


# The Simple Quiver's +1 damage on hits dealt at range 2 or more: an Archer's bow at 2 and 3
# against an enemy Archer, and a Hakkapel's lance at 1 against an enemy Hakkapel, which gains
# nothing. Each row reads the damage dealt without the quiver, then with it: the Simple Bow's 6 +
# 5 MGT against DEF 0 is 11, and 13 at range 3 with Volley's +2 at maximum range.
func _test_simple_quiver() -> void:
	var results: PackedStringArray = []
	for row: Array in [["archer", 2], ["archer", 3], ["hakkapel", 1]]:
		var type_id: String = row[0]
		var distance: int = row[1]
		var dealt: PackedStringArray = []
		for quiver: String in ["", "simple_quiver"]:
			var session: CombatSession = _session()
			var attacker: String = _place(session, type_id, PLAYER, 0, Vector2i(0, 0), quiver)
			var defender: String = _place(session, type_id, ENEMY, -1, Vector2i(distance, 0), "")
			if attacker.is_empty() or defender.is_empty() or session.open_battle().is_rejected():
				_ok("simple quiver: the battle loads", false)
				return
			var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
					session.engine, UnitTurnCommand.new(0, attacker, ATTACK, defender)
			)
			if not forecast.is_legal:
				_ok("simple quiver: the attack is legal", false, forecast.reason)
				return
			dealt.append(str(forecast.attacker.damage))
		results.append("%s at %d: %s" % [type_id, distance, " ".join(dealt)])
	_same("simple quiver: damage dealt without and with, by range", " | ".join(results), (
			"archer at 2: 11 12 | archer at 3: 13 14 | hakkapel at 1: 7 7"
	))


# The Sunshard Band's Phase End heal: 10% of a Hakkapel's HP with the band's +4, rounded half up.
# The HP is read from the unit's stats, so tuning the Hakkapel's HP leaves this case alone.
func _test_sunshard_band() -> void:
	var session: CombatSession = _session()
	var who: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0), "sunshard_band")
	if who.is_empty() or session.open_battle().is_rejected():
		_ok("sunshard band: the battle loads", false)
		return
	var full_hp: int = session.stats(who).get_int(CombatValue.Key.HP)
	session.state.set_hp(who, 10)
	var start: int = session.engine.fact_log.size()
	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	var healed: PackedStringArray = []
	for index: int in range(start, session.engine.fact_log.size()):
		var fact: CombatFact = session.engine.fact_log[index]
		if fact.kind == CombatFact.Kind.HEALED and fact.actor_id == who:
			healed.append(str(fact.amount))
	_same("sunshard band: Phase End heals 10% of full HP, rounded half up", " ".join(healed), (
			str(floori(full_hp * 0.1 + 0.5))
	))


# Tungsten Ooze on a Hakkapel: +4 DEF and -1 Movement against a bare one, the Armored tag added to
# its own, and its movement type unchanged (a tag only).
func _test_tungsten_ooze() -> void:
	var session: CombatSession = _session()
	var plain: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0), "")
	var worn: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(1, 0), "tungsten_ooze")
	if plain.is_empty() or worn.is_empty():
		_ok("tungsten ooze: both hakkapels load", false)
		return
	var bare: StatSheet = session.engine.stats(plain)
	var sheet: StatSheet = session.engine.stats(worn)
	_same("tungsten ooze: DEF and Movement against a bare one", "%+d %+d" % [
		sheet.get_int(CombatValue.Key.DEF) - bare.get_int(CombatValue.Key.DEF),
		sheet.get_int(CombatValue.Key.MOVEMENT) - bare.get_int(CombatValue.Key.MOVEMENT),
	], "+4 -1")
	var expected: PackedStringArray = session.state.unit(plain).tags.duplicate()
	expected.append(ContentIds.TAG_ARMORED)
	_same("tungsten ooze: gains the Armored tag", str(session.state.unit(worn).tags), str(expected))
	_ok("tungsten ooze: its movement type is unchanged", (
			session.state.unit(worn).movement_type == session.state.unit(plain).movement_type
	))


# The real Adept Anchovy used from a Hakkapel's Pouch as its action: +5 Hit for good, kept as a
# delta for the campaign bridge to write back, the booster used up; a mirror applying the host's
# batch follows the STAT_CHANGED to the same Hit and delta. Only the Hit is compared; the mirror's
# Pouch and hash are the Elixir mirror case's.
func _test_hit_booster() -> void:
	var host: CombatSession = _session()
	var mirror: CombatSession = _session()
	var who: String = ""
	for session: CombatSession in [host, mirror]:
		who = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0), "", "adept_anchovy")
		if who.is_empty() or session.open_battle().is_rejected():
			_ok("hit booster: the battle loads", false)
			return
	var before: int = host.engine.stats(who).get_int(CombatValue.Key.HIT)
	var use: UnitTurnCommand = UnitTurnCommand.new(0, who, UnitTurnCommand.Action.ITEM, who)
	use.item_id = host.state.unit(who).pouch_item_id
	host.submit(use)
	var batch: CombatSession.FactBatch = host.resolve_next()
	_ok("hit booster: used as the unit's action", not batch.is_rejected(), batch.rejected_reason)
	var deltas: Array[Modifier] = host.engine.get_deltas(who, CombatValue.Key.HIT)
	_same("hit booster: +5 Hit, one delta to write back, used up", "%+d %d %s" % [
		host.engine.stats(who).get_int(CombatValue.Key.HIT) - before,
		deltas.size(),
		host.state.unit(who).pouch_item_id.is_empty(),
	], "+5 1 true")
	var changed: PackedStringArray = []
	for fact: CombatFact in batch.facts:
		if fact.kind == CombatFact.Kind.STAT_CHANGED:
			changed.append("%d %d" % [fact.key, fact.amount])
	_same("hit booster: STAT_CHANGED names Hit's stat number", ", ".join(changed), "%d 5" % [
		CombatValue.HIT_STAT,
	])
	mirror.apply_batch(batch)
	_same("hit booster: a mirror follows to +5 Hit and one delta", "%+d %d" % [
		mirror.engine.stats(who).get_int(CombatValue.Key.HIT) - before,
		mirror.engine.get_deltas(who, CombatValue.Key.HIT).size(),
	], "+5 1")


# BUG-008: the real Elixir's last use, as a Hakkapel's action at 3 HP. Its heal carries no charges
# and comes before the use the loadout counts, so a mirror that stopped at the heal kept the Elixir
# in the Pouch. A mirror applying the host's batch drops it too, and the state hashes match.
func _test_elixir_mirror() -> void:
	var host: CombatSession = _session()
	var mirror: CombatSession = _session()
	var who: String = ""
	for session: CombatSession in [host, mirror]:
		who = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0), "", "elixir")
		if who.is_empty() or session.open_battle().is_rejected():
			_ok("elixir mirror: the battle loads", false)
			return
		session.state.set_hp(who, 3)
	var use: UnitTurnCommand = UnitTurnCommand.new(0, who, UnitTurnCommand.Action.ITEM, who)
	use.item_id = host.state.unit(who).pouch_item_id
	host.submit(use)
	var batch: CombatSession.FactBatch = host.resolve_next()
	_ok("elixir mirror: used up on the host", (
			not batch.is_rejected() and host.state.unit(who).pouch_item_id.is_empty()
	), batch.rejected_reason)
	var applied: Error = mirror.apply_batch(batch)
	_ok("elixir mirror: the mirror drops it too, and its hash is the host's", (
			applied == OK
			and mirror.state.unit(who).pouch_item_id.is_empty()
			and mirror.state_hash() == host.state_hash()
	), "applied %s, mirror's Pouch '%s'" % [
		error_string(applied), mirror.state.unit(who).pouch_item_id,
	])


# The real Key, 2 total uses, held by a Hakkapel on a locked chest: it isn't a Pouch item to use
# on a unit; the first opening leaves it with a use, the second spends it and it leaves the Pouch.
func _test_key() -> void:
	var session: CombatSession = _chest_session()
	var who: String = _place(session, "hakkapel", PLAYER, 0, CHEST_TILE, "", "key")
	if who.is_empty() or session.open_battle().is_rejected():
		_ok("key: the battle loads", false)
		return
	var key: String = session.state.unit(who).pouch_item_id
	_same(
			"key: not used on a unit like a potion",
			ItemUseResolver.check(session.engine, session.state, who, who, key),
			"opens a lock, used on a chest or door"
	)
	var first: CombatSession.FactBatch = _open_chest(session, who, key)
	_ok("key: opens the locked chest, one use left", (
			not first.is_rejected()
			and session.state.map.object(CHEST_ID).is_used
			and session.state.unit(who).pouch_item_id == key
	), first.rejected_reason)
	var second: CombatSession.FactBatch = _open_chest(session, who, key)
	_ok("key: opens it again, then is used up", (
			not second.is_rejected() and session.state.unit(who).pouch_item_id.is_empty()
	), second.rejected_reason)


# The real Lockpick: a Hakkapel, which can't pick locks, can't open the chest with it; the real
# Thief, whose innate effect grants lock picking, opens it twice and keeps it.
func _test_lockpick() -> void:
	var refused: CombatSession = _chest_session()
	var hakkapel: String = _place(refused, "hakkapel", PLAYER, 0, CHEST_TILE, "", "lockpick")
	if hakkapel.is_empty() or refused.open_battle().is_rejected():
		_ok("lockpick: the Hakkapel's battle loads", false)
		return
	_same(
			"lockpick: only a lock picker uses it",
			MapObjects.check_use(
					refused.engine, refused.state, hakkapel, CHEST_ID,
					refused.state.unit(hakkapel).pouch_item_id
			),
			"can't pick locks"
	)
	var session: CombatSession = _chest_session()
	var thief: String = _place(session, "thief", PLAYER, 0, CHEST_TILE, "", "lockpick")
	if thief.is_empty() or session.open_battle().is_rejected():
		_ok("lockpick: the Thief's battle loads", false)
		return
	var pick: String = session.state.unit(thief).pouch_item_id
	var opened: PackedStringArray = []
	for _attempt: int in 2:
		var batch: CombatSession.FactBatch = _open_chest(session, thief, pick)
		opened.append(batch.rejected_reason if batch.is_rejected() else "opened")
	_same("lockpick: the Thief opens it twice", " ".join(opened), "opened opened")
	_ok("lockpick: never used up", session.state.unit(thief).pouch_item_id == pick)


func _session() -> CombatSession:
	return _session_on(_plain_layout(5))


# A plain row with a locked chest at [constant CHEST_TILE], holding a common item.
func _chest_session() -> CombatSession:
	var layout: MapLayout = _plain_layout(5)
	layout.add_marker(MapLayout.MarkerKind.OBJECT_SPOT, CHEST_TILE, MapLayout.ObjectKind.CHEST)
	layout.index_markers()
	var session: CombatSession = _session_on(layout)
	MapObjects.place(session)
	session.state.map.contents[0] = {"kind": "item", "rarity": "common"}
	return session


func _session_on(layout: MapLayout) -> CombatSession:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	return CombatSession.new(
			0, PackedInt32Array([0]), MapGrid.new(layout), LiveRolls.new(RngStream.new(SEED)), ids
	)


# Uses the chest under [param unit_id] with [param item_id], as its action. The chest is closed
# and the unit's action refreshed first, so one unit can open it again: a test shortcut, never a
# rule.
func _open_chest(
		session: CombatSession, unit_id: String, item_id: String
) -> CombatSession.FactBatch:
	session.state.map.object(CHEST_ID).is_used = false
	session.state.unit(unit_id).has_acted = false
	var command: UnitTurnCommand = UnitTurnCommand.new(
			0, unit_id, UnitTurnCommand.Action.USE_OBJECT, CHEST_ID
	)
	command.item_id = item_id
	session.submit(command)
	return session.resolve_next()


# Loads a new unit of [param type_id] with its type's starting weapon, [param equipment_id] in its
# Equipment slot and [param pouch_id] in its Pouch (empty for none), and places it on
# [param tile]; its id, or empty when it didn't load.
func _place(
		session: CombatSession,
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i,
		equipment_id: String,
		pouch_id: String = ""
) -> String:
	var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
	if unit_type == null:
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


# A new instance of [param definition_id] in [param items]; its id, or empty for no definition.
func _add_item(
		items: Dictionary[String, ItemInstance], ids: InstanceIdAllocator, definition_id: String
) -> String:
	if definition_id.is_empty():
		return ""
	var item: ItemInstance = ItemInstance.new(ids.next_item_id(definition_id), definition_id)
	items[item.instance_id] = item
	return item.instance_id


func _plain_layout(width: int) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "item_content"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for x: int in width:
		layout.set_terrain(Vector2i(x, 0), plain)
	return layout


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
