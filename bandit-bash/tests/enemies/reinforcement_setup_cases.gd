# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reinforcement_setup_cases.gd
# Author:
# Created:  November 15, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Setup steps 5 and 6 through [CampaignSession] as the game runs them: reinforcement waves drawn
## as packs ([EnemySetup.WaveGroups]), the same seed sending the same waves twice, each wave a
## basic or hard pack at the step's count and never the M1 Pack, wave units built at the step's
## level and arriving with their traits; and the Hunted curse's extra enemies
## ([method EnemySetup.draw_additions]): one per copy, a standard class from the seat's own
## stream, at the step's level, in an enemy slot step 4 left free, and listed unplaced with none.
##
## Battles run on the M1 map, a Survive copy of it with a reinforcement point on the leader slot,
## content from the loadout fixture tree plus packs built here (and the real Hunted curse); the
## catalog cases read the real catalog. Waves send Hedge Healers, which never attack, so ending
## turn 1 depends on no roll that could end the battle.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/roster"

const PackCatalog = preload("res://tests/enemies/pack_catalog.gd")

const TREE: String = "res://tests/content/fixtures/loadout/"
const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const HUNTED_PATH: String = "res://data/curses/hunted.tres"
const RUN_SEED: int = 4242
# Floor 6 is step 2: every enemy is level 3.
const FLOOR: int = 6
const LEVEL: int = 3
const NODE: int = 5
const BRUTE: String = "loadout_brute"
const HEALER: String = "loadout_hedge_healer"
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
# The Survive copy's reinforcement point: M1's leader slot, empty in a standard combat.
const POINT_TILE: Vector2i = Vector2i(9, 1)
const POINT_TURNS: Array[int] = [1, 2]

var _check: Callable = Callable()
var _m1: CombatMapDefinition = null
var _survive: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_m1 = load(M1_DEFINITION) as CombatMapDefinition
	if _m1 != null:
		_survive = _survive_copy(_m1)


## Runs every case.
func run() -> void:
	if _m1 == null or _survive == null:
		_check.call("setup: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_waves_same_seed()
	_test_waves_from_the_stream()
	_test_waves_follow_the_pools()
	_test_waves_arrive()
	_test_wave_units_keep_their_traits()
	_test_extra_enemies_value()
	_test_standard_classes()
	_test_hunted_adds_an_enemy()
	_test_hunted_without_a_free_slot()
	_test_no_curse_no_additions()


# The same seed draws the same waves twice: one pack's units per arrival turn, in turn order.
func _test_waves_same_seed() -> void:
	var catalog: EffectCatalog.Index = _catalog(_healer_packs())
	var first: CampaignSession = _run()
	var second: CampaignSession = _run()
	var a: CombatEncounter = first.begin_battle(_request(first, catalog, _survive))
	var b: CombatEncounter = second.begin_battle(_request(second, catalog, _survive))
	var waves: String = _waves(a)
	_check.call("waves: the same seed draws the same waves twice", (
			a != null
			and b != null
			and waves == _waves(b)
			and a.setup.summary() == b.setup.summary()
	), waves)
	var sizes_ok: bool = true
	for size: int in _wave_sizes(a):
		sizes_ok = sizes_ok and (size == 2 or size == 3)
	_check.call("waves: one wave per arrival turn, each one pack's units", (
			_wave_sizes(a).size() == POINT_TURNS.size() and sizes_ok
	), waves)
	first.close()
	second.close()


# Across seeds both packs are drawn for the first wave, so groups come from the stream.
func _test_waves_from_the_stream() -> void:
	var catalog: EffectCatalog.Index = _catalog(_healer_packs())
	var seen: Dictionary[int, int] = {}
	for run_seed: int in range(1, 17):
		var run: CampaignSession = CampaignSession.new(
				CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0])
		)
		var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _survive))
		var sizes: Array[int] = _wave_sizes(battle)
		if not sizes.is_empty():
			seen[sizes[0]] = seen.get(sizes[0], 0) + 1
		run.close()
	_check.call("waves: over 16 seeds both packs send the first wave", (
			seen.has(2) and seen.has(3)
	), str(seen))


# After turn 1's enemy phase the turn-1 wave arrives, each unit at the step's level; the same
# seed sends the same units to the same tiles.
func _test_waves_arrive() -> void:
	var catalog: EffectCatalog.Index = _catalog(_healer_packs())
	var arrivals: PackedStringArray = []
	var expected: int = -1
	var session: CombatSession = null
	var wave_units: PackedStringArray = []
	var runs: Array[CampaignSession] = []
	for i: int in 2:
		var run: CampaignSession = _run()
		runs.append(run)
		var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _survive))
		session = battle.get_session(0)
		expected = _wave_sizes(battle)[0]
		var before: int = session.engine.fact_log.size()
		session.submit(EndTurnCommand.new(0))
		session.resolve_next()
		wave_units = _spawned_since(session, before)
		var spawned: PackedStringArray = []
		for unit_id: String in wave_units:
			var unit_type: String = session.state.unit_type_of(unit_id)
			spawned.append("%s@%s" % [unit_type, session.state.tile_of(unit_id)])
		arrivals.append(", ".join(spawned))
	var newest: String = "" if wave_units.is_empty() else wave_units[wave_units.size() - 1]
	_check.call("arrival: the turn-1 wave arrives after turn 1's enemy phase", (
			wave_units.size() == expected
	), "%s; expected %d" % [arrivals[0], expected])
	_check.call("arrival: the same seed sends the same units to the same tiles", (
			arrivals[0] == arrivals[1]
	), " | ".join(arrivals))
	var mismatches: PackedStringArray = _stat_mismatches(session, catalog, newest, LEVEL)
	_check.call("arrival: a wave unit is built at the step's level", (
			mismatches.is_empty() and session.state.unit(newest).seat == -1
	), str(mismatches))
	_check.call("arrival: a wave unit is named by its class", (
			session.ids.label_of(newest) == catalog.enemy_class(HEALER).display_name
	), session.ids.label_of(newest))
	for run: CampaignSession in runs:
		run.close()


# A real Brute sent by a wave arrives with Cleave registered as its own effect. The point is added
# to a plain M1 battle by hand, so the wave builds from the real catalog.
func _test_wave_units_keep_their_traits() -> void:
	var real: EffectCatalog.Index = EffectCatalog.index()
	var run: CampaignSession = _run()
	var battle: CombatEncounter = run.begin_battle(_request(run, _catalog(_healer_packs()), _m1))
	var session: CombatSession = battle.get_session(0)
	var point: MapState.PointState = MapState.PointState.new()
	point.id = InstanceIdAllocator.point_id(99)
	point.index = 99
	point.tile = POINT_TILE
	point.waves.append({
		Reinforcements.TURN_KEY: 1,
		Reinforcements.GROUP_KEY: [{Reinforcements.UNIT_TYPE_KEY: "brute"}],
	})
	session.state.map.points[99] = point
	var before: int = session.engine.fact_log.size()
	Reinforcements.arrive(session, EnemySetup.WaveGroups.new(real, FLOOR, 0))
	var arrived: PackedStringArray = _spawned_since(session, before)
	var brute_id: String = "" if arrived.size() != 1 else arrived[0]
	var traits: PackedStringArray = []
	for instance: EffectInstance in session.engine.get_instances():
		if instance.owner != null and instance.owner.holder_id == brute_id:
			traits.append(instance.definition.id)
	_check.call("traits: a wave's Brute arrives with Cleave registered", (
			not brute_id.is_empty()
			and session.state.unit_type_of(brute_id) == "brute"
			and traits.has("cleave")
	), str(traits))
	run.close()


# Hunted's value through the stats, before any battle: one per copy held.
func _test_extra_enemies_value() -> void:
	var real: EffectCatalog.Index = EffectCatalog.index()
	var counts: Array[int] = [
		EnemySetup.extra_enemies(real, PackedStringArray(), 0),
		EnemySetup.extra_enemies(real, PackedStringArray(["short_wick"]), 0),
		EnemySetup.extra_enemies(real, PackedStringArray(["hunted"]), 0),
		EnemySetup.extra_enemies(real, PackedStringArray(["hunted", "short_wick", "hunted"]), 1),
	]
	_check.call("hunted: extra enemies 0 / 0 / 1 / 2 (copies stack)", counts == [0, 0, 1, 2], (
			str(counts)
	))


# Standard classes are the classes some drawn pack fields, in id order: the Duelist (hard and key
# packs) among them. A pack in no pool adds none.
func _test_standard_classes() -> void:
	var classes: PackedStringArray = EnemySetup.standard_classes(EffectCatalog.index())
	var expected: PackedStringArray = [
		"brute", "crossbowman", "cutthroat", "duelist", "hedge_healer", "hexer", "hound", "raider",
		"shieldbearer", "warcaller",
	]
	_check.call("standard classes: every class a drawn catalog pack fields, in id order", (
			classes == expected
	), str(classes))
	var catalog: EffectCatalog.Index = _catalog([
		_pack("pack_healers", {HEALER: 3}, PackDefinition.Pool.HARD),
		_pack("pack_unpooled", {BRUTE: 3}, PackDefinition.Pool.NONE),
	])
	var fixture_classes: PackedStringArray = EnemySetup.standard_classes(catalog)
	_check.call("standard classes: a pack setup never draws adds no class", (
			fixture_classes == PackedStringArray([HEALER])
	), str(fixture_classes))


# The real catalog over 16 seeds at every step: a wave is one basic pack's units at the step's
# count while the step has had fewer than 2 standard combats, a hard pack's after, never the M1
# Pack's, and the same on a key map (a wave never draws a key pack).
func _test_waves_follow_the_pools() -> void:
	var real: EffectCatalog.Index = EffectCatalog.index()
	var wrong: PackedStringArray = []
	for floor_number: int in [1, 6, 12]:
		var step: int = EnemySetup.step_of(floor_number)
		for combats: int in [0, 1, 2]:
			var pool: PackDefinition.Pool = EnemySetup.pool_for(false, combats)
			var allowed: PackedStringArray = _pool_units(real, pool, step)
			var source: EnemySetup.WaveGroups = EnemySetup.WaveGroups.new(
					real, floor_number, 0, combats
			)
			for run_seed: int in range(1, 17):
				var streams: CombatEncounter.SetupStreams = CombatEncounter.SetupStreams.new(
						run_seed, floor_number, NODE
				)
				var types: PackedStringArray = []
				for entry: Dictionary in source.draw_group(streams.shared(), null, 1):
					types.append(str(entry.get(Reinforcements.UNIT_TYPE_KEY, "")))
				streams.close()
				var group: String = ", ".join(types)
				if not allowed.has(group) or types.size() != PackDefinition.STEP_SIZES[step - 1]:
					wrong.append("floor %d, %d before, seed %d: %s" % [
						floor_number, combats, run_seed, group,
					])
	_check.call("waves: a basic pack's units, hard after 2, at the step's count, never M1's", (
			wrong.is_empty()
	), "; ".join(wrong))


# The units at step of every pack of pool in catalog, each joined as one string.
func _pool_units(
		catalog: EffectCatalog.Index, pool: PackDefinition.Pool, step: int
) -> PackedStringArray:
	var listed: PackedStringArray = []
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.PACK):
		var pack: PackDefinition = resource as PackDefinition
		if pack != null and pack.pool == pool:
			listed.append(", ".join(pack.units(step)))
	return listed


# A pack of 3 on M1's 4 slots leaves one free: Hunted's enemy takes it, a class drawn from seat 0's
# own stream at the step's level, and step 4's draw is the same as without the curse.
func _test_hunted_adds_an_enemy() -> void:
	var catalog: EffectCatalog.Index = _catalog(_mixed_packs(), true)
	var plain: CampaignSession = _run()
	var cursed: CampaignSession = _run()
	var again: CampaignSession = _run()
	var uncursed: CombatEncounter = plain.begin_battle(_request(plain, catalog, _m1))
	var hunted: CombatEncounter = cursed.begin_battle(_request(cursed, catalog, _m1, ["hunted"]))
	var hunted_again: CombatEncounter = again.begin_battle(
			_request(again, catalog, _m1, ["hunted"])
	)
	var session: CombatSession = hunted.get_session(0)
	var slots: Array[Vector2i] = session.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var units: PackedStringArray = session.state.units_of(ENEMY)
	var extra: String = session.state.occupant_at(slots[3]) if units.size() == 4 else ""
	var classes: PackedStringArray = EnemySetup.standard_classes(catalog)
	var streams: CombatEncounter.SetupStreams = CombatEncounter.SetupStreams.new(
			RUN_SEED, FLOOR, NODE
	)
	var drawn_class: String = classes[streams.for_seat(0).pick_index(classes.size())]
	streams.close()
	_check.call("hunted: one extra enemy, on the enemy slot step 4 left free", (
			uncursed.get_session(0).state.units_of(ENEMY).size() == 3
			and not extra.is_empty()
			and session.state.side_of(extra) == ENEMY
	), "%d enemies" % [units.size()])
	_check.call("hunted: its class is drawn from the seat's own setup stream", (
			not extra.is_empty() and session.state.unit_type_of(extra) == drawn_class
	), "%s, expected %s" % [session.state.unit_type_of(extra), drawn_class])
	_check.call("hunted: the extra enemy is at the step's level", (
			_stat_mismatches(session, catalog, extra, LEVEL).is_empty()
	))
	_check.call("hunted: step 4's shared draw is the same with or without the curse", (
			JSON.stringify(hunted.setup.shared, "", true)
			== JSON.stringify(uncursed.setup.shared, "", true)
	))
	_check.call("hunted: the same seed adds the same enemy twice", (
			hunted.setup.summary() == hunted_again.setup.summary()
	))
	plain.close()
	cursed.close()
	again.close()


# Two copies with one free slot: the first takes it; the second is listed unplaced and reported.
func _test_hunted_without_a_free_slot() -> void:
	var catalog: EffectCatalog.Index = _catalog(_mixed_packs(), true)
	var run: CampaignSession = _run()
	var battle: CombatEncounter = run.begin_battle(
			_request(run, catalog, _m1, ["hunted", "hunted"])
	)
	var session: CombatSession = battle.get_session(0)
	var additions: Dictionary = _additions(battle, 0)
	var units: Variant = additions.get(EnemySetup.UNITS_KEY, [])
	var unplaced: Variant = additions.get(EnemySetup.UNPLACED_KEY, [])
	var reported: bool = false
	for line: String in session.engine.diagnostics:
		reported = reported or line.contains("no free enemy slot for seat 0's extra enemy")
	_check.call("hunted: two copies, one free slot: one placed, one unplaced and reported", (
			session.state.units_of(ENEMY).size() == 4
			and units is Array and (units as Array).size() == 1
			and unplaced is Array and (unplaced as Array).size() == 1
			and reported
	), str(session.engine.diagnostics))
	run.close()


func _test_no_curse_no_additions() -> void:
	var catalog: EffectCatalog.Index = _catalog(_mixed_packs(), true)
	var run: CampaignSession = _run()
	var battle: CombatEncounter = run.begin_battle(_request(run, catalog, _m1))
	_check.call("hunted: an army without the curse draws no addition", (
			battle != null and _additions(battle, 0).is_empty()
	))
	run.close()


func _run() -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0]))


# A request on map whose seat 0 loads one fixture Archer with its bow and holds heirloom_ids, its
# opening swap off so turn 1 starts at once.
func _request(
		run: CampaignSession,
		catalog: EffectCatalog.Index,
		map: CombatMapDefinition,
		heirloom_ids: Array[String] = []
) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [map]
	request.catalog = catalog
	request.opening_swap[0] = false
	var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "loadout_archer")
	var bow_id: String = run.ids.next_item_id("Simple Bow")
	archer.weapon_id = bow_id
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = [archer]
	army.item_instances[bow_id] = ItemInstance.new(bow_id, "loadout_simple_bow")
	army.heirloom_ids = PackedStringArray(heirloom_ids)
	request.armies[0] = army
	return request


# The loadout fixture tree with packs added, and the real Hunted curse when with_hunted.
func _catalog(packs: Array[PackDefinition], with_hunted: bool = false) -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	for pack: PackDefinition in packs:
		index.add("res://tests/enemies/%s.tres" % [pack.id], pack)
	if with_hunted:
		index.add(HUNTED_PATH, load(HUNTED_PATH))
	index.finish()
	return index


func _healer_packs() -> Array[PackDefinition]:
	return [_pack("pack_healer_pair", {HEALER: 2}), _pack("pack_healer_trio", {HEALER: 3})]


func _mixed_packs() -> Array[PackDefinition]:
	return [_pack("pack_brutes", {BRUTE: 3}), _pack("pack_healers", {HEALER: 3})]


func _pack(
		id: String, counts: Dictionary, pool: PackDefinition.Pool = PackDefinition.Pool.BASIC
) -> PackDefinition:
	return PackCatalog.fixture(id, counts, pool)


# A Survive copy of map with a reinforcement point on POINT_TILE sending on POINT_TURNS.
func _survive_copy(map: CombatMapDefinition) -> CombatMapDefinition:
	var root: Node2D = map.scene.instantiate() as Node2D
	if root == null:
		return null
	var terrain: TileMapLayer = root.get_node_or_null(NodePath(MapLoader.TERRAIN_LAYER))
	if terrain == null:
		root.free()
		return null
	var point: MapMarker = MapMarker.new()
	point.kind = MapMarker.Kind.REINFORCEMENT_POINT
	point.arrival_turns = POINT_TURNS.duplicate()
	point.position = terrain.map_to_local(POINT_TILE)
	root.add_child(point)
	point.owner = root
	var packed: PackedScene = PackedScene.new()
	var err: Error = packed.pack(root)
	root.free()
	if err != OK:
		return null
	var copy: CombatMapDefinition = map.duplicate() as CombatMapDefinition
	copy.id = "m1_survive"
	copy.scene = packed
	copy.objective = CombatMapDefinition.Objective.SURVIVE
	copy.survive_turns = 3
	return copy


# Every wave setup drew, as "point: turn [classes]" in order.
func _waves(battle: CombatEncounter) -> String:
	if battle == null:
		return ""
	var parts: PackedStringArray = []
	var drawn: Variant = battle.setup.shared.get(Objectives.WAVES_KEY, {})
	if not drawn is Dictionary:
		return ""
	for point_key: Variant in drawn:
		# Untyped: setup results are plain data.
		for wave: Variant in (drawn as Dictionary)[point_key]:
			var types: PackedStringArray = []
			for entry: Variant in (wave as Dictionary)[Reinforcements.GROUP_KEY]:
				types.append(str((entry as Dictionary)[Reinforcements.UNIT_TYPE_KEY]))
			parts.append("%s: %s %s" % [
				point_key, (wave as Dictionary)[Reinforcements.TURN_KEY], types,
			])
	return "; ".join(parts)


# The size of each wave setup drew, in order.
func _wave_sizes(battle: CombatEncounter) -> Array[int]:
	var sizes: Array[int] = []
	if battle == null:
		return sizes
	var drawn: Variant = battle.setup.shared.get(Objectives.WAVES_KEY, {})
	if not drawn is Dictionary:
		return sizes
	for point_key: Variant in drawn:
		# Untyped: setup results are plain data.
		for wave: Variant in (drawn as Dictionary)[point_key]:
			sizes.append(((wave as Dictionary)[Reinforcements.GROUP_KEY] as Array).size())
	return sizes


# The enemies spawned on session's map from fact first_fact on, in spawn order.
func _spawned_since(session: CombatSession, first_fact: int) -> PackedStringArray:
	var spawned: PackedStringArray = []
	var facts: Array[CombatFact] = session.engine.fact_log
	for i: int in range(first_fact, facts.size()):
		var fact: CombatFact = facts[i]
		if (
				fact.kind == CombatFact.Kind.UNIT_SPAWNED
				and session.state.side_of(fact.actor_id) == ENEMY
		):
			spawned.append(fact.actor_id)
	return spawned


# The extra enemies setup drew for seat; empty when none.
func _additions(battle: CombatEncounter, seat: int) -> Dictionary:
	var seat_setup: CombatEncounter.SeatSetup = battle.setup.seats.get(seat, null)
	if seat_setup == null:
		return {}
	var drawn: Variant = seat_setup.additions.get(EnemySetup.ADDITIONS_KEY, {})
	return drawn if drawn is Dictionary else {}


# Each stat of unit_id's class whose battle value isn't base + floor(growth x (level - 1)).
func _stat_mismatches(
		session: CombatSession, catalog: EffectCatalog.Index, unit_id: String, level: int
) -> PackedStringArray:
	var mismatches: PackedStringArray = []
	var enemy_class: EnemyClassDefinition = (
			null if unit_id.is_empty()
			else catalog.enemy_class(session.state.unit_type_of(unit_id))
	)
	if enemy_class == null:
		mismatches.append("no such unit")
		return mismatches
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
