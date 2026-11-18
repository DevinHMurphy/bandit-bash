# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     roster_enemy_cases.gd
# Author:
# Created:  November 13, 2026
# Modified: November 18, 2026
# ==============================================================================

extends RefCounted
## The roster's enemy cases for tests/content/run_all.gd, over the real [code]res://data/[/code]:
## the seven classes after M1 against enemy-roster.md (behavior, target rule, weapon, gear, stats
## and growths), their traits' text, the shared Javelin (Common) and the enemy-only Fangs and
## Shieldmace (Basic, never carried by a player unit), every pack against enemy-packs.md's lists,
## every class loaded through the loadout, and each trait in a battle: Backstab, Riposte, Braced
## (DEF from current Stance, and the Shieldmace's Standoff), Curse, Trample and Pack, and a killing
## blow still splashing and cursing as its forecast showed. Reports each case through the check
## callable it is given.
##
## The expected values are transcribed from the design docs, never read from the data, so a
## changed .tres fails here until the docs and this file agree. Battles roll with
## [ForecastRolls]: every hit lands, every crit fails.
##
## @tutorial(Enemy roster): docs/design/enemy-roster.md
## @tutorial(Enemy packs): docs/design/enemy-packs.md

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK

# A preloaded script used as a type: its give_rune() registers catalog runes.
const CombatWorld = preload("res://tests/combat/combat_world.gd")

# enemy-roster.md's Classes table. Columns: HP, MGT, SPD, DEF, RES, MOV, CON, Stance, then growths
# HP, MGT, SPD, DEF, RES.
const ROSTER: Dictionary[String, Array] = {
	"cutthroat": [21, 5, 5, 3, 2, 5, 8, 1, 90, 40, 45, 22, 20],
	"duelist": [16, 4, 9, 3, 1, 5, 5, 2, 75, 30, 50, 15, 20],
	"shieldbearer": [25, 1, 2, 1, 1, 4, 14, 3, 70, 25, 28, 45, 10],
	"hexer": [17, 8, 3, 3, 4, 5, 12, 1, 75, 65, 22, 18, 30],
	"warcaller": [22, 6, 3, 2, 4, 5, 12, 2, 65, 45, 29, 18, 22],
	"raider": [21, 6, 4, 5, 1, 7, 12, 2, 85, 40, 27, 25, 10],
	"hound": [20, 4, 6, 1, 0, 7, 10, 1, 70, 30, 45, 5, 8],
}

# The stat value keys in ROSTER's order.
const STAT_KEYS: Array[int] = [
	CombatValue.Key.HP,
	CombatValue.Key.MGT,
	CombatValue.Key.SPD,
	CombatValue.Key.DEF,
	CombatValue.Key.RES,
	CombatValue.Key.MOVEMENT,
	CombatValue.Key.CON,
]

# The growth stats in ROSTER's order.
const GROWTH_STATS: Array[int] = [
	CombatValue.Stat.HP,
	CombatValue.Stat.MGT,
	CombatValue.Stat.SPD,
	CombatValue.Stat.DEF,
	CombatValue.Stat.RES,
]

# Reviewed effect text of each class's trait, one line per effect. The Warcaller's War Horn is
# also its signature move.
const TEXT: Dictionary[String, Array] = {
	"cutthroat": ["While the opponent is Exposed: +2 Attack"],
	"duelist": ["Before Combat, while it is the defender: gain 3 Block"],
	"shieldbearer": ["Always: +2 DEF × this unit's current Stance"],
	"hexer": [
		"Hit dealt: remove 1 Stance from the other unit and adjacent units of the other unit, "
		+ "friend or foe",
	],
	"warcaller": [
		"Every 2nd Phase Start this combat: give this unit and units within 2 tiles, friend or foe "
		+ "+2 Attack until the end of the next phase",
	],
	"raider": [
		"Hit dealt, while this unit moved 3+ tiles this turn: deal 3 splash damage to adjacent "
		+ "units of the other unit, friend or foe",
	],
	"hound": ["Always: +2 Attack × the number of adjacent allies"],
}

# The Raider's, the Hound's and the Shieldbearer's weapons. Columns: Dmg, AtkX, profile, range min,
# range max, Hit, Crit, CritX, Weight, weapon type, rarity. The Javelin is weapons.md's Pilum,
# renamed and shared; the Fangs and the Shieldmace are enemy-roster.md's enemy-only weapons.
const NEW_WEAPONS: Dictionary[String, Array] = {
	"javelin": [
		5, 1, WeaponTriangle.Profile.BALANCE, 1, 2, 80, 0, 3.0, 9, "lance",
		ItemDefinition.Rarity.COMMON,
	],
	"fangs": [
		3, 2, WeaponTriangle.Profile.NIMBLE, 1, 1, 90, 0, 2.0, 0, "gauntlets",
		ItemDefinition.Rarity.BASIC,
	],
	"shieldmace": [
		4, 1, WeaponTriangle.Profile.NONE, 1, 1, 75, 0, 3.0, 12, "sword",
		ItemDefinition.Rarity.BASIC,
	],
}

# The enemy-only weapons: Basic, and carried by no player unit type or starting army.
const ENEMY_ONLY: Array[String] = ["fangs", "shieldmace"]

# Braced's DEF on the Shieldbearer at Stance 3, 2, 1 and 0: base 1, the Iron Shield's +2, and +2 per
# point of current Stance (enemy-roster.md).
const BRACED_DEF: String = "9, 7, 5, 3"

const BASIC: PackDefinition.Pool = PackDefinition.Pool.BASIC
const HARD: PackDefinition.Pool = PackDefinition.Pool.HARD
const KEY: PackDefinition.Pool = PackDefinition.Pool.KEY
const NONE: PackDefinition.Pool = PackDefinition.Pool.NONE

# enemy-packs.md's Pack lists, every pack in the catalog: pool, the units at steps 1, 2 and 3 in
# setup order, the leader class and the mini-boss. The M1 Pack is from M1 (enemy-roster.md).
const PACKS: Dictionary[String, Array] = {
	"shield_and_bolt": [BASIC,
		"shieldbearer, crossbowman, crossbowman",
		"shieldbearer, crossbowman, crossbowman, crossbowman",
		"shieldbearer, shieldbearer, crossbowman, crossbowman, crossbowman",
		"shieldbearer", ""],
	"hex_and_knife": [BASIC,
		"hexer, cutthroat, cutthroat",
		"hexer, cutthroat, cutthroat, cutthroat",
		"hexer, cutthroat, cutthroat, cutthroat, crossbowman",
		"hexer", ""],
	"field_hospital": [BASIC,
		"hedge_healer, brute, shieldbearer",
		"hedge_healer, brute, brute, shieldbearer",
		"hedge_healer, brute, brute, shieldbearer, crossbowman",
		"brute", ""],
	"war_band": [BASIC,
		"warcaller, brute, hound",
		"warcaller, brute, hound, hound",
		"warcaller, brute, brute, hound, hound",
		"warcaller", ""],
	"hunting_party": [BASIC,
		"raider, hound, hound",
		"raider, hound, hound, hound",
		"raider, raider, hound, hound, hound",
		"raider", ""],
	"shield_and_bolt_hard": [HARD,
		"shieldbearer, crossbowman, hedge_healer",
		"shieldbearer, crossbowman, crossbowman, hedge_healer",
		"shieldbearer, shieldbearer, crossbowman, crossbowman, hedge_healer",
		"shieldbearer", ""],
	"hex_and_knife_hard": [HARD,
		"hexer, cutthroat, duelist",
		"hexer, cutthroat, cutthroat, duelist",
		"hexer, cutthroat, cutthroat, duelist, raider",
		"hexer", ""],
	"field_hospital_hard": [HARD,
		"hedge_healer, brute, brute",
		"hedge_healer, brute, brute, shieldbearer",
		"hedge_healer, hedge_healer, brute, brute, shieldbearer",
		"brute", ""],
	"war_band_hard": [HARD,
		"warcaller, raider, hound",
		"warcaller, brute, raider, hound",
		"warcaller, brute, brute, raider, hound",
		"warcaller", ""],
	"hunting_party_hard": [HARD,
		"raider, warcaller, hound",
		"raider, warcaller, hound, hound",
		"raider, raider, warcaller, hound, hound",
		"raider", ""],
	"sellswords": [HARD,
		"duelist, crossbowman, hedge_healer",
		"duelist, crossbowman, crossbowman, hedge_healer",
		"duelist, duelist, crossbowman, crossbowman, hedge_healer",
		"duelist", ""],
	"brigand_captain_escort": [KEY,
		"brute, hedge_healer, duelist",
		"brute, hedge_healer, duelist, shieldbearer",
		"brute, hedge_healer, duelist, shieldbearer, crossbowman",
		"", "brigand_captain"],
	"bloodhound_escort": [KEY,
		"hound, hound, raider",
		"hound, hound, hound, raider",
		"hound, hound, hound, raider, warcaller",
		"", "bloodhound"],
	"hex_matron_escort": [KEY,
		"cutthroat, cutthroat, duelist",
		"cutthroat, cutthroat, cutthroat, duelist",
		"cutthroat, cutthroat, cutthroat, duelist, crossbowman",
		"", "hex_matron"],
	"iron_wall_escort": [KEY,
		"crossbowman, crossbowman, duelist",
		"crossbowman, crossbowman, duelist, hedge_healer",
		"crossbowman, crossbowman, crossbowman, duelist, hedge_healer",
		"", "iron_wall"],
	"m1_pack": [NONE,
		"brute, crossbowman, hedge_healer",
		"brute, crossbowman, hedge_healer",
		"brute, crossbowman, hedge_healer",
		"", ""],
}

# Units a drawn pack fields at steps 1, 2 and 3 (game-vision.md, Run structure).
const STEP_SIZES: Array[int] = [3, 4, 5]

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_test_classes()
	_test_stats()
	_test_text_snapshots()
	_test_new_weapons()
	_test_packs()
	_test_classes_load()
	_test_backstab()
	_test_riposte()
	_test_braced_forecast()
	_test_braced_mitigated_hit()
	_test_braced_stance_loss()
	_test_shieldmace_standoff()
	_test_iron_wall_base()
	_test_curse()
	_test_trample()
	_test_pack_trait()
	_test_killing_blow_splash()


# enemy-roster.md's Classes and Traits tables, with the player's simple weapons (P05 question 13),
# the shared Javelin, the enemy-only Fangs, and the first clause of each target rule.
func _test_classes() -> void:
	var never_unit_types: bool = true
	for class_id: String in ROSTER:
		never_unit_types = never_unit_types and _catalog.unit_type(class_id) == null
	_ok("roster enemies: enemy classes, never unit types", never_unit_types)
	_same("roster enemies: weapons, movement, tags, gear, trait, behavior", _describe(), "; ".join([
		"cutthroat dagger MOBILE [] simple_dagger - Backstab AGGRESSIVE",
		"duelist sword MOBILE [] simple_sword - Riposte GUARD",
		"shieldbearer sword HEAVY [armored] shieldmace iron_shield Braced GUARD",
		"hexer dark DEFAULT [] simple_dark - Curse SKIRMISHER",
		"warcaller lance DEFAULT [] simple_lance - War Horn SUPPORT",
		"raider lance MOUNTED [mounted] javelin - Trample SKIRMISHER",
		"hound gauntlets MOBILE [] fangs - Pack AGGRESSIVE",
	]))
	_same("roster enemies: target rules and their text", _describe_rules(), "; ".join([
		"cutthroat exposed_then_lowest_hp \"Exposed foes first, then lowest HP\"",
		"duelist holds_ground \"Holds its ground\"",
		"shieldbearer back_line_ally \"Stays next to its pack's back-line ally\"",
		"hexer most_cursed \"The foe whose curse catches the most player units\"",
		"warcaller most_allies_near \"Stays within 2 tiles of the most allies\"",
		"raider back_line_foes \"Any foe it can defeat this turn, splash included\"",
		"hound pack_lowest_hp \"Lowest HP\"",
	]))


func _test_stats() -> void:
	for class_id: String in ROSTER:
		var unit: UnitInstance = UnitInstance.new("enemy:1", class_id)
		var row: Array = ROSTER[class_id]
		var sheet: StatSheet = unit.stats(_catalog)
		var stats: PackedStringArray = []
		var expected: PackedStringArray = []
		for column: int in STAT_KEYS.size():
			stats.append(str(sheet.get_int(STAT_KEYS[column])))
			expected.append(str(row[column]))
		stats.append(str(sheet.get_int(CombatValue.Key.STANCE_MAX)))
		expected.append(str(row[7]))
		_same("%s: base stats and Stance (enemy-roster.md)" % [class_id], "/".join(stats), (
				"/".join(expected)
		))
		var growths: PackedStringArray = []
		var expected_growths: PackedStringArray = []
		for column: int in GROWTH_STATS.size():
			growths.append(str(unit.growth(_catalog, GROWTH_STATS[column])))
			expected_growths.append(str(row[8 + column]))
		_same("%s: growths" % [class_id], "/".join(growths), "/".join(expected_growths))


# Generated text is canonical (content catalog plan, Approach); these are its reviewed snapshots.
func _test_text_snapshots() -> void:
	for class_id: String in TEXT:
		var enemy_class: EnemyClassDefinition = _catalog.enemy_class(class_id)
		if enemy_class == null:
			_ok("text %s: in the catalog" % [class_id], false)
			continue
		var expected: PackedStringArray = PackedStringArray(TEXT[class_id])
		_same("text %s" % [class_id], " | ".join(enemy_class.describe()), " | ".join(expected))


# The Javelin (a lance), the Fangs (natural, like gauntlets) and the Shieldmace (a sword outside
# the triangle) with their sources' numbers, all physical. The Javelin is Common, so it is sold and
# found like any lance; the enemy-only weapons are Basic, so no pool, shop or reward ever offers
# them, and no player unit type or starting army carries them.
func _test_new_weapons() -> void:
	for weapon_id: String in NEW_WEAPONS:
		var weapon: WeaponDefinition = _catalog.weapon(weapon_id)
		if weapon == null:
			_ok("%s: in the catalog" % [weapon_id], false)
			continue
		var row: Array = NEW_WEAPONS[weapon_id]
		var actual: Array = [
			weapon.damage, weapon.atk_x, weapon.profile, weapon.range_min, weapon.range_max,
			weapon.hit, weapon.crit, weapon.crit_x, weapon.weight, weapon.weapon_type,
			weapon.rarity,
		]
		_same("%s: its source's numbers and rarity" % [weapon_id], str(actual), str(row))
		var is_enemy_only: bool = ENEMY_ONLY.has(weapon_id)
		_ok("%s: %s, physical" % [weapon_id, "never sold" if is_enemy_only else "sold"], (
				Prices.is_sellable(weapon.rarity) != is_enemy_only
				and weapon.damage_type == CombatFact.DamageType.PHYSICAL
		))
	var carriers: PackedStringArray = []
	for resource: Resource in _catalog.all_of(EffectCatalog.Kind.UNIT_TYPE):
		var unit_type: UnitTypeDefinition = resource
		if ENEMY_ONLY.has(unit_type.starting_weapon_id):
			carriers.append(unit_type.id)
	for resource: Resource in _catalog.all_of(EffectCatalog.Kind.FACTION):
		var faction: FactionDefinition = resource
		for gear: PackedStringArray in faction.starting_gear:
			for item_id: String in gear:
				if ENEMY_ONLY.has(item_id):
					carriers.append("%s %s" % [faction.id, item_id])
	_ok("enemy-only weapons: no player unit type or starting army carries one", (
			carriers.is_empty()
	), str(carriers))


# Every pack against enemy-packs.md's lists: its pool, its units at each step, its leader and its
# mini-boss; every drawn pack at its step's size; and no pack in the catalog the lists lack.
func _test_packs() -> void:
	for pack_id: String in PACKS:
		var expected: Array = PACKS[pack_id]
		var pack: PackDefinition = _catalog.pack(pack_id)
		if pack == null:
			_ok("pack %s: in the catalog" % [pack_id], false)
			continue
		_same("pack %s: its pool" % [pack_id], str(PackDefinition.Pool.find_key(pack.pool)), (
				str(PackDefinition.Pool.find_key(expected[0]))
		))
		var sizes_ok: bool = true
		for step: int in range(1, 4):
			var units: PackedStringArray = pack.units(step)
			_same("pack %s: its units at step %d, in order" % [pack_id, step], (
					", ".join(units)
			), str(expected[step]))
			sizes_ok = sizes_ok and (not pack.is_drawn() or units.size() == STEP_SIZES[step - 1])
		_ok("pack %s: fields 3, 4 and 5 by step" % [pack_id], sizes_ok)
		_same("pack %s: its leader and mini-boss" % [pack_id], "%s / %s" % [
			pack.leader_class_id, pack.mini_boss_id,
		], "%s / %s" % [expected[4], expected[5]])
	var unlisted: PackedStringArray = []
	for resource: Resource in _catalog.all_of(EffectCatalog.Kind.PACK):
		var pack: PackDefinition = resource as PackDefinition
		if pack != null and not PACKS.has(pack.id):
			unlisted.append(pack.id)
	_ok("packs: the catalog holds exactly the listed packs", (
			unlisted.is_empty() and _catalog.all_of(EffectCatalog.Kind.PACK).size() == PACKS.size()
	), str(unlisted))


# Every new class through the loadout as setup builds it: no problems, its weapon (and the
# Shieldbearer's Iron Shield), no use limit, and its full-Stance DEF in battle: 1, the shield's +2
# and Braced's +6.
func _test_classes_load() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var problems: PackedStringArray = []
	var weapons: PackedStringArray = []
	var limited: PackedStringArray = []
	for class_id: String in ROSTER:
		var loaded: Loadout.LoadedUnit = _load(class_id, ENEMY, -1, ids)
		problems.append_array(loaded.problems)
		if not loaded.is_loaded():
			problems.append("%s didn't load" % [class_id])
			continue
		var labels: PackedStringArray = []
		for weapon: CombatState.WeaponStats in loaded.weapons:
			labels.append(weapon.label)
		weapons.append("%s: %s" % [class_id, ", ".join(labels)])
		for instance: EffectInstance in loaded.effects:
			if instance.owner.kind == EffectOwner.Kind.ITEM and instance.definition.charges > 0:
				limited.append("%s %s" % [class_id, instance.definition.id])
	_ok("roster enemies: every class loads at level 1 without problems", problems.is_empty(), (
			str(problems)
	))
	_same("roster enemies: each unit's weapon records", "; ".join(weapons), "; ".join([
		"cutthroat: Simple Dagger", "duelist: Simple Sword", "shieldbearer: Shieldmace",
		"hexer: Shade", "warcaller: Simple Lance", "raider: Javelin", "hound: Fangs",
	]))
	_ok("roster enemies: no weapon use is limited", limited.is_empty(), str(limited))

	var session: CombatSession = _battle(_plain(2, 1), ids)
	var bearer: String = _place(session, "shieldbearer", ENEMY, -1, Vector2i(0, 0))
	_same("shieldbearer: 9 DEF at full Stance in battle", (
			"" if bearer.is_empty() else str(session.stats(bearer).get_int(CombatValue.Key.DEF))
	), "9")


# The Cutthroat's hit on an Archer deals 2 more once the Archer is Exposed.
func _test_backstab() -> void:
	var dealt: PackedStringArray = []
	for stance: int in [2, 0]:
		var session: CombatSession = _battle(_plain(3, 1), InstanceIdAllocator.new())
		var cutthroat: String = _place(session, "cutthroat", ENEMY, -1, Vector2i(0, 0))
		var archer: String = _place(session, "archer", PLAYER, 0, Vector2i(1, 0))
		var facts: Array[CombatFact] = _enemy_attack(
				session, cutthroat, archer, [], func(at: CombatSession) -> void:
					at.state.set_stance(archer, stance)
		)
		dealt.append(str(_first_hit(facts, archer)))
	var gap: int = dealt[1].to_int() - dealt[0].to_int()
	_same("backstab: +2 damage against an Exposed foe", str(gap), "2")


# The Duelist gains 3 Block before combat while it defends, and none when it attacks.
func _test_riposte() -> void:
	var session: CombatSession = _battle(_plain(3, 1), InstanceIdAllocator.new())
	var duelist: String = _place(session, "duelist", ENEMY, -1, Vector2i(0, 0))
	var hakkapel: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(1, 0))
	session.open_battle()
	session.submit(UnitTurnCommand.new(0, hakkapel, ATTACK, duelist))
	var defended: CombatSession.FactBatch = session.resolve_next()
	var as_defender: int = _block_from(session, defended.facts, "riposte")

	var other: CombatSession = _battle(_plain(3, 1), InstanceIdAllocator.new())
	var attacker: String = _place(other, "duelist", ENEMY, -1, Vector2i(0, 0))
	var target: String = _place(other, "hakkapel", PLAYER, 0, Vector2i(1, 0))
	var facts: Array[CombatFact] = _enemy_attack(other, attacker, target, [])
	_same("riposte: 3 Block defending, none attacking", "%d, %d" % [
		as_defender, _block_from(other, facts, "riposte"),
	], "3, 0")


# A Hakkapel's forecast against the Shieldbearer shows Braced's DEF falling 2 per Stance lost: the
# Mitigation stage of its first hit at Stance 3, 2, 1 and 0.
func _test_braced_forecast() -> void:
	var session: CombatSession = _battle(_plain(2, 1), InstanceIdAllocator.new())
	var hakkapel: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
	var bearer: String = _place(session, "shieldbearer", ENEMY, -1, Vector2i(1, 0))
	if hakkapel.is_empty() or bearer.is_empty():
		return
	session.open_battle()
	var shown: PackedStringArray = []
	for stance: int in [3, 2, 1, 0]:
		session.state.set_stance(bearer, stance)
		var command: UnitTurnCommand = UnitTurnCommand.new(0, hakkapel, ATTACK, bearer)
		var found: CombatForecast.ExchangeForecast = CombatForecast.exchange(
				session.engine, command, ForecastRolls.new()
		)
		var side: CombatForecast.SideForecast = null if found == null else found.attacker
		var is_shown: bool = (
				side != null and side.breakdown != null and side.breakdown.mitigation != null
		)
		shown.append(str(roundi(side.breakdown.mitigation.total)) if is_shown else "-")
	_same("braced: the forecast shows its DEF at Stance 3, 2, 1 and 0", ", ".join(shown), (
			BRACED_DEF
	))


# At full Stance a hit Braced's DEF fully mitigates costs no Stance (game-vision.md, Stance and
# Exposure): the Simple Lance's 7 plus 2 Might meets 9 DEF. With 4 Might the first hit deals 2 and
# takes a Stance, and the DEF after the exchange follows the Stance left.
func _test_braced_mitigated_hit() -> void:
	var results: PackedStringArray = []
	var follows: bool = false
	for might: float in [2.0, 4.0]:
		var session: CombatSession = _battle(_plain(2, 1), InstanceIdAllocator.new())
		var hakkapel: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(0, 0))
		var bearer: String = _place(session, "shieldbearer", ENEMY, -1, Vector2i(1, 0))
		if hakkapel.is_empty() or bearer.is_empty():
			return
		session.engine.set_base(hakkapel, CombatValue.Key.MGT, might)
		session.open_battle()
		session.submit(UnitTurnCommand.new(0, hakkapel, ATTACK, bearer))
		var batch: CombatSession.FactBatch = session.resolve_next()
		var facts: Array[CombatFact] = []
		if batch != null:
			facts.assign(batch.facts)
		var stance: int = session.state.get_stance(bearer)
		var first: int = maxi(_first_hit(facts, bearer), 0)
		var def: int = session.stats(bearer).get_int(CombatValue.Key.DEF)
		results.append("first hit %d, Stance %d, DEF %d" % [first, stance, def])
		follows = first == 2 and stance < 3 and def == 3 + 2 * stance
	_same("braced: a fully mitigated hit at full Stance costs no Stance", results[0], (
			"first hit 0, Stance 3, DEF 9"
	))
	_ok("braced: a hit that lands takes Stance, and DEF follows it", follows, results[1])


# Stance lost without damage strips the DEF too: the Shatter rune takes 2 Stance (DEF 9 to 5), and
# the enemy Phase Start refresh brings both back. The Hexer's Curse on a foe beside its own
# Shieldbearer takes 1 from it (DEF 7).
func _test_braced_stance_loss() -> void:
	var session: CombatSession = _battle(_plain(4, 1), InstanceIdAllocator.new())
	var bearer: String = _place(session, "shieldbearer", ENEMY, -1, Vector2i(3, 0))
	_place(session, "archer", PLAYER, 0, Vector2i(0, 0))
	if bearer.is_empty():
		return
	CombatWorld.give_rune(session.engine, 0, "rune:shatter", "shatter")
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(_at: CombatSession) -> Command:
		return null
	)
	session.open_battle()
	var steps: PackedStringArray = [_stance_and_def(session, bearer)]
	session.submit(CastRuneCommand.new(0, "rune:shatter", bearer))
	session.resolve_next()
	steps.append(_stance_and_def(session, bearer))
	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	steps.append(_stance_and_def(session, bearer))
	_same("braced: Shatter takes 2 Stance and 4 DEF; the refresh brings both back", (
			" > ".join(steps)
	), "Stance 3 DEF 9 > Stance 1 DEF 5 > Stance 3 DEF 9")

	var hex: CombatSession = _battle(_plain(5, 3), InstanceIdAllocator.new())
	var hexer: String = _place(hex, "hexer", ENEMY, -1, Vector2i(0, 1))
	var target: String = _place(hex, "hakkapel", PLAYER, 0, Vector2i(2, 1))
	var cursed: String = _place(hex, "shieldbearer", ENEMY, -1, Vector2i(3, 1))
	if cursed.is_empty():
		return
	_enemy_attack(hex, hexer, target, [])
	_same("braced: its own Hexer's Curse takes 1 Stance and 2 DEF", (
			_stance_and_def(hex, cursed)
	), "Stance 2 DEF 7")


# The Shieldmace sits outside the triangle: against a sword (Nimble), a lance (Balance) and an axe
# (Power) both sides get a Standoff, in the triangle's rule and in the forecast's damage stages.
func _test_shieldmace_standoff() -> void:
	var shieldmace: WeaponDefinition = _catalog.weapon("shieldmace")
	if shieldmace == null:
		_ok("shieldmace: in the catalog", false)
		return
	var rows: PackedStringArray = []
	for attacker_type: String in ["sellsword", "hakkapel", "fighter"]:
		var session: CombatSession = _battle(_plain(2, 1), InstanceIdAllocator.new())
		var attacker: String = _place(session, attacker_type, PLAYER, 0, Vector2i(0, 0))
		var bearer: String = _place(session, "shieldbearer", ENEMY, -1, Vector2i(1, 0))
		if attacker.is_empty() or bearer.is_empty():
			return
		session.open_battle()
		var held: CombatState.WeaponStats = session.state.weapon(
				session.state.equipped_weapon_id(attacker)
		)
		if held == null:
			rows.append("%s unarmed" % [attacker_type])
			continue
		var command: UnitTurnCommand = UnitTurnCommand.new(0, attacker, ATTACK, bearer)
		var found: CombatForecast.ExchangeForecast = CombatForecast.exchange(
				session.engine, command, ForecastRolls.new()
		)
		rows.append("%s %s/%s, triangle %s/%s" % [
			WeaponTriangle.Profile.find_key(held.profile),
			_matchup_name(WeaponTriangle.matchup(held.profile, shieldmace.profile)),
			_matchup_name(WeaponTriangle.matchup(shieldmace.profile, held.profile)),
			_triangle_of(null if found == null else found.attacker),
			_triangle_of(null if found == null else found.defender),
		])
	_same("shieldmace: a Standoff against Nimble, Balance and Power, both ways", "; ".join(rows), (
			"; ".join([
				"NIMBLE STANDOFF/STANDOFF, triangle 0/0",
				"BALANCE STANDOFF/STANDOFF, triangle 0/0",
				"POWER STANDOFF/STANDOFF, triangle 0/0",
			])
	))


# The Iron Wall is the Shieldbearer plus Fortify: the same base, weapon, gear and Braced, so its
# DEF falls the same way.
func _test_iron_wall_base() -> void:
	var wall: EnemyClassDefinition = _catalog.enemy_class("iron_wall")
	var base: EnemyClassDefinition = _catalog.enemy_class("shieldbearer")
	if wall == null or base == null:
		_ok("iron wall: it and its base class in the catalog", false)
		return
	_same("iron wall: the Shieldbearer's base, weapon, gear and Braced", _base_of(wall), (
			_base_of(base)
	))
	var session: CombatSession = _battle(_plain(2, 1), InstanceIdAllocator.new())
	var iron_wall: String = _place(session, "iron_wall", ENEMY, -1, Vector2i(0, 0))
	if iron_wall.is_empty():
		return
	var shown: PackedStringArray = []
	for stance: int in [3, 2, 1, 0]:
		session.state.set_stance(iron_wall, stance)
		shown.append(_def_of(session, iron_wall))
	_same("iron wall: its DEF at Stance 3, 2, 1 and 0", ", ".join(shown), BRACED_DEF)


# From 2 tiles, the Hexer's hit on a Hakkapel (which can't answer at that range) costs 1 Stance to
# it, the Archer beside it and the Hexer's own Cutthroat beside it. From beside a Battle Medic
# (whose staff never counters), the Hexer loses 1 too; the Medic's 1 Stance already went to the
# hit, so the curse finds none on it. The curse resolves after the exchange; on a target the hit
# defeats it catches nobody (reported with EN6).
func _test_curse() -> void:
	var lost: PackedStringArray = []
	var boards: Array = [
		[Vector2i(0, 1), "hakkapel", "archer"],
		[Vector2i(1, 1), "battle_medic", "hakkapel"],
	]
	for board: Array in boards:
		var hexer_tile: Vector2i = board[0]
		var session: CombatSession = _battle(_plain(5, 4), InstanceIdAllocator.new())
		var hexer: String = _place(session, "hexer", ENEMY, -1, hexer_tile)
		var target: String = _place(session, str(board[1]), PLAYER, 0, Vector2i(2, 1))
		_place(session, str(board[2]), PLAYER, 0, Vector2i(3, 1))
		_place(session, "cutthroat", ENEMY, -1, Vector2i(2, 0))
		var facts: Array[CombatFact] = _enemy_attack(session, hexer, target, [])
		lost.append(_gained(session, facts, "curse", CombatFact.Kind.STANCE_CHANGED))
	_same("curse: the target and every unit beside it lose 1 Stance, friend or foe", lost[0], (
			"archer -1, cutthroat -1, hakkapel -1"
	))
	_same("curse: the Hexer too when it strikes from beside the target", lost[1], (
			"cutthroat -1, hakkapel -1, hexer -1"
	))


# The Raider's Javelin hit on a Hakkapel after riding 3 tiles splashes 3 on the Archer and its own
# Hound beside the target; after 2 tiles, nothing; riding in beside the target, itself too.
func _test_trample() -> void:
	var rides: Array = [
		[Vector2i(0, 0), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]],
		[Vector2i(1, 0), [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]],
		[Vector2i(0, 0), [
			Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		]],
	]
	var splashed: PackedStringArray = []
	for ride: Array in rides:
		var start: Vector2i = ride[0]
		var path: Array[Vector2i] = []
		path.assign(ride[1] as Array)
		var session: CombatSession = _battle(_plain(8, 3), InstanceIdAllocator.new())
		var raider: String = _place(session, "raider", ENEMY, -1, start)
		var hakkapel: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(5, 0))
		_place(session, "archer", PLAYER, 0, Vector2i(6, 0))
		_place(session, "hound", ENEMY, -1, Vector2i(5, 1))
		var facts: Array[CombatFact] = _enemy_attack(session, raider, hakkapel, path)
		var hits: PackedStringArray = []
		for fact: CombatFact in facts:
			var is_splash: bool = (
					fact.kind == CombatFact.Kind.DAMAGE_TAKEN
					and fact.source == CombatFact.Source.SPLASH
			)
			if is_splash:
				hits.append("%s %d" % [session.state.unit_type_of(fact.actor_id), fact.amount])
		hits.sort()
		splashed.append(", ".join(hits))
	_same("trample: 3 splash beside the target after riding 3 tiles", splashed[0], (
			"archer 3, hound 3"
	))
	_same("trample: none after riding 2", splashed[1], "")
	_same("trample: the Raider too, beside its target", splashed[2], (
			"archer 3, hound 3, raider 3"
	))


# The Hound's Attack rises by 2 for each ally beside it, read live: its hit on an Archer deals 2
# more with each, and moving an ally away takes the bonus off at once.
func _test_pack_trait() -> void:
	var dealt: PackedStringArray = []
	for allies: int in [0, 2]:
		var session: CombatSession = _battle(_plain(4, 3), InstanceIdAllocator.new())
		var hound: String = _place(session, "hound", ENEMY, -1, Vector2i(1, 1))
		var archer: String = _place(session, "archer", PLAYER, 0, Vector2i(2, 1))
		if allies > 0:
			_place(session, "hound", ENEMY, -1, Vector2i(1, 0))
			_place(session, "hound", ENEMY, -1, Vector2i(0, 1))
		var facts: Array[CombatFact] = _enemy_attack(session, hound, archer, [])
		dealt.append(str(_first_hit(facts, archer)))
	var gap: int = dealt[1].to_int() - dealt[0].to_int()
	_same("pack: +2 damage per adjacent ally", str(gap), "4")

	var board: CombatSession = _battle(_plain(4, 3), InstanceIdAllocator.new())
	var leader: String = _place(board, "hound", ENEMY, -1, Vector2i(1, 1))
	var beside: String = _place(board, "hound", ENEMY, -1, Vector2i(1, 0))
	var attack: Array[int] = [board.stats(leader).get_int(DamageStage.Key.ATTACK)]
	board.state.move_unit(beside, Vector2i(3, 2))
	attack.append(board.stats(leader).get_int(DamageStage.Key.ATTACK))
	_same("pack: read live, the bonus leaves with the ally", str(attack[0] - attack[1]), "2")


# A hit that defeats its target still splashes or curses around the tile it stood on, and the
# forecast taken just before shows the same: the Raider's Trample on a 1 HP Hakkapel hits the Archer
# and the Hound beside it for 3; the Hexer's Curse on it takes 1 Stance from the Archer and the
# Cutthroat beside it.
func _test_killing_blow_splash() -> void:
	var raid: CombatSession = _battle(_plain(8, 3), InstanceIdAllocator.new())
	var raider: String = _place(raid, "raider", ENEMY, -1, Vector2i(0, 0))
	var fallen: String = _place(raid, "hakkapel", PLAYER, 0, Vector2i(5, 0))
	var archer: String = _place(raid, "archer", PLAYER, 0, Vector2i(6, 0))
	var hound: String = _place(raid, "hound", ENEMY, -1, Vector2i(5, 1))
	raid.state.set_hp(fallen, 1)
	var ride: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var foreseen: Array[CombatForecast.ExchangeForecast] = []
	var foresee_raid: Callable = func(at: CombatSession) -> void:
		foreseen.append(_forecast(at, raider, fallen, ride))
	var facts: Array[CombatFact] = _enemy_attack(raid, raider, fallen, ride, foresee_raid)
	var splash: PackedStringArray = []
	for fact: CombatFact in facts:
		var is_splash: bool = (
				fact.kind == CombatFact.Kind.DAMAGE_TAKEN
				and fact.source == CombatFact.Source.SPLASH
		)
		if is_splash:
			splash.append("%s %d" % [raid.state.unit_type_of(fact.actor_id), fact.amount])
	splash.sort()
	_same("killing blow: Trample still splashes around the defeated target", (
			"%s; target on the map: %s" % [", ".join(splash), raid.state.has_unit(fallen)]
	), "archer 3, hound 3; target on the map: false")
	var hp_foreseen: bool = not foreseen.is_empty()
	for unit_id: String in [archer, hound]:
		var outcome: CombatForecast.UnitOutcome = _outcome(foreseen, unit_id)
		hp_foreseen = (
				hp_foreseen and outcome != null
				and outcome.hp_after == raid.state.get_hp(unit_id)
		)
	var target_outcome: CombatForecast.UnitOutcome = _outcome(foreseen, fallen)
	_ok("killing blow: the forecast showed the Trample and the kill", (
			hp_foreseen and target_outcome != null and target_outcome.is_defeated
	))

	var hex: CombatSession = _battle(_plain(5, 4), InstanceIdAllocator.new())
	var hexer: String = _place(hex, "hexer", ENEMY, -1, Vector2i(0, 1))
	var cursed: String = _place(hex, "hakkapel", PLAYER, 0, Vector2i(2, 1))
	var beside: String = _place(hex, "archer", PLAYER, 0, Vector2i(3, 1))
	var ally: String = _place(hex, "cutthroat", ENEMY, -1, Vector2i(2, 0))
	hex.state.set_hp(cursed, 1)
	var no_walk: Array[Vector2i] = []
	var hexed: Array[CombatForecast.ExchangeForecast] = []
	var foresee_hex: Callable = func(at: CombatSession) -> void:
		hexed.append(_forecast(at, hexer, cursed, no_walk))
	var hex_facts: Array[CombatFact] = _enemy_attack(hex, hexer, cursed, no_walk, foresee_hex)
	_same("killing blow: Curse still takes Stance around the defeated target", (
			"%s; target on the map: %s" % [
				_gained(hex, hex_facts, "curse", CombatFact.Kind.STANCE_CHANGED),
				hex.state.has_unit(cursed),
			]
	), "archer -1, cutthroat -1; target on the map: false")
	var stance_foreseen: bool = not hexed.is_empty()
	for unit_id: String in [beside, ally]:
		var outcome: CombatForecast.UnitOutcome = _outcome(hexed, unit_id)
		stance_foreseen = (
				stance_foreseen and outcome != null
				and outcome.stance_after == outcome.stance_before - 1
		)
	_ok("killing blow: the forecast showed the Curse", stance_foreseen)


# attacker's attack on target along path on session's board as the forecast panel previews it.
static func _forecast(
		session: CombatSession, attacker: String, target: String, path: Array[Vector2i]
) -> CombatForecast.ExchangeForecast:
	var command: UnitTurnCommand = UnitTurnCommand.new(-1, attacker, ATTACK, target, path)
	return CombatForecast.exchange(session.engine, command, ForecastRolls.new(), false)


# unit_id's outcome in the first forecast of foreseen; null when there is none.
static func _outcome(
		foreseen: Array[CombatForecast.ExchangeForecast], unit_id: String
) -> CombatForecast.UnitOutcome:
	if foreseen.is_empty() or foreseen[0] == null:
		return null
	for outcome: CombatForecast.UnitOutcome in foreseen[0].units:
		if outcome.unit_id == unit_id:
			return outcome
	return null


# The facts of the enemy phase in which attacker attacks target along path (its own tile first;
# empty to stay), after prepare runs on the session as that phase asks for its command.
func _enemy_attack(
		session: CombatSession,
		attacker: String,
		target: String,
		path: Array[Vector2i],
		prepare: Callable = Callable()
) -> Array[CombatFact]:
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(at: CombatSession) -> Command:
		if at.state.unit(attacker).has_acted:
			return null
		if prepare.is_valid():
			prepare.call(at)
		return UnitTurnCommand.new(-1, attacker, ATTACK, target, path)
	)
	session.open_battle()
	session.submit(EndTurnCommand.new(0))
	var turn: CombatSession.FactBatch = session.resolve_next()
	var facts: Array[CombatFact] = []
	if turn != null:
		facts.assign(turn.facts)
	return facts


# The damage of the first non-splash hit target took in facts; -1 for none.
static func _first_hit(facts: Array[CombatFact], target: String) -> int:
	for fact: CombatFact in facts:
		var is_hit: bool = (
				fact.kind == CombatFact.Kind.DAMAGE_TAKEN
				and fact.actor_id == target
				and fact.source != CombatFact.Source.SPLASH
		)
		if is_hit:
			return fact.amount
	return -1


# unit_id's DEF as the stat read API gives it now.
static func _def_of(session: CombatSession, unit_id: String) -> String:
	return str(session.stats(unit_id).get_int(CombatValue.Key.DEF))


# unit_id's current Stance and DEF, as "Stance S DEF D".
static func _stance_and_def(session: CombatSession, unit_id: String) -> String:
	return "Stance %d DEF %s" % [session.state.get_stance(unit_id), _def_of(session, unit_id)]


# A triangle result's enum name.
static func _matchup_name(result: WhileMatchupCondition.Matchup) -> String:
	return str(WhileMatchupCondition.Matchup.find_key(result))


# The triangle damage change in side's first landed hit; "-" when none landed.
static func _triangle_of(side: CombatForecast.SideForecast) -> String:
	if side == null or side.breakdown == null:
		return "-"
	return str(roundi(side.breakdown.triangle))


# What an enemy class shares with the class it is built on: base stats, growths, Stance, trait,
# weapon, gear, weapon types and its first effect's text.
static func _base_of(enemy_class: EnemyClassDefinition) -> String:
	var lines: PackedStringArray = enemy_class.describe()
	return "%s %s %d %s %s %s %s %s" % [
		str(enemy_class.base_stats), str(enemy_class.growths), enemy_class.stance,
		enemy_class.trait_name, enemy_class.starting_weapon_id,
		enemy_class.starting_equipment_id, "/".join(enemy_class.weapon_types),
		"" if lines.is_empty() else lines[0],
	]


# The Block the effect named effect_id gave in facts, summed.
static func _block_from(session: CombatSession, facts: Array[CombatFact], effect_id: String) -> int:
	var total: int = 0
	for fact: CombatFact in facts:
		if fact.kind == CombatFact.Kind.BLOCK_GAINED and _from(session, fact, effect_id):
			total += fact.amount
	return total


# Each unit's change of kind from the effect named effect_id in facts, as "type amount", sorted.
static func _gained(
		session: CombatSession, facts: Array[CombatFact], effect_id: String, kind: CombatFact.Kind
) -> String:
	var parts: PackedStringArray = []
	for fact: CombatFact in facts:
		if fact.kind == kind and _from(session, fact, effect_id):
			parts.append("%s %d" % [session.state.unit_type_of(fact.actor_id), fact.amount])
	parts.sort()
	return ", ".join(parts)


# Whether fact came from an instance of the effect named effect_id.
static func _from(session: CombatSession, fact: CombatFact, effect_id: String) -> bool:
	var instance: EffectInstance = session.engine.get_instance(fact.source_effect_id)
	return instance != null and instance.definition.id == effect_id


func _battle(grid: MapGrid, ids: InstanceIdAllocator) -> CombatSession:
	return CombatSession.new(0, PackedInt32Array([0]), grid, ForecastRolls.new(), ids)


# Loads a new unit of type_id (an enemy class or a unit type) at level 1 with its starting weapon
# and, for an enemy class, its starting equipment.
func _load(
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		ids: InstanceIdAllocator
) -> Loadout.LoadedUnit:
	var unit_id: String = (
			ids.next_enemy_id(type_id) if side == ENEMY else ids.next_unit_id(type_id)
	)
	var unit: UnitInstance = UnitInstance.new(unit_id, type_id)
	var items: Dictionary[String, ItemInstance] = {}
	var definition: UnitTypeDefinition = unit.definition(_catalog)
	if definition != null and not definition.starting_weapon_id.is_empty():
		var weapon: ItemInstance = ItemInstance.new(
				ids.next_item_id(definition.starting_weapon_id), definition.starting_weapon_id
		)
		items[weapon.instance_id] = weapon
		unit.weapon_id = weapon.instance_id
	var enemy_class: EnemyClassDefinition = definition as EnemyClassDefinition
	if enemy_class != null and not enemy_class.starting_equipment_id.is_empty():
		var gear: ItemInstance = ItemInstance.new(
				ids.next_item_id(enemy_class.starting_equipment_id),
				enemy_class.starting_equipment_id
		)
		items[gear.instance_id] = gear
		unit.equipment_id = gear.instance_id
	return Loadout.load_unit(_catalog, unit, items, side, seat, ids)


# Loads and places a unit of type_id on tile; its id, or empty when it didn't load cleanly or
# wasn't placed.
func _place(
		session: CombatSession,
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i
) -> String:
	var loaded: Loadout.LoadedUnit = _load(type_id, side, seat, session.ids)
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		_ok("%s: loads for the battle" % [type_id], false, str(loaded.problems))
		return ""
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = tile
	return loaded.state.id if session.add_unit(loaded.state, loaded.bases) else ""


func _plain(width: int, height: int) -> MapGrid:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "roster_enemies"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for y: int in height:
		for x: int in width:
			layout.set_terrain(Vector2i(x, y), plain)
	return MapGrid.new(layout)


func _describe() -> String:
	var parts: PackedStringArray = []
	for class_id: String in ROSTER:
		var enemy_class: EnemyClassDefinition = _catalog.enemy_class(class_id)
		if enemy_class == null:
			parts.append("%s missing" % [class_id])
			continue
		parts.append("%s %s %s [%s] %s %s %s %s" % [
			class_id,
			"/".join(enemy_class.weapon_types),
			CombatGrid.MovementType.find_key(enemy_class.movement_type),
			", ".join(enemy_class.tags),
			enemy_class.starting_weapon_id,
			"-" if enemy_class.starting_equipment_id.is_empty()
					else enemy_class.starting_equipment_id,
			enemy_class.trait_name,
			EnemyClassDefinition.Behavior.find_key(enemy_class.behavior),
		])
	return "; ".join(parts)


func _describe_rules() -> String:
	var parts: PackedStringArray = []
	for class_id: String in ROSTER:
		var enemy_class: EnemyClassDefinition = _catalog.enemy_class(class_id)
		if enemy_class == null:
			parts.append("%s missing" % [class_id])
			continue
		parts.append("%s %s \"%s\"" % [
			class_id, enemy_class.target_rule_id, enemy_class.target_rule_text,
		])
	return "; ".join(parts)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
