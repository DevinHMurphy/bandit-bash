# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     m1_enemy_cases.gd
# Author:
# Created:  November 3, 2026
# Modified: November 3, 2026
# ==============================================================================

extends RefCounted
## The M1 enemy cases for tests/content/run_all.gd, over the real [code]res://data/[/code]: the
## Brute, Crossbowman and Hedge Healer against enemy-roster.md (behavior, target rule, weapon,
## stats and growths), effect text snapshots of their traits, the M1 pack loaded through the
## loadout at level 1 with unlimited weapon and staff uses, a battle on the M1 greybox drawing it
## into its enemy slots (and its snapshot restoring), Cleave splashing the Brute's own ally, and
## Field Dressing taking an ally past its Stance maximum until its next Phase Start. Reports each
## case through the check callable it is given.
##
## The expected values are transcribed from the design docs, never read from the data, so a
## changed .tres fails here until the docs and this file agree.
##
## @tutorial(Enemy roster): docs/design/enemy-roster.md
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const STAFF: UnitTurnCommand.Action = UnitTurnCommand.Action.STAFF

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# Any fixed seed: the scripted battles draw nothing that their checks depend on.
const SEED: int = 0xE5_0001

# Floor 1 is step 1, whose enemies are level 1 (game-vision.md, Run structure).
const FLOOR: int = 1
const NODE: int = 1

# enemy-roster.md's Classes table. Columns: HP, MGT, SPD, DEF, RES, MOV, CON, Stance, then growths
# HP, MGT, SPD, DEF, RES.
const ROSTER: Dictionary[String, Array] = {
	"brute": [23, 7, 4, 2, 2, 5, 12, 2, 115, 60, 35, 20, 15],
	"crossbowman": [19, 6, 5, 4, 1, 5, 10, 1, 75, 40, 35, 22, 18],
	"hedge_healer": [12, 8, 5, 1, 7, 5, 5, 1, 50, 40, 30, 8, 35],
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

# Reviewed effect text of each class's trait, one line per effect.
const TEXT: Dictionary[String, Array] = {
	"brute": ["Hit dealt: deal 2 splash damage to adjacent units, friend or foe"],
	"crossbowman": ["While it hasn't moved this turn: +10 Hit"],
	"hedge_healer": ["Healed an ally: give the other unit 1 Stance, even above its maximum"],
}

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
	_test_pack()
	_test_pack_loads()
	_test_staff_unlimited()
	_test_m1_battle_draws_the_pack()
	_test_cleave_splashes_an_ally()
	_test_field_dressing_past_maximum()


# enemy-roster.md's Classes and Traits tables, with question 13's weapons (the Simple Bow, not the
# Heavy Crossbow) and question 11's behaviors.
func _test_classes() -> void:
	var never_unit_types: bool = true
	for class_id: String in ROSTER:
		never_unit_types = never_unit_types and _catalog.unit_type(class_id) == null
	_ok("m1 enemies: enemy classes, never unit types", never_unit_types)
	_same("m1 enemies: weapons, movement, tags, starting weapon, trait, behavior", _describe(), (
			"brute axe DEFAULT [] simple_axe Cleave AGGRESSIVE; "
			+ "crossbowman bow DEFAULT [] simple_bow Steady Aim HOLD; "
			+ "hedge_healer staff DEFAULT [] minor_heal Field Dressing SUPPORT"
	))
	_same("m1 enemies: target rules and their text", _describe_rules(), (
			"brute nearest_foe \"Nearest foe it can hit; swings even with its own allies "
			+ "beside it\"; "
			+ "crossbowman lowest_defense \"Lowest Defense in range; moves only if nothing is "
			+ "in range\"; "
			+ "hedge_healer most_wounded_ally \"Heals the most wounded ally; keeps away from your "
			+ "units\""
	))


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
		growths.append(str(unit.growth(_catalog, CombatValue.Stat.MOV)))
		growths.append(str(unit.growth(_catalog, CombatValue.Stat.CON)))
		expected_growths.append_array(["0", "0"])
		_same("%s: growths, none for MOV and CON" % [class_id], "/".join(growths), (
				"/".join(expected_growths)
		))


# Generated text is canonical (content catalog plan, Approach); these are its reviewed snapshots.
func _test_text_snapshots() -> void:
	for class_id: String in TEXT:
		var enemy_class: EnemyClassDefinition = _catalog.enemy_class(class_id)
		if enemy_class == null:
			_ok("text %s: in the catalog" % [class_id], false)
			continue
		var expected: PackedStringArray = PackedStringArray(TEXT[class_id])
		_same("text %s" % [class_id], " | ".join(enemy_class.describe()), " | ".join(expected))


# Question 12: one of each M1 class, in that order.
func _test_pack() -> void:
	var pack: PackDefinition = _catalog.pack("m1_pack")
	_ok("m1 pack: in the catalog, the only pack", (
			pack != null and _catalog.all_of(EffectCatalog.Kind.PACK).size() == 1
	))
	if pack == null:
		return
	_same("m1 pack: a Brute, a Crossbowman and a Hedge Healer", ", ".join(pack.units()), (
			"brute, crossbowman, hedge_healer"
	))


# Each of the pack's units through the loadout as setup builds it (level 1, side enemy, seat -1,
# its class's starting weapon): no problems, the base stats, and no use limit on any item effect.
func _test_pack_loads() -> void:
	var pack: PackDefinition = _catalog.pack("m1_pack")
	if pack == null:
		return
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var problems: PackedStringArray = []
	var weapons: PackedStringArray = []
	var limited: PackedStringArray = []
	var off_base: PackedStringArray = []
	for class_id: String in pack.units():
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
		var hp: float = loaded.bases.get(CombatValue.Key.HP, 0.0)
		if roundi(hp) != ROSTER[class_id][0] or loaded.state.hp != ROSTER[class_id][0]:
			off_base.append("%s HP %d" % [class_id, roundi(hp)])
	_ok("m1 pack: every unit loads at level 1 without problems", (
			problems.is_empty() and off_base.is_empty()
	), "%s %s" % [problems, off_base])
	_same("m1 pack: each unit's weapon records", "; ".join(weapons), (
			"brute: Simple Axe; crossbowman: Simple Bow; hedge_healer: Minor Heal"
	))
	_ok("m1 pack: no weapon or staff use is limited (question 13)", limited.is_empty(), (
			str(limited)
	))


# The real Minor Heal has 3 uses per map; the Hedge Healer's heals a fourth time.
func _test_staff_unlimited() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = _battle(_plain(3, 1), ForecastRolls.new(), ids)
	var healer: String = _place(session, "hedge_healer", ENEMY, -1, Vector2i(0, 0))
	var brute: String = _place(session, "brute", ENEMY, -1, Vector2i(1, 0))
	if healer.is_empty() or brute.is_empty():
		_ok("staff uses: the battle loads", false)
		return
	var heals: int = 0
	for _i: int in 4:
		session.state.set_hp(brute, 5)
		session.engine.begin_step()
		var result: StaffResolver.Result = StaffResolver.resolve(
				session.engine, session.state, healer, brute
		)
		if result.is_legal:
			heals += 1
	_same("staff uses: the Hedge Healer's Minor Heal heals past its 3 per-map uses", str(heals), (
			"4"
	))


# Setup step 4 through CampaignSession on the real catalog, as the game runs it: floor 1's level 1,
# the pack's units on the first three of M1's four enemy slots in layout order, the fourth and the
# leader slot empty. A snapshot of the battle restores into the same battle rebuilt from Begin,
# with the catalog's own definitions for the enemies' traits.
func _test_m1_battle_draws_the_pack() -> void:
	var m1: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	if m1 == null:
		_ok("m1 battle: the M1 map definition loads", false, M1_DEFINITION)
		return
	var run: CampaignSession = _run()
	var battle: CombatEncounter = run.begin_battle(_request(run, m1))
	if battle == null:
		_ok("m1 battle: begins", false)
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var drawn: Variant = battle.setup.shared.get(EnemySetup.ENEMIES_KEY, {})
	var result: Dictionary = drawn if drawn is Dictionary else {}
	var levels: Array = []
	var units: Variant = result.get(EnemySetup.UNITS_KEY, [])
	if units is Array:
		for entry: Variant in units:
			levels.append((entry as Dictionary).get(EnemySetup.LEVEL_KEY, 0))
	_ok("m1 battle: the M1 pack is drawn at level 1, every unit placed", (
			str(result.get(EnemySetup.PACK_KEY, "")) == "m1_pack"
			and levels == [1, 1, 1]
			and (result.get(EnemySetup.UNPLACED_KEY, []) as Array).is_empty()
	), str(result))

	var slots: Array[Vector2i] = session.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var expected: PackedStringArray = []
	var class_ids: Array[String] = ["brute", "crossbowman", "hedge_healer"]
	for i: int in mini(class_ids.size(), slots.size()):
		expected.append("%s@%s" % [class_ids[i], slots[i]])
	var placed: String = _placed(session)
	_ok("m1 battle: the units take the enemy slots in layout order, in pack order", (
			slots.size() == 4 and placed == ", ".join(expected)
	), placed)
	var leaders_empty: bool = true
	for tile: Vector2i in session.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT):
		leaders_empty = leaders_empty and session.state.occupant_at(tile).is_empty()
	_ok("m1 battle: the fourth slot and the leader slot stay empty", (
			slots.size() == 4 and session.state.occupant_at(slots[3]).is_empty() and leaders_empty
	))

	var off_base: PackedStringArray = []
	for unit_id: String in session.state.units_of(ENEMY):
		var class_id: String = session.state.unit_type_of(unit_id)
		var row: Array = ROSTER.get(class_id, [])
		var sheet: StatSheet = session.stats(unit_id)
		for column: int in STAT_KEYS.size():
			if row.is_empty() or sheet.get_int(STAT_KEYS[column]) != row[column]:
				off_base.append("%s column %d" % [class_id, column])
	_ok("m1 battle: each enemy has its level 1 stats in battle", off_base.is_empty(), (
			str(off_base)
	))
	var setup_problems: PackedStringArray = []
	for line: String in session.engine.diagnostics:
		if line.begins_with("EnemySetup") or line.begins_with("Loadout"):
			setup_problems.append(line)
	_ok("m1 battle: setup reports nothing", setup_problems.is_empty(), str(setup_problems))

	var taken: Variant = JSON.parse_string(JSON.stringify(session.snapshot()))
	var again: CampaignSession = _run()
	var rebuilt: CombatEncounter = again.begin_battle(_request(again, m1))
	var loaded: Error = (
			rebuilt.get_session(0).load_snapshot(taken as Dictionary)
			if rebuilt != null and taken is Dictionary else ERR_UNCONFIGURED
	)
	_ok("m1 battle: its snapshot restores, the enemies' traits from the catalog", (
			loaded == OK and rebuilt.get_session(0).state_hash() == session.state_hash()
	), error_string(loaded))
	run.close()
	again.close()


# On Plain, a Crossbowman (the Brute's ally) at (0, 0), the Brute at (1, 0) and a player Hakkapel
# at (2, 0); hits land. The Brute's one hit on the Hakkapel splashes 2 on every other unit beside
# it: its own ally and the Hakkapel. The Hakkapel's counter is a lance's, with no splash.
func _test_cleave_splashes_an_ally() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = _battle(_plain(3, 1), ForecastRolls.new(), ids)
	var ally: String = _place(session, "crossbowman", ENEMY, -1, Vector2i(0, 0))
	var brute: String = _place(session, "brute", ENEMY, -1, Vector2i(1, 0))
	var target: String = _place(session, "hakkapel", PLAYER, 0, Vector2i(2, 0))
	if ally.is_empty() or brute.is_empty() or target.is_empty():
		_ok("cleave: the battle loads", false)
		return
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(at: CombatSession) -> Command:
		if at.state.unit(brute).has_acted:
			return null
		return UnitTurnCommand.new(-1, brute, ATTACK, target)
	)
	session.open_battle()
	var ally_hp: int = session.state.get_hp(ally)
	session.submit(EndTurnCommand.new(0))
	var turn: CombatSession.FactBatch = session.resolve_next()
	var splashed: PackedStringArray = []
	for fact: CombatFact in turn.facts:
		if fact.kind == CombatFact.Kind.DAMAGE_TAKEN and fact.source == CombatFact.Source.SPLASH:
			splashed.append("%s %d" % [session.state.unit_type_of(fact.actor_id), fact.amount])
	_same("cleave: the Brute's hit splashes its own ally and its target", ", ".join(splashed), (
			"crossbowman 2, hakkapel 2"
	))
	_same("cleave: the ally loses 2 HP", str(session.state.get_hp(ally)), str(ally_hp - 2))


# On Plain, the Hedge Healer at (0, 0), a Brute at full Stance (2) wounded to 10 HP at (1, 0), and
# a player Archer out of the way at (4, 0); hits land. The healer's Minor Heal on the Brute gives it
# 1 Stance past its maximum (P03 question 21: like Triage); the player's Phase Start leaves it, and
# the Brute's own side's next Phase Start sets it back to 2.
func _test_field_dressing_past_maximum() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = _battle(_plain(5, 1), ForecastRolls.new(), ids)
	var healer: String = _place(session, "hedge_healer", ENEMY, -1, Vector2i(0, 0))
	var brute: String = _place(session, "brute", ENEMY, -1, Vector2i(1, 0))
	var archer: String = _place(session, "archer", PLAYER, 0, Vector2i(4, 0))
	if healer.is_empty() or brute.is_empty() or archer.is_empty():
		_ok("field dressing: the battle loads", false)
		return
	# The Brute's Stance each time an enemy command is asked for.
	var seen: Array[int] = []
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(at: CombatSession) -> Command:
		seen.append(at.state.get_stance(brute))
		if at.state.unit(healer).has_acted or at.state.turn > 1:
			return null
		return UnitTurnCommand.new(-1, healer, STAFF, brute)
	)
	session.open_battle()
	session.state.set_hp(brute, 10)

	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	_ok("field dressing: the heal lands", session.state.get_hp(brute) > 10, (
			str(session.state.get_hp(brute))
	))
	_same(
			"field dressing: the ally's Stance is its maximum + 1 into the player's phase",
			str(session.state.get_stance(brute)),
			"3"
	)
	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	_same(
			"field dressing: 2, then 3 after the heal; the Brute's next Phase Start sets 2",
			str(seen),
			str([2, 3, 2])
	)


# A battle on [param grid] with [param rolls] and ids from [param ids]; units placed later.
func _battle(grid: MapGrid, rolls: RollSource, ids: InstanceIdAllocator) -> CombatSession:
	return CombatSession.new(0, PackedInt32Array([0]), grid, rolls, ids)


# Loads a new unit of [param type_id] (an enemy class or a unit type) at level 1 with its starting
# weapon.
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
	return Loadout.load_unit(_catalog, unit, items, side, seat, ids)


# Loads and places a unit of [param type_id] on [param tile]; its id, or empty when it didn't load
# cleanly or wasn't placed.
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


func _run() -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))


# A request on [param map] for floor 1 on the real catalog, whose seat 0 loads one Archer with its
# Simple Bow, its ids minted by [param run]'s allocator so they never collide with the enemies'.
func _request(run: CampaignSession, map: CombatMapDefinition) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [map]
	var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "archer")
	var bow_id: String = run.ids.next_item_id("Simple Bow")
	archer.weapon_id = bow_id
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = [archer]
	army.item_instances[bow_id] = ItemInstance.new(bow_id, "simple_bow")
	request.armies[0] = army
	return request


# The session's enemies as "class@tile", in the order they were placed.
func _placed(session: CombatSession) -> String:
	var parts: PackedStringArray = []
	var state: CombatState = session.state
	for unit_id: String in state.units_of(ENEMY):
		parts.append("%s@%s" % [state.unit_type_of(unit_id), state.tile_of(unit_id)])
	return ", ".join(parts)


func _plain(width: int, height: int) -> MapGrid:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "m1_enemies"
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
		parts.append("%s %s %s [%s] %s %s %s" % [
			class_id,
			"/".join(enemy_class.weapon_types),
			CombatGrid.MovementType.find_key(enemy_class.movement_type),
			", ".join(enemy_class.tags),
			enemy_class.starting_weapon_id,
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
