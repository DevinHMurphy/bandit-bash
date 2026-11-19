# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_setup.gd
# Author:
# Created:  October 30, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name EnemySetup
extends RefCounted
## Setup steps 4 to 6 for the battle's enemies: the pack every map shares, each reinforcement
## wave's group, and each seat's extra enemies (the Hunted curse).
##
## [method draw] (step 4) picks one pack from the combat's pool ([method pool_for]) with the shared
## [code]ENCOUNTER_SETUP[/code] stream and gives its units at the floor's step the map's enemy
## slots in [MapLayout] order, but its leader, an elite, the leader slot. On a key map the pack is
## the escort of the run's next mini-boss ([method mini_boss_for]), who takes the leader slot, so
## no mini-boss repeats until all have fought. [WaveGroups] draws a pack
## per reinforcement wave from a standard pool (step 5). [method draw_additions] (step 6) draws a
## seat's extra enemies from that seat's stream into the slots step 4 left free.
## [method place] builds each unit through [Loadout] (side enemy, seat -1) and places it; every map
## places its own copies of the shared units, plus its seats' additions. Results are plain data,
## never saved: a restart from Begin draws them again, and a resume restores units from the
## snapshot. Pure rules code: it draws only from the streams handed to it and reports problems in
## the session's [member EffectEngine.diagnostics].
##
## @tutorial(Enemy packs): docs/design/enemy-packs.md
## @tutorial(Run structure): docs/design/game-vision.md

## The key of the drawn enemies in [member CombatEncounter.EncounterSetup.shared]: a Dictionary
## with [constant PACK_KEY], [constant UNITS_KEY], [constant UNPLACED_KEY], on a key map
## [constant MINI_BOSS_KEY], and, when the leader slot stays empty, [constant NO_LEADER_KEY] or
## [constant NO_LEADER_SLOT_KEY].
const ENEMIES_KEY: String = "enemies"

## The key of a seat's extra enemies in [member CombatEncounter.SeatSetup.additions]: a
## Dictionary with [constant UNITS_KEY] and [constant UNPLACED_KEY], shaped as step 4's.
const ADDITIONS_KEY: String = "extra_enemies"

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

## A unit's tile, its enemy slot's or the leader slot's, as [code][x, y][/code].
const TILE_KEY: String = "tile"

## The elite's prefix id ([method UnitPrefixDefinition.roll_elite]); only the entry of a leader or
## a mini-boss has it.
const PREFIX_KEY: String = "prefix_id"

## The leader class id of a pack whose step doesn't field it, so the leader slot stays empty;
## absent otherwise. [method place] reports it.
const NO_LEADER_KEY: String = "no_leader"

## The drawn key pack's mini-boss class id ([member PackDefinition.mini_boss_id]); absent on a map
## that isn't a key map.
const MINI_BOSS_KEY: String = "mini_boss"

## The mini-boss class id of a key map with no leader slot, so only its escort fields; absent
## otherwise. [method place] reports it.
const NO_LEADER_SLOT_KEY: String = "no_leader_slot"

## Levels a key combat's enemies have over their step's (game-vision.md, Run structure).
const KEY_COMBAT_LEVELS: int = 1

## Levels a leader or mini-boss has over its step's enemies (game-vision.md, Run structure).
const LEADER_LEVELS: int = 2

## A difficulty step's first standard combats that draw the basic pool; later ones draw the hard
## pool (enemy-packs.md, Decision 5). A first value to tune in playtesting.[br]
## [b]Units:[/b] standard combats. [b]0:[/b] every standard combat draws the hard pool.
const BASIC_COMBATS_PER_STEP: int = 2

# game-vision.md, Run structure: each difficulty step's last floor and its Normal enemy level.
const _STEP_LAST_FLOORS: Array[int] = [5, 11, 17]
const _STEP_LEVELS: Array[int] = [1, 3, 5]


## Setup step 4: one pack drawn from [param catalog]'s [method pool_for] pool with [param ctx]'s
## shared stream, its units at the floor's step given the enemy slots in order at
## [method level_for] plus [param level_modifier]; the pack's leader takes the leader slot at the
## leader's level with a drawn elite prefix. On a key map the pack escorts [param mini_boss_id],
## who stands on the leader slot. A scripted map ([member CombatMapDefinition.fixed_pack_id])
## takes its pack undrawn, with its fixed levels and leader prefix. Register it bound:
## [code]draw.bind(catalog, floor_number, level_modifier, standard_combats, mini_boss_id)[/code].
static func draw(
		ctx: CombatEncounter.SetupContext,
		catalog: EffectCatalog.Index,
		floor_number: int,
		level_modifier: int,
		standard_combats: int = 0,
		mini_boss_id: String = ""
) -> void:
	var map: CombatMapDefinition = ctx.setup.map
	var is_key: bool = _is_key(map)
	var is_fixed: bool = map != null and not map.fixed_pack_id.is_empty()
	var pool: PackDefinition.Pool = pool_for(is_key, standard_combats)
	var pack: PackDefinition = null
	if is_fixed:
		pack = catalog.definition(map.fixed_pack_id) as PackDefinition
	elif is_key and not mini_boss_id.is_empty():
		pack = _pick_pack(catalog, pool, ctx.stream, mini_boss_id)
	if pack == null and not is_fixed:
		pack = _pick_pack(catalog, pool, ctx.stream)
	if pack == null:
		return
	var classes: PackedStringArray = pack.units(step_of(floor_number))
	var level: int = level_for(floor_number, is_key, false, level_modifier)
	if is_fixed and map.fixed_enemy_level > 0:
		level = maxi(map.fixed_enemy_level + level_modifier, 1)
	var slots: Array[Vector2i] = ctx.setup.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var leader_slots: Array[Vector2i] = ctx.setup.layout.tiles_of(
			MapLayout.MarkerKind.LEADER_SLOT
	)
	var leader_at: int = -1
	var drawn: Dictionary = {PACK_KEY: pack.id}
	var units: Array[Dictionary] = []
	if is_key and not pack.mini_boss_id.is_empty():
		drawn[MINI_BOSS_KEY] = pack.mini_boss_id
		if leader_slots.is_empty():
			drawn[NO_LEADER_SLOT_KEY] = pack.mini_boss_id
		else:
			var boss_tile: Vector2i = leader_slots[0]
			units.append({
				CLASS_KEY: pack.mini_boss_id,
				LEVEL_KEY: level_for(floor_number, is_key, true, level_modifier),
				TILE_KEY: [boss_tile.x, boss_tile.y],
				PREFIX_KEY: UnitPrefixDefinition.roll_elite(ctx.stream, catalog),
			})
	if not leader_slots.is_empty() and not pack.leader_class_id.is_empty():
		leader_at = classes.find(pack.leader_class_id)
		if leader_at < 0:
			drawn[NO_LEADER_KEY] = pack.leader_class_id
	var unplaced: Array[String] = []
	var filled: int = 0
	for index: int in classes.size():
		var class_id: String = classes[index]
		if index == leader_at:
			var leader_tile: Vector2i = leader_slots[0]
			var leader_level: int = level_for(floor_number, is_key, true, level_modifier)
			var prefix_id: String = ""
			if is_fixed and map.fixed_leader_level > 0:
				leader_level = maxi(map.fixed_leader_level + level_modifier, 1)
			if is_fixed and not map.fixed_leader_prefix_id.is_empty():
				prefix_id = map.fixed_leader_prefix_id
			else:
				prefix_id = UnitPrefixDefinition.roll_elite(ctx.stream, catalog)
			units.append({
				CLASS_KEY: class_id,
				LEVEL_KEY: leader_level,
				TILE_KEY: [leader_tile.x, leader_tile.y],
				PREFIX_KEY: prefix_id,
			})
			continue
		if filled >= slots.size():
			unplaced.append(class_id)
			continue
		var tile: Vector2i = slots[filled]
		filled += 1
		units.append({CLASS_KEY: class_id, LEVEL_KEY: level, TILE_KEY: [tile.x, tile.y]})
	drawn[UNITS_KEY] = units
	drawn[UNPLACED_KEY] = unplaced
	ctx.setup.shared[ENEMIES_KEY] = drawn


## Setup step 6 for [param ctx]'s seat: one extra enemy per point of the seat's count in
## [param extra_by_seat] ([method extra_enemies]), each a class drawn evenly from
## [method standard_classes] with the seat's stream, at the level step 4's units have. They take
## the enemy slots step 4 left free, in [MapLayout] order; one with no free slot is listed as
## unplaced and never arrives. A seat with no count draws nothing. Writes under
## [constant ADDITIONS_KEY] in [member CombatEncounter.SeatSetup.additions]. Register it bound:
## [code]draw_additions.bind(catalog, floor_number, level_modifier, extra_by_seat)[/code].
static func draw_additions(
		ctx: CombatEncounter.SetupContext,
		catalog: EffectCatalog.Index,
		floor_number: int,
		level_modifier: int,
		extra_by_seat: Dictionary[int, int]
) -> void:
	var count: int = extra_by_seat.get(ctx.seat, 0)
	var classes: PackedStringArray = standard_classes(catalog)
	if count <= 0 or classes.is_empty() or ctx.seat_setup == null:
		return
	var level: int = level_for(floor_number, _is_key(ctx.setup.map), false, level_modifier)
	var free: Array[Vector2i] = _free_slots(ctx.setup)
	var units: Array[Dictionary] = []
	var unplaced: Array[String] = []
	for i: int in count:
		var class_id: String = classes[ctx.stream.pick_index(classes.size())]
		if units.size() >= free.size():
			unplaced.append(class_id)
			continue
		var tile: Vector2i = free[units.size()]
		units.append({CLASS_KEY: class_id, LEVEL_KEY: level, TILE_KEY: [tile.x, tile.y]})
	ctx.seat_setup.additions[ADDITIONS_KEY] = {
		UNITS_KEY: units,
		UNPLACED_KEY: unplaced,
	}


## [constant CampaignValue.Key.EXTRA_ENEMIES] of [param seat]'s army (Hunted adds 1 a copy), read
## before the battle exists, on a throwaway engine holding the effects of [param heirloom_ids]
## (the seat's heirlooms and curses, an id once per copy held) with fresh campaign lanes. Setup
## runs before the battle registers the army's carriers, so no session can answer yet. Never
## below 0.
static func extra_enemies(
		catalog: EffectCatalog.Index, heirloom_ids: PackedStringArray, seat: int
) -> int:
	if heirloom_ids.is_empty():
		return 0
	var engine: EffectEngine = EffectEngine.new(
			CombatState.new(), ForcedRolls.new(PackedInt32Array())
	)
	# NOTE: a fresh allocator, so the scratch effects' ids are minted outside the run's.
	var scratch: InstanceIdAllocator = InstanceIdAllocator.new()
	for heirloom_id: String in heirloom_ids:
		for instance: EffectInstance in Loadout.heirloom_effects(catalog, heirloom_id, seat, scratch):
			engine.register(instance)
	var sheet: StatSheet = engine.stats(InstanceIdAllocator.seat_subject_id(seat))
	return maxi(sheet.get_int(CampaignValue.Key.EXTRA_ENEMIES), 0)


## Ids of the standard enemy classes in [param catalog], in id order: every class some pack setup
## can draw ([method PackDefinition.is_drawn]) fields at any step. Mini-bosses and the boss never
## sit in a drawn pack's units (the boss leads only its map's undrawn pack), so they are left out
## without a mark of their own; so is a class a pack names that the catalog lacks.
static func standard_classes(catalog: EffectCatalog.Index) -> PackedStringArray:
	var found: Dictionary[String, bool] = {}
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.PACK):
		var pack: PackDefinition = resource as PackDefinition
		if pack == null or not pack.is_drawn():
			continue
		for class_id: String in pack.class_ids():
			if catalog.enemy_class(class_id) != null:
				found[class_id] = true
	var ids: PackedStringArray = PackedStringArray(found.keys())
	ids.sort()
	return ids


## Builds and places on [param session]'s map every enemy setup drew, reading content from
## [param catalog]: the shared units ([method draw]) in order, then the additions of each of its
## seats ([method draw_additions]). Call once per session, before the army deploys, so automatic
## deployment ranks its tiles by the enemies' real tiles. A unit that can't be built or whose tile
## is taken or can't be stood on is skipped, as is each unplaced unit, an empty leader slot
## ([constant NO_LEADER_KEY]) and a mini-boss with no slot ([constant NO_LEADER_SLOT_KEY]), with a
## line in the session's diagnostics. The leader or mini-boss is marked by the slot it stands on
## ([method Objectives.marked_ids]).
## Returns the ids of the units placed, in order.
static func place(session: CombatSession, catalog: EffectCatalog.Index) -> PackedStringArray:
	var placed: PackedStringArray = []
	if session.setup == null:
		return placed
	var shared: Variant = session.setup.shared.get(ENEMIES_KEY, null)
	placed.append_array(_place_result(session, catalog, shared, "no enemy slot left"))
	if shared is Dictionary and (shared as Dictionary).has(NO_LEADER_KEY):
		_report(session, "the pack fields no %s at this step, so the leader slot stays empty" % [
			(shared as Dictionary)[NO_LEADER_KEY],
		])
	if shared is Dictionary and (shared as Dictionary).has(NO_LEADER_SLOT_KEY):
		_report(session, "the key map has no leader slot, so its mini-boss %s isn't placed" % [
			(shared as Dictionary)[NO_LEADER_SLOT_KEY],
		])
	for seat: int in session.seats:
		var seat_setup: CombatEncounter.SeatSetup = session.setup.seats.get(seat, null)
		if seat_setup == null:
			continue
		placed.append_array(_place_result(
				session,
				catalog,
				seat_setup.additions.get(ADDITIONS_KEY, null),
				"no free enemy slot for seat %d's extra enemy" % [seat]
		))
	return placed


## The pool a combat draws its pack from: [constant PackDefinition.Pool.KEY] for a key combat;
## for any other, [constant PackDefinition.Pool.BASIC] while [param standard_combats] (those
## entered earlier in the step) is below [constant BASIC_COMBATS_PER_STEP], else
## [constant PackDefinition.Pool.HARD].
static func pool_for(is_key: bool, standard_combats: int) -> PackDefinition.Pool:
	if is_key:
		return PackDefinition.Pool.KEY
	if standard_combats < BASIC_COMBATS_PER_STEP:
		return PackDefinition.Pool.BASIC
	return PackDefinition.Pool.HARD


## Ids of the mini-bosses in [param catalog], in id order: every enemy class a key pack names as
## its [member PackDefinition.mini_boss_id]. A name the catalog lacks is left out.
static func mini_boss_ids(catalog: EffectCatalog.Index) -> PackedStringArray:
	var found: Dictionary[String, bool] = {}
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.PACK):
		var pack: PackDefinition = resource as PackDefinition
		if pack == null or pack.pool != PackDefinition.Pool.KEY or pack.mini_boss_id.is_empty():
			continue
		if catalog.enemy_class(pack.mini_boss_id) != null:
			found[pack.mini_boss_id] = true
	var ids: PackedStringArray = PackedStringArray(found.keys())
	ids.sort()
	return ids


## The mini-boss of a run's key combat with [param key_combats_before] key combats before it: its
## place in the run's order, shuffled from [param order], a stream fresh from the run's
## [constant RngKey.RngPurpose.MINI_BOSS_DRAW] key. Every [method mini_boss_ids] fights once
## before any repeats; past them all a new shuffle begins. Empty when the catalog has none.
static func mini_boss_for(
		catalog: EffectCatalog.Index, order: RngStream, key_combats_before: int
) -> String:
	var ids: PackedStringArray = mini_boss_ids(catalog)
	if ids.is_empty():
		return ""
	var index: int = maxi(key_combats_before, 0)
	var shuffled: PackedInt32Array = []
	for _cycle: int in floori(float(index) / float(ids.size())) + 1:
		shuffled = order.shuffle_indices(ids.size())
	return ids[shuffled[index % ids.size()]]


## The difficulty step of floor [param floor_number] (game-vision.md, Run structure), 1 to
## [constant PackDefinition.STEPS]. A floor before the first step counts as step 1; one past the
## last, as the last.
static func step_of(floor_number: int) -> int:
	# ASSUMPTION: CombatEncounter.floor_number counts floors from 1, as the vision's table does;
	# P08 owns the numbering.
	for step: int in _STEP_LAST_FLOORS.size():
		if floor_number <= _STEP_LAST_FLOORS[step]:
			return step + 1
	return _STEP_LAST_FLOORS.size()


## The level of an enemy on floor [param floor_number]: its step's ([method step_of]) Normal
## level, +[constant KEY_COMBAT_LEVELS] in a key combat, +[constant LEADER_LEVELS] for a leader or
## mini-boss, plus [param modifier] (such as the difficulty ladder's), never below 1.
static func level_for(
		floor_number: int, is_key: bool, is_leader: bool = false, modifier: int = 0
) -> int:
	var level: int = _STEP_LEVELS[step_of(floor_number) - 1]
	# ASSUMPTION: a leader's or mini-boss's +2 is over its step's level and replaces a key
	# combat's +1 rather than adding to it; EN7 is the first to place one.
	if is_leader:
		level += LEADER_LEVELS
	elif is_key:
		level += KEY_COMBAT_LEVELS
	return maxi(level + modifier, 1)


# Places every unit of result (step 4's or a seat's additions, plain data) and reports each of its
# unplaced classes as "<missing>: <class>". Returns the ids placed, in order.
static func _place_result(
		session: CombatSession, catalog: EffectCatalog.Index, result: Variant, missing: String
) -> PackedStringArray:
	var placed: PackedStringArray = []
	if not result is Dictionary:
		return placed
	var drawn: Dictionary = result
	var units: Variant = drawn.get(UNITS_KEY, [])
	if units is Array:
		# Untyped: setup results are plain data.
		for entry: Variant in units:
			if not entry is Dictionary:
				continue
			var unit_id: String = _place_unit(session, catalog, entry as Dictionary)
			if not unit_id.is_empty():
				placed.append(unit_id)
	var unplaced: Variant = drawn.get(UNPLACED_KEY, [])
	if unplaced is Array:
		for class_id: Variant in unplaced:
			_report(session, "%s for %s" % [missing, class_id])
	return placed


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

	var prefix_id: String = str(entry.get(PREFIX_KEY, UnitPrefixDefinition.NO_PREFIX))
	var loaded: Loadout.LoadedUnit = _load(
			session,
			catalog,
			enemy_class,
			_whole(entry.get(LEVEL_KEY, 1)),
			session.ids.next_enemy_id(_label_of(catalog, enemy_class, prefix_id)),
			prefix_id
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
		_report(session, "%s wasn't placed on %s" % [session.describe(loaded.state.id), tile])
		return ""
	return loaded.state.id


# Loads enemy_class at level as unit unit_id, with its class's starting weapon and equipment and
# prefix_id (none when empty), item ids minted by session's allocator. Changes nothing in session
# but the ids it mints.
static func _load(
		session: CombatSession,
		catalog: EffectCatalog.Index,
		enemy_class: EnemyClassDefinition,
		level: int,
		unit_id: String,
		prefix_id: String = UnitPrefixDefinition.NO_PREFIX
) -> Loadout.LoadedUnit:
	var unit: UnitInstance = UnitInstance.new(unit_id, enemy_class.id)
	unit.level = level
	unit.prefix_id = prefix_id
	var items: Dictionary[String, ItemInstance] = {}
	var weapon_id: String = enemy_class.starting_weapon_id
	if not weapon_id.is_empty():
		var weapon: ItemDefinition = catalog.item(weapon_id)
		var item_id: String = session.ids.next_item_id(
				weapon_id if weapon == null else weapon.display_name
		)
		items[item_id] = ItemInstance.new(item_id, weapon_id)
		unit.weapon_id = item_id
	var equipment_id: String = enemy_class.starting_equipment_id
	if not equipment_id.is_empty():
		var equipment: ItemDefinition = catalog.item(equipment_id)
		var gear_id: String = session.ids.next_item_id(
				equipment_id if equipment == null else equipment.display_name
		)
		items[gear_id] = ItemInstance.new(gear_id, equipment_id)
		unit.equipment_id = gear_id
	return Loadout.load_unit(catalog, unit, items, CombatFact.CombatSide.ENEMY, -1, session.ids)


# One pack drawn evenly from catalog's packs of pool, in id order, only those escorting
# mini_boss_id when it isn't empty; null, drawing nothing, when none is left.
static func _pick_pack(
		catalog: EffectCatalog.Index,
		pool: PackDefinition.Pool,
		stream: RngStream,
		mini_boss_id: String = ""
) -> PackDefinition:
	var packs: Array[PackDefinition] = []
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.PACK):
		var pack: PackDefinition = resource as PackDefinition
		if pack == null or pack.pool != pool:
			continue
		if mini_boss_id.is_empty() or pack.mini_boss_id == mini_boss_id:
			packs.append(pack)
	if packs.is_empty():
		return null
	return packs[stream.pick_index(packs.size())]


# The enemy slots of setup's layout, in MapLayout order, that step 4 gave no unit.
static func _free_slots(setup: CombatEncounter.EncounterSetup) -> Array[Vector2i]:
	var taken: Dictionary[Vector2i, bool] = {}
	var drawn: Variant = setup.shared.get(ENEMIES_KEY, null)
	if drawn is Dictionary:
		var units: Variant = (drawn as Dictionary).get(UNITS_KEY, [])
		if units is Array:
			# Untyped: setup results are plain data.
			for entry: Variant in units:
				if entry is Dictionary:
					taken[_tile_of(entry as Dictionary)] = true
	var free: Array[Vector2i] = []
	for tile: Vector2i in setup.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT):
		if not taken.has(tile):
			free.append(tile)
	return free


static func _is_key(map: CombatMapDefinition) -> bool:
	return map != null and map.combat_type == CombatMapDefinition.CombatType.KEY


# The unit's name in logs and the HUD: its prefix before its class (unit-roster.md, Prefixes), as
# "Sturdy Warcaller"; the class alone with no prefix or one the catalog lacks.
static func _label_of(
		catalog: EffectCatalog.Index, enemy_class: EnemyClassDefinition, prefix_id: String
) -> String:
	if prefix_id.is_empty():
		return enemy_class.display_name
	var prefix: UnitPrefixDefinition = catalog.unit_prefix(prefix_id)
	if prefix == null:
		return enemy_class.display_name
	return "%s %s" % [prefix.display_name, enemy_class.display_name]


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


## Reinforcement waves' groups (setup step 5): each wave is one pack at the floor's step, drawn
## as [method draw] draws a standard combat's (basic or hard pool, even on a key map, whose escorts
## belong with their mini-boss), and each of its units is built at the level step 4's units have,
## with its weapon, equipment and traits. Make one per battle, for that battle's catalog and floor,
## and hand the same one to [method Reinforcements.draw_waves] and [method Reinforcements.register].
class WaveGroups:
	extends Reinforcements.GroupSource

	var _catalog: EffectCatalog.Index = null
	var _floor_number: int = -1
	var _level_modifier: int = 0
	var _standard_combats: int = 0

	## [param catalog]: the battle's content. [param floor_number], [param level_modifier],
	## [param standard_combats]: as [method EnemySetup.draw]'s.
	func _init(
			catalog: EffectCatalog.Index,
			floor_number: int,
			level_modifier: int,
			standard_combats: int = 0
	) -> void:
		_catalog = catalog
		_floor_number = floor_number
		_level_modifier = level_modifier
		_standard_combats = standard_combats

	## One pack's units drawn from [param stream], one entry per unit naming its class as its
	## [constant Reinforcements.UNIT_TYPE_KEY]; empty, drawing nothing, with an empty pool. Every
	## wave draws its own pack, whatever its point and turn.
	func draw_group(stream: RngStream, _point: MapLayout.Marker, _turn: int) -> Array[Dictionary]:
		var group: Array[Dictionary] = []
		# ASSUMPTION: a wave is one standard pack at the step's size, also on a key map; wave sizes
		# are left to playtesting (enemy-packs.md, Decision 4).
		var pack: PackDefinition = EnemySetup._pick_pack(
				_catalog, EnemySetup.pool_for(false, _standard_combats), stream
		)
		if pack == null:
			return group
		for class_id: String in pack.units(EnemySetup.step_of(_floor_number)):
			group.append({Reinforcements.UNIT_TYPE_KEY: class_id})
		return group

	## [param entry]'s class as unit [param unit_id], at [method EnemySetup.level_for] this floor
	## and [param session]'s map, named by its class's display name; null for a class the catalog
	## lacks or one that doesn't load. The level is read here, not drawn, so a wave saved before a
	## resume builds the same units.
	func build(session: CombatSession, entry: Dictionary, unit_id: String) -> Reinforcements.Recruit:
		var class_id: String = str(entry.get(Reinforcements.UNIT_TYPE_KEY, ""))
		var enemy_class: EnemyClassDefinition = _catalog.enemy_class(class_id)
		if enemy_class == null:
			return null
		var is_key: bool = session.setup != null and EnemySetup._is_key(session.setup.map)
		var level: int = EnemySetup.level_for(_floor_number, is_key, false, _level_modifier)
		session.ids.set_label(unit_id, enemy_class.display_name)
		var loaded: Loadout.LoadedUnit = EnemySetup._load(
				session, _catalog, enemy_class, level, unit_id
		)
		if not loaded.is_loaded():
			return null
		var recruit: Reinforcements.Recruit = Reinforcements.Recruit.new()
		recruit.unit = loaded.state
		recruit.bases = loaded.bases
		recruit.weapons = loaded.weapons
		recruit.effects = loaded.effects
		return recruit
