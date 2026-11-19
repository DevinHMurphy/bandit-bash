# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     elite_cases.gd
# Author:
# Created:  November 17, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Elites and leaders on the real catalog (enemies and AI plan, EN7 row; enemy-packs.md, Decisions
## 9 and 10): an elite's prefix is always positive; on each Defeat the Leader map the first unit of
## the pack's leader class stands on the leader slot at its step's level +2 with that prefix,
## counted in the step's count; the same seed fields the same leader twice; a map with no leader
## slot fields none. In a battle the leader is the one marked enemy, the HUD names it with its
## prefix, its state holds its prefix and level (through a JSON trip too) as its unit detail
## shows them, and its fall ends the map. The Warcaller's War Horn shows as its intent the phase
## before it fires, and fires then. Reports each case through the check callable it is given.
##
## @tutorial(Enemy packs): docs/design/enemy-packs.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/roster"

const AiWorld = preload("res://tests/enemies/ai_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

## The Defeat the Leader maps, each [code]res://maps/standard/<id>.tres[/code].
const LEADER_MAPS: Array[String] = ["bandit_camp", "watch_post"]

## A Rout map with no leader slot.
const ROUT_MAP: String = "crossroads"

const RUN_SEED: int = 7070
const SEEDS: int = 24
const PREFIX_ROLLS: int = 400
const NODE: int = 5
const FLOORS: Array[int] = [1, 6, 12]
const BATTLE_FLOOR: int = 6
const WARCALLER: String = "warcaller"
const WAR_HORN: String = "war_horn"
const HORN_SHAPE: String = "res://data/shapes/within_2_with_center.tres"

const PLAIN_8X8: Array[String] = [
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
]

var _check: Callable = Callable()
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_elite_prefix()
	_test_leader_draws()
	_test_same_seed_same_leader()
	_test_no_leader_slot()
	for map_id: String in LEADER_MAPS:
		_test_leader_in_battle(map_id)
	_test_war_horn_intent()


# roll_elite keeps only the positive tiers, at their weights (+1 35, +2 10).
func _test_elite_prefix() -> void:
	var by_tier: Dictionary[int, int] = {}
	var wrong: PackedStringArray = []
	for run_seed: int in range(1, PREFIX_ROLLS + 1):
		var stream: RngStream = RngStream.new(run_seed)
		var prefix_id: String = UnitPrefixDefinition.roll_elite(stream, _catalog)
		var prefix: UnitPrefixDefinition = _catalog.unit_prefix(prefix_id)
		if prefix == null or prefix.tier <= 0:
			wrong.append("seed %d: \"%s\"" % [run_seed, prefix_id])
			continue
		by_tier[prefix.tier] = by_tier.get(prefix.tier, 0) + 1
	_check.call("elite prefix: always a positive prefix, never none or a negative one", (
			wrong.is_empty()
	), "; ".join(wrong))
	_check.call("elite prefix: both positive tiers come up, +1 more often than +2", (
			by_tier.get(1, 0) > by_tier.get(2, 0) and by_tier.get(2, 0) > 0
	), str(by_tier))
	_check.call("elite prefix: the same stream rolls the same prefix", (
			UnitPrefixDefinition.roll_elite(RngStream.new(99), _catalog)
			== UnitPrefixDefinition.roll_elite(RngStream.new(99), _catalog)
	))


func _test_leader_draws() -> void:
	var wrong: PackedStringArray = []
	var checked: int = 0
	for map_id: String in LEADER_MAPS:
		var map: CombatMapDefinition = _map(map_id)
		for run_seed: int in range(1, SEEDS + 1):
			for floor_number: int in FLOORS:
				for combats: int in [0, EnemySetup.BASIC_COMBATS_PER_STEP]:
					var setup: CombatEncounter.EncounterSetup = _draw_only(
							map, floor_number, combats, run_seed
					)
					var problem: String = _leader_problem(setup, floor_number)
					checked += 1
					if not problem.is_empty():
						wrong.append("%s seed %d floor %d: %s" % [
							map_id, run_seed, floor_number, problem,
						])
	_check.call(
			"leader: the pack's leader class stands on the leader slot at step level +2 with a "
			+ "positive prefix, counted in the step's count",
			checked > 0 and wrong.is_empty(),
			"; ".join(wrong.slice(0, 5))
	)


func _test_same_seed_same_leader() -> void:
	for map_id: String in LEADER_MAPS:
		var map: CombatMapDefinition = _map(map_id)
		var first: String = _leader_text(_draw_only(map, BATTLE_FLOOR, 0, RUN_SEED))
		var second: String = _leader_text(_draw_only(map, BATTLE_FLOOR, 0, RUN_SEED))
		_check.call("seed: %s fields the same leader with the same prefix twice" % [map_id], (
				not first.is_empty() and first == second
		), "%s / %s" % [first, second])


func _test_no_leader_slot() -> void:
	var map: CombatMapDefinition = _map(ROUT_MAP)
	var leaders: int = 0
	var has_slot: bool = false
	for run_seed: int in range(1, SEEDS + 1):
		var setup: CombatEncounter.EncounterSetup = _draw_only(map, 1, 0, run_seed)
		var slots: Array[Vector2i] = setup.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT)
		has_slot = has_slot or not slots.is_empty()
		leaders += _leaders_in(setup).size()
	_check.call("no leader slot: a Rout map fields no leader and no prefix", (
			not has_slot and leaders == 0
	), "%d leaders" % [leaders])


# A real battle on map_id at floor 6 (step 2): the leader's mark, name, stats and count; the same
# seed fields it again; another enemy's fall leaves the map open, the leader's ends it.
func _test_leader_in_battle(map_id: String) -> void:
	var map: CombatMapDefinition = _map(map_id)
	var run: CampaignSession = _run()
	var battle: CombatEncounter = run.begin_battle(_request(run, map))
	if battle == null:
		_check.call("battle %s: it begins" % [map_id], false)
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var leader_tile: Vector2i = session.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT)[0]
	var leader_id: String = state.occupant_at(leader_tile)
	var leaders: Array[Dictionary] = _leaders_in(battle.setup)
	var entry: Dictionary = leaders[0] if leaders.size() == 1 else {}
	var prefix: UnitPrefixDefinition = _catalog.unit_prefix(
			str(entry.get(EnemySetup.PREFIX_KEY, ""))
	)
	var enemy_class: EnemyClassDefinition = _catalog.enemy_class(state.unit_type_of(leader_id))
	_check.call("battle %s: the leader on the leader slot is the one marked enemy" % [map_id], (
			not leader_id.is_empty()
			and state.side_of(leader_id) == ENEMY
			and Objectives.marked_ids(session) == PackedStringArray([leader_id])
	), "%s; marked %s" % [leader_id, Objectives.marked_ids(session)])
	var view: HudViewModel.ObjectiveView = HudViewModel.objective_view(session)
	var expected_name: String = "" if prefix == null or enemy_class == null else (
			"%s %s" % [prefix.display_name, enemy_class.display_name]
	)
	_check.call("battle %s: the HUD marks the leader by its prefixed name" % [map_id], (
			view != null
			and not expected_name.is_empty()
			and view.marked_left_ids == PackedStringArray([leader_id])
			and view.marked_left_names == PackedStringArray([expected_name])
	), "" if view == null else "%s, expected %s" % [view.marked_left_names, expected_name])
	_check.call("battle %s: the leader carries its prefix, its HP at its level" % [map_id], (
			_carries_prefix(session, leader_id, entry, prefix)
	), str(entry))
	var shown_problem: String = _shown_elite_problem(session, leader_id, entry, prefix)
	_check.call("battle %s: the leader's state holds its prefix and level, as its detail shows" % [
		map_id,
	], shown_problem.is_empty(), shown_problem)
	_check.call("battle %s: the enemies number step 2's count, the leader included" % [map_id], (
			state.units_of(ENEMY).size() == PackDefinition.STEP_SIZES[1]
	), "%d enemies" % [state.units_of(ENEMY).size()])

	var again_run: CampaignSession = _run()
	var again: CombatEncounter = again_run.begin_battle(_request(again_run, map))
	var again_id: String = "" if again == null else (
			again.get_session(0).state.occupant_at(leader_tile)
	)
	_check.call("battle %s: a seeded run fields the same leader with the same prefix" % [map_id], (
			again != null
			and _leader_text(again.setup) == _leader_text(battle.setup)
			and BattleText.name_of(again.get_session(0), again_id) == expected_name
	), _leader_text(battle.setup))
	again_run.close()

	var players: PackedStringArray = state.units_of(PLAYER)
	var player_id: String = players[0] if not players.is_empty() else ""
	var other_id: String = ""
	for enemy_id: String in state.units_of(ENEMY):
		if enemy_id != leader_id:
			other_id = enemy_id
			break
	_check.call("battle %s: turn 1 has started" % [map_id], state.turn >= 1, str(state.turn))
	_send(session, DefeatFixture.new([other_id], player_id))
	_check.call("battle %s: another enemy's fall leaves the map open" % [map_id], (
			not session.is_finished
	))
	_send(session, DefeatFixture.new([leader_id], player_id))
	_check.call("battle %s: the leader's fall wins the map with enemies left" % [map_id], (
			session.is_won and not state.units_of(ENEMY).is_empty() and _has_ended(session)
	), "won %s, %d enemies left" % [session.is_won, state.units_of(ENEMY).size()])
	run.close()


# War Horn fires on every 2nd enemy Phase Start: turn 2's player phase shows it, the 2nd enemy
# Phase Start fires it, and the intents of turns 1 and 3 don't show it.
func _test_war_horn_intent() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", WARCALLER, Vector2i(0, 0))
	world.add_player("p1", Vector2i(7, 7), "bow")
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	world.session.open_battle()
	var turn_1: EnemyIntent = _intent(world, "e1")
	_check.call("war horn: turn 1 shows no signature (its 1st enemy Phase Start)", (
			turn_1 != null and turn_1.kind != EnemyIntent.Kind.SIGNATURE
	), "" if turn_1 == null else turn_1.describe())
	_send(world.session, EndTurnCommand.new(0))
	_check.call("war horn: silent at the 1st enemy Phase Start", _horns(world, 0) == 0)

	var turn_2: EnemyIntent = _intent(world, "e1")
	var expected: Array[Vector2i] = _horn_area(world, world.state().tile_of("e1"))
	_check.call("war horn: turn 2 shows War Horn the phase before it fires, over its area", (
			turn_2 != null
			and turn_2.kind == EnemyIntent.Kind.SIGNATURE
			and turn_2.signature_name == "War Horn"
			and turn_2.area == expected
	), "" if turn_2 == null else "%s; area %s" % [turn_2.describe(), turn_2.area])
	var preview: Intents = Intents.preview(world.session, "p1", Vector2i(7, 6))
	var previewed: EnemyIntent = null if preview == null else preview.intent_of("e1")
	_check.call("war horn: a move preview shows it too", (
			previewed != null and previewed.kind == EnemyIntent.Kind.SIGNATURE
	), "" if previewed == null else previewed.describe())
	var before: int = world.engine().fact_log.size()
	_send(world.session, EndTurnCommand.new(0))
	_check.call("war horn: it fires at the 2nd enemy Phase Start, as shown", (
			_horns(world, before) == 1
	), str(_horns(world, before)))

	var turn_3: EnemyIntent = _intent(world, "e1")
	_check.call("war horn: turn 3 shows no signature", (
			turn_3 != null and turn_3.kind != EnemyIntent.Kind.SIGNATURE
	), "" if turn_3 == null else turn_3.describe())


# What is wrong with setup's leader at floor_number; empty when nothing is.
func _leader_problem(setup: CombatEncounter.EncounterSetup, floor_number: int) -> String:
	var drawn: Dictionary = _result(setup)
	var pack: PackDefinition = _catalog.pack(str(drawn.get(EnemySetup.PACK_KEY, "")))
	if pack == null:
		return "no pack"
	var step: int = EnemySetup.step_of(floor_number)
	var units: Array = drawn.get(EnemySetup.UNITS_KEY, [])
	var unplaced: Array = drawn.get(EnemySetup.UNPLACED_KEY, [])
	if units.size() + unplaced.size() != PackDefinition.STEP_SIZES[step - 1]:
		return "%d units and %d unplaced" % [units.size(), unplaced.size()]
	var enemy_slots: Array[Vector2i] = setup.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var classes: PackedStringArray = []
	for entry: Variant in units:
		var unit: Dictionary = entry
		classes.append(str(unit.get(EnemySetup.CLASS_KEY, "")))
		if not unit.has(EnemySetup.PREFIX_KEY) and not enemy_slots.has(_tile_of(unit)):
			return "%s off the enemy slots" % [unit]
	var expected: PackedStringArray = pack.units(step)
	classes.sort()
	expected.sort()
	if classes != expected:
		return "fields %s, not the pack's %s" % [classes, expected]
	var leaders: Array[Dictionary] = _leaders_in(setup)
	if leaders.size() != 1:
		return "%d leaders" % [leaders.size()]
	var leader: Dictionary = leaders[0]
	var prefix: UnitPrefixDefinition = _catalog.unit_prefix(
			str(leader.get(EnemySetup.PREFIX_KEY, ""))
	)
	if (
			str(leader.get(EnemySetup.CLASS_KEY, "")) != pack.leader_class_id
			or _tile_of(leader) != setup.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT)[0]
			or _whole(leader.get(EnemySetup.LEVEL_KEY, 0))
					!= EnemySetup.level_for(floor_number, false, true)
			or prefix == null
			or prefix.tier <= 0
	):
		return "leader %s of %s" % [leader, pack.id]
	return ""


# Whether unit_id's HP is its class's at its level with its prefix, and an effect named for the
# prefix is registered on it.
func _carries_prefix(
		session: CombatSession, unit_id: String, entry: Dictionary, prefix: UnitPrefixDefinition
) -> bool:
	if unit_id.is_empty() or prefix == null:
		return false
	var unit: UnitInstance = UnitInstance.new("elite_check", session.state.unit_type_of(unit_id))
	unit.level = _whole(entry.get(EnemySetup.LEVEL_KEY, 0))
	unit.prefix_id = prefix.id
	var hp: int = unit.stats(_catalog).get_int(CombatValue.Key.HP)
	var is_named: bool = false
	for instance: EffectInstance in session.engine.get_instances():
		if instance.owner != null and instance.owner.subject_id() == unit_id:
			is_named = is_named or instance.label == prefix.display_name
	return is_named and session.stats(unit_id).get_int(CombatValue.Key.HP) == hp


# Why unit_id's battle state or detail doesn't hold entry's prefix and level, through a JSON trip
# of its capture too, or another enemy has a prefix; empty when all hold.
func _shown_elite_problem(
		session: CombatSession, unit_id: String, entry: Dictionary, prefix: UnitPrefixDefinition
) -> String:
	if unit_id.is_empty() or prefix == null or not session.state.has_unit(unit_id):
		return "no leader or prefix"
	var level: int = _whole(entry.get(EnemySetup.LEVEL_KEY, 0))
	var placed: CombatUnitState = session.state.unit(unit_id)
	var trip: Variant = JSON.parse_string(JSON.stringify(placed.capture()))
	var back: CombatUnitState = (
			CombatUnitState.from_capture(trip as Dictionary) if trip is Dictionary else null
	)
	var detail: UnitDetailViewModel = UnitDetailViewModel.build(session, unit_id)
	if placed.prefix_id != prefix.id or placed.level != level:
		return "state %s level %d, drawn %s level %d" % [
			placed.prefix_id, placed.level, prefix.id, level,
		]
	if back == null or back.prefix_id != prefix.id or back.level != level:
		return "lost through its capture"
	if detail == null or detail.prefix_name != prefix.display_name or detail.level != level:
		return "detail %s level %d" % [
			"-" if detail == null else detail.prefix_name, 0 if detail == null else detail.level,
		]
	for enemy_id: String in session.state.units_of(ENEMY):
		if enemy_id != unit_id and not session.state.unit(enemy_id).prefix_id.is_empty():
			return "%s has a prefix too" % [enemy_id]
	return ""


# The leader's class, prefix, tile and level in setup's draw; empty when there is none.
func _leader_text(setup: CombatEncounter.EncounterSetup) -> String:
	var leaders: Array[Dictionary] = _leaders_in(setup)
	if leaders.size() != 1:
		return ""
	var leader: Dictionary = leaders[0]
	return "%s %s %s level %s" % [
		leader.get(EnemySetup.CLASS_KEY, ""), leader.get(EnemySetup.PREFIX_KEY, ""),
		_tile_of(leader), leader.get(EnemySetup.LEVEL_KEY, 0),
	]


# The drawn units that carry a prefix: the leader.
func _leaders_in(setup: CombatEncounter.EncounterSetup) -> Array[Dictionary]:
	var leaders: Array[Dictionary] = []
	var units: Variant = _result(setup).get(EnemySetup.UNITS_KEY, [])
	if units is Array:
		for entry: Variant in units:
			if entry is Dictionary and (entry as Dictionary).has(EnemySetup.PREFIX_KEY):
				leaders.append(entry as Dictionary)
	return leaders


# War Horn activations on world from fact index from on.
func _horns(world: AiWorld, from: int) -> int:
	var count: int = 0
	var facts: Array[CombatFact] = world.engine().fact_log
	for index: int in range(from, facts.size()):
		var fact: CombatFact = facts[index]
		if fact.kind != CombatFact.Kind.EFFECT_ACTIVATED:
			continue
		var instance: EffectInstance = world.engine().get_instance(fact.source_effect_id)
		if instance != null and instance.definition.id == WAR_HORN:
			count += 1
	return count


# The tiles within 2 of center on world's map, center included, in row-major order.
func _horn_area(world: AiWorld, center: Vector2i) -> Array[Vector2i]:
	var shape: TargetShape = load(HORN_SHAPE) as TargetShape
	var tiles: Array[Vector2i] = []
	if shape == null:
		return tiles
	for tile: Vector2i in shape.tiles(center):
		if world.state().grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
			tiles.append(tile)
	tiles.sort_custom(EnemyPlan.tile_precedes)
	return tiles


func _intent(world: AiWorld, unit_id: String) -> EnemyIntent:
	var shown: Intents = world.session.intents
	return null if shown == null else shown.intent_of(unit_id)


func _has_ended(session: CombatSession) -> bool:
	for fact: CombatFact in session.engine.fact_log:
		if fact.kind == CombatFact.Kind.COMBAT_ENDED and fact.side == PLAYER:
			return true
	return false


func _send(session: CombatSession, command: Command) -> void:
	session.submit(command)
	var batch: CombatSession.FactBatch = session.resolve_next()
	if batch != null and batch.is_rejected():
		_check.call("send: %s accepted" % [batch.label], false, batch.rejected_reason)


func _map(map_id: String) -> CombatMapDefinition:
	return load("res://maps/standard/%s.tres" % [map_id]) as CombatMapDefinition


func _run() -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0]))


# A request on map at BATTLE_FLOOR whose seat 0 is one real Archer with a Simple Bow, turn 1 at
# once (no opening swap).
func _request(run: CampaignSession, map: CombatMapDefinition) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BATTLE_FLOOR
	request.node = NODE
	request.pool = [map]
	request.catalog = _catalog
	request.opening_swap[0] = false
	var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "archer")
	var bow_id: String = run.ids.next_item_id("Simple Bow")
	archer.weapon_id = bow_id
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = [archer]
	army.item_instances[bow_id] = ItemInstance.new(bow_id, "simple_bow")
	request.armies[0] = army
	return request


# Setup step 4 alone on map at floor_number, standard_combats before it in its step.
func _draw_only(
		map: CombatMapDefinition, floor_number: int, standard_combats: int, run_seed: int
) -> CombatEncounter.EncounterSetup:
	var battle: CombatEncounter = CombatEncounter.new(
			floor_number, NODE, PackedInt32Array([0]), InstanceIdAllocator.new()
	)
	battle.add_setup_step(
			CombatEncounter.SetupStep.ENEMY_SLOTS,
			EnemySetup.draw.bind(_catalog, floor_number, 0, standard_combats)
	)
	var pool: Array[CombatMapDefinition] = [map]
	battle.run_setup(pool, CombatEncounter.SetupStreams.new(run_seed, floor_number, NODE))
	return battle.setup


func _result(setup: CombatEncounter.EncounterSetup) -> Dictionary:
	var drawn: Variant = setup.shared.get(EnemySetup.ENEMIES_KEY, {})
	return drawn if drawn is Dictionary else {}


func _tile_of(entry: Dictionary) -> Vector2i:
	var tile: Variant = entry.get(EnemySetup.TILE_KEY, null)
	if not tile is Array or (tile as Array).size() != 2:
		return CombatFact.NO_TILE
	var parts: Array = tile
	return Vector2i(_whole(parts[0]), _whole(parts[1]))


# A whole number from plain data, an int or a float; 0 for anything else.
func _whole(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	var number: float = value
	return roundi(number)


# Defeats each unit in order through CombatState.defeat, by by_id; a test command, so a case's
# defeats need no roll.
class DefeatFixture:
	extends Command

	var unit_ids: PackedStringArray = []
	var by_id: String = ""

	func _init(defeated: Array[String], defeated_by: String) -> void:
		unit_ids = PackedStringArray(defeated)
		by_id = defeated_by

	func get_label() -> String:
		return "defeat"

	func resolve(session: CombatSession) -> void:
		for unit_id: String in unit_ids:
			session.state.defeat(session.engine, unit_id, by_id)
