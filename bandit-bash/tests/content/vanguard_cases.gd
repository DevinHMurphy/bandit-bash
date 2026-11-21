# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     vanguard_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Drengr's Vanguard cases for tests/content/run_all.gd, over the real
## [code]res://data/[/code] (unit-roster.md, Commander): its generated text; Block equal to 2 ×
## the Drengr's level at every player Phase Start, at levels 1, 3 and 10, with an ally nearer the
## enemy; and a battle resumed from a snapshot keeping the saved level's amount. Reports each case
## through the check callable it is given.
##
## The expected values are transcribed from unit-roster.md, never read from the data.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "content"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# Any fixed seed: the enemy only waits, so nothing is drawn from it.
const SEED: int = 0xC7_0014

# unit-roster.md's Vanguard: Block per level, at every Phase Start.
const BLOCK_PER_LEVEL: int = 2

# The levels checked: the first, a mid-run one and a high one.
const LEVELS: Array[int] = [1, 3, 10]

# The reviewed text of the Drengr's one trait.
const TEXT: String = "At Phase Start, gain Block equal to 2 × this unit's level."

# The row: the Drengr at (0, 0), an Archer ally at (3, 0) and an enemy Hakkapel at (5, 0), so the
# ally (2 tiles) stands nearer the enemy than the Drengr (5 tiles).
const ROW_WIDTH: int = 6
const DRENGR_TILE: Vector2i = Vector2i(0, 0)
const ALLY_TILE: Vector2i = Vector2i(3, 0)
const ENEMY_TILE: Vector2i = Vector2i(5, 0)

# The level the resumed battle is saved at, and the level its rebuilt units load at before the
# snapshot replaces them: a resumed amount from the rebuilt level would read 2, not 6.
const SAVED_LEVEL: int = 3
const REBUILT_LEVEL: int = 1

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_test_text()
	_test_block_by_level()
	_test_resumed_battle()


# The trait's one effect: Phase Start, no condition, and its generated text.
func _test_text() -> void:
	var drengr: UnitTypeDefinition = _catalog.unit_type("drengr")
	if drengr == null:
		_ok("vanguard text: the Drengr is in the catalog", false)
		return
	_same("vanguard text: the trait keeps its name", drengr.trait_name, "Vanguard")
	if drengr.effects.size() != 1:
		_ok("vanguard text: one effect", false, str(drengr.effects.size()))
		return
	var vanguard: EffectDefinition = drengr.effects[0]
	_ok("vanguard text: Phase Start, with no condition", (
			vanguard.trigger == EffectTerms.Trigger.PHASE_START and vanguard.conditions.is_empty()
	), "%d, %d" % [vanguard.trigger, vanguard.conditions.size()])
	_same("vanguard text: the generated text", vanguard.describe(), TEXT)
	_same("vanguard text: the unit type's trait lines", " | ".join(drengr.describe()), TEXT)


# At each level, the opening Phase Start and the next one each give the Drengr 2 × its level,
# though the ally stands nearer the enemy; the Block left after each is that amount.
func _test_block_by_level() -> void:
	for level: int in LEVELS:
		var expected: int = BLOCK_PER_LEVEL * level
		var battle: Battle = _battle(level, LiveRolls.new(RngStream.new(SEED)))
		if battle == null:
			continue
		battle.session.open_battle()
		var first: int = battle.session.state.get_block(battle.drengr_id)
		battle.session.submit(EndTurnCommand.new(0))
		battle.session.resolve_next()
		_same("vanguard level %d: Block at each player Phase Start, ally nearer" % [level], (
				"%d %d [%s]" % [
					first,
					battle.session.state.get_block(battle.drengr_id),
					", ".join(_gains(battle.session, battle.drengr_id)),
				]
		), "%d %d [%d, %d]" % [expected, expected, expected, expected])


# A battle opened at level 3, snapshotted through JSON and loaded into the same battle rebuilt at
# level 1: the restored Drengr is level 3, and the next Phase Start gives it 6.
func _test_resumed_battle() -> void:
	var saved: Battle = _battle(SAVED_LEVEL, LiveRolls.new(RngStream.new(SEED)))
	var rebuilt: Battle = _battle(REBUILT_LEVEL, LiveRolls.new(RngStream.new(SEED)))
	if saved == null or rebuilt == null:
		return
	saved.session.open_battle()
	var taken: Variant = JSON.parse_string(JSON.stringify(saved.session.snapshot()))
	var loaded: Error = (
			rebuilt.session.load_snapshot(taken as Dictionary)
			if taken is Dictionary else ERR_PARSE_ERROR
	)
	_ok("vanguard resumed: the snapshot loads", loaded == OK, error_string(loaded))
	if loaded != OK:
		return
	var resumed: CombatSession = rebuilt.session
	_same("vanguard resumed: the level and Block are the saved ones", "%d %d" % [
		resumed.state.level_of(rebuilt.drengr_id), resumed.state.get_block(rebuilt.drengr_id),
	], "%d %d" % [SAVED_LEVEL, BLOCK_PER_LEVEL * SAVED_LEVEL])
	resumed.submit(EndTurnCommand.new(0))
	resumed.resolve_next()
	_same("vanguard resumed: the next Phase Start gives the saved level's amount", (
			"%d [%s]" % [
				resumed.state.get_block(rebuilt.drengr_id),
				", ".join(_gains(resumed, rebuilt.drengr_id)),
			]
	), "%d [%d]" % [BLOCK_PER_LEVEL * SAVED_LEVEL, BLOCK_PER_LEVEL * SAVED_LEVEL])


# The row's three units, the Drengr at [param level], with the enemy waiting through its phases;
# null when a unit doesn't load. Ids come from a fresh allocator, so two calls give equal ids.
func _battle(level: int, rolls: LiveRolls) -> Battle:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = CombatSession.new(
			0, PackedInt32Array([0]), _plain_row(ROW_WIDTH), rolls, ids
	)
	var battle: Battle = Battle.new()
	battle.session = session
	battle.drengr_id = _place(
			session, "drengr", PLAYER, 0, DRENGR_TILE, ids.next_unit_id("drengr"), level
	)
	var ally: String = _place(session, "archer", PLAYER, 0, ALLY_TILE, ids.next_unit_id("archer"))
	var enemy: String = _place(
			session, "hakkapel", ENEMY, -1, ENEMY_TILE, ids.next_enemy_id("hakkapel")
	)
	if battle.drengr_id.is_empty() or ally.is_empty() or enemy.is_empty():
		_ok("vanguard level %d: the battle loads" % [level], false)
		return null
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(_at: CombatSession) -> Command:
		return null
	)
	return battle


# Each Block gain [param unit_id] has had in [param session]'s fact log, in order.
func _gains(session: CombatSession, unit_id: String) -> PackedStringArray:
	var gains: PackedStringArray = []
	for fact: CombatFact in session.engine.fact_log:
		if fact.kind == CombatFact.Kind.BLOCK_GAINED and fact.actor_id == unit_id:
			gains.append(str(fact.amount))
	return gains


# Loads a new unit of [param type_id] at [param level] with its type's starting weapon and places
# it; its id, or empty when it didn't load.
func _place(
		session: CombatSession,
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i,
		unit_id: String,
		level: int = 1
) -> String:
	var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
	if unit_type == null:
		return ""
	var weapon: ItemInstance = ItemInstance.new(
			session.ids.next_item_id(unit_type.starting_weapon_id), unit_type.starting_weapon_id
	)
	var unit: UnitInstance = UnitInstance.new(unit_id, type_id)
	unit.weapon_id = weapon.instance_id
	unit.level = level
	var items: Dictionary[String, ItemInstance] = {weapon.instance_id: weapon}
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			_catalog, unit, items, side, seat, session.ids
	)
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		_ok("%s: loads for the Vanguard battle" % [type_id], false, str(loaded.problems))
		return ""
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = tile
	return unit_id if session.add_unit(loaded.state, loaded.bases) else ""


func _plain_row(width: int) -> MapGrid:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "vanguard_content"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for x: int in width:
		layout.set_terrain(Vector2i(x, 0), plain)
	return MapGrid.new(layout)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])


## One row battle: its session and the Drengr's id.
class Battle:
	extends RefCounted

	## The battle's session, not yet opened.
	var session: CombatSession = null
	## The Drengr's instance id.
	var drengr_id: String = ""
