# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     deploy_cases.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## The deployment cases for tests/map/run_all.gd: [AutoDeploy]'s roles, the Mercenary starting
## army and a six-unit army on a fixture zone, the commander's row, edges, ties by roster order,
## tiles a unit can't stand on, determinism, and the opening swap's legality. Reports each case
## through the check callable it is given.

# Preloaded scripts used as types (gdscript.md, Naming): the test map has no class name.
const MapWorld = preload("res://tests/map/map_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const DEFAULT: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT
const HEAVY: CombatGrid.MovementType = CombatGrid.MovementType.HEAVY
const MOBILE: CombatGrid.MovementType = CombatGrid.MovementType.MOBILE
const MOUNTED: CombatGrid.MovementType = CombatGrid.MovementType.MOUNTED
const FLIER: CombatGrid.MovementType = CombatGrid.MovementType.FLIER

# Weapon presets: range min, range max, staff (game-vision.md's Simple weapons, weapons.md).
const WEAPONS: Dictionary[String, Array] = {
	"sword": [1, 1, CombatState.WeaponStats.Staff.NONE],
	"axe": [1, 1, CombatState.WeaponStats.Staff.NONE],
	"lance": [1, 1, CombatState.WeaponStats.Staff.NONE],
	"bow": [2, 3, CombatState.WeaponStats.Staff.NONE],
	"dagger": [1, 2, CombatState.WeaponStats.Staff.NONE],
	"fire": [1, 2, CombatState.WeaponStats.Staff.NONE],
	"minor_heal": [1, 1, CombatState.WeaponStats.Staff.HEAL],
}

# Units from unit-roster.md: unit type, movement type, tags, base HP, DEF, weapon, stowed weapon.
const ROSTER: Dictionary[String, Array] = {
	"drengr": ["Drengr", DEFAULT, [], 24, 3, "axe", ""],
	"hakkapel": ["Hakkapel", MOUNTED, ["Mounted"], 22, 4, "lance", ""],
	"archer": ["Archer", DEFAULT, [], 13, 0, "bow", ""],
	"medic": ["Battle Medic", MOBILE, [], 16, 1, "dagger", "minor_heal"],
	"lance_armor": ["Lance Armor", HEAVY, ["Armored"], 23, 7, "lance", ""],
	"ward": ["Ward", HEAVY, [], 25, 7, "lance", ""],
	"freewing": ["Freewing", FLIER, ["Flier", "Mounted"], 17, 2, "sword", ""],
	"sellsword": ["Sellsword", DEFAULT, [], 22, 4, "sword", ""],
	"mage": ["Mage", DEFAULT, [], 16, 1, "fire", ""],
}

# The fixture zone: 4 × 2 tiles near the bottom of a 6 × 6 plain, enemies two tiles in from the
# top corners' middle. Ranked: (2, 4) (3, 4) | (1, 4) (4, 4) (2, 5) (3, 5) | (1, 5) (4, 5).
const ZONE: Array[Vector2i] = [
	Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4),
	Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
]
const ENEMIES: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_roles()
	_test_mercenary_army()
	_test_six_unit_army()
	_test_edges_and_roster_order()
	_test_front_ties()
	_test_tiles_a_unit_cant_stand_on()
	_test_same_inputs_same_layout()
	_test_opening_swap()


func _test_roles() -> void:
	var world: MapWorld = MapWorld.new(["plain"])
	var expected: Dictionary[String, AutoDeploy.Role] = {
		"drengr": AutoDeploy.Role.STRIKER,
		"hakkapel": AutoDeploy.Role.STRIKER,
		"archer": AutoDeploy.Role.RANGED,
		"medic": AutoDeploy.Role.SUPPORT,
		"lance_armor": AutoDeploy.Role.FRONT,
		"ward": AutoDeploy.Role.FRONT,
		"freewing": AutoDeploy.Role.STRIKER,
		"mage": AutoDeploy.Role.STRIKER,
	}
	for key: String in expected:
		var unit: CombatUnitState = _unit(world, key)
		var role: AutoDeploy.Role = AutoDeploy.role_of(world.state, unit)
		_ok(
				"role: %s is %s" % [key, AutoDeploy.Role.find_key(expected[key])],
				role == expected[key],
				AutoDeploy.Role.find_key(role) as String
		)
	var bare: CombatUnitState = _unit(world, "sellsword", "bare")
	bare.equipped_weapon_id = ""
	_ok("role: no weapon counts as melee", AutoDeploy.role_of(world.state, bare) == 1)
	var heavy: CombatUnitState = _unit(world, "sellsword", "heavy")
	heavy.movement_type = HEAVY
	_ok("role: Heavy movement is front", AutoDeploy.role_of(world.state, heavy) == 0)
	var staff_in_hand: CombatUnitState = _unit(world, "archer", "staffer")
	staff_in_hand.equipped_weapon_id = "w:staffer:stowed"
	_add_weapon(world, "w:staffer:stowed", "minor_heal")
	_ok("role: a staff in hand is support", AutoDeploy.role_of(world.state, staff_in_hand) == 3)


func _test_mercenary_army() -> void:
	var world: MapWorld = _zone_world()
	var army: Array[CombatUnitState] = _army(world, ["drengr", "hakkapel", "archer", "medic"])
	var placement: AutoDeploy.Placement = AutoDeploy.deploy(
			world.engine, world.state, army, ZONE, ENEMIES, "drengr"
	)
	_same(
			"mercenary: the layout",
			_describe(placement),
			"drengr (1, 4); hakkapel (2, 4); archer (4, 4); medic (2, 5)"
	)
	_ok("mercenary: everyone placed", placement.unplaced.is_empty())
	_ok(
			"mercenary: the commander is in the second row",
			_enemy_distance(placement.tiles["drengr"]) == 5
	)
	_ok(
			"mercenary: the striker holds the nearest row",
			_enemy_distance(placement.tiles["hakkapel"]) == 4
	)
	_ok(
			"mercenary: the archer is 1-2 tiles behind the line",
			world.grid.distance(placement.tiles["archer"], placement.tiles["hakkapel"]) <= 2
			and _enemy_distance(placement.tiles["archer"]) > 4
	)


func _test_six_unit_army() -> void:
	var world: MapWorld = _zone_world()
	var army: Array[CombatUnitState] = _army(
			world, ["drengr", "lance_armor", "ward", "archer", "medic", "freewing"]
	)
	var placement: AutoDeploy.Placement = AutoDeploy.deploy(
			world.engine, world.state, army, ZONE, ENEMIES, "drengr"
	)
	_same(
			"six: the layout",
			_describe(placement),
			"drengr (1, 4); lance_armor (3, 4); ward (2, 4); archer (2, 5); medic (3, 5); "
			+ "freewing (4, 4)"
	)
	_ok("six: the bulkiest front unit takes the nearest tile", placement.tiles["ward"] == ZONE[1])
	_ok(
			"six: support behind the line next to the most allies",
			_enemy_distance(placement.tiles["medic"]) > 4
	)
	var crowd: Array[CombatUnitState] = _army(
			world,
			["drengr", "lance_armor", "ward", "archer", "medic", "freewing", "sellsword", "mage"]
	)
	crowd.append(_unit(world, "sellsword", "extra"))
	var full: AutoDeploy.Placement = AutoDeploy.deploy(
			world.engine, world.state, crowd, ZONE, ENEMIES, "drengr"
	)
	_ok(
			"six: nine units on eight tiles leave off the last role placed",
			full.tiles.size() == 8 and full.unplaced == PackedStringArray(["medic"]),
			str(full.unplaced)
	)


func _test_edges_and_roster_order() -> void:
	var world: MapWorld = MapWorld.new(["plain plain plain", "plain plain plain"])
	var zone: Array[Vector2i] = world.layout.tiles()
	var none: Array[Vector2i] = []
	var foot_first: Array[CombatUnitState] = [
		_unit(world, "sellsword", "a"),
		_unit(world, "hakkapel", "rider"),
	]
	var placement: AutoDeploy.Placement = AutoDeploy.deploy(
			world.engine, world.state, foot_first, zone, none, ""
	)
	_same(
			"edges: a rider skips a side tile for the row's corner",
			_describe(placement),
			"a (0, 0); rider (2, 0)"
	)
	var two_foot: Array[CombatUnitState] = [
		_unit(world, "sellsword", "a"),
		_unit(world, "sellsword", "b"),
	]
	_same(
			"ties: roster order",
			_describe(AutoDeploy.deploy(world.engine, world.state, two_foot, zone, none, "")),
			"a (0, 0); b (1, 0)"
	)
	two_foot.reverse()
	_same(
			"ties: the other roster order",
			_describe(AutoDeploy.deploy(world.engine, world.state, two_foot, zone, none, "")),
			"b (0, 0); a (1, 0)"
	)
	var commander: Array[CombatUnitState] = [_unit(world, "sellsword", "a"), _unit(world, "drengr")]
	var one_row: AutoDeploy.Placement = AutoDeploy.deploy(
			world.engine, world.state, commander, zone, none, "drengr"
	)
	_same("commander: one row, so the first", _describe(one_row), "a (1, 0); drengr (0, 0)")


func _test_front_ties() -> void:
	var world: MapWorld = _zone_world()
	var twins: Array[CombatUnitState] = [
		_unit(world, "lance_armor", "first"),
		_unit(world, "lance_armor", "second"),
		_unit(world, "ward"),
	]
	_same(
			"front: bulk first, then roster order",
			_describe(AutoDeploy.deploy(world.engine, world.state, twins, ZONE, ENEMIES, "")),
			"first (3, 4); second (1, 4); ward (2, 4)"
	)


func _test_tiles_a_unit_cant_stand_on() -> void:
	var world: MapWorld = MapWorld.new(["plain river plain"])
	var zone: Array[Vector2i] = world.layout.tiles()
	var none: Array[Vector2i] = []
	var walkers: Array[CombatUnitState] = [
		_unit(world, "sellsword", "a"),
		_unit(world, "sellsword", "b"),
		_unit(world, "sellsword", "c"),
	]
	var placement: AutoDeploy.Placement = AutoDeploy.deploy(
			world.engine, world.state, walkers, zone, none, ""
	)
	_same("terrain: never into the river", _describe(placement), "a (0, 0); b (2, 0)")
	_ok("terrain: the third is left off", placement.unplaced == PackedStringArray(["c"]))
	walkers[2] = _unit(world, "freewing", "c")
	_same(
			"terrain: a flier takes the river",
			_describe(AutoDeploy.deploy(world.engine, world.state, walkers, zone, none, "")),
			"a (0, 0); b (2, 0); c (1, 0)"
	)
	world.add_unit("e1", ENEMY, Vector2i(0, 0))
	_same(
			"terrain: never onto a unit already there",
			_describe(AutoDeploy.deploy(world.engine, world.state, walkers, zone, none, "")),
			"a (2, 0); c (1, 0)"
	)


func _test_same_inputs_same_layout() -> void:
	var keys: Array[String] = ["drengr", "lance_armor", "ward", "archer", "medic", "freewing"]
	var first: MapWorld = _zone_world()
	var second: MapWorld = _zone_world()
	var once: String = _describe(
			AutoDeploy.deploy(
					first.engine, first.state, _army(first, keys), ZONE, ENEMIES, "drengr"
			)
	)
	var twice: String = _describe(
			AutoDeploy.deploy(
					second.engine, second.state, _army(second, keys), ZONE, ENEMIES, "drengr"
			)
	)
	_same("determinism: the same army and map, the same layout", twice, once)
	var shuffled: Array[Vector2i] = ZONE.duplicate()
	shuffled.reverse()
	var enemies: Array[Vector2i] = ENEMIES.duplicate()
	enemies.reverse()
	_same(
			"determinism: whatever order the tiles come in",
			_describe(
					AutoDeploy.deploy(
							first.engine, first.state, _army(first, keys), shuffled, enemies,
							"drengr"
					)
			),
			once
	)


func _test_opening_swap() -> void:
	var world: MapWorld = _zone_world()
	var army: Array[CombatUnitState] = _army(world, ["drengr", "hakkapel", "archer", "medic"])
	var placement: AutoDeploy.Placement = AutoDeploy.deploy(
			world.engine, world.state, army, ZONE, ENEMIES, "drengr"
	)
	for unit: CombatUnitState in army:
		unit.tile = placement.tiles[unit.id]
		world.state.place_unit(world.engine, unit)
	world.add_unit("e1", ENEMY, ENEMIES[0])
	var state: CombatState = world.state
	_same(
			"swap: not before the first Phase Start",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "archer", ZONE),
			"not the first player phase"
	)
	state.turn = 1
	state.phase_side = CombatFact.CombatSide.PLAYER
	_same(
			"swap: legal before anyone acts on turn 1",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "archer", ZONE),
			""
	)
	_same(
			"swap: only the seat's own units",
			AutoDeploy.check_opening_swap(state, 1, "drengr", "archer", ZONE),
			"not two of the seat's units"
	)
	_same(
			"swap: never an enemy",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "e1", ZONE),
			"not two of the seat's units"
	)
	_same(
			"swap: two units, not one",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "drengr", ZONE),
			"not two of the seat's units"
	)
	var outside: Array[Vector2i] = ZONE.duplicate()
	outside.erase(placement.tiles["archer"])
	_same(
			"swap: only on deployment tiles",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "archer", outside),
			"not on a deployment tile"
	)
	state.unit("hakkapel").has_acted = true
	_same(
			"swap: closed once a unit has acted",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "archer", ZONE),
			"a unit has already acted"
	)
	state.unit("hakkapel").has_acted = false
	state.turn = 2
	_same(
			"swap: closed after turn 1",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "archer", ZONE),
			"not the first player phase"
	)
	state.turn = 1
	state.phase_side = CombatFact.CombatSide.ENEMY
	_same(
			"swap: closed in the enemy phase",
			AutoDeploy.check_opening_swap(state, 0, "drengr", "archer", ZONE),
			"not the first player phase"
	)

	var river: MapWorld = MapWorld.new(["plain river"])
	river.add_unit("foot", PLAYER, Vector2i(0, 0))
	river.add_unit("flier", PLAYER, Vector2i(1, 0), FLIER)
	river.state.turn = 1
	river.state.phase_side = CombatFact.CombatSide.PLAYER
	_same(
			"swap: each must stand on the other's tile",
			AutoDeploy.check_opening_swap(
					river.state, 0, "foot", "flier", river.layout.tiles()
			),
			"a unit can't stand on the other's tile"
	)


func _zone_world() -> MapWorld:
	var rows: Array[String] = []
	for y: int in 6:
		rows.append("plain plain plain plain plain plain")
	return MapWorld.new(rows)


# Units for `keys` in roster order, each with its ROSTER entry's id.
func _army(world: MapWorld, keys: Array[String]) -> Array[CombatUnitState]:
	var units: Array[CombatUnitState] = []
	for key: String in keys:
		units.append(_unit(world, key))
	return units


# A unit off the map built from ROSTER[key], its bases and weapons set in the world.
func _unit(world: MapWorld, key: String, id: String = "") -> CombatUnitState:
	var spec: Array = ROSTER[key]
	var tags: Array = spec[2]
	var hp: int = spec[3]
	var defense: int = spec[4]
	var weapon: String = spec[5]
	var stowed: String = spec[6]
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = key if id.is_empty() else id
	unit.side = PLAYER
	unit.seat = 0
	unit.unit_type = spec[0]
	unit.movement_type = spec[1]
	unit.tags = PackedStringArray(tags)
	unit.hp = hp
	world.engine.set_base(unit.id, CombatValue.Key.HP, hp)
	world.engine.set_base(unit.id, CombatValue.Key.DEF, defense)
	world.engine.set_base(unit.id, CombatValue.Key.STANCE_MAX, 2.0)
	unit.equipped_weapon_id = "w:%s" % [unit.id]
	_add_weapon(world, unit.equipped_weapon_id, weapon)
	if not stowed.is_empty():
		unit.stowed_weapon_id = "w:%s:stowed" % [unit.id]
		_add_weapon(world, unit.stowed_weapon_id, stowed)
	return unit


func _add_weapon(world: MapWorld, weapon_id: String, preset: String) -> void:
	var stats: CombatState.WeaponStats = CombatState.WeaponStats.new()
	stats.id = weapon_id
	stats.range_min = WEAPONS[preset][0]
	stats.range_max = WEAPONS[preset][1]
	stats.staff = WEAPONS[preset][2]
	world.state.add_weapon(stats)


func _enemy_distance(tile: Vector2i) -> int:
	return mini(absi(tile.x - 2), absi(tile.x - 3)) + tile.y


# "id tile" per placed unit, in roster order, joined by "; ".
func _describe(placement: AutoDeploy.Placement) -> String:
	var parts: PackedStringArray = []
	for unit_id: String in placement.tiles:
		parts.append("%s %s" % [unit_id, placement.tiles[unit_id]])
	return "; ".join(parts)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
