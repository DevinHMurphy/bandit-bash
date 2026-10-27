# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     shove_cases.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## Shove and splash cases for tests/combat/run_all.gd: a golden fact log for each way a shove
## stops and for an oil slide, Shove legality, and the splash rule through bumps and spikes.
##
## Every shove starts with p1 at (1, 1) pushing the unit at (2, 1) to the right on an 8 by 4 stub
## map. Every scenario also asserts that the engine reported no diagnostics.

const CombatWorld: GDScript = preload("res://tests/combat/combat_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const OBJECT_SIDE: CombatFact.CombatSide = CombatFact.CombatSide.NONE
const FOOT: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT

# Reviewed golden fact logs, one CombatFact.to_log_line() per fact, by fixture name.
const GOLDEN: Dictionary[String, Array] = {
	"one tile": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 UNIT_MOVED e1 tile (3, 1)",
	],
	"off the map": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 UNIT_MOVED e1 tile (3, 1)",
	],
	"plain wall": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 UNIT_MOVED e1 tile (3, 1)",
	],
	"tile it can't stand on": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 UNIT_MOVED e1 tile (3, 1)",
	],
	"bump": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 DAMAGE_TAKEN e1 <- p1 amount 2 (hp 2, block 0) source bump",
		"s0#4 DAMAGE_TAKEN e2 <- p1 amount 2 (hp 2, block 0) source bump",
	],
	"spiked wall": [
		"s0#2 SHOVED_A_UNIT p1 -> e1",
		"s0#3 SHOVED e1 <- p1",
		"s0#4 DAMAGE_TAKEN e1 <- p1 amount 4 (hp 3, block 1) source spike",
	],
	"oil slide": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 UNIT_MOVED e1 tile (6, 1)",
	],
	"oil slide into a unit": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 UNIT_MOVED e1 tile (4, 1)",
		"s0#4 DAMAGE_TAKEN e1 <- p1 amount 2 (hp 2, block 0) source bump",
		"s0#5 DAMAGE_TAKEN p2 <- p1 amount 2 (hp 2, block 0) source bump",
	],
	"lethal bump": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 SHOVED e1 <- p1",
		"s0#3 DAMAGE_TAKEN e1 <- p1 amount 2 (hp 2, block 0) source bump",
		"s0#4 DEFEATED e1 <- p1",
		"s0#5 DEFEATED_AN_ENEMY p1 -> e1",
		"s0#6 DAMAGE_TAKEN e2 <- p1 amount 2 (hp 2, block 0) source bump",
	],
	"shove reaction": [
		"s0#1 SHOVED_A_UNIT p1 -> e1",
		"s0#2 EFFECT_ACTIVATED p1 effect effect:shoving_pole",
		"s0#3 SHOVED e1 <- p1",
		"s0#4 UNIT_MOVED e1 tile (3, 1)",
		"s0#5 BLOCK_GAINED p1 amount 2 (hp 0, block 2) source effect effect effect:shoving_pole",
	],
}

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_one_tile()
	_test_edge()
	_test_wall()
	_test_terrain()
	_test_bump()
	_test_spiked_wall()
	_test_oil_slide()
	_test_oil_slide_into_a_unit()
	_test_shove_distance()
	_test_lethal_bump()
	_test_legality()
	_test_reactions_resolve_inside()


func _test_one_tile() -> void:
	var world: Variant = _push()
	var result: ShoveResolver.Result = _shove(world)
	_ok("shove: legal", result.is_legal)
	_ok("shove: one tile away", world.state.tile_of("e1") == Vector2i(3, 1))
	_ok("shove: occupancy follows", world.state.occupant_at(Vector2i(2, 1)).is_empty())
	_ok("shove: marked shoved", world.state.unit("e1").has_been_shoved)
	_ok("shove: the shover acted", world.state.unit("p1").has_acted)
	_ok(
			"shove: not an attack",
			world.state.get_stance("e1") == 0 and world.state.get_hp("e1") == 20
	)
	_golden("one tile", world)


func _test_edge() -> void:
	var world: Variant = _push(Vector2i(4, 4))
	world.add_effect("effect:pole", _shove_bonus(1.0), "p1")
	var result: ShoveResolver.Result = _shove(world)
	_ok("edge: stops at the map's edge", world.state.tile_of("e1") == Vector2i(3, 1))
	_ok("edge: no damage", world.state.get_hp("e1") == 20)
	_ok("edge: why", result.path.stop == ShoveResolver.Stop.EDGE)
	_golden("off the map", world)


func _test_wall() -> void:
	var world: Variant = _push()
	world.grid.set_blocker(Vector2i(4, 1), CombatGrid.Blocker.PLAIN)
	world.add_effect("effect:pole", _shove_bonus(1.0), "p1")
	var result: ShoveResolver.Result = _shove(world)
	_ok("wall: stops before it", world.state.tile_of("e1") == Vector2i(3, 1))
	_ok("wall: no damage", world.state.get_hp("e1") == 20)
	_ok("wall: why", result.path.stop == ShoveResolver.Stop.BLOCKED)
	_golden("plain wall", world)


func _test_terrain() -> void:
	var world: Variant = _push()
	world.grid.forbid(Vector2i(4, 1), FOOT)
	world.add_effect("effect:pole", _shove_bonus(1.0), "p1")
	_shove(world)
	_ok("water: never onto a tile it can't stand on", world.state.tile_of("e1") == Vector2i(3, 1))
	_golden("tile it can't stand on", world)

	var flier: Variant = _push()
	flier.grid.forbid(Vector2i(4, 1), FOOT)
	flier.state.unit("e1").movement_type = CombatGrid.MovementType.FLIER
	flier.add_effect("effect:pole", _shove_bonus(1.0), "p1")
	_shove(flier)
	_ok("water: a flier crosses it", flier.state.tile_of("e1") == Vector2i(4, 1))
	_quiet(flier)


func _test_bump() -> void:
	var world: Variant = _push()
	world.add_unit("e2", ENEMY, -1, Vector2i(3, 1))
	var result: ShoveResolver.Result = _shove(world)
	_ok("bump: legal without moving (question 8)", result.is_legal and result.path.tiles_moved == 0)
	_ok("bump: both take 2", world.state.get_hp("e1") == 18 and world.state.get_hp("e2") == 18)
	_ok("bump: no Stance lost", world.state.get_stance("e2") == 2)
	_golden("bump", world)


func _test_spiked_wall() -> void:
	var world: Variant = _push()
	world.grid.set_blocker(Vector2i(3, 1), CombatGrid.Blocker.SPIKED_WALL)
	world.engine.gain_block("e1", 1.0)
	var start: int = world.engine.fact_log.size()
	var result: ShoveResolver.Result = _shove(world)
	_ok("spikes: legal without moving (question 8)", result.is_legal)
	_ok("spikes: 4 damage, Block first", world.state.get_hp("e1") == 17)
	_golden("spiked wall", world, start)


func _test_oil_slide() -> void:
	var world: Variant = _push()
	for x: int in [3, 4, 5]:
		world.grid.set_slick(Vector2i(x, 1))
	var result: ShoveResolver.Result = _shove(world)
	_ok("oil: slides past its Shove distance", world.state.tile_of("e1") == Vector2i(6, 1))
	_ok("oil: four tiles", result.path.tiles_moved == 4 and result.path.slid)
	_golden("oil slide", world)


func _test_oil_slide_into_a_unit() -> void:
	var world: Variant = _push()
	world.grid.set_slick(Vector2i(3, 1))
	world.grid.set_slick(Vector2i(4, 1))
	world.add_unit("p2", PLAYER, 0, Vector2i(5, 1))
	_shove(world)
	_ok("oil: stopped on the oil by a unit", world.state.tile_of("e1") == Vector2i(4, 1))
	_ok(
			"oil: the bump still hurts",
			world.state.get_hp("e1") == 18 and world.state.get_hp("p2") == 18
	)
	_golden("oil slide into a unit", world)


func _test_shove_distance() -> void:
	var world: Variant = _push()
	world.add_effect("effect:pole", _shove_bonus(1.0), "p1")
	var reach: int = world.engine.stats("p1").get_int(CombatValue.Key.SHOVE_DISTANCE)
	_ok("distance: 1 by default, 2 with +1", reach == 2)
	_shove(world)
	_ok("distance: two tiles", world.state.tile_of("e1") == Vector2i(4, 1))
	_quiet(world)


func _test_lethal_bump() -> void:
	var world: Variant = _push()
	world.add_unit("e2", ENEMY, -1, Vector2i(3, 1))
	world.state.set_hp("e1", 2)
	_shove(world)
	_ok("lethal bump: defeated", not world.state.has_unit("e1"))
	_ok("lethal bump: the other still takes its 2", world.state.get_hp("e2") == 18)
	_golden("lethal bump", world)


func _test_legality() -> void:
	var far: Variant = _push()
	far.state.move_unit("e1", Vector2i(3, 1))
	_same("legal: not adjacent", _reason(far), "not adjacent")
	var guarded: Variant = _push()
	guarded.state.set_stance("e1", 1)
	_same("legal: a foe with Stance can't be shoved", _reason(guarded), "a foe must be Exposed")
	var ally: Variant = _push()
	ally.add_unit("p2", PLAYER, 0, Vector2i(1, 2))
	_same(
			"legal: an ally is always willing",
			ShoveResolver.check(ally.engine, ally.state, "p1", "p2"),
			""
	)
	var twice: Variant = _push()
	_shove(twice)
	twice.state.move_unit("p1", Vector2i(2, 1))
	_same("legal: once per phase", _reason(twice), "already shoved this phase")
	var boss: Variant = _push()
	var unshovable: SetPermission = SetPermission.new()
	unshovable.permission = CombatValue.Permission.CAN_BE_SHOVED
	unshovable.allow = false
	var definition: EffectDefinition = EffectDefinition.new()
	definition.operations.assign([unshovable])
	boss.add_effect("effect:unshovable", definition, "e1")
	_same("legal: Unshovable", _reason(boss), "can't be shoved")
	var stuck: Variant = _push()
	stuck.grid.set_blocker(Vector2i(3, 1), CombatGrid.Blocker.PLAIN)
	_same("legal: nothing would happen", _reason(stuck), "nothing would happen")
	var keg: Variant = _push()
	keg.add_unit("keg", OBJECT_SIDE, -1, Vector2i(1, 2))
	_same(
			"legal: objects aren't shoved",
			ShoveResolver.check(keg.engine, keg.state, "p1", "keg"),
			"not a unit"
	)
	_ok("legal: refusals record nothing", stuck.engine.fact_log.is_empty())
	_ok("legal: refusals cost nothing", not stuck.state.unit("p1").has_acted)


func _test_reactions_resolve_inside() -> void:
	var world: Variant = _push()
	var amount: Constant = Constant.new()
	amount.value = 2.0
	var gain: GainResource = GainResource.new()
	gain.pool = GainResource.Pool.BLOCK
	gain.amount = amount
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = EffectDefinition.Trigger.SHOVED_A_UNIT
	definition.operations.assign([gain])
	world.add_effect("effect:shoving_pole", definition, "p1")
	_shove(world)
	_ok(
			"reaction: Shoved a unit's Block lands in the shove's drain",
			world.state.get_block("p1") == 2
	)
	_golden("shove reaction", world)


# p1 (seat 0) at (1, 1) facing an Exposed enemy e1 at (2, 1); every unit has 20 HP and Stance 2.
func _push(size: Vector2i = Vector2i(8, 4)) -> Variant:
	var world: Variant = CombatWorld.new(null, size)
	world.add_unit("p1", PLAYER, 0, Vector2i(1, 1))
	world.add_unit("e1", ENEMY, -1, Vector2i(2, 1))
	world.state.set_stance("e1", 0)
	return world


func _shove(world: Variant) -> ShoveResolver.Result:
	world.engine.begin_step()
	return ShoveResolver.resolve(world.engine, world.state, "p1", "e1")


func _reason(world: Variant) -> String:
	return ShoveResolver.check(world.engine, world.state, "p1", "e1")


# Always: Shove distance +amount.
func _shove_bonus(amount: float) -> EffectDefinition:
	var modify: ModifyValue = ModifyValue.new()
	modify.key = CombatValue.Key.SHOVE_DISTANCE
	modify.mode = Modifier.Mode.ADD
	modify.value = amount
	var definition: EffectDefinition = EffectDefinition.new()
	definition.operations.assign([modify])
	return definition


# Compares the log from start on with GOLDEN[name]; on a mismatch prints the actual log as a
# GDScript array for review. Also checks the engine reported no diagnostics.
func _golden(name: String, world: Variant, start: int = 0) -> void:
	var lines: Array[String] = world.log_lines(start)
	var expected: Array = GOLDEN.get(name, [])
	var same: bool = lines.size() == expected.size()
	for i: int in mini(lines.size(), expected.size()):
		same = same and lines[i] == expected[i]
	if not same:
		var listing: PackedStringArray = []
		for line: String in lines:
			listing.append("\t\t\"%s\"," % [line])
		print("GOLDEN \"%s\": [\n%s\n\t]," % [name, "\n".join(listing)])
	_ok("golden: %s" % [name], same)
	_quiet(world)


func _quiet(world: Variant) -> void:
	var engine: EffectEngine = world.engine
	_ok("diagnostics: none", engine.diagnostics.is_empty(), str(engine.diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
