# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_setup_cases.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

extends RefCounted
## Setup step 4 ([EnemySetup]) on the M1 map, through [CampaignSession] as the game runs it: the
## same seed draws the same enemies twice, a battle restarted from Begin draws them again, levels
## by step, slots filled in [MapLayout] order with the leader slot empty, and units built through
## [Loadout] with their stats at the drawn level.
##
## Content is the loadout fixture tree (EN1's Brute and Hedge Healer, and an Archer for the army)
## plus packs built here; no real enemy data exists yet.

const TREE: String = "res://tests/content/fixtures/loadout/"
const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const RUN_SEED: int = 4242
const FLOOR: int = 2
const NODE: int = 5
const BRUTE: String = "loadout_brute"
const HEALER: String = "loadout_hedge_healer"
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

var _check: Callable = Callable()
var _m1: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_m1 = load(M1_DEFINITION) as CombatMapDefinition


## Runs every case.
func run() -> void:
	if _m1 == null:
		_check.call("setup: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_levels_by_step()
	_test_same_seed_same_enemies()
	_test_draw_uses_the_stream()
	_test_restart_from_begin()
	_test_slots_in_layout_order()
	_test_more_units_than_slots()
	_test_no_pack_draws_nothing()
	_test_built_through_the_loadout()
	_test_key_combat_level()
	_test_enemies_placed_before_deployment()


# game-vision.md, Run structure: levels 1 / 3 / 5 by step, +1 in key combats, +2 for leaders.
func _test_levels_by_step() -> void:
	var expected: Dictionary[int, int] = {1: 1, 5: 1, 6: 3, 11: 3, 12: 5, 17: 5}
	var by_floor: PackedStringArray = []
	var holds: bool = true
	for floor_number: int in expected:
		var level: int = EnemySetup.level_for(floor_number, false)
		by_floor.append("%d:%d" % [floor_number, level])
		holds = holds and level == expected[floor_number]
	_check.call("levels: floors 1-5 level 1, 6-11 level 3, 12-17 level 5", holds, str(by_floor))
	_check.call("levels: a floor outside 1-17 takes the nearest step", (
			EnemySetup.level_for(0, false) == 1 and EnemySetup.level_for(18, false) == 5
	))
	_check.call("levels: a key combat adds 1", (
			EnemySetup.level_for(1, true) == 2
			and EnemySetup.level_for(6, true) == 4
			and EnemySetup.level_for(12, true) == 6
	))
	_check.call("levels: a leader or mini-boss adds 2", (
			EnemySetup.level_for(1, false, true) == 3 and EnemySetup.level_for(6, true, true) == 5
	))
	_check.call("levels: a modifier adds, never below level 1", (
			EnemySetup.level_for(6, false, false, 1) == 4
			and EnemySetup.level_for(1, false, false, -5) == 1
	))


func _test_same_seed_same_enemies() -> void:
	var catalog: EffectCatalog.Index = _catalog([_pack("pack_mixed", {BRUTE: 2, HEALER: 1})])
	var first: CampaignSession = _run(RUN_SEED)
	var second: CampaignSession = _run(RUN_SEED)
	var a: CombatEncounter = first.begin_battle(_request(first, catalog, _m1, FLOOR))
	var b: CombatEncounter = second.begin_battle(_request(second, catalog, _m1, FLOOR))
	var placed_a: String = _placed(a.get_session(0))
	_check.call("same seed: the same enemies, levels and tiles twice", (
			a.setup.summary() == b.setup.summary()
			and placed_a == _placed(b.get_session(0))
			and a.get_session(0).state.units_of(ENEMY).size() == 3
	), placed_a)
	first.close()
	second.close()


# Two packs: across seeds the draw picks each, so the pack comes from the stream.
func _test_draw_uses_the_stream() -> void:
	var catalog: EffectCatalog.Index = _catalog([
		_pack("pack_brutes", {BRUTE: 3}),
		_pack("pack_healers", {HEALER: 3}),
	])
	var drawn: Dictionary[String, int] = {}
	for run_seed: int in range(1, 17):
		var battle: CombatEncounter = CombatEncounter.new(
				FLOOR, NODE, PackedInt32Array([0]), InstanceIdAllocator.new()
		)
		battle.add_setup_step(
				CombatEncounter.SetupStep.ENEMY_SLOTS,
				EnemySetup.draw.bind(catalog, FLOOR, 0)
		)
		var pool: Array[CombatMapDefinition] = [_m1]
		battle.run_setup(pool, CombatEncounter.SetupStreams.new(run_seed, FLOOR, NODE))
		var pack_id: String = str(_result(battle.setup).get(EnemySetup.PACK_KEY, ""))
		drawn[pack_id] = drawn.get(pack_id, 0) + 1
	_check.call("stream: over 16 seeds both packs are drawn", (
			drawn.has("pack_brutes") and drawn.has("pack_healers")
	), str(drawn))


func _test_restart_from_begin() -> void:
	var catalog: EffectCatalog.Index = _catalog([
		_pack("pack_brutes", {BRUTE: 3}),
		_pack("pack_mixed", {BRUTE: 2, HEALER: 1}),
	])
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _m1, FLOOR))
	var summary: String = battle.setup.summary()
	var placed: String = _placed(battle.get_session(0))
	run.abandon_battle()
	var again: CombatEncounter = run.begin_battle(_request(run, catalog, _m1, FLOOR))
	_check.call("restart from Begin: the same enemies are drawn again", (
			again != null
			and again.setup.summary() == summary
			and _placed(again.get_session(0)) == placed
	), placed)
	run.close()


# A pack of 3 on M1's 4 slots: the first 3 in layout order, in pack order; the rest stay empty.
func _test_slots_in_layout_order() -> void:
	var catalog: EffectCatalog.Index = _catalog([_pack("pack_mixed", {BRUTE: 2, HEALER: 1})])
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _m1, FLOOR))
	var session: CombatSession = battle.get_session(0)
	var slots: Array[Vector2i] = session.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var expected: PackedStringArray = []
	for i: int in 3:
		expected.append("%s@%s" % [[BRUTE, BRUTE, HEALER][i], slots[i]])
	var placed: String = _placed(session)
	_check.call("slots: units take the enemy slots in layout order, in pack order", (
			slots.size() == 4 and placed == ", ".join(expected)
	), placed)
	_check.call("slots: a slot left over stays empty", (
			session.state.occupant_at(slots[3]).is_empty()
	))
	var leaders_empty: bool = true
	for tile: Vector2i in session.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT):
		leaders_empty = leaders_empty and session.state.occupant_at(tile).is_empty()
	_check.call("slots: the leader slot stays empty", (
			not session.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT).is_empty()
			and leaders_empty
	))
	run.close()


func _test_more_units_than_slots() -> void:
	var catalog: EffectCatalog.Index = _catalog([_pack("pack_big", {BRUTE: 5})])
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _m1, FLOOR))
	var session: CombatSession = battle.get_session(0)
	var unplaced: Variant = _result(battle.setup).get(EnemySetup.UNPLACED_KEY, [])
	var reported: bool = false
	for line: String in session.engine.diagnostics:
		reported = reported or line.contains("no enemy slot left for %s" % [BRUTE])
	_check.call("too many units: one per slot is placed, the rest are listed and reported", (
			session.state.units_of(ENEMY).size() == 4
			and unplaced is Array
			and (unplaced as Array) == [BRUTE]
			and reported
	), str(session.engine.diagnostics))
	run.close()


func _test_no_pack_draws_nothing() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _m1, FLOOR))
	_check.call("no pack: nothing is drawn or placed", (
			battle != null
			and not battle.setup.shared.has(EnemySetup.ENEMIES_KEY)
			and battle.get_session(0).state.units_of(ENEMY).is_empty()
	))
	run.close()


# Floor 6 is step 2, level 3: each stat is base + floor(growth x 2) on the battle's own sheet.
func _test_built_through_the_loadout() -> void:
	var catalog: EffectCatalog.Index = _catalog([_pack("pack_mixed", {BRUTE: 2, HEALER: 1})])
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _m1, 6))
	var session: CombatSession = battle.get_session(0)
	for class_id: String in [BRUTE, HEALER]:
		var unit_id: String = _first_of(session, class_id)
		var mismatches: PackedStringArray = _stat_mismatches(session, catalog, unit_id, 3)
		_check.call("loadout: a level 3 %s's stats are base + floor(growth x 2)" % [class_id], (
				not unit_id.is_empty() and mismatches.is_empty()
		), str(mismatches))
		var unit: CombatUnitState = session.state.unit(unit_id)
		var hp: int = session.stats(unit_id).get_int(CombatValue.Key.HP)
		_check.call("loadout: the %s is an enemy at full HP with its weapon" % [class_id], (
				unit != null
				and unit.side == ENEMY
				and unit.seat == -1
				and unit.hp == hp
				and session.state.weapon(unit.equipped_weapon_id) != null
		))
	run.close()


# A key combat on floor 12: step 3's level 5, +1.
func _test_key_combat_level() -> void:
	var catalog: EffectCatalog.Index = _catalog([_pack("pack_brutes", {BRUTE: 3})])
	var key_map: CombatMapDefinition = _m1.duplicate()
	key_map.combat_type = CombatMapDefinition.CombatType.KEY
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, key_map, 12))
	var session: CombatSession = battle.get_session(0)
	var levels: Array = []
	var units: Variant = _result(battle.setup).get(EnemySetup.UNITS_KEY, [])
	if units is Array:
		for entry: Variant in units:
			levels.append((entry as Dictionary).get(EnemySetup.LEVEL_KEY, 0))
	_check.call("key combat: every enemy is a level above its step", (
			levels == [6, 6, 6]
			and _stat_mismatches(session, catalog, _first_of(session, BRUTE), 6).is_empty()
	), str(levels))
	run.close()


# Automatic deployment ranks its tiles by the enemies' tiles, so they are on the map first.
func _test_enemies_placed_before_deployment() -> void:
	var catalog: EffectCatalog.Index = _catalog([_pack("pack_brutes", {BRUTE: 3})])
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _m1, FLOOR))
	var session: CombatSession = battle.get_session(0)
	var order: PackedStringArray = []
	for fact: CombatFact in session.engine.fact_log:
		if fact.kind == CombatFact.Kind.UNIT_SPAWNED:
			order.append("E" if session.state.side_of(fact.actor_id) == ENEMY else "P")
	_check.call("deployment: the enemies are placed before the army", (
			"".join(order) == "EEEP"
	), "".join(order))
	run.close()


func _run(run_seed: int) -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0]))


# A request on map for floor_number whose seat 0 loads one fixture Archer with its bow, its ids
# minted by run's allocator so they never collide with the enemies'.
func _request(
		run: CampaignSession,
		catalog: EffectCatalog.Index,
		map: CombatMapDefinition,
		floor_number: int
) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = floor_number
	request.node = NODE
	request.pool = [map]
	request.catalog = catalog
	var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "loadout_archer")
	var bow_id: String = run.ids.next_item_id("Simple Bow")
	archer.weapon_id = bow_id
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = [archer]
	army.item_instances[bow_id] = ItemInstance.new(bow_id, "loadout_simple_bow")
	request.armies[0] = army
	return request


# The loadout fixture tree with packs added, as the catalog would list them.
func _catalog(packs: Array[PackDefinition]) -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	for pack: PackDefinition in packs:
		index.add("res://tests/enemies/%s.tres" % [pack.id], pack)
	index.finish()
	return index


func _pack(id: String, counts: Dictionary) -> PackDefinition:
	var pack: PackDefinition = PackDefinition.new()
	pack.id = id
	pack.display_name = id
	pack.class_counts.assign(counts)
	return pack


# The setup's enemies result; empty when none was drawn.
func _result(setup: CombatEncounter.EncounterSetup) -> Dictionary:
	var drawn: Variant = setup.shared.get(EnemySetup.ENEMIES_KEY, {})
	return drawn if drawn is Dictionary else {}


# The session's enemies as "class@tile", in the order they were placed.
func _placed(session: CombatSession) -> String:
	var parts: PackedStringArray = []
	var state: CombatState = session.state
	for unit_id: String in state.units_of(ENEMY):
		parts.append("%s@%s" % [state.unit_type_of(unit_id), state.tile_of(unit_id)])
	return ", ".join(parts)


func _first_of(session: CombatSession, class_id: String) -> String:
	for unit_id: String in session.state.units_of(ENEMY):
		if session.state.unit_type_of(unit_id) == class_id:
			return unit_id
	return ""


# Each stat of unit_id's class whose battle value isn't base + floor(growth x (level - 1)).
func _stat_mismatches(
		session: CombatSession, catalog: EffectCatalog.Index, unit_id: String, level: int
) -> PackedStringArray:
	var mismatches: PackedStringArray = []
	if unit_id.is_empty():
		mismatches.append("no such unit")
		return mismatches
	var enemy_class: EnemyClassDefinition = catalog.enemy_class(
			session.state.unit_type_of(unit_id)
	)
	var sheet: StatSheet = session.stats(unit_id)
	for stat: int in enemy_class.base_stats:
		var growth: int = enemy_class.growths.get(stat, 0)
		var gain: int = floori(float(growth * (level - 1)) / 100.0)
		var expected: int = enemy_class.base_stats[stat] + gain
		var actual: int = sheet.get_int(CombatValue.STAT_KEYS[stat])
		if actual != expected:
			var stat_name: String = str(CombatValue.Stat.find_key(stat))
			mismatches.append("%s %d, not %d" % [stat_name, actual, expected])
	return mismatches
