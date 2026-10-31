# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     m1_content_cases.gd
# Author:
# Created:  October 30, 2026
# Modified: October 31, 2026
# ==============================================================================

extends RefCounted
## The M1 content cases for tests/content/run_all.gd, over the real [code]res://data/[/code]: the
## Mercenary faction and the army [method StartingArmy.build] makes of it, each unit type's stats
## against unit-roster.md, the Simple weapons, Shelter, Minor Heal, the Potion and the Guard Tonic
## against game-vision.md and items.md, the Potion used once per map over two battles, Triage
## taking an ally past its Stance maximum until its next Phase Start, effect text snapshots of
## every trait, item and Iron Heart, and two forecasts of Simple weapons against hand-computed
## numbers. Reports each case through the check callable it is given.
##
## The expected values are transcribed from the design docs, never read from the data, so a
## changed .tres fails here until the docs and this file agree.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const STAFF: UnitTurnCommand.Action = UnitTurnCommand.Action.STAFF

const NIMBLE: WeaponTriangle.Profile = WeaponTriangle.Profile.NIMBLE
const BALANCE: WeaponTriangle.Profile = WeaponTriangle.Profile.BALANCE
const POWER: WeaponTriangle.Profile = WeaponTriangle.Profile.POWER
const NO_PROFILE: WeaponTriangle.Profile = WeaponTriangle.Profile.NONE
const PHYSICAL: CombatFact.DamageType = CombatFact.DamageType.PHYSICAL
const MAGIC: CombatFact.DamageType = CombatFact.DamageType.MAGIC

# Any fixed seed: the forecasts draw nothing from it.
const SEED: int = 0xC7_0003

# unit-roster.md's MVP roster and Commander tables. Columns: HP, MGT, SPD, DEF, RES, MOV, CON,
# Stance, then growths HP, MGT, SPD, DEF, RES.
const ROSTER: Dictionary[String, Array] = {
	"drengr": [24, 5, 6, 3, 2, 5, 13, 3, 85, 55, 40, 35, 15],
	"archer": [13, 5, 8, 0, 0, 5, 6, 1, 55, 38, 58, 8, 17],
	"battle_medic": [16, 4, 5, 1, 1, 6, 7, 1, 65, 35, 35, 18, 18],
	"hakkapel": [22, 4, 5, 4, 0, 7, 10, 2, 70, 30, 40, 20, 12],
}

# unit-roster.md's Upgrades table: stat gains as HP, MGT, SPD, DEF, RES.
const UPGRADES: Dictionary[String, Array] = {
	"archer": [0, 2, 1, 0, 0],
	"battle_medic": [0, 1, 0, 1, 1],
	"hakkapel": [0, 2, 0, 1, 0],
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

# game-vision.md's Simple weapon table. Columns: weapon type, profile, damage, AtkX, damage type,
# range min, range max, Hit, crit, CritX, weight, effective against.
const SIMPLE_WEAPONS: Dictionary[String, Array] = {
	"simple_sword": ["sword", NIMBLE, 5, 1, PHYSICAL, 1, 1, 80, 0, 3.0, 8, []],
	"simple_axe": ["axe", POWER, 10, 1, PHYSICAL, 1, 1, 65, 0, 3.0, 15, []],
	"simple_lance": ["lance", BALANCE, 7, 1, PHYSICAL, 1, 1, 80, 0, 3.0, 12, []],
	"simple_bow": ["bow", NO_PROFILE, 6, 1, PHYSICAL, 2, 3, 100, 0, 3.0, 5, ["flier"]],
	"simple_gauntlets": ["gauntlets", NO_PROFILE, 2, 2, PHYSICAL, 1, 1, 100, 0, 2.0, 1, []],
	"simple_dagger": ["dagger", NIMBLE, 2, 1, PHYSICAL, 1, 2, 100, 0, 5.0, 3, []],
	"simple_anima": ["anima", BALANCE, 5, 1, MAGIC, 1, 2, 80, 0, 3.0, 1, []],
	"simple_holy": ["holy", NIMBLE, 4, 1, MAGIC, 1, 2, 100, 0, 3.0, 6, []],
	"simple_dark": ["dark", POWER, 7, 1, MAGIC, 1, 2, 80, 0, 3.0, 8, []],
}

# weapons.md's Staves table. Columns: staff kind, base amount, uses per map (0: unlimited), range
# min, range max, weight, rarity.
const STAVES: Dictionary[String, Array] = {
	"shelter": ["block", 3, 0, 1, 1, 0, ItemDefinition.Rarity.BASIC],
	"minor_heal": ["heal", 5, 3, 1, 1, 0, ItemDefinition.Rarity.COMMON],
}

# items.md's Consumables table. Columns: use kind, amount, uses, rarity.
const CONSUMABLES: Dictionary[String, Array] = {
	"potion": ["heal", 8, 1, ItemDefinition.Rarity.COMMON],
	"guard_tonic": ["block", 6, 1, ItemDefinition.Rarity.COMMON],
}

# Reviewed effect text, one line per effect, in each list's order.
const TEXT: Dictionary[String, Array] = {
	"drengr": ["Phase Start, while no ally is closer to an enemy than this unit: gain 3 Block"],
	"archer": ["Hit dealt, while at maximum range: +2 Attack stage for that hit"],
	"archer+": ["Hit dealt, while at maximum range: +4 Attack stage for that hit"],
	"battle_medic": ["Used a staff on an ally: give the other unit 1 Stance, even above its maximum"],
	"battle_medic+": ["Used a staff on an ally: give the other unit 2 Stance, even above its maximum"],
	"hakkapel": ["While this unit moved 4+ tiles this turn: +2 Attack stage"],
	"hakkapel+": ["While this unit moved 4+ tiles this turn: +4 Attack stage"],
	"iron_heart": ["Every 7th Attack made by Your Unit this combat: that attack gains lifesteal"],
	"potion": ["Always: heal the target for 8"],
	"guard_tonic": ["Always: give the target 6 Block"],
	"shelter": [],
	"minor_heal": [],
}

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_test_faction()
	_test_starting_army()
	_test_starting_army_unknown_faction()
	_test_starting_army_loads()
	_test_unit_types()
	_test_unit_stats()
	_test_upgraded_stats()
	_test_simple_weapons()
	_test_staves()
	_test_consumables()
	_test_potion_per_map()
	_test_triage_past_maximum()
	_test_iron_heart()
	_test_text_snapshots()
	_test_bow_forecast()
	_test_axe_forecast()


func _test_faction() -> void:
	var faction: FactionDefinition = _catalog.faction("mercenary")
	_ok("m1 faction: the Mercenary is in the catalog", faction != null)
	if faction == null:
		return
	_ok("m1 faction: led by the Drengr", faction.commander_id == "drengr")
	_same(
			"m1 faction: starts with the Hakkapel, Archer and Battle Medic",
			", ".join(faction.starting_unit_type_ids),
			"hakkapel, archer, battle_medic"
	)
	_ok("m1 faction: max army size 4, starting at 100 gold", (
			faction.max_army_size == 4 and faction.starting_gold == 100
	), "%d, %d" % [faction.max_army_size, faction.starting_gold])


func _test_starting_army() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var army: StartingArmy = StartingArmy.build(_catalog, "mercenary", ids)
	_ok("starting army: no problems", army.problems.is_empty(), str(army.problems))
	_same("starting army: the commander first, then the faction's order", _describe(army), (
			"drengr [simple_axe, -, -]; hakkapel [simple_lance, -, potion]; "
			+ "archer [simple_bow, -, guard_tonic]; battle_medic [shelter, -, minor_heal]"
	))
	_ok("starting army: the commander's id and heirloom", (
			not army.units.is_empty()
			and army.commander_id == army.units[0].instance_id
			and army.heirloom_ids == PackedStringArray(["iron_heart"])
	), "%s %s" % [army.commander_id, army.heirloom_ids])
	var fresh: bool = true
	for unit: UnitInstance in army.units:
		fresh = (
				fresh and unit.level == 1 and unit.hp == UnitInstance.FULL_HP
				and unit.prefix_id.is_empty() and not unit.is_upgraded
		)
	_ok("starting army: level 1, full HP, no prefix, not upgraded", fresh)
	var minted: Dictionary[String, bool] = {}
	for unit: UnitInstance in army.units:
		minted[unit.instance_id] = true
	for item_id: String in army.items:
		minted[item_id] = true
	_ok("starting army: every id minted once by the allocator", (
			minted.size() == army.units.size() + army.items.size()
			and ids.is_known(army.commander_id)
	), str(minted.keys()))


func _test_starting_army_unknown_faction() -> void:
	var army: StartingArmy = StartingArmy.build(
			_catalog, "no_such_faction", InstanceIdAllocator.new()
	)
	_ok("starting army: an unknown faction builds nothing and says so", (
			army.units.is_empty() and army.items.is_empty() and army.problems.size() == 1
	), str(army.problems))


# Each starting unit through the loadout: no problems, its weapon records and its slots.
func _test_starting_army_loads() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var army: StartingArmy = StartingArmy.build(_catalog, "mercenary", ids)
	var problems: PackedStringArray = []
	var weapons: PackedStringArray = []
	for unit: UnitInstance in army.units:
		var loaded: Loadout.LoadedUnit = Loadout.load_unit(
				_catalog, unit, army.items, PLAYER, 0, ids
		)
		problems.append_array(loaded.problems)
		if not loaded.is_loaded():
			problems.append("%s didn't load" % [unit.unit_type_id])
			continue
		var labels: PackedStringArray = []
		for weapon: CombatState.WeaponStats in loaded.weapons:
			labels.append(weapon.label)
		weapons.append("%s: %s" % [unit.unit_type_id, ", ".join(labels)])
	_ok("starting army: every unit loads without problems", problems.is_empty(), str(problems))
	_same("starting army: each unit's weapon records", "; ".join(weapons), (
			"drengr: Simple Axe; hakkapel: Simple Lance; archer: Simple Bow; "
			+ "battle_medic: Shelter, Minor Heal"
	))


func _test_unit_types() -> void:
	var drengr: UnitTypeDefinition = _catalog.commander("drengr")
	_ok("drengr: a commander with Iron Heart, never upgraded", (
			drengr != null
			and drengr.is_commander
			and drengr.commander_heirloom_id == "iron_heart"
			and drengr.upgraded_effects.is_empty()
			and drengr.upgrade_stat_gains.is_empty()
	))
	_same("unit types: weapons, movement, tags, role, starting weapon, trait", _describe_types(), (
			"drengr axe/sword DEFAULT [] - simple_axe Vanguard; "
			+ "archer bow DEFAULT [] bow simple_bow Volley; "
			+ "battle_medic dagger/staff MOBILE [] support shelter Triage; "
			+ "hakkapel lance/sword MOUNTED [mounted] mounted simple_lance Charge"
	))
	var big: PackedStringArray = []
	for type_id: String in UPGRADES:
		var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
		if (
				unit_type == null
				or unit_type.grants_sidearm()
				or unit_type.upgrade_changes_movement()
				or not unit_type.upgrade_tags.is_empty()
		):
			big.append(type_id)
	_ok("unit types: none of the three has a big upgrade", big.is_empty(), str(big))


func _test_unit_stats() -> void:
	for type_id: String in ROSTER:
		var unit: UnitInstance = UnitInstance.new("unit:1", type_id)
		var row: Array = ROSTER[type_id]
		var sheet: StatSheet = unit.stats(_catalog)
		var stats: PackedStringArray = []
		var expected: PackedStringArray = []
		for column: int in STAT_KEYS.size():
			stats.append(str(sheet.get_int(STAT_KEYS[column])))
			expected.append(str(row[column]))
		stats.append(str(sheet.get_int(CombatValue.Key.STANCE_MAX)))
		expected.append(str(row[7]))
		_same("%s: base stats and Stance (unit-roster.md)" % [type_id], "/".join(stats), (
				"/".join(expected)
		))
		var growths: PackedStringArray = []
		var expected_growths: PackedStringArray = []
		for column: int in GROWTH_STATS.size():
			growths.append(str(unit.growth(_catalog, GROWTH_STATS[column])))
			expected_growths.append(str(row[8 + column]))
		growths.append(str(unit.growth(_catalog, CombatValue.Stat.MOV)))
		growths.append(str(unit.growth(_catalog, CombatValue.Stat.CON)))
		expected_growths.append_array(["0", "0"])
		_same("%s: growths, none for MOV and CON" % [type_id], "/".join(growths), (
				"/".join(expected_growths)
		))


func _test_upgraded_stats() -> void:
	for type_id: String in UPGRADES:
		var unit: UnitInstance = UnitInstance.new("unit:1", type_id)
		unit.is_upgraded = true
		var sheet: StatSheet = unit.stats(_catalog)
		var gains: Array = UPGRADES[type_id]
		var stats: PackedStringArray = []
		var expected: PackedStringArray = []
		for column: int in gains.size():
			stats.append(str(sheet.get_int(STAT_KEYS[column])))
			var base: int = ROSTER[type_id][column]
			var gain: int = gains[column]
			expected.append(str(base + gain))
		_same("%s+: stats with the upgrade's gains" % [type_id], "/".join(stats), (
				"/".join(expected)
		))


func _test_simple_weapons() -> void:
	for weapon_id: String in SIMPLE_WEAPONS:
		var weapon: WeaponDefinition = _catalog.weapon(weapon_id)
		if weapon == null or weapon is StaffDefinition:
			_ok("%s: a weapon in the catalog" % [weapon_id], false)
			continue
		var row: Array = SIMPLE_WEAPONS[weapon_id]
		var actual: Array = [
			weapon.weapon_type, weapon.profile, weapon.damage, weapon.atk_x, weapon.damage_type,
			weapon.range_min, weapon.range_max, weapon.hit, weapon.crit, weapon.crit_x,
			weapon.weight, Array(weapon.effective_against),
		]
		_same("%s: the vision's numbers" % [weapon_id], str(actual), str(row))
		_ok("%s: Basic, scaling with Might x1, no effects" % [weapon_id], (
				weapon.rarity == ItemDefinition.Rarity.BASIC
				and weapon.scaling_stat == CombatValue.Stat.MGT
				and is_equal_approx(weapon.scaling_modifier, 1.0)
				and weapon.effects.is_empty()
		))


func _test_staves() -> void:
	for staff_id: String in STAVES:
		var staff: StaffDefinition = _catalog.staff(staff_id)
		if staff == null:
			_ok("%s: a staff in the catalog" % [staff_id], false)
			continue
		var actual: Array = [
			staff.staff_kind, staff.base_amount, staff.uses, staff.range_min, staff.range_max,
			staff.weight, staff.rarity,
		]
		_same("%s: weapons.md's numbers" % [staff_id], str(actual), str(STAVES[staff_id]))
		_ok("%s: a staff covering its target only" % [staff_id], (
				staff.weapon_type == "staff" and staff.area_shape_id.is_empty()
		))


func _test_consumables() -> void:
	for item_id: String in CONSUMABLES:
		var consumable: ConsumableDefinition = _catalog.consumable(item_id)
		if consumable == null:
			_ok("%s: a consumable in the catalog" % [item_id], false)
			continue
		var actual: Array = [
			consumable.use_kind, consumable.amount, consumable.uses, consumable.rarity,
		]
		_same("%s: items.md's numbers" % [item_id], str(actual), str(CONSUMABLES[item_id]))
		var use: EffectDefinition = (
				consumable.effects[0] if consumable.effects.size() == 1 else null
		)
		_ok("%s: one use effect counting nothing, uses per map, weightless" % [item_id], (
				use != null
				and use.trigger == EffectTerms.Trigger.ALWAYS
				and use.charges == 0
				and consumable.uses_lane == EffectTerms.Lane.COMBAT
				and consumable.weight == 0
		))


# The real Potion in the same Hakkapel's Pouch over two battles, one run's ids: one use per map
# (items.md), refilled by the next battle's loadout, and never leaving the Pouch.
func _test_potion_per_map() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var potion: ItemInstance = ItemInstance.new(ids.next_item_id("potion"), "potion")
	var unit: UnitInstance = UnitInstance.new(ids.next_unit_id("hakkapel"), "hakkapel")
	unit.pouch_id = potion.instance_id
	var items: Dictionary[String, ItemInstance] = {potion.instance_id: potion}
	var who: String = unit.instance_id
	for battle: int in [1, 2]:
		var loaded: Loadout.LoadedUnit = Loadout.load_unit(_catalog, unit, items, PLAYER, 0, ids)
		var session: CombatSession = _pouch_battle(loaded, ids)
		if session == null:
			return
		session.state.set_hp(who, 10)
		session.engine.begin_step()
		var first: ItemUseResolver.Result = ItemUseResolver.resolve(
				session.engine, session.state, who, who, potion.instance_id
		)
		_ok("potion, battle %d: heals 8 and stays in the Pouch" % [battle], (
				first.is_legal
				and not first.is_consumed
				and session.state.get_hp(who) == 18
				and session.state.unit(who).pouch_item_id == potion.instance_id
		), first.reason)
		var second: String = ItemUseResolver.check(
				session.engine, session.state, who, who, potion.instance_id
		)
		_same("potion, battle %d: no second use this map" % [battle], second, "no uses left")
		loaded.write_back()
		_ok("potion, battle %d: per-map uses leave nothing on the item" % [battle], (
				potion.charges.is_empty() and potion.counters.is_empty()
		), "%s %s" % [potion.charges, potion.counters])


func _test_iron_heart() -> void:
	var heart: HeirloomDefinition = _catalog.heirloom("iron_heart")
	_ok("iron heart: a commander heirloom scoped Your Unit, not unique", (
			heart != null
			and heart.tier == ContentIds.HEIRLOOM_COMMANDER
			and heart.effects.size() == 1
			and heart.effects[0].scope == EffectTerms.Scope.YOUR_UNIT
			and not heart.has_effect_tag(EffectDefinition.Tag.UNIQUE)
	))


# Generated text is canonical (content catalog plan, Approach); these are its reviewed snapshots.
func _test_text_snapshots() -> void:
	for key: String in TEXT:
		var type_id: String = key.trim_suffix("+")
		var texts: PackedStringArray = []
		var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
		if unit_type != null and key.ends_with("+"):
			for effect: EffectDefinition in unit_type.upgraded_effects:
				texts.append(effect.describe())
		else:
			var carrier: EffectCarrierDefinition = (
					_catalog.definition(type_id) as EffectCarrierDefinition
			)
			if carrier == null:
				_ok("text %s: in the catalog" % [key], false)
				continue
			texts = carrier.describe()
		var expected: PackedStringArray = PackedStringArray(TEXT[key])
		_same("text %s" % [key], " | ".join(texts), " | ".join(expected))


# The Archer's Simple Bow against an enemy Hakkapel on Plain, at range 2 and at range 3 (Volley).
# Hit: 100 - 5 Plain avoid; no triangle (the bow has no profile). Damage: 6 + 5 MGT - 4 DEF = 7,
# +2 at maximum range. Attack Speed 8 against 5 - (12 - 10) = 3: a gap of 5 gives one bonus turn,
# and a lance can't counter at range 2 or 3, so two hits land on HP 22.
func _test_bow_forecast() -> void:
	for distance: int in [2, 3]:
		var damage: int = 7 if distance == 2 else 9
		var forecast: CombatForecast.ExchangeForecast = _forecast(
				"archer", "hakkapel", Vector2i(distance, 0)
		)
		if forecast == null:
			return
		var defender: CombatForecast.UnitOutcome = forecast.defender.outcome
		_same("bow forecast at range %d: Hit, damage, turns, HP after" % [distance], (
				"%d %d %d/%d %s %d %d" % [
					forecast.attacker.hit,
					forecast.attacker.damage,
					forecast.attacker.turns,
					forecast.defender.turns,
					forecast.can_counter,
					forecast.attacks.size(),
					-1 if defender == null else defender.hp_after,
				]
		), "95 %d 2/0 false 2 %d" % [damage, 22 - 2 * damage])


# The Drengr's Simple Axe (Power) against an enemy Hakkapel's Simple Lance (Balance), adjacent on
# Plain: Advantage. Drengr Hit 65 + 15 - 5 = 75; damage 10 + 5 MGT + round(10 / 4) = 18, - 4 DEF =
# 14. Hakkapel Hit 80 - 15 - 5 = 60; damage 7 + 4 MGT - round(7 / 4) = 9, - 3 DEF = 6, of which
# Vanguard's 3 Block (Phase Start, no ally nearer an enemy) takes 3. Attack Speed 6 - (15 - 13) = 4
# against 3: no bonus turn.
func _test_axe_forecast() -> void:
	var forecast: CombatForecast.ExchangeForecast = _forecast(
			"drengr", "hakkapel", Vector2i(1, 0)
	)
	if forecast == null:
		return
	var attacker: CombatForecast.UnitOutcome = forecast.attacker.outcome
	var defender: CombatForecast.UnitOutcome = forecast.defender.outcome
	_same("axe forecast: Hit and damage each way", "%d %d / %d %d" % [
		forecast.attacker.hit, forecast.attacker.damage,
		forecast.defender.hit, forecast.defender.damage,
	], "75 14 / 60 6")
	_same("axe forecast: turn order", ", ".join(forecast.turn_order), "%s, %s" % [
		forecast.actor_id, forecast.target_id,
	])
	_same("axe forecast: HP and Block after", "%d %d / %d" % [
		-1 if attacker == null else attacker.hp_after,
		-1 if attacker == null else attacker.block_after,
		-1 if defender == null else defender.hp_after,
	], "21 0 / 8")


# A battle on a row of Plain with the player's [param attacker_type] at (0, 0) and an enemy
# [param defender_type] at [param defender_tile], both loaded from the real data with their
# starting weapons, then the attacker's forecast against it.
func _forecast(
		attacker_type: String, defender_type: String, defender_tile: Vector2i
) -> CombatForecast.ExchangeForecast:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = CombatSession.new(
			0, PackedInt32Array([0]), _plain_row(5), LiveRolls.new(RngStream.new(SEED)), ids
	)
	var attacker_id: String = _place(
			session, attacker_type, PLAYER, 0, Vector2i(0, 0), ids.next_unit_id(attacker_type)
	)
	var defender_id: String = _place(
			session, defender_type, ENEMY, -1, defender_tile, ids.next_enemy_id(defender_type)
	)
	if attacker_id.is_empty() or defender_id.is_empty():
		_ok("forecast %s vs %s: both units load" % [attacker_type, defender_type], false)
		return null
	var opened: CombatSession.FactBatch = session.open_battle()
	if opened.is_rejected():
		_ok("forecast: the battle opens", false, opened.rejected_reason)
		return null
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			session.engine, UnitTurnCommand.new(0, attacker_id, ATTACK, defender_id)
	)
	_ok("forecast %s vs %s: legal" % [attacker_type, defender_type], forecast.is_legal, (
			forecast.reason
	))
	return forecast if forecast.is_legal else null


# Loads a new unit of [param type_id] with its type's starting weapon, upgraded when
# [param is_upgraded], and places it; its id, or empty when it didn't load.
func _place(
		session: CombatSession,
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i,
		unit_id: String,
		is_upgraded: bool = false
) -> String:
	var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
	if unit_type == null:
		return ""
	var weapon: ItemInstance = ItemInstance.new(
			session.ids.next_item_id(unit_type.starting_weapon_id), unit_type.starting_weapon_id
	)
	var unit: UnitInstance = UnitInstance.new(unit_id, type_id)
	unit.weapon_id = weapon.instance_id
	unit.is_upgraded = is_upgraded
	var items: Dictionary[String, ItemInstance] = {weapon.instance_id: weapon}
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			_catalog, unit, items, side, seat, session.ids
	)
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		_ok("%s: loads for the forecast" % [type_id], false, str(loaded.problems))
		return ""
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = tile
	return unit_id if session.add_unit(loaded.state, loaded.bases) else ""


# The real Battle Medic's Shelter on an Archer at full Stance (maximum 1; Triage +1, Triage+ +2,
# past the maximum), with hits landing: the forecast shows it and equals execution; the enemy
# Phase Start leaves it; an adjacent enemy Hakkapel's one hit (11 damage against Shelter's 7 or 8
# Block, so real damage) takes 1 of the extra and doesn't expose it; the player's next Phase Start
# sets it back to 1. The bow can't counter at range 1; the lance's Attack Speed (3) can't double.
func _test_triage_past_maximum() -> void:
	for is_upgraded: bool in [false, true]:
		var trait_name: String = "triage+" if is_upgraded else "triage"
		var gain: int = 2 if is_upgraded else 1
		var ids: InstanceIdAllocator = InstanceIdAllocator.new()
		var session: CombatSession = CombatSession.new(
				0, PackedInt32Array([0]), _plain_row(5), ForecastRolls.new(), ids
		)
		var medic: String = _place(
				session, "battle_medic", PLAYER, 0, Vector2i(0, 0), ids.next_unit_id("medic"),
				is_upgraded
		)
		var archer: String = _place(
				session, "archer", PLAYER, 0, Vector2i(1, 0), ids.next_unit_id("archer")
		)
		var enemy: String = _place(
				session, "hakkapel", ENEMY, -1, Vector2i(2, 0), ids.next_enemy_id("hakkapel")
		)
		if medic.is_empty() or archer.is_empty() or enemy.is_empty():
			_ok("%s: the battle loads" % [trait_name], false)
			continue
		# The archer's Stance each time the enemy is asked for a command: before and after its hit.
		var seen: Array[int] = []
		session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(at: CombatSession) -> Command:
			seen.append(at.state.get_stance(archer))
			if at.state.unit(enemy).has_acted:
				return null
			return UnitTurnCommand.new(-1, enemy, ATTACK, archer)
		)
		session.open_battle()

		var command: UnitTurnCommand = UnitTurnCommand.new(0, medic, STAFF, archer)
		var forecast: CombatForecast.StaffForecast = CombatForecast.staff(session.engine, command)
		var shown: CombatForecast.UnitOutcome = forecast.unit(archer)
		_ok("%s: the forecast shows Stance past the maximum" % [trait_name], (
				shown != null and shown.stance_before == 1 and shown.stance_after == 1 + gain
		))
		command.based_on_seq = forecast.based_on_seq
		session.submit(command)
		var used: CombatSession.FactBatch = session.resolve_next()
		_same(
				"%s: the forecast equals execution" % [trait_name],
				"\n".join(_fact_lines(forecast.facts)),
				"\n".join(_fact_lines(used.facts))
		)
		_ok("%s: the ally's Stance is its maximum + %d" % [trait_name, gain], (
				session.state.get_stance(archer) == 1 + gain
		), str(session.state.get_stance(archer)))

		session.submit(EndTurnCommand.new(0))
		var turn: CombatSession.FactBatch = session.resolve_next()
		_same(
				"%s: kept through the enemy Phase Start, then the hit takes 1" % [trait_name],
				str(seen),
				str([1 + gain, gain])
		)
		var exposed: bool = false
		for fact: CombatFact in turn.facts:
			exposed = exposed or (fact.kind == CombatFact.Kind.EXPOSED and fact.actor_id == archer)
		_ok("%s: the extra kept the ally from being Exposed" % [trait_name], not exposed)
		_ok("%s: the ally's next Phase Start sets it to its maximum" % [trait_name], (
				session.state.get_stance(archer) == 1 and session.state.has_unit(archer)
		), str(session.state.get_stance(archer)))


# A battle on a row of Plain with [param loaded] at (0, 0) and an enemy Hakkapel at (4, 0), ids
# from [param ids], opened; null when either doesn't load or it doesn't open.
func _pouch_battle(loaded: Loadout.LoadedUnit, ids: InstanceIdAllocator) -> CombatSession:
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		_ok("pouch battle: the unit loads", false, str(loaded.problems))
		return null
	var session: CombatSession = CombatSession.new(
			0, PackedInt32Array([0]), _plain_row(5), LiveRolls.new(RngStream.new(SEED)), ids
	)
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = Vector2i(0, 0)
	var enemy_id: String = _place(
			session, "hakkapel", ENEMY, -1, Vector2i(4, 0), ids.next_enemy_id("hakkapel")
	)
	if not session.add_unit(loaded.state, loaded.bases) or enemy_id.is_empty():
		_ok("pouch battle: both units are placed", false)
		return null
	var opened: CombatSession.FactBatch = session.open_battle()
	if opened.is_rejected():
		_ok("pouch battle: the battle opens", false, opened.rejected_reason)
		return null
	return session


func _fact_lines(facts: Array[CombatFact]) -> PackedStringArray:
	var lines: PackedStringArray = []
	for fact: CombatFact in facts:
		lines.append(fact.to_log_line())
	return lines


func _plain_row(width: int) -> MapGrid:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "m1_content"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for x: int in width:
		layout.set_terrain(Vector2i(x, 0), plain)
	return MapGrid.new(layout)


# Each unit as "type [weapon, equipment, pouch]" by item definition, "-" for an empty slot.
func _describe(army: StartingArmy) -> String:
	var parts: PackedStringArray = []
	for unit: UnitInstance in army.units:
		var slots: PackedStringArray = []
		for item_id: String in [unit.weapon_id, unit.equipment_id, unit.pouch_id]:
			var item: ItemInstance = army.items.get(item_id, null)
			slots.append("-" if item == null else item.definition_id)
		parts.append("%s [%s]" % [unit.unit_type_id, ", ".join(slots)])
	return "; ".join(parts)


func _describe_types() -> String:
	var parts: PackedStringArray = []
	for type_id: String in ROSTER:
		var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
		if unit_type == null:
			parts.append("%s missing" % [type_id])
			continue
		parts.append("%s %s %s [%s] %s %s %s" % [
			type_id,
			"/".join(unit_type.weapon_types),
			CombatGrid.MovementType.find_key(unit_type.movement_type),
			", ".join(unit_type.tags),
			"-" if unit_type.role.is_empty() else unit_type.role,
			unit_type.starting_weapon_id,
			unit_type.trait_name,
		])
	return "; ".join(parts)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
