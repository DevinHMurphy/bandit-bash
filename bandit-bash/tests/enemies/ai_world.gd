# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ai_world.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

extends RefCounted
## A small battle for the enemy AI cases and benchmark: a real [CombatSession] on a hand-built map,
## enemies of the loadout fixture tree's classes loaded through [Loadout], and hand-built player
## units with chosen stats.
##
## Test-only. Enemies are [code]loadout_brute[/code] (Aggressive, Simple Axe),
## [code]loadout_crossbowman[/code] (Hold, Simple Bow) and [code]loadout_hedge_healer[/code]
## (Support, Minor Heal) at level 1, with enemy-roster.md's base stats. Player units default to
## HP 20, Stance 2, movement 5, Might 3, Speed 5, DEF 2, RES 1 and Constitution 20.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

## The seed of a world's combat stream when no roll source is given.
const SEED: int = 20261030

# Player weapon presets: damage, AtkX, profile, range min, range max, Hit, weight. The sword is the
# combat tests' (game-vision.md's Simple Sword); the bow is the loadout fixture's Simple Bow.
const WEAPONS: Dictionary[String, Array] = {
	"sword": [5, 1, WeaponTriangle.Profile.NIMBLE, 1, 1, 80, 8],
	"bow": [6, 1, WeaponTriangle.Profile.NONE, 2, 3, 100, 5],
}

const PLAYER_BASES: Dictionary = {
	CombatValue.Key.HP: 20.0,
	CombatValue.Key.STANCE_MAX: 2.0,
	CombatValue.Key.MOVEMENT: 5.0,
	CombatValue.Key.MGT: 3.0,
	CombatValue.Key.SPD: 5.0,
	CombatValue.Key.DEF: 2.0,
	CombatValue.Key.RES: 1.0,
	CombatValue.Key.CON: 20.0,
}

## The fixture catalog the enemies load from, and the AI reads their classes from.
var catalog: EffectCatalog.Index = null

## The battle.
var session: CombatSession = null

## Problems the loadout reported for any enemy added.
var problems: PackedStringArray = []

var _ids: InstanceIdAllocator = InstanceIdAllocator.new()


## [param rows]: terrain ids per row, space-separated, from [code]res://data/terrain/[/code].
## [param rolls]: the session's roll source; null gives [LiveRolls] on [constant SEED].
func _init(fixtures: EffectCatalog.Index, rows: Array[String], rolls: RollSource = null) -> void:
	catalog = fixtures
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "enemy_ai"
	var cache: Dictionary[String, MapLayout.Terrain] = {}
	for y: int in rows.size():
		var terrain_ids: PackedStringArray = rows[y].split(" ", false)
		for x: int in terrain_ids.size():
			var terrain_id: String = terrain_ids[x]
			if not cache.has(terrain_id):
				cache[terrain_id] = MapLayout.Terrain.from_definition(
						MapLoader.load_terrain(terrain_id)
				)
			layout.set_terrain(Vector2i(x, y), cache[terrain_id])
	var source: RollSource = rolls if rolls != null else LiveRolls.new(RngStream.new(SEED))
	session = CombatSession.new(0, PackedInt32Array([0]), MapGrid.new(layout), source, _ids)


func state() -> CombatState:
	return session.state


func engine() -> EffectEngine:
	return session.engine


## Loads an enemy of [param class_id] holding its class's starting weapon and places it on
## [param tile].
func add_enemy(unit_id: String, class_id: String, tile: Vector2i) -> void:
	var definition: EnemyClassDefinition = catalog.enemy_class(class_id)
	var item_id: String = "item:%s" % [unit_id]
	var unit: UnitInstance = UnitInstance.new(unit_id, class_id)
	unit.weapon_id = item_id
	var items: Dictionary[String, ItemInstance] = {
		item_id: ItemInstance.new(item_id, definition.starting_weapon_id),
	}
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(catalog, unit, items, ENEMY, -1, _ids)
	problems.append_array(loaded.problems)
	for weapon: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(weapon)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = tile
	session.add_unit(loaded.state, loaded.bases)


## Places a player unit of seat 0 on [param tile] holding [param weapon] (a [constant WEAPONS]
## preset), with [constant PLAYER_BASES] changed by [param changes] (value key to number).
func add_player(
		unit_id: String, tile: Vector2i, weapon: String = "sword", changes: Dictionary = {}
) -> void:
	var bases: Dictionary = PLAYER_BASES.duplicate()
	bases.merge(changes, true)
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = unit_id
	unit.side = PLAYER
	unit.seat = 0
	unit.tile = tile
	var max_hp: float = bases[CombatValue.Key.HP]
	unit.hp = roundi(max_hp)
	unit.equipped_weapon_id = "w:%s" % [unit_id]
	session.state.add_weapon(_weapon(unit.equipped_weapon_id, weapon))
	session.add_unit(unit, bases)


## Wounds [param unit_id] to [param hp].
func wound(unit_id: String, hp: int) -> void:
	session.state.set_hp(unit_id, hp)


## The AI's plan for [param unit_id] now, with [param flooded] tiles.
func decide(unit_id: String, flooded: Dictionary[Vector2i, bool] = {}) -> EnemyPlan:
	return EnemyAI.decide(session.engine, catalog, unit_id, flooded)


func _weapon(weapon_id: String, preset: String) -> CombatState.WeaponStats:
	var stats: CombatState.WeaponStats = CombatState.WeaponStats.new()
	stats.id = weapon_id
	stats.label = preset.capitalize()
	# Columns: damage, AtkX, profile, range min, range max, Hit, weight.
	var columns: Array = WEAPONS[preset]
	stats.damage = columns[0]
	stats.atk_x = columns[1]
	stats.profile = columns[2]
	stats.range_min = columns[3]
	stats.range_max = columns[4]
	stats.hit = columns[5]
	stats.weight = columns[6]
	return stats
