# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     state_cases.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## The combat state's cases for tests/combat/run_all.gd: the stub grid, [CombatUnitState],
## [CombatState] (placement, occupancy, the [SandboxState] reads and writes, sandbox copies,
## defeat), [SplashResolver] through the engine, dormancy, and the combat core's value keys.
## Reports each case through the check callable it is given.

# Preloaded scripts used as types (gdscript.md, Naming): the test map and stub have no class name.
const CombatWorld = preload("res://tests/combat/combat_world.gd")
const StubGrid = preload("res://tests/combat/stub_combat_grid.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const OBJECT_SIDE: CombatFact.CombatSide = CombatFact.CombatSide.NONE
const ADD: Modifier.Mode = Modifier.Mode.ADD

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_stub_grid()
	_test_placement()
	_test_reads()
	_test_walking_distance_uses_the_walker()
	_test_occupancy()
	_test_defeat()
	_test_sandbox_copy()
	_test_engine_paths()
	_test_splash()
	_test_dormancy()
	_test_sandbox_purity()
	_test_value_keys_present()


func _test_stub_grid() -> void:
	var grid: StubGrid = StubGrid.new(Vector2i(4, 3))
	_ok(
			"grid: distance is tiles up plus across",
			grid.distance(Vector2i(0, 0), Vector2i(3, 2)) == 5
	)
	_ok(
			"grid: the open stub walks the grid distance",
			grid.walking_distance(Vector2i(0, 0), Vector2i(3, 2), CombatGrid.MovementType.HEAVY)
			== 5
	)
	_ok(
			"grid: no walk off the map",
			grid.walking_distance(Vector2i(0, 0), Vector2i(4, 0), CombatGrid.MovementType.DEFAULT)
			== -1
	)
	_ok("grid: a corner has two neighbors", grid.neighbors(Vector2i(0, 0)).size() == 2)
	_ok("grid: a middle tile has four", grid.neighbors(Vector2i(1, 1)).size() == 4)
	_ok("grid: a step off the map", grid.step(Vector2i(3, 0), Vector2i.RIGHT) == CombatFact.NO_TILE)
	_ok("grid: a step on the map", grid.step(Vector2i(1, 1), Vector2i.UP) == Vector2i(1, 0))

	grid.set_blocker(Vector2i(2, 0), CombatGrid.Blocker.SPIKED_WALL)
	grid.forbid(Vector2i(1, 2), CombatGrid.MovementType.DEFAULT)
	grid.set_slick(Vector2i(2, 2))
	_ok("grid: a spiked wall", grid.blocker_at(Vector2i(2, 0)) == CombatGrid.Blocker.SPIKED_WALL)
	_ok("grid: off the map blocks", grid.blocker_at(Vector2i(-1, 0)) == CombatGrid.Blocker.PLAIN)
	_ok("grid: nobody stands in a wall", not grid.can_stand(Vector2i(2, 0), 4))
	_ok(
			"grid: water stops units on foot, not fliers",
			not grid.can_stand(Vector2i(1, 2), CombatGrid.MovementType.DEFAULT)
			and grid.can_stand(Vector2i(1, 2), CombatGrid.MovementType.FLIER)
	)
	_ok("grid: oil is slick", grid.is_slick(Vector2i(2, 2)) and not grid.is_slick(Vector2i(0, 0)))
	var bonus: CombatGrid.TileBonus = grid.tile_bonus(Vector2i(0, 0))
	_ok("grid: plain ground has no bonus", bonus.avoid == 0 and bonus.defense == 0)

	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var check: CombatGrid.PathCheck = grid.validate_path("p1", path)
	_ok("grid: a legal path", check.is_legal and check.tiles_moved == 2 and check.cost == 2)
	path.append(Vector2i(2, 0))
	_ok("grid: a jump is illegal", not grid.validate_path("p1", path).is_legal)


func _test_placement() -> void:
	var world: CombatWorld = CombatWorld.new()
	var p1: CombatUnitState = world.add_unit(
			"p1", PLAYER, 0, Vector2i(1, 1), {CombatValue.Key.STANCE_MAX: 3.0}
	)
	_ok("place: placed", p1 != null and world.state.has_unit("p1"))
	_ok("place: full Stance from STANCE_MAX", p1.stance == 3 and world.state.get_stance("p1") == 3)
	_ok("place: Block starts at 0", p1.block == 0)
	_ok("place: on its tile", world.state.occupant_at(Vector2i(1, 1)) == "p1")
	_ok("place: no facts", world.engine.fact_log.is_empty())

	var again: CombatUnitState = CombatUnitState.new()
	again.id = "p1"
	again.tile = Vector2i(2, 2)
	_ok("place: a known id is refused", not world.state.place_unit(world.engine, again))
	var crowded: CombatUnitState = CombatUnitState.new()
	crowded.id = "p2"
	crowded.tile = Vector2i(1, 1)
	_ok("place: a taken tile is refused", not world.state.place_unit(world.engine, crowded))
	var nowhere: CombatUnitState = CombatUnitState.new()
	nowhere.id = "p3"
	_ok("place: no tile is refused", not world.state.place_unit(world.engine, nowhere))
	_ok("place: refusals place nothing", world.state.unit_ids() == PackedStringArray(["p1"]))
	_quiet(world)


func _test_reads() -> void:
	var world: CombatWorld = _two_sides()
	var state: CombatState = world.state
	_ok("reads: placement order", state.unit_ids() == PackedStringArray(["p1", "p2", "e1"]))
	_ok("reads: units of a side", state.units_of(ENEMY) == PackedStringArray(["e1"]))
	_ok("reads: sides", state.side_of("p1") == PLAYER and state.side_of("e1") == ENEMY)
	_ok("reads: seats", state.seat_of("p2") == 1 and state.seat_of("e1") == -1)
	_ok("reads: unknown id", state.side_of("x") == OBJECT_SIDE and state.seat_of("x") == -1)
	_ok("reads: tiles", state.tile_of("e1") == Vector2i(3, 1))
	_ok("reads: unknown tile", state.tile_of("x") == CombatFact.NO_TILE)
	_ok("reads: hp", state.get_hp("p1") == 20)
	state.unit("p1").tiles_moved = 3
	state.unit("p1").equipped_weapon_id = "item:1"
	_ok("reads: tiles moved", state.tiles_moved("p1") == 3)
	_ok("reads: equipped weapon", state.equipped_weapon_id("p1") == "item:1")
	_ok("reads: dry until the darkness plan", state.darkness_layer("p1") == 0)
	state.set_hp("p1", 7)
	state.set_block("p1", 4)
	state.set_stance("p1", 1)
	_ok(
			"writes: hp, block, stance",
			state.get_hp("p1") == 7 and state.get_block("p1") == 4 and state.get_stance("p1") == 1
	)
	_quiet(world)


func _test_walking_distance_uses_the_walker() -> void:
	var grid: RecordingGrid = RecordingGrid.new()
	var state: CombatState = CombatState.new(grid)
	var engine: EffectEngine = EffectEngine.new(state, ForcedRolls.new(PackedInt32Array()))
	for id: String in ["flier", "foot"]:
		engine.set_base(id, CombatValue.Key.STANCE_MAX, 2.0)
	var flier: CombatUnitState = _unit("flier", PLAYER, 0, Vector2i(0, 0))
	flier.movement_type = CombatGrid.MovementType.FLIER
	var foot: CombatUnitState = _unit("foot", PLAYER, 0, Vector2i(2, 0))
	state.place_unit(engine, flier)
	state.place_unit(engine, foot)
	_ok("walk: a flier walks the grid", state.walking_distance("flier", "foot") == 2)
	_ok("walk: with its own movement type", grid.last_type == CombatGrid.MovementType.FLIER)
	_ok("walk: on foot, the long way round", state.walking_distance("foot", "flier") == 4)
	_ok("walk: the walker's type, not the target's", grid.last_type == 0)
	_ok("walk: nobody to walk to", state.walking_distance("foot", "x") == -1)

	var within: WhilePositionCondition = WhilePositionCondition.new()
	within.kind = WhilePositionCondition.Kind.WITHIN
	within.tiles = 3
	within.distance = EffectDefinition.Distance.MOVABLE
	var ctx: EffectContext = EffectContext.new()
	ctx.engine = engine
	ctx.subject_id = "foot"
	_ok("walk: not within 3 movable tiles on foot", not within.test(ctx))
	ctx.subject_id = "flier"
	_ok("walk: within 3 movable tiles flying", within.test(ctx))
	within.distance = EffectDefinition.Distance.GRID
	ctx.subject_id = "foot"
	_ok("walk: within 3 tiles either way", within.test(ctx))


func _test_occupancy() -> void:
	var world: CombatWorld = _two_sides()
	var state: CombatState = world.state
	world.grid.set_blocker(Vector2i(5, 5), CombatGrid.Blocker.SPIKED_WALL)
	world.add_unit("keg", OBJECT_SIDE, -1, Vector2i(4, 4))
	_ok("blocker: a unit", state.blocker_at(Vector2i(3, 1)) == CombatGrid.Blocker.UNIT)
	_ok("blocker: an object", state.blocker_at(Vector2i(4, 4)) == CombatGrid.Blocker.PLAIN)
	_ok("blocker: the grid's", state.blocker_at(Vector2i(5, 5)) == CombatGrid.Blocker.SPIKED_WALL)
	_ok("blocker: open ground", state.blocker_at(Vector2i(6, 6)) == CombatGrid.Blocker.NONE)

	state.move_unit("p1", Vector2i(0, 3))
	_ok(
			"move: occupancy follows",
			state.occupant_at(Vector2i(0, 3)) == "p1"
			and state.occupant_at(Vector2i(1, 1)).is_empty()
	)
	state.move_unit("p1", Vector2i(3, 1))
	_ok("move: onto a unit is ignored", state.tile_of("p1") == Vector2i(0, 3))
	state.swap_units("p1", "e1")
	_ok(
			"swap: tiles and occupancy",
			state.tile_of("p1") == Vector2i(3, 1) and state.tile_of("e1") == Vector2i(0, 3)
			and state.occupant_at(Vector2i(3, 1)) == "p1"
			and state.occupant_at(Vector2i(0, 3)) == "e1"
	)
	_ok("move: no facts", world.engine.fact_log.is_empty())
	_quiet(world)


func _test_defeat() -> void:
	var world: CombatWorld = _two_sides()
	var state: CombatState = world.state
	state.defeat(world.engine, "e1", "p1")
	_ok(
			"defeat: off the map",
			not state.has_unit("e1") and state.tile_of("e1") == CombatFact.NO_TILE
	)
	_ok("defeat: the tile is free", state.occupant_at(Vector2i(3, 1)).is_empty())
	_ok("defeat: side and seat stay readable", state.side_of("e1") == ENEMY)
	_ok("defeat: out of unit_ids", not state.unit_ids().has("e1"))
	_same("defeat: facts", world.kinds(), "DEFEATED DEFEATED_AN_ENEMY")
	state.defeat(world.engine, "p2", "p1")
	_same(
			"defeat: an ally's kill isn't an enemy defeated", world.kinds(2), "DEFEATED"
	)
	state.defeat(world.engine, "p2", "p1")
	_ok("defeat: only once", world.engine.fact_log.size() == 3)
	_quiet(world)


func _test_sandbox_copy() -> void:
	var world: CombatWorld = _two_sides()
	var state: CombatState = world.state
	state.turn = 2
	state.phase_side = PLAYER
	state.ended_seats.append(1)
	state.rune_slots[0] = PackedStringArray(["rune:1"])
	var copy: CombatState = state.copy_for_sandbox()
	_ok("copy: same grid", copy.grid == state.grid)
	_ok("copy: same units", copy.unit_ids() == state.unit_ids())
	_ok(
			"copy: turn, phase, seats and runes",
			copy.turn == 2 and copy.phase_side == PLAYER and copy.ended_seats.has(1)
			and copy.rune_slots[0].has("rune:1")
	)
	copy.set_hp("p1", 1)
	copy.move_unit("p2", Vector2i(6, 6))
	copy.defeat(world.engine, "e1", "p1")
	copy.rune_slots[0].clear()
	copy.ended_seats.append(0)
	copy.unit("p1").tags.append("Flier")
	copy.add_growth("p1", CombatValue.Stat.RES, 5)
	_ok("copy: hp is its own", state.get_hp("p1") == 20)
	_ok("copy: occupancy is its own", state.tile_of("p2") == Vector2i(1, 2))
	_ok("copy: defeats are its own", state.has_unit("e1"))
	_ok("copy: runes are their own", state.rune_slots[0].has("rune:1"))
	_ok("copy: seats are their own", not state.ended_seats.has(0))
	_ok("copy: tags are their own", state.unit("p1").tags.is_empty())
	_ok("copy: growth changes are their own", state.unit("p1").growth_changes.is_empty())
	state.add_growth("p1", CombatValue.Stat.RES, 5)
	state.add_growth("p1", CombatValue.Stat.RES, 5)
	state.add_growth("ghost", CombatValue.Stat.RES, 5)
	_ok(
			"growth: changes add up per stat",
			state.unit("p1").growth_changes == {CombatValue.Stat.RES: 10}
	)


func _test_engine_paths() -> void:
	var world: CombatWorld = _two_sides()
	var engine: EffectEngine = world.engine
	var state: CombatState = world.state
	engine.gain_block("p1", 3.0, "p2")
	_ok("paths: Block gained", state.get_block("p1") == 3)
	engine.lose_block("p1", 5.0)
	_ok("paths: Block lost, never below 0", state.get_block("p1") == 0)
	state.set_hp("p1", 15)
	_ok("paths: heal capped at maximum HP", engine.heal("p1", 8.0, "p2") == 5)
	_ok("paths: back to full", state.get_hp("p1") == 20)
	engine.change_stance("p1", -2.0, "e1")
	_ok("paths: Stance to 0", state.get_stance("p1") == 0)
	engine.change_stance("p1", 5.0)
	_ok("paths: Stance capped at its maximum", state.get_stance("p1") == 2)
	_same(
			"paths: facts",
			world.kinds(),
			"BLOCK_GAINED BLOCK_LOST HEALED_AN_ALLY HEALED STANCE_CHANGED EXPOSED STANCE_CHANGED"
	)
	_quiet(world)


func _test_splash() -> void:
	var world: CombatWorld = _two_sides()
	var engine: EffectEngine = world.engine
	var state: CombatState = world.state
	state.set_block("e1", 1)
	engine.deal_splash("p1", "e1", 3.0, "effect:cleave")
	_ok("splash: Block absorbs, then HP", state.get_block("e1") == 0 and state.get_hp("e1") == 18)
	_ok("splash: no Stance lost", state.get_stance("e1") == 2)
	_same(
			"splash: Damage taken only",
			world.log_lines()[0],
			"s0#1 DAMAGE_TAKEN e1 <- p1 amount 3 (hp 2, block 1) source splash effect effect:cleave"
	)
	engine.deal_splash("p1", "e1", 0.0)
	_ok("splash: nothing for 0", engine.fact_log.size() == 1)
	SplashResolver.deal(engine, state, "p2", "e1", 30, CombatFact.Source.BUMP)
	_same("splash: a lethal bump", world.kinds(1), "DAMAGE_TAKEN DEFEATED DEFEATED_AN_ENEMY")
	_ok("splash: overkill isn't counted", engine.fact_log[1].amount == 18)
	_ok("splash: source kept", engine.fact_log[1].source == CombatFact.Source.BUMP)
	_ok("splash: defeated", not state.has_unit("e1"))
	SplashResolver.deal(engine, state, "p2", "e1", 3, CombatFact.Source.SPIKE)
	_ok("splash: nothing off the map", engine.fact_log.size() == 4)
	_quiet(world)


func _test_dormancy() -> void:
	var world: CombatWorld = _two_sides()
	var engine: EffectEngine = world.engine
	var state: CombatState = world.state
	var hit_bonus: EffectDefinition = _always(CombatValue.Key.HIT, 10.0)
	world.add_effect("effect:sword", hit_bonus, "p1", Modifier.SourceKind.WEAPON, "item:sword")
	world.add_effect("effect:axe", _always(CombatValue.Key.HIT, 20.0), "p1",
			Modifier.SourceKind.WEAPON, "item:axe")
	state.unit("p1").equipped_weapon_id = "item:sword"
	state.unit("p1").stowed_weapon_id = "item:axe"
	_ok(
			"dormant: only the Weapon slot counts",
			engine.stats("p1").get_int(CombatValue.Key.HIT) == 10
	)
	state.unit("p1").equipped_weapon_id = "item:axe"
	state.unit("p1").stowed_weapon_id = "item:sword"
	_ok("dormant: a swap wakes the other", engine.stats("p1").get_int(CombatValue.Key.HIT) == 20)

	world.add_effect("effect:trait", _always(CombatValue.Key.AVOID, 5.0), "e1")
	_ok("dormant: a trait on the map", engine.stats("e1").get_int(CombatValue.Key.AVOID) == 5)
	state.defeat(engine, "e1", "p1")
	_ok(
			"dormant: a defeated unit's trait sleeps",
			engine.stats("e1").get_int(CombatValue.Key.AVOID) == 0
	)
	_quiet(world)


func _test_sandbox_purity() -> void:
	var world: CombatWorld = _two_sides()
	var engine: EffectEngine = world.engine
	var state: CombatState = world.state
	var sandbox: Sandbox = Sandbox.new(engine, ForecastRolls.new())
	var copy: CombatState = sandbox.engine.state
	_ok("sandbox: a CombatState copy", copy != state and copy.unit_ids() == state.unit_ids())
	sandbox.engine.deal_splash("p1", "e1", 30.0)
	sandbox.engine.gain_block("p1", 4.0)
	_ok("sandbox: the copy changed", not copy.has_unit("e1") and copy.get_block("p1") == 4)
	_ok(
			"sandbox: the real state didn't",
			state.has_unit("e1") and state.get_hp("e1") == 20 and state.get_block("p1") == 0
			and state.occupant_at(Vector2i(3, 1)) == "e1"
	)
	_ok("sandbox: no real facts", engine.fact_log.is_empty())
	_ok("sandbox: no diagnostics", sandbox.engine.diagnostics.is_empty())


func _test_value_keys_present() -> void:
	var keys: PackedStringArray = [
		"ATTACK_SPEED", "NET_WEIGHT", "ATK_X", "PARRY", "HIT", "AVOID", "CRIT_CHANCE", "CRIT_X",
		"STANCE_MAX", "SHOVE_DISTANCE", "RANGE_MIN", "RANGE_MAX", "DAMAGE_TYPE",
		"EFFECTIVE_MODIFIER", "STAFF_AMOUNT", "MOVEMENT",
	]
	var missing: PackedStringArray = []
	for key: String in keys:
		if not CombatValue.Key.has(key):
			missing.append(key)
	for key: String in ["ATTACK", "MITIGATION", "CRITICAL", "MULTIPLIERS"]:
		if not DamageStage.Key.has(key):
			missing.append(key)
	for key: String in [
		"CAN_COUNTER", "CAN_BE_SHOVED", "MAY_MOVE_AFTER_ACTING", "FREE_WEAPON_SWAP",
		"SKIP_MITIGATION_ON_CRIT",
	]:
		if not CombatValue.Permission.has(key):
			missing.append(key)
	if not CampaignValue.Key.has("POUCH_ITEM_WEIGHT"):
		missing.append("POUCH_ITEM_WEIGHT")
	_ok("keys: every combat core key and permission is seeded", missing.is_empty(), str(missing))


# p1 (seat 0) and p2 (seat 1) on the player side, e1 on the enemy side, all at 20 HP.
func _two_sides() -> CombatWorld:
	var world: CombatWorld = CombatWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(1, 1))
	world.add_unit("p2", PLAYER, 1, Vector2i(1, 2))
	world.add_unit("e1", ENEMY, -1, Vector2i(3, 1))
	return world


func _unit(id: String, side: CombatFact.CombatSide, seat: int, tile: Vector2i) -> CombatUnitState:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.side = side
	unit.seat = seat
	unit.tile = tile
	unit.hp = 20
	return unit


# An always-on "+value" to key.
func _always(key: int, value: float) -> EffectDefinition:
	var modify: ModifyValue = ModifyValue.new()
	modify.key = key
	modify.mode = ADD
	modify.value = value
	var definition: EffectDefinition = EffectDefinition.new()
	definition.operations.assign([modify])
	return definition


# Every scenario ends with no engine diagnostics.
func _quiet(world: CombatWorld) -> void:
	var engine: EffectEngine = world.engine
	_ok("diagnostics: none", engine.diagnostics.is_empty(), str(engine.diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])


## A grid that records the movement type it was asked about; a unit on foot walks twice as far.
class RecordingGrid:
	extends "res://tests/combat/stub_combat_grid.gd"

	## The movement type of the last walking_distance call.
	var last_type: int = -1

	func walking_distance(
			a: Vector2i, b: Vector2i, movement_type: CombatGrid.MovementType
	) -> int:
		last_type = movement_type
		var steps: int = super(a, b, movement_type)
		return steps if movement_type == CombatGrid.MovementType.FLIER else steps * 2
