# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     weapon_content_cases.gd
# Author:
# Created:  November 15, 2026
# Modified: November 18, 2026
# ==============================================================================

extends RefCounted
## The weapon and staff cases for tests/content/run_all.gd, over the real [code]res://data/[/code]:
## all 70 MVP weapons and staves against weapons.md, each type folder holding exactly the listed
## ones, effect text snapshots, hand-computed forecasts (one per weapon type, effectiveness,
## both lifesteals, Everbloom), the Short Quiver's range read the same way by attacks, counters,
## the danger zone, a stowed bow and the detail panel's stowed line, Sanctuary's and Everwall's
## areas, and an area or full-heal
## staff record surviving a save and a version 1 save migrating. Reports each case through the
## check callable it is given.
##
## The expected values are transcribed from weapons.md, never read from the data, so a changed
## .tres fails here until the doc and this file agree.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const STAFF: UnitTurnCommand.Action = UnitTurnCommand.Action.STAFF

const BASIC: ItemDefinition.Rarity = ItemDefinition.Rarity.BASIC
const COMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.COMMON
const UNCOMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.UNCOMMON
const RARE: ItemDefinition.Rarity = ItemDefinition.Rarity.RARE
const LEGENDARY: ItemDefinition.Rarity = ItemDefinition.Rarity.LEGENDARY

const NONE: WeaponTriangle.Profile = WeaponTriangle.Profile.NONE
const NIMBLE: WeaponTriangle.Profile = WeaponTriangle.Profile.NIMBLE
const BALANCE: WeaponTriangle.Profile = WeaponTriangle.Profile.BALANCE
const POWER: WeaponTriangle.Profile = WeaponTriangle.Profile.POWER

const PHYSICAL: CombatFact.DamageType = CombatFact.DamageType.PHYSICAL
const MAGIC: CombatFact.DamageType = CombatFact.DamageType.MAGIC

const WEAPONS_DIR: String = "res://data/items/weapons/"

# How many MVP weapons and staves weapons.md lists.
const MVP_COUNT: int = 70

# Any fixed seed: the forecasts draw nothing from it.
const SEED: int = 0xC7_0004

# The enemy-only weapons (enemy-roster.md): in a weapon folder, never an MVP weapon.
const ENEMY_ONLY: PackedStringArray = ["fangs", "shieldmace"]

# weapons.md's weapon tables and game-vision.md's Simple weapons. Columns: type, profile, damage,
# damage type, AtkX, range min, range max, Hit, crit, CritX, weight, rarity, effective against.
const WEAPONS: Dictionary[String, Array] = {
	"simple_sword": ["sword", NIMBLE, 5, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 8, BASIC, ""],
	"simple_axe": ["axe", POWER, 10, PHYSICAL, 1, 1, 1, 65, 0, 3.0, 15, BASIC, ""],
	"simple_lance": ["lance", BALANCE, 7, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 12, BASIC, ""],
	"simple_bow": ["bow", NONE, 6, PHYSICAL, 1, 2, 3, 100, 0, 3.0, 5, BASIC, "flier"],
	"simple_gauntlets": ["gauntlets", NONE, 2, PHYSICAL, 2, 1, 1, 100, 0, 2.0, 1, BASIC, ""],
	"simple_dagger": ["dagger", NIMBLE, 2, PHYSICAL, 1, 1, 2, 100, 0, 5.0, 3, BASIC, ""],
	"simple_anima": ["anima", BALANCE, 5, MAGIC, 1, 1, 2, 80, 0, 3.0, 1, BASIC, ""],
	"simple_holy": ["holy", NIMBLE, 4, MAGIC, 1, 1, 2, 100, 0, 3.0, 6, BASIC, ""],
	"simple_dark": ["dark", POWER, 7, MAGIC, 1, 1, 2, 80, 0, 3.0, 8, BASIC, ""],
	"gladius": ["sword", NIMBLE, 3, PHYSICAL, 1, 1, 1, 100, 15, 3.0, 8, COMMON, ""],
	"woodsmans_axe": ["axe", NIMBLE, 8, PHYSICAL, 1, 1, 1, 80, 5, 3.0, 12, COMMON, ""],
	"throwing_hatchet": ["axe", POWER, 6, PHYSICAL, 1, 1, 2, 70, 0, 3.0, 10, COMMON, ""],
	"ash_spear": ["lance", NIMBLE, 4, PHYSICAL, 1, 1, 1, 85, 0, 3.0, 8, COMMON, ""],
	# weapons.md's Pilum, renamed and entered by EN6.
	"javelin": ["lance", BALANCE, 5, PHYSICAL, 1, 1, 2, 80, 0, 3.0, 9, COMMON, ""],
	"hunters_bow": ["bow", NONE, 9, PHYSICAL, 1, 2, 3, 100, 0, 3.0, 5, COMMON, "flier"],
	"butchers_knife": ["dagger", POWER, 6, PHYSICAL, 1, 1, 1, 100, 0, 5.0, 9, COMMON, ""],
	"brass_knuckles": ["gauntlets", NONE, 1, PHYSICAL, 3, 1, 1, 120, 15, 3.0, 6, COMMON, ""],
	"earthsplitter": ["anima", BALANCE, 13, MAGIC, 1, 1, 2, 90, 0, 3.0, 12, COMMON, ""],
	"arming_sword": ["sword", NIMBLE, 8, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 13, UNCOMMON, ""],
	"rapier": ["sword", NIMBLE, 6, PHYSICAL, 1, 1, 1, 80, 10, 3.0, 8, UNCOMMON, "armored"],
	"sabre": ["sword", BALANCE, 9, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 14, UNCOMMON, "mounted"],
	"bearded_axe": ["axe", POWER, 15, PHYSICAL, 1, 1, 1, 65, 0, 3.0, 20, UNCOMMON, ""],
	"halberd": ["axe", BALANCE, 12, PHYSICAL, 1, 1, 1, 65, 0, 3.0, 20, UNCOMMON, "mounted"],
	"hand_axe": ["axe", POWER, 9, PHYSICAL, 1, 1, 2, 65, 0, 3.0, 17, UNCOMMON, ""],
	"boar_spear": ["lance", BALANCE, 11, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 17, UNCOMMON, ""],
	"heavy_lance": ["lance", POWER, 11, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 18, UNCOMMON, "armored"],
	"recurve_bow": ["bow", NONE, 12, PHYSICAL, 1, 2, 3, 100, 0, 3.0, 10, UNCOMMON, "flier"],
	"short_bow": ["bow", NONE, 5, PHYSICAL, 1, 1, 2, 100, 15, 3.5, 3, UNCOMMON, "flier"],
	"rondel": ["dagger", BALANCE, 5, PHYSICAL, 1, 1, 2, 100, 0, 5.0, 5, UNCOMMON, ""],
	"armorbreaker": ["dagger", POWER, 4, PHYSICAL, 1, 1, 2, 100, 0, 5.0, 8, UNCOMMON, "armored"],
	"cestus": ["gauntlets", NONE, 4, PHYSICAL, 2, 1, 1, 100, 0, 3.0, 4, UNCOMMON, ""],
	"wind": ["anima", BALANCE, 1, MAGIC, 2, 1, 2, 90, 0, 3.0, 3, UNCOMMON, "flier"],
	"mandate": ["holy", NIMBLE, 1, MAGIC, 2, 1, 2, 100, 5, 5.0, 4, UNCOMMON, ""],
	"fiend_fire": ["dark", POWER, 8, MAGIC, 1, 1, 2, 80, 0, 3.0, 7, UNCOMMON, ""],
	"starforged_blade": ["sword", NIMBLE, 13, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 11, RARE, ""],
	"heartseeker": ["sword", NIMBLE, 8, PHYSICAL, 1, 1, 1, 80, 30, 3.0, 8, RARE, ""],
	"twin_fang": ["sword", NIMBLE, 9, PHYSICAL, 2, 1, 1, 80, 0, 3.0, 15, RARE, ""],
	"dark_sword": ["sword", POWER, 12, MAGIC, 1, 1, 2, 80, 0, 3.0, 15, RARE, ""],
	"headsmans_axe": ["axe", POWER, 17, PHYSICAL, 1, 1, 1, 65, 0, 3.0, 17, RARE, ""],
	"tomahawk": ["axe", POWER, 15, PHYSICAL, 1, 1, 2, 65, 5, 3.0, 19, RARE, ""],
	"wyvern_pike": ["lance", BALANCE, 15, PHYSICAL, 1, 1, 1, 80, 0, 3.0, 14, RARE, ""],
	"spear": ["lance", BALANCE, 13, PHYSICAL, 1, 1, 2, 80, 5, 3.0, 14, RARE, ""],
	"steppe_hornbow": ["bow", NONE, 15, PHYSICAL, 1, 2, 3, 100, 0, 3.0, 6, RARE, "flier"],
	"dragonslayer_bow": ["bow", NONE, 18, PHYSICAL, 1, 3, 5, 100, 0, 3.0, 15, RARE, "flier"],
	"whisperknife": ["dagger", NIMBLE, 11, PHYSICAL, 1, 1, 2, 100, 5, 5.0, 6, RARE, ""],
	"stiletto": ["dagger", NIMBLE, 7, PHYSICAL, 1, 1, 2, 100, 30, 5.0, 9, RARE, ""],
	"kukri": ["dagger", POWER, 1, PHYSICAL, 1, 1, 2, 105, 25, 6.0, 9, RARE, ""],
	"ogre_knuckles": ["gauntlets", NONE, 6, PHYSICAL, 2, 1, 1, 100, 5, 3.0, 4, RARE, ""],
	"torrent": ["anima", BALANCE, 10, MAGIC, 1, 1, 3, 90, 30, 3.0, 10, RARE, ""],
	"lumen": ["holy", NIMBLE, 15, MAGIC, 1, 1, 2, 100, 25, 3.0, 14, RARE, ""],
	"life_tap": ["dark", POWER, 10, MAGIC, 1, 1, 2, 80, 0, 3.0, 14, RARE, ""],
	"colossus": ["axe", POWER, 27, PHYSICAL, 1, 1, 1, 65, 20, 3.0, 25, LEGENDARY, ""],
	"zweihander": ["sword", POWER, 22, PHYSICAL, 1, 1, 1, 100, 20, 3.0, 16, LEGENDARY, ""],
	"titans_will": ["lance", BALANCE, 12, PHYSICAL, 1, 1, 2, 100, 5, 3.0, 24, LEGENDARY, ""],
	"ebonflight": ["bow", NONE, 12, PHYSICAL, 2, 2, 3, 100, 30, 3.0, 10, LEGENDARY, "flier"],
	"sanguis": ["dagger", NIMBLE, 9, PHYSICAL, 2, 1, 2, 105, 40, 6.0, 7, LEGENDARY, ""],
	"all_seeing_hands": ["gauntlets", NONE, 4, PHYSICAL, 5, 1, 1, 100, 0, 3.0, 4, LEGENDARY, ""],
	"mage_blade": ["anima", BALANCE, 16, MAGIC, 2, 1, 1, 80, 15, 3.0, 20, LEGENDARY, ""],
	"deliverance": ["holy", NIMBLE, 12, MAGIC, 1, 1, 2, 115, 45, 5.0, 14, LEGENDARY, ""],
	"abyss_typhoon": ["dark", POWER, 8, MAGIC, 3, 1, 2, 85, 25, 3.0, 14, LEGENDARY, ""],
}

# weapons.md's Staves table. Columns: kind, base amount, range min, range max, uses (0:
# unlimited), weight, rarity, area shape id, full heal, damage, Hit. "—" range is 0 (the user).
const STAVES: Dictionary[String, Array] = {
	"shelter": ["block", 3, 1, 1, 0, 0, BASIC, "", false, 0, 0],
	"rampart": ["block", 5, 1, 1, 0, 1, COMMON, "", false, 0, 0],
	"far_ward": ["block", 3, 1, 3, 0, 1, UNCOMMON, "", false, 0, 0],
	"sanctuary": ["block", 3, 1, 2, 2, 2, RARE, "adjacent_with_center", false, 0, 0],
	"everwall": ["block", 5, 0, 0, 1, 3, LEGENDARY, "within_3", false, 0, 0],
	"minor_heal": ["heal", 5, 1, 1, 3, 0, COMMON, "", false, 0, 0],
	"recover": ["heal", 15, 1, 1, 1, 3, UNCOMMON, "", false, 0, 0],
	"everbloom": ["heal", 0, 1, 10, 1, 7, LEGENDARY, "", true, 0, 0],
	"harm": ["attack", 0, 1, 2, 2, 10, UNCOMMON, "", false, 15, 100],
	"ruin": ["attack", 0, 1, 4, 1, 15, RARE, "", false, 20, 85],
}

# The generated text of every weapon with effects; the rest have none.
const TEXT: Dictionary[String, Array] = {
	# weapons.md: "Hit dealt: heals the attacker for half the damage it deals to HP".
	"dark_sword": ["Damage dealt: heal for 50% of the damage dealt to HP"],
	"kukri": ["Crit dealt: that hit skips Mitigation"],
	"life_tap": ["Hit dealt: that hit gains lifesteal"],
	"colossus": ["Always: +20 HP, +5 DEF, +5 CON"],
	"zweihander": ["Always: +4 MGT, +2 SPD"],
	"titans_will": ["Always: +17 HP, +5 MGT, +9 SPD, +4 DEF, +14 RES"],
	"ebonflight": ["Always: +5 SPD"],
	"abyss_typhoon": ["Always: +5 MGT"],
}

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_test_count()
	_test_weapons()
	_test_staves()
	_test_folders()
	_test_text_snapshots()
	_test_forecasts()
	_test_lifesteal()
	_test_everbloom()
	_test_short_quiver_attacks()
	_test_short_quiver_reads()
	_test_sanctuary()
	_test_everwall()
	_test_records_saved()
	_test_version_1_migrates()


func _test_count() -> void:
	_same("weapons.md: %d MVP weapons and staves" % [MVP_COUNT],
			str(WEAPONS.size() + STAVES.size()), str(MVP_COUNT))


func _test_weapons() -> void:
	for id: String in WEAPONS:
		var weapon: WeaponDefinition = _catalog.weapon(id)
		if weapon == null or weapon is StaffDefinition:
			_ok("weapon %s: a weapon in the catalog" % [id], false)
			continue
		var row: Array = WEAPONS[id]
		var effective: PackedStringArray = []
		if not (row[12] as String).is_empty():
			effective.append(row[12] as String)
		var got: Array = [
			weapon.weapon_type, weapon.profile, weapon.damage, weapon.damage_type, weapon.atk_x,
			weapon.range_min, weapon.range_max, weapon.hit, weapon.crit, weapon.crit_x,
			weapon.weight, weapon.rarity, ",".join(weapon.effective_against),
		]
		var expected: Array = row.duplicate()
		expected[12] = ",".join(effective)
		_same("weapon %s: weapons.md's numbers" % [id], str(got), str(expected))
		_ok("weapon %s: scales with Might x1" % [id], (
				weapon.scaling_stat == CombatValue.Stat.MGT
				and is_equal_approx(weapon.scaling_modifier, 1.0)
		))


func _test_staves() -> void:
	for id: String in STAVES:
		var staff: StaffDefinition = _catalog.staff(id)
		if staff == null:
			_ok("staff %s: in the catalog" % [id], false)
			continue
		var got: Array = [
			staff.staff_kind, staff.base_amount, staff.range_min, staff.range_max, staff.uses,
			staff.weight, staff.rarity, staff.area_shape_id, staff.full_heal, staff.damage,
			staff.hit,
		]
		_same("staff %s: weapons.md's numbers" % [id], str(got), str(STAVES[id]))
		# Every staff is Magic and outside the triangle, attack staves included (weapons.md).
		_ok("staff %s: Magic, profile None, type staff" % [id], (
				staff.damage_type == MAGIC
				and staff.profile == NONE
				and staff.weapon_type == ContentIds.WEAPON_STAFF
		))


func _test_folders() -> void:
	for weapon_type: String in ContentIds.WEAPON_TYPES:
		var expected: PackedStringArray = []
		for id: String in WEAPONS:
			if WEAPONS[id][0] == weapon_type:
				expected.append(id)
		if weapon_type == ContentIds.WEAPON_STAFF:
			expected.append_array(PackedStringArray(STAVES.keys()))
		for id: String in ENEMY_ONLY:
			var held: WeaponDefinition = _catalog.weapon(id)
			if held != null and held.weapon_type == weapon_type:
				expected.append(id)
		expected.sort()
		var found: PackedStringArray = []
		for file: String in DirAccess.get_files_at(WEAPONS_DIR + weapon_type):
			if file.ends_with(".tres"):
				found.append(file.get_basename())
		found.sort()
		_same("%s%s/: holds exactly the listed weapons" % [WEAPONS_DIR, weapon_type],
				", ".join(found), ", ".join(expected))


# Generated text is canonical (content catalog plan, Approach); these are its reviewed snapshots.
func _test_text_snapshots() -> void:
	for id: String in WEAPONS:
		var weapon: WeaponDefinition = _catalog.weapon(id)
		if weapon == null:
			continue
		var listed: Array = TEXT.get(id, [])
		var expected: PackedStringArray = PackedStringArray(listed)
		_same("text %s" % [id], " | ".join(weapon.describe()), " | ".join(expected))


# One forecast per weapon type against an enemy Ward (HP 25, DEF 7, RES 1, Simple Lance: Balance,
# 7 damage) on Plain (5 avoid): the attacker's Hit, first-hit damage and attacks per turn.
# Damage is weapon + MGT +- the triangle's quarter of the weapon (halves up, at least 1) - DEF or
# RES; Hit is the weapon's +-15 for the triangle - 5. Balance beats Nimble, Nimble beats Power,
# Power beats Balance. No row meets a trait: no Volley off maximum range, no Overwhelm at a lower
# Attack Speed, Flow's third attack and Charge's move unreached.
func _test_forecasts() -> void:
	var rows: Array[Array] = [
		# Nimble vs Balance: -3 (13 / 4). 13 + 5 - 3 - 7; 80 - 15 - 5.
		["sword", "sellsword", "starforged_blade", 1, "ward", "hit 60 dmg 8 x1"],
		# Power vs Balance: +4 (15 / 4 = 3.75). 15 + 6 + 4 - 7; 65 + 15 - 5.
		["axe", "fighter", "bearded_axe", 1, "ward", "hit 75 dmg 18 x1"],
		# Standoff. 15 + 3 - 7; 80 - 5.
		["lance", "lancer", "wyvern_pike", 1, "ward", "hit 75 dmg 11 x1"],
		# Range 2, not the bow's maximum 3. 12 + 5 - 7; 100 - 5.
		["bow", "archer", "recurve_bow", 2, "ward", "hit 95 dmg 10 x1"],
		# AtkX 2, the Ward has no Parry. 6 + 6 - 7.
		["gauntlets", "brawler", "ogre_knuckles", 1, "ward", "hit 95 dmg 5 x2"],
		# Nimble vs Balance: -3 (11 / 4 = 2.75). 11 + 3 - 3 - 7; 100 - 15 - 5.
		["dagger", "thief", "whisperknife", 1, "ward", "hit 80 dmg 4 x1"],
		# Standoff, Magic against RES 1. 10 + 3 - 1; 90 - 5.
		["anima", "mage", "torrent", 1, "ward", "hit 85 dmg 12 x1"],
		# Nimble vs Balance: -4 (15 / 4 = 3.75). 15 + 1 - 4 - 1; 100 - 15 - 5.
		["holy", "suncaster", "lumen", 1, "ward", "hit 80 dmg 11 x1"],
		# Power vs Balance: +3 (10 / 4 = 2.5, halves up). 10 + 8 + 3 - 1; 80 + 15 - 5.
		["dark", "shaman", "life_tap", 2, "ward", "hit 90 dmg 20 x1"],
		# An attack staff: profile None, Magic. 15 + 4 - 1; 100 - 5.
		["staff", "battle_medic", "harm", 2, "ward", "hit 95 dmg 18 x1"],
		# Effective against the Mounted Hakkapel (DEF 4): + 2 x 9. Standoff. 9 + 5 + 18 - 4.
		["effective", "sellsword", "sabre", 1, "hakkapel", "hit 75 dmg 28 x1"],
	]
	for row: Array in rows:
		var type_id: String = row[1]
		var weapon_id: String = row[2]
		var distance: int = row[3]
		var foe_type: String = row[4]
		var expected: String = row[5]
		var name: String = "forecast %s: %s's %s at %d" % [row[0], type_id, weapon_id, distance]
		var session: CombatSession = _session()
		var attacker: String = _place(session, type_id, PLAYER, 0, Vector2i(0, 0), weapon_id)
		var defender: String = _place(session, foe_type, ENEMY, -1, Vector2i(distance, 0), "")
		if attacker.is_empty() or defender.is_empty() or session.open_battle().is_rejected():
			_ok("%s: the battle loads" % [name], false)
			continue
		var forecast: CombatForecast.ExchangeForecast = _exchange(session, attacker, defender)
		if not forecast.is_legal:
			_ok("%s: legal" % [name], false, forecast.reason)
			continue
		_same(name, "hit %d dmg %d x%d" % [
			forecast.attacker.hit, forecast.attacker.damage, forecast.attacker.attacks_per_turn,
		], expected)


# Lifesteal pays out of the damage that reached HP, at range 2 where the Ward can't counter and
# with no bonus turn either way: damage, the heal, then the attacker's HP. Life Tap (Shaman at 2
# HP, max 17): all 20 to HP heals 20, capped at 17. Dark Sword (Sellsword at 5 HP): Power vs
# Balance +3, Magic: 12 + 5 + 3 - 1 = 19, half is 9.5, rounded half up to 10, to 15.
func _test_lifesteal() -> void:
	var rows: Array[Array] = [
		["shaman", "life_tap", 2, "20 20 17"], ["sellsword", "dark_sword", 5, "19 10 15"],
	]
	for row: Array in rows:
		var type_id: String = row[0]
		var weapon_id: String = row[1]
		var hp: int = row[2]
		var name: String = "lifesteal: %s" % [weapon_id]
		var session: CombatSession = _session()
		var attacker: String = _place(session, type_id, PLAYER, 0, Vector2i(0, 0), weapon_id)
		var defender: String = _place(session, "ward", ENEMY, -1, Vector2i(2, 0), "")
		if attacker.is_empty() or defender.is_empty() or session.open_battle().is_rejected():
			_ok("%s: the battle loads" % [name], false)
			continue
		session.state.set_hp(attacker, hp)
		var forecast: CombatForecast.ExchangeForecast = _exchange(session, attacker, defender)
		var outcome: CombatForecast.UnitOutcome = (
				null if not forecast.is_legal else forecast.attacker.outcome
		)
		var healed: int = 0
		for fact: CombatFact in forecast.facts:
			if fact.kind == CombatFact.Kind.HEALED and fact.actor_id == attacker:
				healed += fact.amount
		var expected: String = row[3]
		_same("%s: damage, heal, then the attacker's HP" % [name], "%d %d %d" % [
			forecast.attacker.damage, healed, -1 if outcome == null else outcome.hp_after,
		], expected)


# Everbloom from 5 tiles (range 1-10) on an Archer at 3 HP: it gives the Archer's maximum HP, not
# base 0 + the Battle Medic's 4 Might, and restores all that is missing. The maximum is read from
# the Archer's stats, so tuning its HP leaves this case alone.
func _test_everbloom() -> void:
	var session: CombatSession = _session()
	var medic: String = _place(session, "battle_medic", PLAYER, 0, Vector2i(0, 0), "everbloom")
	var archer: String = _place(session, "archer", PLAYER, 0, Vector2i(5, 0), "")
	if medic.is_empty() or archer.is_empty() or session.open_battle().is_rejected():
		_ok("everbloom: the battle loads", false)
		return
	var full_hp: int = session.stats(archer).get_int(CombatValue.Key.HP)
	session.state.set_hp(archer, 3)
	var forecast: CombatForecast.StaffForecast = CombatForecast.staff(
			session.engine, UnitTurnCommand.new(0, medic, STAFF, archer)
	)
	var restored: int = -1 if forecast.recipients.is_empty() else forecast.recipients[0].restored
	_same("everbloom: legal at 5, amount and HP restored", "%s %d %d" % [
		forecast.is_legal, roundi(forecast.amount), restored,
	], "true %d %d" % [full_hp, full_hp - 3])


# The Short Quiver on an Archer against an enemy Ward: every bow reaches 1-2, so 1 is legal and
# the Ward counters there, while 3 is out of range; without it the Simple Bow can't reach 1.
# Simple Bow at 1: 6 + 5 - 7 = 4 (Volley needs maximum range, now 2). Dragonslayer Bow (3-5) at
# 1: 18 + 5 - 7 = 16. Short Bow (already 1-2) at 1: 5 + 5 - 7 = 3.
func _test_short_quiver_attacks() -> void:
	var rows: Array[Array] = [
		["simple_bow", "", 1, "out of range"],
		["simple_bow", "short_quiver", 1, "dmg 4 counter true"],
		["simple_bow", "short_quiver", 2, "dmg 6 counter false"],
		["simple_bow", "short_quiver", 3, "out of range"],
		["dragonslayer_bow", "", 1, "out of range"],
		["dragonslayer_bow", "short_quiver", 1, "dmg 16 counter true"],
		["dragonslayer_bow", "short_quiver", 3, "out of range"],
		["short_bow", "short_quiver", 1, "dmg 3 counter true"],
	]
	for row: Array in rows:
		var bow: String = row[0]
		var quiver: String = row[1]
		var distance: int = row[2]
		var expected: String = row[3]
		var name: String = "short quiver: %s%s at %d" % [
			bow, "" if quiver.is_empty() else " with it", distance,
		]
		var session: CombatSession = _session()
		var archer: String = _place(session, "archer", PLAYER, 0, Vector2i(0, 0), bow, quiver)
		var ward: String = _place(session, "ward", ENEMY, -1, Vector2i(distance, 0), "")
		if archer.is_empty() or ward.is_empty() or session.open_battle().is_rejected():
			_ok("%s: the battle loads" % [name], false)
			continue
		var forecast: CombatForecast.ExchangeForecast = _exchange(session, archer, ward)
		var got: String = forecast.reason
		if forecast.is_legal:
			got = "dmg %d counter %s" % [forecast.attacker.damage, forecast.can_counter]
		_same(name, got, expected)


# Outside attacks the Short Quiver reads the same: the danger zone's (and so the move preview's)
# ranges, a stowed bow's range through ExchangeResolver.weapon_range(), and a lance it doesn't
# touch. An enemy Archer holds a Simple Bow with a Dragonslayer Bow stowed.
func _test_short_quiver_reads() -> void:
	var results: PackedStringArray = []
	for quiver: String in ["", "short_quiver"]:
		var session: CombatSession = _session()
		var archer: String = _place(
				session, "archer", ENEMY, -1, Vector2i(0, 0), "simple_bow", quiver,
				"dragonslayer_bow"
		)
		var lancer: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(4, 0), "", quiver)
		if archer.is_empty() or lancer.is_empty() or session.open_battle().is_rejected():
			_ok("short quiver reads: the battle loads", false)
			return
		var holder: CombatUnitState = session.state.unit(archer)
		var lance: CombatUnitState = session.state.unit(lancer)
		var held_before: String = holder.equipped_weapon_id
		results.append("held %s stowed %s danger %s lance %s" % [
			ExchangeResolver.weapon_range(session.engine, archer, holder.equipped_weapon_id),
			ExchangeResolver.weapon_range(session.engine, archer, holder.stowed_weapon_id),
			DangerZone.attack_ranges(session.engine, archer),
			ExchangeResolver.weapon_range(session.engine, lancer, lance.equipped_weapon_id),
		])
		_ok("short quiver reads: a stowed read changes nothing on the map", (
				session.state.unit(archer).equipped_weapon_id == held_before
				and session.engine.stats(archer).get_int(CombatValue.Key.RANGE_MAX)
				== (3 if quiver.is_empty() else 2)
		))
		# The unit detail panel's stowed line reads the same range (combat UI plan, UI12).
		var detail: UnitDetailViewModel = UnitDetailViewModel.build(session, archer)
		var shown: String = "none" if detail == null or detail.stowed == null else (
				detail.stowed.range_text()
		)
		_same("short quiver reads: the stowed line's range %s" % [
			"without" if quiver.is_empty() else "with",
		], shown, "3-5" if quiver.is_empty() else "1-2")
	_same("short quiver reads: without, then with", " | ".join(results), (
			"held (2, 3) stowed (3, 5) danger [(2, 3)] lance (1, 1)"
			+ " | held (1, 2) stowed (1, 2) danger [(1, 2)] lance (1, 1)"
	))


# Sanctuary (range 1-2) on an Archer 2 tiles away: it and every ally adjacent to it gain 3 + the
# Battle Medic's 4 Might; a Thief beside the Archer gains it, a Fighter 2 tiles past doesn't.
func _test_sanctuary() -> void:
	var session: CombatSession = _session()
	var medic: String = _place(session, "battle_medic", PLAYER, 0, Vector2i(0, 0), "sanctuary")
	var archer: String = _place(session, "archer", PLAYER, 0, Vector2i(2, 0), "")
	var thief: String = _place(session, "thief", PLAYER, 0, Vector2i(3, 0), "")
	var fighter: String = _place(session, "fighter", PLAYER, 0, Vector2i(5, 0), "")
	if (
			medic.is_empty() or archer.is_empty() or thief.is_empty() or fighter.is_empty()
			or session.open_battle().is_rejected()
	):
		_ok("sanctuary: the battle loads", false)
		return
	var forecast: CombatForecast.StaffForecast = CombatForecast.staff(
			session.engine, UnitTurnCommand.new(0, medic, STAFF, archer)
	)
	_same("sanctuary: Block given to the target and its neighbours", _gains(forecast), (
			"%s 7, %s 7" % [archer, thief]
	))


# Everwall (range 0, the user) gives 5 + 4 Might to every ally within 3 of the Battle Medic, but
# not to the Medic itself: an Archer 3 tiles away gains it, a Thief 4 away doesn't.
func _test_everwall() -> void:
	var session: CombatSession = _session()
	var medic: String = _place(session, "battle_medic", PLAYER, 0, Vector2i(0, 0), "everwall")
	var archer: String = _place(session, "archer", PLAYER, 0, Vector2i(3, 0), "")
	var thief: String = _place(session, "thief", PLAYER, 0, Vector2i(4, 0), "")
	if medic.is_empty() or archer.is_empty() or thief.is_empty():
		_ok("everwall: the battle loads", false)
		return
	if session.open_battle().is_rejected():
		_ok("everwall: the battle opens", false)
		return
	var forecast: CombatForecast.StaffForecast = CombatForecast.staff(
			session.engine, UnitTurnCommand.new(0, medic, STAFF, "")
	)
	_same("everwall: legal on the user, Block given", "%s %s %s" % [
		forecast.is_legal, forecast.target_id == medic, _gains(forecast),
	], "true true %s 9" % [archer])


# A Sanctuary and an Everbloom record keep their area and full heal through capture and JSON, so
# a saved or transferred battle plays the same (CombatState.WeaponStats.capture()).
func _test_records_saved() -> void:
	for row: Array in [["sanctuary", "adjacent_with_center", false], ["everbloom", "", true]]:
		var staff_id: String = row[0]
		var definition: StaffDefinition = _catalog.staff(staff_id)
		if definition == null:
			_ok("record %s: in the catalog" % [staff_id], false)
			continue
		var record: CombatState.WeaponStats = Loadout.weapon_record(definition, "item:1")
		record.area = (
				null if record.area_shape_id.is_empty()
				else CombatState.WeaponStats.staff_area(_catalog.shape(record.area_shape_id))
		)
		var text: String = JSON.stringify(record.capture())
		var parsed: Variant = JSON.parse_string(text)
		var back: CombatState.WeaponStats = (
				CombatState.WeaponStats.from_capture(parsed as Dictionary)
				if parsed is Dictionary else null
		)
		var shape_id: String = "" if back == null or back.area == null else back.area.shape.id
		_same("record %s: area and full heal after a save" % [row[0]], "%s %s %s" % [
			back != null, shape_id, back != null and back.full_heal,
		], "true %s %s" % [row[1], row[2]])
		_same("record %s: captures the same again" % [row[0]],
				"" if back == null else JSON.stringify(back.capture()), text)


# Version 1 weapon records, on a map and on a unit between maps, gain an empty area and no full
# heal; the rest of the data is untouched, and a later version refuses the migration.
func _test_version_1_migrates() -> void:
	var data: Dictionary = {
		"encounter": {"in_transit": [{"weapons": [{"id": "item:1"}]}]},
		"sessions": [{"combat_state": {"weapons": [{"id": "item:2"}], "turn": 3}}],
	}
	var section: CombatStateSection = CombatStateSection.new()
	var err: Error = section.migrate(data, 1)
	var moving: Dictionary = data["encounter"]["in_transit"][0]["weapons"][0]
	var placed: Dictionary = data["sessions"][0]["combat_state"]["weapons"][0]
	_same("migration: version 1 to %d" % [section.get_version()], "%s %s %s %s" % [
		error_string(err), JSON.stringify(moving), JSON.stringify(placed),
		data["sessions"][0]["combat_state"]["turn"],
	], "OK %s %s 3" % [
		JSON.stringify({"id": "item:1", "area_shape_id": "", "full_heal": false}),
		JSON.stringify({"id": "item:2", "area_shape_id": "", "full_heal": false}),
	])


# The units [param forecast] gave Block to, as "id amount", in the order it gave.
func _gains(forecast: CombatForecast.StaffForecast) -> String:
	var gains: PackedStringArray = []
	for recipient: CombatForecast.Recipient in forecast.recipients:
		gains.append("%s %d" % [recipient.unit_id, recipient.block_gained])
	return ", ".join(gains) if forecast.is_legal else forecast.reason


func _exchange(
		session: CombatSession, attacker: String, defender: String
) -> CombatForecast.ExchangeForecast:
	return CombatForecast.exchange(
			session.engine, UnitTurnCommand.new(0, attacker, ATTACK, defender)
	)


func _session() -> CombatSession:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "weapon_content"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for x: int in 8:
		layout.set_terrain(Vector2i(x, 0), plain)
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	return CombatSession.new(
			0, PackedInt32Array([0]), MapGrid.new(layout), LiveRolls.new(RngStream.new(SEED)), ids
	)


# Loads a new unit of [param type_id] holding [param weapon_id] (empty: its type's starting
# weapon), with [param equipment_id] and [param stowed_id] in its Pouch (empty for none), and
# places it on [param tile]; its id, or empty when it didn't load.
func _place(
		session: CombatSession,
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i,
		weapon_id: String,
		equipment_id: String = "",
		stowed_id: String = ""
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
	var held: String = unit_type.starting_weapon_id if weapon_id.is_empty() else weapon_id
	unit.weapon_id = _add_item(items, ids, held)
	unit.equipment_id = _add_item(items, ids, equipment_id)
	unit.pouch_id = _add_item(items, ids, stowed_id)
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


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
