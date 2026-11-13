# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     sessions_case_base.gd
# Author:
# Created:  November 9, 2026
# Modified: November 12, 2026
# ==============================================================================

extends RefCounted
## Shared by the case files split from the sessions suite's runner: reporting through its check,
## the tree's root for reaching autoloads as nodes, the skip count, and the values, helpers and
## fixtures more than one of them uses. Never names an autoload: a suite compiles before they
## are registered.

# The combat map tests' fixture: 5 × 4, deployment (0, 3) (1, 3) (2, 3), an enemy slot at (3, 2),
# a chest (container 0) at (0, 0) and a house (container 1) at (0, 2).
const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")

const WireCases = preload("res://tests/sessions/wire_cases.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# Any fixed seed: these cases compare runs with each other, never with golden numbers.
const TEST_STREAM_SEED: int = 0x5EED

# Any fixed run seed and combat node, for the same reason.
const RUN_SEED: int = 0x3F9A12C077E1A
const FLOOR: int = 2
const NODE: int = 5

# NetLog.Level values: this script can't name the autoload (see the class doc).
const LOG_WARN: int = 1
const LOG_DEBUG: int = 3

## The tree's root: the suite's script is a [SceneTree] and the case files aren't.
var root: Window = null

var _report: Callable
var _skips: int = 0


func _init(check: Callable, tree_root: Window) -> void:
	_report = check
	root = tree_root


## Runs every case in the file. Each case file overrides it.
func run() -> void:
	pass


## How many cases this file skipped, for the suite's summary line.
func skip_count() -> int:
	return _skips


# A battle request on the fixture map: each seat's army from its unit types, in roster order. Its
# catalog has no packs, so no enemies are drawn and a case places its own.
func _request(run: CampaignSession, types_by_seat: Dictionary) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = Battle.pool(["map_a"])
	request.catalog = WireCases.Kit.catalog_without_packs()
	# Untyped: callers pass dictionary literals, which are untyped.
	for seat: Variant in types_by_seat:
		var army: CampaignSession.Army = CampaignSession.Army.new()
		var types: Array = types_by_seat[seat]
		for unit_type: Variant in types:
			var unit: CombatUnitState = CombatUnitState.new()
			unit.id = run.ids.next_unit_id(unit_type as String)
			unit.seat = seat as int
			unit.unit_type = unit_type as String
			unit.hp = 20
			army.units.append(unit)
			army.bases[unit.id] = Battle.unit_bases()
		request.armies[seat as int] = army
	return request


func _add_enemy(run: CampaignSession, session: CombatSession) -> String:
	var enemy: CombatUnitState = CombatUnitState.new()
	enemy.id = run.ids.next_enemy_id("Brute")
	enemy.side = ENEMY
	enemy.tile = Vector2i(3, 2)
	enemy.hp = 20
	session.add_unit(enemy, Battle.unit_bases())
	return enemy.id


# "Hit dealt by Any Ally Unit: that unit gains 2 Block", every [param every]th hit this combat.
func _every_hit_by_allies(every: int) -> EffectDefinition:
	var definition: EffectDefinition = _hit_dealt_block("war_ledger", 2.0, every)
	definition.scope = EffectTerms.Scope.ANY_ALLY_UNIT
	var gain: GainResource = definition.operations[0] as GainResource
	gain.target = FactActor.new()
	return definition


# "Hit dealt: gain [param block] Block", every [param every]th hit this combat when above 1.
func _hit_dealt_block(id: String, block: float, every: int = 1) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.id = id
	definition.trigger = EffectTerms.Trigger.HIT_DEALT
	if every > 1:
		var counter: CounterCondition = CounterCondition.new()
		counter.count = every
		definition.conditions.append(counter)
	var gain: GainResource = GainResource.new()
	gain.pool = GainResource.Pool.BLOCK
	var amount: Constant = Constant.new()
	amount.value = block
	gain.amount = amount
	definition.operations.append(gain)
	return definition


func _first_of(facts: Array[CombatFact], kind: CombatFact.Kind) -> CombatFact:
	for fact: CombatFact in facts:
		if fact.kind == kind:
			return fact
	return CombatFact.new(kind)


func _kinds_of(facts: Array[CombatFact]) -> String:
	var names: PackedStringArray = []
	for fact: CombatFact in facts:
		names.append(CombatFact.Kind.find_key(fact.kind) as String)
	return " ".join(names)


# Whether this run uses a test user folder, which the lifecycle cases need (see run_all.gd's class
# doc): a custom one whose name starts "bandit_bash_tests", as tools/run_tests.sh names each run's.
func _has_test_user_dir() -> bool:
	var custom_dir: bool = ProjectSettings.get_setting(
			"application/config/use_custom_user_dir", false
	)
	var dir_name: String = ProjectSettings.get_setting(
			"application/config/custom_user_dir_name", ""
	)
	return custom_dir and dir_name.begins_with("bandit_bash_tests")


# Runs one case. A script error aborts a case without failing a check, so each case returns true
# at its end and a case that doesn't is reported.
func _run(test: Callable) -> void:
	var finished: Variant = test.call()
	if not (finished is bool and finished as bool):
		_check("%s ran to its end" % [test.get_method()], false)


func _set_log_level(level: int) -> void:
	root.get_node(^"NetLog").set(&"min_level", level)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)


# One session on the fixture map, rolling from a fixed stream, with units minted by its allocator.
class World:
	extends RefCounted

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = null

	func _init(seats: PackedInt32Array = PackedInt32Array([0])) -> void:
		var grid: MapGrid = MapGrid.new(World.fixture_layout())
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(TEST_STREAM_SEED))
		session = CombatSession.new(0, seats, grid, rolls, ids)
		session.engine.verify = true

	# Places a unit of [param unit_type] with HP 20, Stance 2 and 5 movement. Returns its id.
	func add_unit(
			unit_type: String, side: CombatFact.CombatSide, seat: int, tile: Vector2i
	) -> String:
		var id: String = ""
		if side == CombatFact.CombatSide.PLAYER:
			id = ids.next_unit_id(unit_type)
		else:
			id = ids.next_enemy_id(unit_type)
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.unit_type = unit_type
		unit.hp = 20
		session.add_unit(unit, {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
		})
		return id

	# Registers [param definition] as a trait of [param unit_id]. Returns the instance id.
	func add_trait(unit_id: String, definition: EffectDefinition) -> String:
		var state: CombatState = session.state
		var instance: EffectInstance = EffectInstance.new(
				ids.next_effect_id(),
				definition,
				EffectOwner.for_unit(unit_id, state.seat_of(unit_id), state.side_of(unit_id)),
				Modifier.SourceKind.UNIT_TRAIT
		)
		session.engine.register(instance)
		return instance.instance_id

	# The fixture map's layout.
	static func fixture_layout() -> MapLayout:
		var definition: CombatMapDefinition = CombatMapDefinition.new()
		definition.id = "fixture"
		definition.scene = FIXTURE_SCENE
		return MapLoader.load_layout(definition)


# One encounter on the fixture map for the given seats, with the run's stream registry beside it
# as the campaign session holds it. With loot, a step 7 fills every container from its stream.
class Battle:
	extends RefCounted

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var rng: RngStreams = RngStreams.new(RUN_SEED)
	var encounter: CombatEncounter = null

	func _init(
			seats: PackedInt32Array = PackedInt32Array([0]), with_loot: bool = false
	) -> void:
		encounter = CombatEncounter.new(FLOOR, NODE, seats, ids)
		if with_loot:
			encounter.add_setup_step(
					CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers
			)

	# Fresh setup streams for this battle's node.
	func make_streams() -> CombatEncounter.SetupStreams:
		return CombatEncounter.SetupStreams.new(rng.run_seed, FLOOR, NODE)

	func set_up(
			map_pool: Array[CombatMapDefinition] = Battle.pool(["map_a"])
	) -> Error:
		return encounter.run_setup(map_pool, make_streams())

	# Opens a session per seat, each with its seat's COMBAT_ROLLS stream from the registry.
	func open() -> bool:
		var rolls: Dictionary[int, RngStream] = {}
		for seat: int in encounter.seats:
			rolls[seat] = rng.stream(Battle.rolls_key(seat))
		return encounter.open_sessions(rolls)

	# Places a unit on a map with the standard bases. Returns its id.
	func add_unit(
			session_id: int,
			unit_type: String,
			side: CombatFact.CombatSide,
			seat: int,
			tile: Vector2i
	) -> String:
		var unit: CombatUnitState = CombatUnitState.new()
		if side == CombatFact.CombatSide.PLAYER:
			unit.id = ids.next_unit_id(unit_type)
		else:
			unit.id = ids.next_enemy_id(unit_type)
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.unit_type = unit_type
		unit.hp = 20
		encounter.get_session(session_id).add_unit(unit, Battle.unit_bases())
		return unit.id

	# An instance of [param definition] owned by [param seat]'s army, as a heirloom.
	func army_effect(seat: int, definition: EffectDefinition) -> EffectInstance:
		return EffectInstance.new(
				ids.next_effect_id(),
				definition,
				EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(seat), seat),
				Modifier.SourceKind.HEIRLOOM
		)

	# Map definitions on the fixture scene, one per id, in order.
	static func pool(map_ids: Array[String]) -> Array[CombatMapDefinition]:
		var maps: Array[CombatMapDefinition] = []
		for map_id: String in map_ids:
			var definition: CombatMapDefinition = CombatMapDefinition.new()
			definition.id = map_id
			definition.scene = FIXTURE_SCENE
			maps.append(definition)
		return maps

	# A stream of this battle's node derived from scratch, to compare draws with.
	static func fresh_stream(purpose: RngKey.RngPurpose, seat: int, index: int) -> RngStream:
		return RngStream.new(RngKey.derive_seed(RUN_SEED, purpose, FLOOR, NODE, seat, index))

	static func rolls_key(seat: int) -> RngKey:
		return RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, FLOOR, NODE, seat, -1)

	# HP 20, Stance 2 and 5 movement.
	static func unit_bases() -> Dictionary:
		return {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
		}

	# A step-7 fake: each container on the map gets a numbered item from its own stream.
	static func fill_containers(ctx: CombatEncounter.SetupContext) -> void:
		for marker: MapLayout.Marker in ctx.setup.layout.markers_of(
				MapLayout.MarkerKind.OBJECT_SPOT
		):
			if marker.container_index < 0:
				continue
			var stream: RngStream = ctx.loot_stream(marker.container_index)
			ctx.seat_setup.map.contents[marker.container_index] = (
					"item_%d" % [stream.randi_range(0, 1 << 30)]
			)


# Moves its unit to a free tile and records UNIT_MOVED. Needs no forecast.
class MoveFixture:
	extends Command

	var to_tile: Vector2i = Vector2i.ZERO

	func _init(sender: int, unit_id: String, tile: Vector2i) -> void:
		seat = sender
		actor_id = unit_id
		to_tile = tile

	func get_label() -> String:
		return "move"

	func validate(session: CombatSession) -> String:
		if not session.state.has_unit(actor_id):
			return "%s isn't on the map" % [actor_id]
		if not session.state.occupant_at(to_tile).is_empty():
			return "%s is taken" % [to_tile]
		return ""

	func resolve(session: CombatSession) -> void:
		session.state.move_unit(actor_id, to_tile)
		var moved: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, actor_id)
		moved.tile = to_tile
		session.engine.record(moved)


# Records one hit of its unit on a target, as an exchange would; it needs a fresh forecast.
class AttackFixture:
	extends Command

	var target: String = ""

	func _init(sender: int, unit_id: String, target_id: String) -> void:
		seat = sender
		actor_id = unit_id
		target = target_id

	func get_label() -> String:
		return "attack"

	func get_target_id() -> String:
		return target

	func needs_fresh_forecast() -> bool:
		return true

	func validate(session: CombatSession) -> String:
		if not session.state.has_unit(actor_id) or not session.state.has_unit(target):
			return "both units must be on the map"
		return ""

	func resolve(session: CombatSession) -> void:
		session.engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, actor_id, target))
		session.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, actor_id, target))
		session.engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, target, actor_id))


# A rune cast by its seat on a unit: RUNE_USED (the casting seat in amount), then a heal of 5.
class RuneFixture:
	extends Command

	var rune_id: String = ""
	var target: String = ""

	func _init(sender: int, rune: String, target_id: String) -> void:
		seat = sender
		rune_id = rune
		target = target_id

	func get_label() -> String:
		return "rune"

	func get_target_id() -> String:
		return target

	func validate(session: CombatSession) -> String:
		return "" if session.state.has_unit(target) else "%s isn't on the map" % [target]

	func resolve(session: CombatSession) -> void:
		var used: CombatFact = CombatFact.new(CombatFact.Kind.RUNE_USED, "", target)
		used.item_id = rune_id
		used.amount = seat
		used.tile = session.state.tile_of(target)
		session.engine.record(used)
		session.engine.heal(target, 5.0)


# Draws three rolls through the session's roll source, as an exchange would, and records the
# attack.
class RollFixture:
	extends Command

	var target: String = ""

	func _init(sender: int, unit_id: String, target_id: String) -> void:
		seat = sender
		actor_id = unit_id
		target = target_id

	func resolve(session: CombatSession) -> void:
		session.engine.rolls.roll_hit_2rn(70)
		session.engine.rolls.roll_percent(25)
		session.engine.rolls.pick_index(3)
		session.engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, actor_id, target))


# Ends the map's combat as the objectives check will (P04 MP4), naming the side that won.
class EndMapFixture:
	extends Command

	var winner: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

	func _init(winning_side: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER) -> void:
		winner = winning_side

	func resolve(session: CombatSession) -> void:
		var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
		ended.side = winner
		session.engine.record(ended)
