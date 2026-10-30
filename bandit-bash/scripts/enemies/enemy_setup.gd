# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_setup.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name EnemySetup
extends RefCounted
## Setup step 4: the battle's enemies, drawn once for every map and placed on each.
##
## [method draw] runs on [constant CombatEncounter.SetupStep.ENEMY_SLOTS]: it picks one pack from
## the battle's catalog with the shared [code]ENCOUNTER_SETUP[/code] stream and writes plain data
## under [constant ENEMIES_KEY] in [member CombatEncounter.EncounterSetup.shared]: the pack, and
## for each of its units in pack order, its class, its level ([method level_for]) and the enemy
## slot it fills. Units fill the map's enemy slots in [MapLayout] order (enemies and AI plan,
## question 16); slots left over stay empty, and units beyond the last slot are listed as
## unplaced. The leader slot is never filled (question 12).[br]
## [method place] builds each drawn unit through [Loadout] (side enemy, seat -1, its class's
## starting weapon) with ids from the session's allocator, and places it on its slot's tile. Each
## map places its own copies, so co-op maps start identical. The setup result is never saved: a
## battle restarted from Begin draws it again, and a resumed one restores its units from the
## snapshot. Pure rules code: it draws only from the stream handed to it and reports problems in
## the session's [member EffectEngine.diagnostics].
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md
## @tutorial(Run structure): docs/design/game-vision.md

## The key of the drawn enemies in [member CombatEncounter.EncounterSetup.shared]: a Dictionary
## with [constant PACK_KEY], [constant UNITS_KEY] and [constant UNPLACED_KEY].
const ENEMIES_KEY: String = "enemies"

## The drawn pack's content id.
const PACK_KEY: String = "pack"

## The units to place, in pack order: one Dictionary each with [constant CLASS_KEY],
## [constant LEVEL_KEY] and [constant TILE_KEY].
const UNITS_KEY: String = "units"

## Class ids of the pack's units that had no enemy slot left, in pack order.
const UNPLACED_KEY: String = "unplaced"

## A unit's enemy class id.
const CLASS_KEY: String = "class_id"

## A unit's level.
const LEVEL_KEY: String = "level"

## A unit's tile, its enemy slot's, as [code][x, y][/code].
const TILE_KEY: String = "tile"

## Levels a key combat's enemies have over their step's (game-vision.md, Run structure).
const KEY_COMBAT_LEVELS: int = 1

## Levels a leader or mini-boss has over its step's enemies (game-vision.md, Run structure).
const LEADER_LEVELS: int = 2

# game-vision.md, Run structure: each difficulty step's last floor and its Normal enemy level.
const _STEP_LAST_FLOORS: Array[int] = [5, 11, 17]
const _STEP_LEVELS: Array[int] = [1, 3, 5]


## Setup step 4: draws one pack from every [PackDefinition] in [param catalog] (in id order) with
## [param ctx]'s shared stream and assigns its units to the map's enemy slots, each at
## [method level_for] the floor [param floor_number], key when the drawn map is a key combat, plus
## [param level_modifier]. No pack in the catalog draws and writes nothing. Register it bound:
## [code]draw.bind(catalog, floor_number, level_modifier)[/code].
static func draw(
		ctx: CombatEncounter.SetupContext,
		catalog: EffectCatalog.Index,
		floor_number: int,
		level_modifier: int
) -> void:
	var packs: Array[Resource] = catalog.all_of(EffectCatalog.Kind.PACK)
	if packs.is_empty():
		return
	var pack: PackDefinition = packs[ctx.stream.pick_index(packs.size())]
	var is_key: bool = (
			ctx.setup.map != null
			and ctx.setup.map.combat_type == CombatMapDefinition.CombatType.KEY
	)
	var level: int = level_for(floor_number, is_key, false, level_modifier)
	var slots: Array[Vector2i] = ctx.setup.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var units: Array[Dictionary] = []
	var unplaced: Array[String] = []
	for class_id: String in pack.units():
		if units.size() >= slots.size():
			unplaced.append(class_id)
			continue
		var tile: Vector2i = slots[units.size()]
		units.append({CLASS_KEY: class_id, LEVEL_KEY: level, TILE_KEY: [tile.x, tile.y]})
	ctx.setup.shared[ENEMIES_KEY] = {
		PACK_KEY: pack.id,
		UNITS_KEY: units,
		UNPLACED_KEY: unplaced,
	}


## Builds and places on [param session]'s map every enemy setup drew ([method draw]), in order,
## reading content from [param catalog]. Call once per session, before the army deploys, so
## automatic deployment ranks its tiles by the enemies' real tiles. A unit that can't be built or
## whose tile is taken or can't be stood on is skipped, as is each unplaced unit, with a line in
## the session's diagnostics.
## Returns the ids of the units placed, in order.
static func place(session: CombatSession, catalog: EffectCatalog.Index) -> PackedStringArray:
	var placed: PackedStringArray = []
	if session.setup == null:
		return placed
	var drawn: Variant = session.setup.shared.get(ENEMIES_KEY, null)
	if not drawn is Dictionary:
		return placed
	var result: Dictionary = drawn
	var units: Variant = result.get(UNITS_KEY, [])
	if units is Array:
		# Untyped: setup results are plain data.
		for entry: Variant in units:
			if not entry is Dictionary:
				continue
			var unit_id: String = _place_unit(session, catalog, entry as Dictionary)
			if not unit_id.is_empty():
				placed.append(unit_id)
	var unplaced: Variant = result.get(UNPLACED_KEY, [])
	if unplaced is Array:
		for class_id: Variant in unplaced:
			_report(session, "no enemy slot left for %s" % [class_id])
	return placed


## The level of an enemy on floor [param floor_number] (counted from 1, as in game-vision.md's
## Run structure): its step's Normal level, +[constant KEY_COMBAT_LEVELS] in a key combat,
## +[constant LEADER_LEVELS] for a leader or mini-boss, plus [param modifier] (such as the
## difficulty ladder's), never below 1. A floor before the first step counts as step 1; one past
## the last, as the last.
static func level_for(
		floor_number: int, is_key: bool, is_leader: bool = false, modifier: int = 0
) -> int:
	# ASSUMPTION: CombatEncounter.floor_number counts floors from 1, as the vision's table does;
	# P08 owns the numbering.
	var level: int = _STEP_LEVELS[_STEP_LEVELS.size() - 1]
	for step: int in _STEP_LAST_FLOORS.size():
		if floor_number <= _STEP_LAST_FLOORS[step]:
			level = _STEP_LEVELS[step]
			break
	# ASSUMPTION: a leader's or mini-boss's +2 is over its step's level and replaces a key
	# combat's +1 rather than adding to it; EN7 is the first to place one.
	if is_leader:
		level += LEADER_LEVELS
	elif is_key:
		level += KEY_COMBAT_LEVELS
	return maxi(level + modifier, 1)


# Builds entry's unit through the loadout and places it on its tile. Returns its id, or empty
# when it wasn't placed.
static func _place_unit(
		session: CombatSession, catalog: EffectCatalog.Index, entry: Dictionary
) -> String:
	var state: CombatState = session.state
	var class_id: String = str(entry.get(CLASS_KEY, ""))
	var enemy_class: EnemyClassDefinition = catalog.enemy_class(class_id)
	if enemy_class == null:
		_report(session, "enemy class \"%s\" is not in the catalog" % [class_id])
		return ""
	var tile: Vector2i = _tile_of(entry)
	if (
			not state.occupant_at(tile).is_empty()
			or not state.can_stand(tile, enemy_class.movement_type)
	):
		_report(session, "%s can't stand on %s" % [enemy_class.display_name, tile])
		return ""

	var unit: UnitInstance = UnitInstance.new(
			session.ids.next_enemy_id(enemy_class.display_name), class_id
	)
	unit.level = _whole(entry.get(LEVEL_KEY, 1))
	var items: Dictionary[String, ItemInstance] = {}
	var weapon_id: String = enemy_class.starting_weapon_id
	if not weapon_id.is_empty():
		var weapon: ItemDefinition = catalog.item(weapon_id)
		var item_id: String = session.ids.next_item_id(
				weapon_id if weapon == null else weapon.display_name
		)
		items[item_id] = ItemInstance.new(item_id, weapon_id)
		unit.weapon_id = item_id
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			catalog, unit, items, CombatFact.CombatSide.ENEMY, -1, session.ids
	)
	for problem: String in loaded.problems:
		_report(session, problem)
	if not loaded.is_loaded():
		return ""

	for weapon_stats: CombatState.WeaponStats in loaded.weapons:
		state.add_weapon(weapon_stats)
	# Effects first, so the full Stance set at placement counts them.
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = tile
	if not session.add_unit(loaded.state, loaded.bases):
		_report(session, "%s wasn't placed on %s" % [session.describe(unit.instance_id), tile])
		return ""
	return unit.instance_id


static func _report(session: CombatSession, problem: String) -> void:
	session.engine.diagnostics.append("EnemySetup: %s" % [problem])


# The tile in entry's [x, y]; NO_TILE when it isn't one.
static func _tile_of(entry: Dictionary) -> Vector2i:
	var tile: Variant = entry.get(TILE_KEY, null)
	if not tile is Array or (tile as Array).size() != 2:
		return CombatFact.NO_TILE
	var parts: Array = tile
	return Vector2i(_whole(parts[0]), _whole(parts[1]))


# A whole number from plain data, an int or a float after a JSON round trip; 0 for anything else.
static func _whole(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	var number: float = value
	return roundi(number)
