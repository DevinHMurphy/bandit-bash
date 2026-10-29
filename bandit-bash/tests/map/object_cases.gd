# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     object_cases.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

extends RefCounted
## Map object cases for tests/map/run_all.gd: a golden fact log per object, an attack on debris
## shaped like one on a unit, kegs exploding and a three-keg chain, destroyed debris restoring its
## terrain, a lever both ways, keys and lockpicks, Cutthroat carry and drop, Spark through
## [constant CombatHooks.Hook.OBJECT_OPERATIONS], a sandbox leaving the real map alone, P06's
## queries, the door, lever and passage [MapMarker] kinds, and setup step 7's contents per seat.
##
## Most cases run a real [CombatSession] on a small plain map with the objects the case needs,
## placed by [method MapObjects.place], so actions go through [UnitTurnCommand] and
## [CastRuneCommand] as in a battle. Rolls are forced hits, so no case depends on a roll. Golden
## logs are fact log lines without their sequence prefix.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const USE: UnitTurnCommand.Action = UnitTurnCommand.Action.USE_OBJECT
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const WAIT: UnitTurnCommand.Action = UnitTurnCommand.Action.WAIT
const OBJECT_SPOT: MapLayout.MarkerKind = MapLayout.MarkerKind.OBJECT_SPOT

const CHEST: MapLayout.ObjectKind = MapLayout.ObjectKind.CHEST
const DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const LEVER: MapLayout.ObjectKind = MapLayout.ObjectKind.LEVER
const HOUSE: MapLayout.ObjectKind = MapLayout.ObjectKind.HOUSE
const BOOK_SHELF: MapLayout.ObjectKind = MapLayout.ObjectKind.BOOK_SHELF
const WOODEN: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS
const STONE: MapLayout.ObjectKind = MapLayout.ObjectKind.STONE_DEBRIS
const PASSAGE: MapLayout.ObjectKind = MapLayout.ObjectKind.PASSAGE
const KEG: MapLayout.ObjectKind = MapLayout.ObjectKind.POWDER_KEG
const BRAZIER: MapLayout.ObjectKind = MapLayout.ObjectKind.BRAZIER

const PLAIN_ROWS: Array[String] = [
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
]

const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")
const TILE_SET: TileSet = preload("res://maps/greybox_tile_set.tres")

# Any fixed run seed and node: the contents case compares streams, never golden numbers.
const RUN_SEED: int = 0x0B1EC7
const FLOOR: int = 3
const NODE: int = 2

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_placement()
	_test_chest()
	_test_chest_locks()
	_test_door()
	_test_lever()
	_test_searchables()
	_test_passage()
	_test_brazier()
	_test_debris()
	_test_attack_shape()
	_test_keg_hit()
	_test_keg_chain()
	_test_sandbox()
	_test_spark()
	_test_cutthroat()
	_test_darkness_queries()
	_test_marker_kinds()
	_test_contents()


func _test_placement() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(1, 0), CHEST],
		[Vector2i(3, 0), DOOR],
		[Vector2i(4, 1), WOODEN],
		[Vector2i(2, 2), KEG],
	])
	var state: CombatState = world.state()
	_same(
			"placed: ids from the spot index",
			", ".join(PackedStringArray(state.map.objects.keys())),
			"object:0, object:1, object:2, object:3"
	)
	_same("placed: named", world.ids.describe("object:0"), "object:0 (Chest)")
	_ok("placed: a closed door blocks everyone", (
			state.map.blocking_at(Vector2i(3, 0)) == MapState.Blocking.ALL
			and not state.has_unit("object:1")
	))
	_ok("placed: breakables stand on the map, blocking all but fliers", (
			state.has_unit("object:2")
			and state.side_of("object:2") == CombatFact.CombatSide.NONE
			and state.get_hp("object:2") == 25
			and state.map.blocking_at(Vector2i(4, 1)) == MapState.Blocking.ALL_BUT_FLIERS
	))
	_ok("placed: a chest blocks nothing", (
			state.map.blocking_at(Vector2i(1, 0)) == MapState.Blocking.NONE
			and state.occupant_at(Vector2i(1, 0)).is_empty()
	))
	_ok("placed: objects are on no side", (
			state.units_of(PLAYER).is_empty() and state.units_of(ENEMY).is_empty()
	))


func _test_chest() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [[Vector2i(1, 0), CHEST]])
	world.state().map.contents[0] = {"kind": "item", "rarity": "rare"}
	world.add_unit("p1", PLAYER, Vector2i(1, 1))
	var key: String = world.give_item("p1", MapObjects.KEY_EFFECT_ID, 1)
	world.open()
	var start: int = world.log_size()
	var batch: CombatSession.FactBatch = world.send(
			world.use("p1", "object:0", [Vector2i(1, 1), Vector2i(1, 0)], key)
	)
	_ok("chest: opened with a key", batch.rejected_reason.is_empty(), batch.rejected_reason)
	_same_lines("chest: golden log", world.lines(start), [
		"UNIT_MOVED p1 tile (1, 0)",
		"EFFECT_ACTIVATED p1 effect eff:key:p1",
		"OBJECT_USED p1 -> object:0 item item:key:p1 tile (1, 0)",
		"OBJECT_STATE_CHANGED object:0 -> p1 change 0 tile (1, 0)",
	])
	var state: CombatState = world.state()
	_ok("chest: the key is used up", state.unit("p1").pouch_item_id.is_empty())
	_same("chest: the loot is the seat's", str(state.map.found.get(0, [])), str([
		{"kind": "item", "rarity": "rare"},
	]))
	_ok("chest: opened once", state.map.object("object:0").is_used)


func _test_chest_locks() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [[Vector2i(1, 0), CHEST]])
	world.state().map.contents[0] = {"kind": "item", "rarity": "common"}
	world.add_unit("p1", PLAYER, Vector2i(1, 0))
	world.add_unit("p2", PLAYER, Vector2i(5, 3), "", ["Lockpicker"])
	world.add_unit("e1", ENEMY, Vector2i(0, 3))
	var pick: String = world.give_item("p1", MapObjects.LOCKPICK_EFFECT_ID, 1)
	world.open()
	_same(
			"locks: nothing to open it with",
			MapObjects.check_use(world.engine(), world.state(), "p1", "object:0"),
			"needs a key or a lockpick"
	)
	_same(
			"locks: a lockpick needs a lock picker",
			MapObjects.check_use(world.engine(), world.state(), "p1", "object:0", pick),
			"can't pick locks"
	)
	world.state().unit("p1").tags = PackedStringArray(["Lockpicker"])
	var batch: CombatSession.FactBatch = world.send(world.use("p1", "object:0", [], pick))
	_ok("locks: a lock picker opens it", batch.rejected_reason.is_empty(), batch.rejected_reason)
	_ok("locks: the lockpick is kept", world.state().unit("p1").pouch_item_id == pick)
	world.state().map.object("object:0").is_used = false
	world.state().move_unit("e1", Vector2i(1, 1))
	world.state().move_unit("p1", Vector2i(2, 2))
	world.state().move_unit("e1", Vector2i(1, 0))
	_same(
			"locks: other enemies don't loot",
			MapObjects.check_use(world.engine(), world.state(), "e1", "object:0"),
			"only player units and Cutthroats loot"
	)


func _test_door() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(2, 1), DOOR],
		[Vector2i(2, 2), DOOR],
		[Vector2i(4, 0), DOOR],
	])
	world.add_unit("p1", PLAYER, Vector2i(1, 1))
	var key: String = world.give_item("p1", MapObjects.KEY_EFFECT_ID, 2)
	world.open()
	var through: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	_ok("door: closed, it blocks", not world.state().validate_path(
			world.engine(), "p1", through
	).is_legal)
	var start: int = world.log_size()
	world.send(world.use("p1", "object:1", [], key))
	_same_lines("door: golden log, both tiles open as one door", world.lines(start), [
		"EFFECT_ACTIVATED p1 effect eff:key:p1",
		"OBJECT_USED p1 -> object:1 item item:key:p1 tile (2, 1)",
		"OBJECT_STATE_CHANGED object:1 -> p1 change 0 tile (2, 1)",
		"OBJECT_STATE_CHANGED object:2 -> p1 change 0 tile (2, 2)",
	])
	_ok("door: a key with uses left stays", not world.state().unit("p1").pouch_item_id.is_empty())
	_ok("door: open, it lets units through", world.state().validate_path(
			world.engine(), "p1", through
	).is_legal)
	_ok("door: another door stays shut", not world.state().map.object("object:0").is_open)


func _test_lever() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(0, 0), LEVER, 0],
		[Vector2i(3, 0), DOOR, 0],
		[Vector2i(3, 3), DOOR, 0],
	])
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.open()
	var start: int = world.log_size()
	world.send(world.use("p1", "object:0"))
	_same_lines("lever: golden log, the group opens", world.lines(start), [
		"OBJECT_USED p1 -> object:0 tile (0, 0)",
		"OBJECT_STATE_CHANGED object:1 -> p1 change 0 tile (3, 0)",
		"OBJECT_STATE_CHANGED object:2 -> p1 change 0 tile (3, 3)",
	])
	var state: CombatState = world.state()
	world.state().unit("p1").has_acted = false
	start = world.log_size()
	world.send(world.use("p1", "object:0"))
	_same_lines("lever: pulled again, the group closes", world.lines(start), [
		"OBJECT_USED p1 -> object:0 tile (0, 0)",
		"OBJECT_STATE_CHANGED object:1 -> p1 change 1 tile (3, 0)",
		"OBJECT_STATE_CHANGED object:2 -> p1 change 1 tile (3, 3)",
	])
	_ok("lever: closed doors block again", (
			state.map.blocking_at(Vector2i(3, 0)) == MapState.Blocking.ALL
			and not state.map.object("object:1").is_open
	))
	MapObjects.use(world.engine(), state, "p1", "object:0")
	state.move_unit("e1", Vector2i(3, 3))
	state.unit("p1").has_acted = false
	MapObjects.use(world.engine(), state, "p1", "object:0")
	_ok("lever: a door with a unit in it stays open", (
			state.map.object("object:2").is_open and not state.map.object("object:1").is_open
	))


func _test_searchables() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(1, 0), HOUSE],
		[Vector2i(4, 0), BOOK_SHELF],
	])
	world.state().map.contents[0] = {"kind": "gold", "amount": 18}
	world.state().map.contents[1] = {"kind": "rune"}
	world.add_unit("p1", PLAYER, Vector2i(1, 1))
	world.add_unit("p2", PLAYER, Vector2i(4, 0))
	world.open()
	var start: int = world.log_size()
	world.send(world.use("p1", "object:0", [Vector2i(1, 1), Vector2i(1, 0)]))
	_same_lines("house: golden log", world.lines(start), [
		"UNIT_MOVED p1 tile (1, 0)",
		"OBJECT_USED p1 -> object:0 tile (1, 0)",
		"OBJECT_STATE_CHANGED object:0 -> p1 change 2 tile (1, 0)",
	])
	world.send(world.use("p2", "object:1"))
	_same("searchables: each seat's loot, in order", str(world.state().map.found[0]), str([
		{"kind": "gold", "amount": 18},
		{"kind": "rune"},
	]))
	world.state().unit("p1").has_acted = false
	_same(
			"searchables: one search each",
			MapObjects.check_use(world.engine(), world.state(), "p1", "object:0"),
			"already searched"
	)


func _test_passage() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(0, 3), PASSAGE, -1, 0],
		[Vector2i(5, 0), PASSAGE, -1, 0],
	])
	world.add_unit("p1", PLAYER, Vector2i(0, 3))
	world.add_unit("e1", ENEMY, Vector2i(4, 0))
	world.open()
	var start: int = world.log_size()
	world.send(world.use("p1", "object:1"))
	_same_lines("passage: golden log", world.lines(start), [
		"OBJECT_USED p1 -> object:1 tile (0, 3)",
		"UNIT_MOVED p1 tile (5, 0)",
	])
	world.state().move_unit("e1", Vector2i(0, 3))
	world.state().move_unit("p1", Vector2i(1, 1))
	world.state().move_unit("e1", Vector2i(5, 0))
	world.state().move_unit("p1", Vector2i(0, 3))
	world.state().unit("p1").has_acted = false
	_same(
			"passage: the other end must be free",
			MapObjects.check_use(world.engine(), world.state(), "p1", "object:1"),
			"the other end is taken"
	)


func _test_brazier() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [[Vector2i(2, 1), BRAZIER]])
	world.add_unit("p1", PLAYER, Vector2i(1, 1))
	world.add_unit("p2", PLAYER, Vector2i(2, 2))
	world.open()
	_same(
			"brazier: from next to it",
			MapObjects.check_use(world.engine(), world.state(), "p1", "object:0") + "|"
			+ MapObjects.check_use(world.engine(), world.state(), "p1", "object:9"),
			"|no such object on the map"
	)
	var start: int = world.log_size()
	world.send(world.use("p1", "object:0"))
	world.send(world.use("p2", "object:0"))
	_same_lines("brazier: golden log, lit then doused", world.lines(start), [
		"OBJECT_USED p1 -> object:0 tile (2, 1)",
		"OBJECT_STATE_CHANGED object:0 -> p1 change 3 tile (2, 1)",
		"OBJECT_USED p2 -> object:0 tile (2, 1)",
		"OBJECT_STATE_CHANGED object:0 -> p2 change 4 tile (2, 1)",
	])
	_ok("brazier: P06 reads it doused", not MapObjects.is_lit(world.state(), "object:0"))


func _test_debris() -> void:
	var rows: Array[String] = [
		"plain plain plain plain plain plain",
		"plain plain forest plain plain plain",
		"plain plain plain plain plain plain",
		"plain plain plain plain plain plain",
	]
	var world: ObjectWorld = ObjectWorld.new(rows, [
		[Vector2i(2, 1), WOODEN],
		[Vector2i(4, 1), STONE],
	])
	world.add_unit("p1", PLAYER, Vector2i(1, 1), "sword")
	world.add_unit("p2", PLAYER, Vector2i(5, 1), "sword")
	world.add_unit("f1", PLAYER, Vector2i(0, 0), "", [], CombatGrid.MovementType.FLIER)
	world.open()
	var state: CombatState = world.state()
	var onto: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]
	_ok("debris: a flier passes over but can't stop on it", (
			state.validate_path(world.engine(), "f1", [
				Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
			]).is_legal
			and not state.validate_path(world.engine(), "f1", onto).is_legal
	))
	var start: int = world.log_size()
	world.send(world.unit_turn("p1", ATTACK, "object:0"))
	_same_lines("debris: golden log, 8 damage with no forest bonus", world.lines(start), [
		"BEFORE_COMBAT p1 -> object:0",
		"BEFORE_COMBAT object:0 -> p1",
		"ATTACK_MADE p1 -> object:0",
		"HIT_DEALT p1 -> object:0 amount 8 type physical",
		"HIT_TAKEN object:0 <- p1 amount 8 type physical",
		"DAMAGE_DEALT p1 -> object:0 amount 8 (hp 8, block 0) source attack type physical",
		"DAMAGE_TAKEN object:0 <- p1 amount 8 (hp 8, block 0) source attack type physical",
		"AFTER_COMBAT p1 -> object:0",
		"AFTER_COMBAT object:0 -> p1",
	])
	world.send(world.unit_turn("p2", ATTACK, "object:1"))
	_same("debris: stone's 5 DEF", str(state.get_hp("object:1")), "32")
	state.set_hp("object:0", 5)
	state.unit("p1").has_acted = false
	start = world.log_size()
	world.send(world.unit_turn("p1", ATTACK, "object:0"))
	_same_lines("debris: broken, no defeat facts", world.lines(start).slice(-4), [
		"DAMAGE_DEALT p1 -> object:0 amount 5 (hp 5, block 0) source attack type physical",
		"DAMAGE_TAKEN object:0 <- p1 amount 5 (hp 5, block 0) source attack type physical",
		"OBJECT_STATE_CHANGED object:0 -> p1 change 5 tile (2, 1)",
		"AFTER_COMBAT p1 -> object:0",
	])
	_ok("debris: destroyed, its terrain is back", (
			not state.has_unit("object:0")
			and state.map.object("object:0").is_destroyed
			and state.map.blocking_at(Vector2i(2, 1)) == MapState.Blocking.NONE
			and state.can_stand(Vector2i(2, 1), CombatGrid.MovementType.DEFAULT)
			and state.grid.tile_bonus(Vector2i(2, 1)).avoid == 20
			and state.validate_path(world.engine(), "f1", onto).is_legal
	))


# An attack on debris records the same kinds, in the same order, as one on a unit that can't
# counter; only the unit's Stance loss differs, since an object has no Stance.
func _test_attack_shape() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [[Vector2i(2, 1), WOODEN]])
	world.add_unit("p1", PLAYER, Vector2i(1, 1), "sword")
	world.add_unit("p2", PLAYER, Vector2i(3, 2), "sword")
	world.add_unit("e1", ENEMY, Vector2i(3, 3))
	world.open()
	var start: int = world.log_size()
	world.send(world.unit_turn("p1", ATTACK, "object:0"))
	var on_object: String = world.kinds(start)
	start = world.log_size()
	world.send(world.unit_turn("p2", ATTACK, "e1"))
	var on_unit: String = world.kinds(start).replace(" STANCE_CHANGED", "")
	_same("shape: an attack on debris is shaped like one on a unit", on_object, on_unit)


func _test_keg_hit() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [[Vector2i(2, 1), KEG]])
	world.add_unit("p1", PLAYER, Vector2i(1, 1), "sword")
	world.add_unit("e1", ENEMY, Vector2i(2, 2))
	world.add_unit("e2", ENEMY, Vector2i(4, 1))
	world.open()
	var start: int = world.log_size()
	world.send(world.unit_turn("p1", ATTACK, "object:0"))
	var lines: Array[String] = world.lines(start)
	_same_lines("keg: any hit explodes it, after the exchange", lines.slice(lines.find(
			"AFTER_COMBAT p1 -> object:0"
	)), [
		"AFTER_COMBAT p1 -> object:0",
		"AFTER_COMBAT object:0 -> p1",
		"OBJECT_STATE_CHANGED object:0 -> p1 change 5 effect effect:1 tile (2, 1)",
		"DAMAGE_TAKEN p1 <- object:0 amount 5 (hp 5, block 0) source splash effect effect:1",
		"DAMAGE_TAKEN e1 <- object:0 amount 5 (hp 5, block 0) source splash effect effect:1",
	])
	_ok("keg: beyond 1 tile, untouched", world.state().get_hp("e2") == 20)


func _test_keg_chain() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(1, 1), KEG],
		[Vector2i(2, 1), KEG],
		[Vector2i(3, 1), KEG],
		[Vector2i(4, 1), WOODEN],
		[Vector2i(5, 1), WOODEN],
	])
	world.add_unit("p1", PLAYER, Vector2i(1, 2))
	world.add_unit("e1", ENEMY, Vector2i(3, 0))
	world.open()
	var engine: EffectEngine = world.engine()
	var state: CombatState = world.state()
	var start: int = world.log_size()
	engine.begin_step()
	_ok("chain: the darkness erodes the first keg", MapObjects.erode(engine, state, "object:0"))
	engine.drain()
	_same_lines("chain: golden log", world.lines(start), [
		"OBJECT_STATE_CHANGED object:0 change 5 tile (1, 1)",
		"DAMAGE_TAKEN p1 <- object:0 amount 5 (hp 5, block 0) source splash effect effect:1",
		"OBJECT_STATE_CHANGED object:1 -> object:0 change 5 effect effect:1 tile (2, 1)",
		"OBJECT_STATE_CHANGED object:2 -> object:1 change 5 effect effect:3 tile (3, 1)",
		"DAMAGE_TAKEN e1 <- object:2 amount 5 (hp 5, block 0) source splash effect effect:5",
		"OBJECT_STATE_CHANGED object:3 -> object:2 change 5 effect effect:5 tile (4, 1)",
	])
	_ok("chain: three kegs and the debris next to the last are gone", (
			not state.has_unit("object:0")
			and not state.has_unit("object:1")
			and not state.has_unit("object:2")
			and not state.has_unit("object:3")
			and state.has_unit("object:4")
	))
	_ok("chain: never cut short", engine.diagnostics.is_empty(), str(engine.diagnostics))


func _test_sandbox() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(2, 1), KEG],
		[Vector2i(3, 1), DOOR],
	])
	world.add_unit("p1", PLAYER, Vector2i(2, 2))
	world.open()
	var trial: EffectEngine = world.engine().copy_for_sandbox(ForcedRolls.new())
	var trial_state: CombatState = trial.state
	MapObjects.erode(trial, trial_state, "object:0")
	trial_state.map.object("object:1").is_open = true
	trial.drain()
	var state: CombatState = world.state()
	_ok("sandbox: the copy broke its keg", not trial_state.has_unit("object:0"))
	_ok("sandbox: the real keg stands", (
			state.has_unit("object:0")
			and not state.map.object("object:0").is_destroyed
			and state.map.blocking_at(Vector2i(2, 1)) == MapState.Blocking.ALL_BUT_FLIERS
			and state.get_hp("p1") == 20
			and not state.map.object("object:1").is_open
	))


func _test_spark() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(4, 2), KEG],
		[Vector2i(0, 0), CHEST],
	])
	world.add_unit("p1", PLAYER, Vector2i(0, 3))
	world.add_unit("e1", ENEMY, Vector2i(4, 3))
	var spark: String = world.give_rune(0, MapObjects.SPARK_EFFECT_ID)
	var mend: String = world.give_rune(0, "mend")
	world.open()
	_same(
			"spark: not on a chest",
			world.send(CastRuneCommand.new(0, spark, "object:0")).rejected_reason,
			"it can't act on that object"
	)
	_same(
			"spark: only Spark acts on a keg",
			world.send(CastRuneCommand.new(0, mend, "object:1")).rejected_reason,
			"it can't act on that object"
	)
	var start: int = world.log_size()
	var batch: CombatSession.FactBatch = world.send(CastRuneCommand.new(0, spark, "object:1"))
	_ok("spark: cast", batch.rejected_reason.is_empty(), batch.rejected_reason)
	_same_lines("spark: golden log, the keg explodes", world.lines(start), [
		"OBJECT_STATE_CHANGED object:1 change 5 effect eff:rune:spark tile (4, 2)",
		"DAMAGE_TAKEN e1 <- object:1 amount 5 (hp 5, block 0) source splash effect effect:1",
		"RUNE_USED -> object:1 item rune:spark tile (4, 2)",
	])
	_ok("spark: the rune leaves its slot", not world.state().rune_slots[0].has(spark))


func _test_cutthroat() -> void:
	var world: ObjectWorld = ObjectWorld.new(PLAIN_ROWS, [
		[Vector2i(1, 0), CHEST],
		[Vector2i(4, 0), HOUSE],
		[Vector2i(4, 2), KEG],
	])
	var state: CombatState = world.state()
	state.map.contents[0] = {"kind": "item", "rarity": "uncommon"}
	state.map.contents[1] = {"kind": "consumable"}
	var walker: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("c1", ENEMY, Vector2i(1, 0), "", [], walker, MapObjects.CUTTHROAT_UNIT_TYPE)
	world.add_unit("c2", ENEMY, Vector2i(4, 0), "", [], walker, MapObjects.CUTTHROAT_UNIT_TYPE)
	world.open()
	var engine: EffectEngine = world.engine()
	_same(
			"cutthroat: opens a chest with nothing",
			MapObjects.use(engine, state, "c1", "object:0"),
			""
	)
	MapObjects.use(engine, state, "c2", "object:1")
	_same("cutthroat: carries the loot", str(state.map.carried.get("c1", [])), str([
		{"kind": "item", "rarity": "uncommon"},
	]))
	state.defeat(engine, "c1", "p1")
	_same(
			"cutthroat: drops it to the seat that defeats it",
			str(state.map.found.get(0, [])),
			str([{"kind": "item", "rarity": "uncommon"}])
	)
	state.move_unit("c2", Vector2i(4, 1))
	state.set_hp("c2", 5)
	MapObjects.erode(engine, state, "object:2")
	engine.drain()
	_ok("cutthroat: loot no player unit takes is lost", (
			not state.has_unit("c2")
			and not state.map.carried.has("c2")
			and state.map.found[0].size() == 1
	))


func _test_darkness_queries() -> void:
	var rows: Array[String] = [
		"plain wall plain plain plain plain",
		"plain plain plain plain plain plain",
		"plain plain plain plain plain plain",
		"plain plain plain plain plain plain",
	]
	var world: ObjectWorld = ObjectWorld.new(rows, [
		[Vector2i(3, 0), DOOR],
		[Vector2i(4, 1), WOODEN],
		[Vector2i(2, 2), BRAZIER],
	])
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	var state: CombatState = world.state()
	var floodable: PackedStringArray = []
	for tile: Vector2i in [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0), Vector2i(4, 1), Vector2i(2, 2),
		Vector2i(9, 9),
	]:
		floodable.append("%s=%s" % [tile, MapObjects.is_floodable(state, tile)])
	_same("darkness: floodable tiles", " ".join(floodable), (
			"(0, 0)=true (1, 0)=false (3, 0)=false (4, 1)=false (2, 2)=true (9, 9)=false"
	))
	_ok("darkness: doors never erode", not MapObjects.erode(world.engine(), state, "object:0"))
	_ok("darkness: erosion breaks debris", (
			MapObjects.erode(world.engine(), state, "object:1")
			and MapObjects.is_floodable(state, Vector2i(4, 1))
	))
	_ok("darkness: a brazier starts unlit", not MapObjects.is_lit(state, "object:2"))


func _test_marker_kinds() -> void:
	var root: Node2D = Node2D.new()
	var terrain: TileMapLayer = TileMapLayer.new()
	terrain.name = MapLoader.TERRAIN_LAYER
	terrain.tile_set = TILE_SET
	root.add_child(terrain)
	var plain: Vector2i = _atlas_of(TILE_SET, MapLoader.TERRAIN_DATA, "plain")
	for y: int in 4:
		for x: int in 6:
			terrain.set_cell(Vector2i(x, y), 0, plain)
	var nodes: Array[MapMarker] = [
		_marker_node(terrain, MapMarker.Kind.DOOR, Vector2i(2, 1), 0, -1, Vector2i(1, 2)),
		_marker_node(terrain, MapMarker.Kind.LEVER, Vector2i(0, 0), 0),
		_marker_node(terrain, MapMarker.Kind.PASSAGE, Vector2i(5, 0), -1, 1),
		_marker_node(terrain, MapMarker.Kind.PASSAGE, Vector2i(5, 3), -1, 1),
	]
	for node: MapMarker in nodes:
		root.add_child(node)
	var layout: MapLayout = MapLoader.from_scene(root, "markers")
	root.free()
	var parts: PackedStringArray = []
	for marker: MapLayout.Marker in layout.markers_of(OBJECT_SPOT):
		parts.append("%s %s %d g%d p%d" % [
			marker.tile,
			MapLayout.ObjectKind.find_key(marker.object_kind),
			marker.index,
			marker.group_id,
			marker.pair_id,
		])
	_same("marker kinds: doors span tiles; ids row-major", "; ".join(parts), (
			"(0, 0) LEVER 0 g0 p-1; (5, 0) PASSAGE 1 g-1 p1; (2, 1) DOOR 2 g0 p-1; "
			+ "(2, 2) DOOR 3 g0 p-1; (5, 3) PASSAGE 4 g-1 p1"
	))
	var failures: Array[MapCheck.Failure] = MapCheck.check(CombatMapDefinition.new(), layout)
	var matching: PackedStringArray = []
	for failure: MapCheck.Failure in failures:
		if failure.rule != MapCheck.Rule.DEPLOYMENT_TILES:
			matching.append(failure.describe())
	_ok("marker kinds: they match up", matching.is_empty(), "; ".join(matching))


# Step 7 rolls each seat's contents from its own MAP_LOOT stream into its map state, and a session
# starts from a copy.
func _test_contents() -> void:
	var pool: Array[CombatMapDefinition] = []
	var definition: CombatMapDefinition = CombatMapDefinition.new()
	definition.id = "fixture"
	definition.scene = FIXTURE_SCENE
	pool.append(definition)
	var summaries: PackedStringArray = []
	var first: CombatEncounter = null
	for attempt: int in 2:
		var encounter: CombatEncounter = CombatEncounter.new(
				FLOOR, NODE, PackedInt32Array([0, 1]), InstanceIdAllocator.new()
		)
		encounter.add_setup_step(
				CombatEncounter.SetupStep.CONTAINER_CONTENTS, MapObjects.roll_contents
		)
		encounter.run_setup(pool, CombatEncounter.SetupStreams.new(RUN_SEED, FLOOR, NODE))
		summaries.append(encounter.setup.summary())
		if attempt == 0:
			first = encounter
	_ok("contents: the same on a restart", summaries[0] == summaries[1])
	var expected: PackedStringArray = []
	var actual: PackedStringArray = []
	for seat: int in [0, 1]:
		for index: int in [0, 1]:
			var kind: MapLayout.ObjectKind = CHEST if index == 0 else HOUSE
			var stream: RngStream = RngStream.new(RngKey.derive_seed(
					RUN_SEED, RngKey.RngPurpose.MAP_LOOT, FLOOR, NODE, seat, index
			))
			expected.append(str(MapObjects.roll(kind, stream)))
			actual.append(str(first.setup.seats[seat].map.contents.get(index)))
	_same("contents: each seat from its own stream per container", " | ".join(actual), (
			" | ".join(expected)
	))
	var rolls: Dictionary[int, RngStream] = {0: RngStream.new(1), 1: RngStream.new(2)}
	first.open_sessions(rolls)
	var session: CombatSession = first.get_session(0)
	session.state.map.contents[0] = {"kind": "taken"}
	_ok("contents: a session starts from a copy", (
			str(first.setup.seats[0].map.contents[0]) == expected[0]
			and first.get_session(1).state.map.contents.size() == 2
	))
	_ok("contents: a chest rolls a rarity", (
			MapObjects.CHEST_RARITIES.has(
					(first.setup.seats[0].map.contents[0] as Dictionary).get("rarity", "")
			)
	))


func _marker_node(
		terrain: TileMapLayer,
		kind: MapMarker.Kind,
		tile: Vector2i,
		group_id: int = -1,
		pair_id: int = -1,
		size: Vector2i = Vector2i.ONE
) -> MapMarker:
	var node: MapMarker = MapMarker.new()
	node.kind = kind
	node.group_id = group_id
	node.pair_id = pair_id
	node.door_size = size
	node.position = terrain.map_to_local(tile)
	return node


func _atlas_of(tile_set: TileSet, data_name: String, value: String) -> Vector2i:
	var source: TileSetAtlasSource = tile_set.get_source(0) as TileSetAtlasSource
	for i: int in source.get_tiles_count():
		var coords: Vector2i = source.get_tile_id(i)
		if source.get_tile_data(coords, 0).get_custom_data(data_name) == value:
			return coords
	return Vector2i(-1, -1)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])


func _same_lines(case_name: String, actual: Array[String], expected: Array[String]) -> void:
	_check.call(case_name, actual == expected, "got\n      " + "\n      ".join(actual))


## A session on a small map with map objects placed, forced hits, and helpers to act on it.
class ObjectWorld:
	extends RefCounted

	# Weapon presets: damage, AtkX, profile, Hit, weight (game-vision.md's Simple weapons).
	const WEAPONS: Dictionary[String, Array] = {
		"sword": [5, 1, WeaponTriangle.Profile.NIMBLE, 80, 8],
	}

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = null

	# [param spots]: [tile, ObjectKind, group id, pair id] each; the ids are optional.
	func _init(rows: Array[String], spots: Array) -> void:
		var layout: MapLayout = MapLayout.new()
		layout.map_id = "objects"
		var cache: Dictionary[String, MapLayout.Terrain] = {}
		for y: int in rows.size():
			var terrain_ids: PackedStringArray = rows[y].split(" ", false)
			for x: int in terrain_ids.size():
				if not cache.has(terrain_ids[x]):
					cache[terrain_ids[x]] = MapLayout.Terrain.from_definition(
							MapLoader.load_terrain(terrain_ids[x])
					)
				layout.set_terrain(Vector2i(x, y), cache[terrain_ids[x]])
		# Untyped: each spot is an array literal.
		for spot: Variant in spots:
			var entry: Array = spot
			var marker: MapLayout.Marker = layout.add_marker(
					MapLayout.MarkerKind.OBJECT_SPOT, entry[0] as Vector2i, entry[1] as int
			)
			marker.group_id = entry[2] if entry.size() > 2 else -1
			marker.pair_id = entry[3] if entry.size() > 3 else -1
		layout.index_markers()
		var hits: PackedInt32Array = []
		hits.resize(64)
		hits.fill(1)
		session = CombatSession.new(
				0, PackedInt32Array([0]), MapGrid.new(layout), ForcedRolls.new(hits), ids
		)
		session.engine.verify = true
		MapObjects.place(session)

	func state() -> CombatState:
		return session.state

	func engine() -> EffectEngine:
		return session.engine

	# Places a unit: HP 20, Stance 2, 5 movement, Might 3, Speed 5, Constitution 20, holding
	# [param weapon] when given. Player units are seat 0's.
	func add_unit(
			id: String,
			side: CombatFact.CombatSide,
			tile: Vector2i,
			weapon: String = "",
			tags: Array[String] = [],
			movement_type: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT,
			unit_type: String = ""
	) -> void:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = 0 if side == CombatFact.CombatSide.PLAYER else -1
		unit.tile = tile
		unit.hp = 20
		unit.tags = PackedStringArray(tags)
		unit.movement_type = movement_type
		unit.unit_type = unit_type
		if not weapon.is_empty():
			var preset: Array = WEAPONS[weapon]
			var stats: CombatState.WeaponStats = CombatState.WeaponStats.new()
			stats.id = "w:%s:%s" % [weapon, id]
			stats.damage = preset[0]
			stats.atk_x = preset[1]
			stats.profile = preset[2]
			stats.hit = preset[3]
			stats.weight = preset[4]
			unit.equipped_weapon_id = stats.id
			session.state.add_weapon(stats)
		session.add_unit(unit, {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
			CombatValue.Key.MGT: 3.0,
			CombatValue.Key.SPD: 5.0,
			CombatValue.Key.CON: 20.0,
		})

	# Puts an item in [param unit_id]'s Pouch whose use effect is [param effect_id] with
	# [param uses] campaign-lane uses. Returns the item id.
	func give_item(unit_id: String, effect_id: String, uses: int) -> String:
		var item_id: String = "item:%s:%s" % [effect_id, unit_id]
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = effect_id
		definition.charges = uses
		definition.charge_lane = EffectDefinition.Lane.CAMPAIGN
		session.engine.register(EffectInstance.new(
				"eff:%s:%s" % [effect_id, unit_id],
				definition,
				EffectOwner.for_item(item_id, unit_id, session.state.seat_of(unit_id), (
						session.state.side_of(unit_id)
				)),
				Modifier.SourceKind.POUCH_ITEM
		))
		session.state.unit(unit_id).pouch_item_id = item_id
		return item_id

	# Puts a rune whose effect is [param effect_id] in [param seat]'s slots. Returns its id.
	func give_rune(seat: int, effect_id: String) -> String:
		var rune_id: String = "rune:%s" % [effect_id]
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = effect_id
		session.engine.register(EffectInstance.new(
				"eff:%s" % [rune_id],
				definition,
				EffectOwner.for_rune(rune_id, seat),
				Modifier.SourceKind.RUNE
		))
		var slots: PackedStringArray = session.state.rune_slots.get(seat, PackedStringArray())
		slots.append(rune_id)
		session.state.rune_slots[seat] = slots
		return rune_id

	# Opens the battle: turn 1's player phase.
	func open() -> void:
		session.open_battle()

	func use(
			unit_id: String, object_id: String, path: Array = [], item_id: String = ""
	) -> UnitTurnCommand:
		var walk: Array[Vector2i] = []
		walk.assign(path)
		var command: UnitTurnCommand = UnitTurnCommand.new(0, unit_id, USE, object_id, walk)
		command.item_id = item_id
		return command

	func unit_turn(
			unit_id: String, action: UnitTurnCommand.Action, target_id: String
	) -> UnitTurnCommand:
		return UnitTurnCommand.new(0, unit_id, action, target_id)

	func send(command: Command) -> CombatSession.FactBatch:
		session.submit(command)
		return session.resolve_next()

	func log_size() -> int:
		return session.engine.fact_log.size()

	# Log lines from [param start], without their "sN#M " prefix.
	func lines(start: int = 0) -> Array[String]:
		var found: Array[String] = []
		for i: int in range(start, session.engine.fact_log.size()):
			var line: String = session.engine.fact_log[i].to_log_line()
			found.append(line.substr(line.find(" ") + 1))
		return found

	func kinds(start: int = 0) -> String:
		var names: PackedStringArray = []
		for i: int in range(start, session.engine.fact_log.size()):
			names.append(CombatFact.Kind.find_key(session.engine.fact_log[i].kind) as String)
		return " ".join(names)
