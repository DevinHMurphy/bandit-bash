# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_state.gd
# Author:
# Created:  October 27, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name CombatState
extends SandboxState
## One map's combat state: its units, occupancy, turn, phase and rune slots, and the effect
## engine's whole view of the map.
##
## Implements every [SandboxState] read and write, so the engine's conditions, selectors and
## resource paths work on the real map. The writes ([method set_hp], [method set_block],
## [method set_stance]) are for the engine's resource paths only; the combat core's damage rules
## and [SplashResolver] are the other writers, and every change they make emits a fact. A unit's
## effects go dormant while [method has_unit] is false, and a stowed weapon's while it isn't
## [method equipped_weapon_id], so nothing is ever unregistered for a defeat or a swap.[br]
## Plain data with ids only: [method copy_for_sandbox] copies everything except [member grid] and
## the weapon records, which are shared and never changed by rules code; [member map] is copied.
## Questions that depend on units or map objects ([method can_stand], [method blocker_at],
## [method validate_path]) are answered here, never by the shared grid.[br]
## Each weapon's numbers ([WeaponStats], built by [Loadout] from its definition) become its
## holder's base values when the unit is placed or swaps weapons ([method load_bases]), so effects
## that replace a weapon's base (Short Quiver's range) and conditions that read it (at maximum
## range) see the weapon in the Weapon slot. A weapon prefix and an item's deltas are effects of
## the item, never part of its record, so they sleep with a stowed weapon.[br]
## [b]Saves and mirrors:[/b] [method capture] and [method restore] carry everything but
## [member grid] and [member map] (P04's) as plain JSON, for snapshots and the
## [code]combat_state[/code] save section; a client mirror applies the host's facts with
## [method follow].
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md
## @tutorial(Save system design): docs/design/save-system.md
##
## @todo: TOD-001 - Answer darkness_layer() from the darkness plan (P06); every tile is DRY.
## @todo: TOD-002 - Save an area staff's shape by its content id once P03 CT6 gives records one
## (loadout.gd:TOD-001); [method WeaponStats.capture] leaves [member WeaponStats.area] out.

# Facts follow() applies only once the engine has followed every fact before them: a refresh reads
# the unit's Stance maximum, a Pouch item's use reads its charges.
const _FOLLOWED_AFTER_ENGINE: Array[CombatFact.Kind] = [
	CombatFact.Kind.BLOCK_STANCE_REFRESHED,
	CombatFact.Kind.ITEM_USED,
]

# Facts whose actor took its action, which ends its turn. An attack's is the attacker's Before
# Combat and a swap's is WEAPON_SWAPPED, which follow() tells apart from the defender's and from a
# free swap.
const _ACTION_KINDS: Array[CombatFact.Kind] = [
	CombatFact.Kind.ITEM_USED,
	CombatFact.Kind.SHOVED_A_UNIT,
	CombatFact.Kind.USED_STAFF_ON_ALLY,
	CombatFact.Kind.UNIT_WAITED,
	CombatFact.Kind.OBJECT_USED,
]

# What _seat_list() returns inside a list that isn't one; never a seat.
const _NO_SEAT: int = -1

## Terrain and walls. Shared with sandbox copies. Never null in use.
var grid: CombatGrid = null

## The map objects' state ([MapState]). Copied for a sandbox. Never null.
var map: MapState = MapState.new()

## The turn counter: it rises at the player Phase Start, so 0 before the first one.
var turn: int = 0

## Whose phase it is; [constant CombatFact.CombatSide.NONE] before the first Phase Start.
var phase_side: CombatFact.CombatSide = CombatFact.CombatSide.NONE

## Seats that have ended their turn in the current player phase.
var ended_seats: PackedInt32Array = []

## Whether the current phase's Phase End has run: true from then until the next Phase Start, when
## no unit of either side may act ([PhaseRunner]).
var is_phase_ended: bool = false

## Seats in the opening swap window ([member MapState.opening_swap_open]) that haven't sent their
## Start: those with the opening-swap setting on and units on the map. Turn 1's player Phase Start
## runs when it empties ([method PhaseRunner.start]).
var seats_to_start: PackedInt32Array = []

## Rune instance ids in each seat's slots, copied in at battle start by the campaign bridge. A cast
## rune leaves its slot.
var rune_slots: Dictionary[int, PackedStringArray] = {}

var _units: Dictionary[String, CombatUnitState] = {}

# Roster order, then spawn order: the order of placement.
var _order: PackedStringArray = []

var _occupancy: Dictionary[Vector2i, String] = {}

# Weapon records by item instance id, from the loadout.
var _weapons: Dictionary[String, WeaponStats] = {}


func _init(map_grid: CombatGrid = null) -> void:
	grid = map_grid


## Places [param unit] on its tile, with its bases loaded ([method load_bases]), Block 0 and its
## full Stance (its [constant CombatValue.Key.STANCE_MAX] in [param engine]), so a unit attacked
## before its side's first Phase Start still has Stance. Battle start, spawns, reinforcements and
## transfers all place units this way; the caller records any fact. Add its weapons first.
## Returns false, placing nothing, for a known id or a tile that is off the map or taken.
func place_unit(engine: EffectEngine, unit: CombatUnitState) -> bool:
	if unit == null or _units.has(unit.id) or unit.is_defeated:
		return false
	if unit.tile == CombatFact.NO_TILE or _occupancy.has(unit.tile):
		return false
	_units[unit.id] = unit
	_order.append(unit.id)
	_occupancy[unit.tile] = unit.id
	load_bases(engine, unit.id)
	unit.block = 0
	unit.stance = engine.stats(unit.id).get_int(CombatValue.Key.STANCE_MAX)
	return true


## Adds a weapon's record, by its [member WeaponStats.id]. Records are never changed afterwards.
func add_weapon(stats: WeaponStats) -> void:
	_weapons[stats.id] = stats


## The record of the weapon [param weapon_id]; null if unknown.
func weapon(weapon_id: String) -> WeaponStats:
	return _weapons.get(weapon_id, null)


## The record of the weapon in [param unit_id]'s Weapon slot; null when it holds none.
func equipped_weapon(unit_id: String) -> WeaponStats:
	return weapon(equipped_weapon_id(unit_id))


## Sets [param unit_id]'s base values in [param engine] that come from its weapon rather than its
## unit type: the weapon's numbers (Hit, crit, CritX, AtkX, range, damage type, damage as the
## Attack stage, staff amount) and its net weight (weapon plus Pouch items, before equipment and
## effects). Called on placement and after every weapon swap; with no weapon, the weapon numbers
## are 0. Rule bases aren't set here: [StatSheet] falls back to
## [constant DamageStage.DEFAULT_BASES] and [constant CombatValue.DEFAULT_BASES].
func load_bases(engine: EffectEngine, unit_id: String) -> void:
	var holder: CombatUnitState = unit(unit_id)
	if holder == null:
		return
	var held: WeaponStats = equipped_weapon(unit_id)
	if held == null:
		held = WeaponStats.new()
	var label: String = held.label
	engine.set_base(unit_id, CombatValue.Key.HIT, held.hit, label)
	engine.set_base(unit_id, CombatValue.Key.CRIT_CHANCE, held.crit, label)
	engine.set_base(unit_id, CombatValue.Key.CRIT_X, held.crit_x, label)
	engine.set_base(unit_id, CombatValue.Key.ATK_X, held.atk_x, label)
	engine.set_base(unit_id, CombatValue.Key.RANGE_MIN, held.range_min, label)
	engine.set_base(unit_id, CombatValue.Key.RANGE_MAX, held.range_max, label)
	engine.set_base(unit_id, CombatValue.Key.DAMAGE_TYPE, held.damage_type, label)
	engine.set_base(unit_id, CombatValue.Key.STAFF_AMOUNT, held.staff_amount, label)
	engine.set_base(unit_id, DamageStage.Key.ATTACK, held.damage, label)
	var pouch_weight: int = holder.pouch_count() * holder.pouch_item_weight
	engine.set_base(
			unit_id, CombatValue.Key.NET_WEIGHT, held.weight + pouch_weight, "weapon and Pouch"
	)


## The state of [param id], defeated or not; null if unknown.
func unit(id: String) -> CombatUnitState:
	return _units.get(id, null)


## Units of [param side] on the map, in [method unit_ids] order.
func units_of(side: CombatFact.CombatSide) -> PackedStringArray:
	var ids: PackedStringArray = []
	for id: String in unit_ids():
		if _units[id].side == side:
			ids.append(id)
	return ids


## The unit or object standing on [param tile]; empty when none.
func occupant_at(tile: Vector2i) -> String:
	return _occupancy.get(tile, "")


## What stands in the way on [param tile]: [constant CombatGrid.Blocker.UNIT] for a unit,
## [constant CombatGrid.Blocker.PLAIN] for a map object standing there or blocking it in
## [member map], otherwise the grid's answer. Shove asks this, never the grid.
func blocker_at(tile: Vector2i) -> CombatGrid.Blocker:
	var occupant: String = occupant_at(tile)
	if not occupant.is_empty():
		if _units[occupant].side == CombatFact.CombatSide.NONE:
			return CombatGrid.Blocker.PLAIN
		return CombatGrid.Blocker.UNIT
	if map.blocking_at(tile) != MapState.Blocking.NONE:
		return CombatGrid.Blocker.PLAIN
	return grid.blocker_at(tile)


## Whether a unit of [param movement_type] may stand on [param tile] as far as terrain and map
## objects go; units are not counted, so a swap or a shove asks [method occupant_at] as well.
## Rules code asks this, never [method CombatGrid.can_stand].
func can_stand(tile: Vector2i, movement_type: CombatGrid.MovementType) -> bool:
	return grid.can_stand(tile, movement_type) and not map.blocks(tile, movement_type)


## Whether [param unit_id] may walk [param path] now, and what it costs: [method Pathing.check_path]
## on this state. [param path] starts with the unit's tile; the budget is its
## [constant CombatValue.Key.MOVEMENT] in [param engine], less the cost already spent this turn.
func validate_path(
		engine: EffectEngine, unit_id: String, path: Array[Vector2i]
) -> CombatGrid.PathCheck:
	return Pathing.check_path(engine, self, unit_id, path)


## Moves [param id] to the free tile [param tile], updating occupancy. Records nothing: the action
## that moves it records [constant CombatFact.Kind.UNIT_MOVED].
func move_unit(id: String, tile: Vector2i) -> void:
	if not has_unit(id) or _occupancy.has(tile):
		return
	var moving: CombatUnitState = _units[id]
	_occupancy.erase(moving.tile)
	moving.tile = tile
	_occupancy[tile] = id


## Swaps the tiles of two units on the map (the Recall rune). Records nothing.
func swap_units(first_id: String, second_id: String) -> void:
	if not has_unit(first_id) or not has_unit(second_id):
		return
	var first: CombatUnitState = _units[first_id]
	var second: CombatUnitState = _units[second_id]
	var first_tile: Vector2i = first.tile
	first.tile = second.tile
	second.tile = first_tile
	_occupancy[first.tile] = first_id
	_occupancy[second.tile] = second_id


## Records [param id]'s defeat and takes it off the map: [constant CombatFact.Kind.DEFEATED],
## then [constant CombatFact.Kind.DEFEATED_AN_ENEMY] when [param by_id] is on the other side,
## then it leaves occupancy and drops any loot it carried ([method MapObjects.drop_carried]). Its
## effects react to its own defeat before they go dormant. A map object (side
## [constant CombatFact.CombatSide.NONE]) records neither fact: it leaves the map and breaks
## ([method MapObjects.broken]). [param by_id]: the unit or object that defeated it, or empty.
func defeat(engine: EffectEngine, id: String, by_id: String, source_effect_id: String = "") -> void:
	if not has_unit(id):
		return
	if side_of(id) == CombatFact.CombatSide.NONE:
		var broken: CombatUnitState = _units[id]
		broken.is_defeated = true
		_occupancy.erase(broken.tile)
		MapObjects.broken(engine, self, id, by_id, source_effect_id)
		return
	var defeated: CombatFact = CombatFact.new(CombatFact.Kind.DEFEATED, id, by_id)
	defeated.source_effect_id = source_effect_id
	engine.record(defeated)
	if engine.matches_side(side_of(by_id), id, EffectTerms.UnitSide.ENEMY):
		var kill: CombatFact = CombatFact.new(CombatFact.Kind.DEFEATED_AN_ENEMY, by_id, id)
		kill.source_effect_id = source_effect_id
		engine.record(kill)
	var gone: CombatUnitState = _units[id]
	gone.is_defeated = true
	_occupancy.erase(gone.tile)
	MapObjects.drop_carried(self, id, by_id)


## The Wait action: [param id] ends its turn without acting and records
## [constant CombatFact.Kind.UNIT_WAITED]. Returns false, recording nothing, when it is off the
## map or has already acted.
func wait(engine: EffectEngine, id: String) -> bool:
	if not has_unit(id) or _units[id].has_acted:
		return false
	_units[id].has_acted = true
	engine.record(CombatFact.new(CombatFact.Kind.UNIT_WAITED, id))
	return true


## This state as plain JSON values: the turn, the phase and its side, the seats that have ended
## or not yet started, each seat's rune slots, every unit placed ([method CombatUnitState.capture],
## defeated ones and map objects included, in placement order) and every weapon record, by id.
## Seat lists are sorted, so equal states write equal text. [method restore] reverses it.
func capture() -> Dictionary:
	var runes: Dictionary = {}
	var rune_seats: Array[int] = rune_slots.keys()
	rune_seats.sort()
	for seat: int in rune_seats:
		runes[str(seat)] = Array(rune_slots[seat])
	var units: Array = []
	for id: String in _order:
		units.append(_units[id].capture())
	var weapon_ids: Array[String] = _weapons.keys()
	weapon_ids.sort()
	var weapons: Array = []
	for weapon_id: String in weapon_ids:
		weapons.append(_weapons[weapon_id].capture())
	var ended: PackedInt32Array = ended_seats.duplicate()
	ended.sort()
	var starting: PackedInt32Array = seats_to_start.duplicate()
	starting.sort()
	return {
		"turn": turn,
		"phase_side": CombatFact.CombatSide.find_key(phase_side) as String,
		"is_phase_ended": is_phase_ended,
		"ended_seats": Array(ended),
		"seats_to_start": Array(starting),
		"rune_slots": runes,
		"units": units,
		"weapons": weapons,
	}


## Replaces everything [method capture] holds with [param data], also after a trip through JSON;
## occupancy is rebuilt from the units on the map. [member grid] and [member map] are untouched,
## but for [member MapState.opening_swap_open], which is open exactly while
## [member seats_to_start] isn't empty ([PhaseRunner]). Bases and effects are the engine's
## ([method EffectEngine.restore]). Returns [constant OK], or
## [constant ERR_INVALID_DATA], changing nothing, when any part is malformed, an id repeats, two
## units on the map share a tile, or a unit holds a weapon with no record.
func restore(data: Dictionary) -> Error:
	var turn_number: Variant = _whole(data.get("turn", null))
	var side_name: String = str(data.get("phase_side", ""))
	var ended: PackedInt32Array = _seat_list(data.get("ended_seats", null))
	var starting: PackedInt32Array = _seat_list(data.get("seats_to_start", null))
	var runes: Variant = data.get("rune_slots", null)
	var unit_data: Variant = data.get("units", null)
	var weapon_data: Variant = data.get("weapons", null)
	if (
			turn_number == null
			or not CombatFact.CombatSide.has(side_name)
			or not data.get("is_phase_ended", null) is bool
			or ended.has(_NO_SEAT)
			or starting.has(_NO_SEAT)
			or not runes is Dictionary
			or not unit_data is Array
			or not weapon_data is Array
	):
		return ERR_INVALID_DATA
	var slots: Dictionary[int, PackedStringArray] = {}
	var by_seat: Dictionary = runes
	for seat_text: Variant in by_seat:
		var listed: Variant = by_seat[seat_text]
		if not str(seat_text).is_valid_int() or not listed is Array:
			return ERR_INVALID_DATA
		var rune_ids: PackedStringArray = []
		# Untyped: the parts come from JSON and are checked entry by entry.
		for rune_id: Variant in listed:
			if not rune_id is String:
				return ERR_INVALID_DATA
			rune_ids.append(rune_id as String)
		slots[str(seat_text).to_int()] = rune_ids
	var weapons: Dictionary[String, WeaponStats] = {}
	for entry: Variant in weapon_data:
		var record: WeaponStats = (
				WeaponStats.from_capture(entry as Dictionary) if entry is Dictionary else null
		)
		if record == null or weapons.has(record.id):
			return ERR_INVALID_DATA
		weapons[record.id] = record
	var units: Dictionary[String, CombatUnitState] = {}
	var order: PackedStringArray = []
	var occupancy: Dictionary[Vector2i, String] = {}
	for entry: Variant in unit_data:
		var placed: CombatUnitState = (
				CombatUnitState.from_capture(entry as Dictionary) if entry is Dictionary else null
		)
		if placed == null or units.has(placed.id):
			return ERR_INVALID_DATA
		for weapon_id: String in [placed.equipped_weapon_id, placed.stowed_weapon_id]:
			if not weapon_id.is_empty() and not weapons.has(weapon_id):
				return ERR_INVALID_DATA
		if not placed.is_defeated:
			if placed.tile == CombatFact.NO_TILE or occupancy.has(placed.tile):
				return ERR_INVALID_DATA
			occupancy[placed.tile] = placed.id
		units[placed.id] = placed
		order.append(placed.id)

	turn = turn_number
	var side_value: int = CombatFact.CombatSide[side_name]
	phase_side = side_value as CombatFact.CombatSide
	is_phase_ended = data["is_phase_ended"]
	ended_seats = ended
	seats_to_start = starting
	map.opening_swap_open = not starting.is_empty()
	rune_slots = slots
	_units = units
	_order = order
	_occupancy = occupancy
	_weapons = weapons
	return OK


## Applies [param facts], one batch the host recorded, to this state and to [param engine], as a
## client mirror does: the combat core's facts change the units, the turn and the phase as the
## host's rules did, and the engine follows the effects' state ([method EffectEngine.follow]) in
## step, so a value read mid-batch (the Stance a refresh sets, a Pouch item's last use) is the one
## the host read. Draws no roll and fires nothing. A unit's tiles moved, movement spent and second
## move aren't followed: no fact carries them. Nor are a spawned unit no state here knows, map
## objects (P04) or a non-final End Turn or Start on a map several seats share.
func follow(engine: EffectEngine, facts: Array[CombatFact]) -> void:
	var waiting: Array[CombatFact] = []
	# The exchange whose two Before Combat facts are open, "attacker>defender", and the last unit
	# that swapped weapons: an attack right after its swap was a free Sidearm swap.
	var open_exchange: String = ""
	var swapped_id: String = ""
	for fact: CombatFact in facts:
		if _FOLLOWED_AFTER_ENGINE.has(fact.kind) and not waiting.is_empty():
			engine.follow(waiting)
			waiting = []
		waiting.append(fact)
		var actor: CombatUnitState = _units.get(fact.actor_id, null)
		if actor != null and _ACTION_KINDS.has(fact.kind):
			actor.has_acted = true
		match fact.kind:
			CombatFact.Kind.PHASE_START:
				_follow_phase_start(fact)
			CombatFact.Kind.PHASE_END:
				is_phase_ended = true
				if fact.side == CombatFact.CombatSide.PLAYER:
					ended_seats = _seats_on_map()
			CombatFact.Kind.BLOCK_STANCE_REFRESHED:
				if actor != null:
					actor.has_acted = false
					actor.tiles_moved = 0
					actor.movement_spent = 0
					actor.is_second_move_pending = false
					actor.has_used_sidearm = false
					actor.block = 0
					actor.stance = engine.stats(actor.id).get_int(CombatValue.Key.STANCE_MAX)
			CombatFact.Kind.UNIT_MOVED:
				_follow_move(fact.actor_id, fact.tile)
			CombatFact.Kind.DAMAGE_TAKEN:
				if actor != null:
					actor.hp = maxi(0, actor.hp - fact.hp_amount)
					actor.block = maxi(0, actor.block - fact.block_amount)
			CombatFact.Kind.HEALED:
				if actor != null:
					actor.hp += fact.hp_amount
			CombatFact.Kind.BLOCK_GAINED:
				if actor != null:
					actor.block += fact.amount
			CombatFact.Kind.BLOCK_LOST:
				if actor != null:
					actor.block = maxi(0, actor.block - fact.amount)
			CombatFact.Kind.STANCE_CHANGED:
				if actor != null:
					actor.stance = maxi(0, actor.stance + fact.amount)
			CombatFact.Kind.DEFEATED:
				if has_unit(fact.actor_id):
					actor.is_defeated = true
					_occupancy.erase(actor.tile)
			CombatFact.Kind.BEFORE_COMBAT:
				if open_exchange == "%s>%s" % [fact.target_id, fact.actor_id]:
					open_exchange = ""
				elif actor != null:
					open_exchange = "%s>%s" % [fact.actor_id, fact.target_id]
					actor.has_acted = true
					if swapped_id == fact.actor_id:
						actor.has_used_sidearm = true
			CombatFact.Kind.WEAPON_SWAPPED:
				if actor != null:
					actor.stowed_weapon_id = actor.equipped_weapon_id
					actor.equipped_weapon_id = fact.item_id
					# A free Sidearm swap is told apart by the attack that follows it.
					actor.has_acted = true
					swapped_id = fact.actor_id
					load_bases(engine, fact.actor_id)
			CombatFact.Kind.ITEM_USED:
				if actor != null and _is_used_up(engine, fact.item_id):
					actor.pouch_item_id = ""
					load_bases(engine, fact.actor_id)
			CombatFact.Kind.SHOVED:
				if actor != null:
					actor.has_been_shoved = true
			CombatFact.Kind.RUNE_USED:
				if rune_slots.has(fact.amount):
					var slots: PackedStringArray = rune_slots[fact.amount]
					var index: int = slots.find(fact.item_id)
					if index >= 0:
						slots.remove_at(index)
						rune_slots[fact.amount] = slots
			CombatFact.Kind.GROWTH_CHANGED:
				add_growth(fact.actor_id, fact.key, fact.amount)
	if not waiting.is_empty():
		engine.follow(waiting)


func copy_for_sandbox() -> SandboxState:
	var copy: CombatState = CombatState.new(grid)
	copy.map = map.copy()
	copy.turn = turn
	copy.phase_side = phase_side
	copy.ended_seats = ended_seats.duplicate()
	copy.is_phase_ended = is_phase_ended
	copy.seats_to_start = seats_to_start.duplicate()
	for seat: int in rune_slots:
		copy.rune_slots[seat] = rune_slots[seat].duplicate()
	for id: String in _order:
		copy._units[id] = _units[id].copy()
	copy._order = _order.duplicate()
	copy._occupancy = _occupancy.duplicate()
	copy._weapons = _weapons.duplicate()
	return copy


func unit_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for id: String in _order:
		if not _units[id].is_defeated:
			ids.append(id)
	return ids


func has_unit(id: String) -> bool:
	return _units.has(id) and not _units[id].is_defeated


func side_of(id: String) -> CombatFact.CombatSide:
	return _units[id].side if _units.has(id) else CombatFact.CombatSide.NONE


func seat_of(id: String) -> int:
	return _units[id].seat if _units.has(id) else -1


func tile_of(id: String) -> Vector2i:
	return _units[id].tile if has_unit(id) else CombatFact.NO_TILE


func get_hp(id: String) -> int:
	return _units[id].hp if _units.has(id) else 0


func get_block(id: String) -> int:
	return _units[id].block if _units.has(id) else 0


func get_stance(id: String) -> int:
	return _units[id].stance if _units.has(id) else 0


func tiles_moved(id: String) -> int:
	return _units[id].tiles_moved if _units.has(id) else 0


func darkness_layer(_id: String) -> int:
	# TODO(TOD-001): Answer from the darkness plan (P06).
	return WhileLayerCondition.Layer.DRY


func equipped_weapon_id(unit_id: String) -> String:
	return _units[unit_id].equipped_weapon_id if _units.has(unit_id) else ""


func tags_of(id: String) -> PackedStringArray:
	return _units[id].tags if _units.has(id) else PackedStringArray()


func unit_type_of(id: String) -> String:
	return _units[id].unit_type if _units.has(id) else ""


func weapon_type_of(weapon_id: String) -> String:
	var held: WeaponStats = weapon(weapon_id)
	return "" if held == null else held.weapon_type


func set_hp(id: String, value: int) -> void:
	if _units.has(id):
		_units[id].hp = value


func set_block(id: String, value: int) -> void:
	if _units.has(id):
		_units[id].block = value


func set_stance(id: String, value: int) -> void:
	if _units.has(id):
		_units[id].stance = value


func add_growth(id: String, stat: int, points: int) -> void:
	if not _units.has(id):
		return
	var changes: Dictionary[int, int] = _units[id].growth_changes
	changes[stat] = changes.get(stat, 0) + points


## The combat core's one splash rule, through [SplashResolver]; the engine's splash is
## [constant CombatFact.Source.SPLASH].
func deal_splash(
		engine: EffectEngine,
		source_id: String,
		target_id: String,
		amount: int,
		source_effect_id: String
) -> void:
	SplashResolver.deal(
			engine, self, source_id, target_id, amount, CombatFact.Source.SPLASH, source_effect_id
	)


# A PHASE_START as PhaseRunner._phase_start changes the state: a player Phase Start raises the
# turn (the fact carries it), clears the ended seats and closes the opening swap window.
func _follow_phase_start(fact: CombatFact) -> void:
	if fact.side == CombatFact.CombatSide.PLAYER:
		turn = fact.amount
		ended_seats.clear()
		seats_to_start.clear()
		map.opening_swap_open = false
	phase_side = fact.side
	is_phase_ended = false
	for id: String in unit_ids():
		_units[id].has_been_shoved = false


# A UNIT_MOVED to tile. A swap (the opening swap, Recall) records both units' moves, so the first
# finds the other unit on its tile: they swap then, and the second move changes nothing.
func _follow_move(id: String, tile: Vector2i) -> void:
	if not has_unit(id) or tile == CombatFact.NO_TILE or _units[id].tile == tile:
		return
	var occupant: String = occupant_at(tile)
	if occupant.is_empty():
		move_unit(id, tile)
	elif has_unit(occupant):
		swap_units(id, occupant)


# The seats with player units on the map, ascending: the seats that have ended at a player Phase
# End, since it runs only once every one of them has.
func _seats_on_map() -> PackedInt32Array:
	var found: PackedInt32Array = []
	for id: String in units_of(CombatFact.CombatSide.PLAYER):
		if not found.has(_units[id].seat):
			found.append(_units[id].seat)
	found.sort()
	return found


# Whether item_id's use effects are used up, which takes it out of its holder's Pouch.
# NOTE: The same test as ItemUseResolver._used_up; keep them in step.
static func _is_used_up(engine: EffectEngine, item_id: String) -> bool:
	var totals: bool = false
	for instance: EffectInstance in ItemUseResolver.use_effects(engine, item_id):
		if instance.definition.charges <= 0:
			return false
		if instance.definition.charge_lane != EffectTerms.Lane.CAMPAIGN:
			return false
		totals = true
		if instance.has_charge():
			return false
	return totals


# The seats in value, a JSON array of whole numbers; a list holding _NO_SEAT when it isn't one.
static func _seat_list(value: Variant) -> PackedInt32Array:
	if not value is Array:
		return PackedInt32Array([_NO_SEAT])
	var seats: PackedInt32Array = []
	# Untyped: the parts come from JSON and are checked entry by entry.
	for entry: Variant in value:
		var seat: Variant = _whole(entry)
		if seat == null or (seat as int) < 0:
			return PackedInt32Array([_NO_SEAT])
		seats.append(seat as int)
	return seats


# value as an int when it is one, or a whole float within JSON's exact range; null otherwise.
# NOTE: The same rule as CombatSession._wire_int and CombatUnitState._whole; keep them in step.
static func _whole(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var number: float = value
	if number != floorf(number) or absf(number) > CombatFact.MAX_EXACT_JSON_INT:
		return null
	return int(number)


## One weapon's numbers in combat (game-vision.md, Weapons and equipment; weapons.md): its
## [WeaponDefinition]'s, copied by [method Loadout.weapon_record]. Read-only once added to a
## [CombatState].
class WeaponStats:
	extends RefCounted

	## What a staff does when used. [b]Append only[/b], with explicit values.
	enum Staff {
		## Not a staff.
		NONE = 0,
		## Gives an ally Block (Shelter).
		BLOCK = 1,
		## Heals a damaged ally (Minor Heal).
		HEAL = 2,
		## Attacks like a weapon and never counters (Harm, Ruin).
		ATTACK = 3,
	}

	## Instance id of the weapon, such as [code]item:412[/code].
	var id: String = ""
	## Display name for breakdowns, such as "Iron Sword".
	var label: String = ""
	## Weapon type, from [constant ContentIds.WEAPON_TYPES], such as [code]bow[/code]: which units
	## can use it, and what conditions test.
	var weapon_type: String = ""
	## Weapon damage: the Attack stage's base, the triangle's and effectiveness's measure.
	var damage: int = 0
	## Attacks per turn before the defender's Parry.
	var atk_x: int = 1
	## Triangle profile.
	var profile: WeaponTriangle.Profile = WeaponTriangle.Profile.NONE
	## Shortest range, in tiles.
	var range_min: int = 1
	## Longest range, in tiles.
	var range_max: int = 1
	## Hit before the triangle, effects and the defender's avoid.
	var hit: int = 0
	## Crit chance added to the base 25, against an Exposed defender only.
	var crit: int = 0
	## The crit multiplier.
	var crit_x: float = 3.0
	## Weight against Constitution, for Attack Speed.
	var weight: int = 0
	## Which mitigation stat it meets.
	var damage_type: CombatFact.DamageType = CombatFact.DamageType.PHYSICAL
	## Unit tags it is effective against, from [constant ContentIds.TAGS], such as
	## [code]flier[/code].
	var effective_against: PackedStringArray = []
	## What it does as a staff.
	var staff: Staff = Staff.NONE
	## A Block or heal staff's amount before Might.
	var staff_amount: int = 0
	# ASSUMPTION: an area staff carries its shape as an Area selector until P03's staff data does.
	## An area staff's shape around its target or user (Sanctuary, Everwall); null: the target only.
	var area: Area = null

	## Whether it is a staff of any kind; its holder never counters.
	func is_staff() -> bool:
		return staff != Staff.NONE

	## Its numbers as plain JSON values, enums by name. [member area] is left out
	## ([code]combat_state.gd:TOD-002[/code]); no loaded record has one yet.
	## [method from_capture] reverses it.
	func capture() -> Dictionary:
		return {
			"id": id,
			"label": label,
			"weapon_type": weapon_type,
			"damage": damage,
			"atk_x": atk_x,
			"profile": WeaponTriangle.Profile.find_key(profile) as String,
			"range_min": range_min,
			"range_max": range_max,
			"hit": hit,
			"crit": crit,
			"crit_x": crit_x,
			"weight": weight,
			"damage_type": CombatFact.DamageType.find_key(damage_type) as String,
			"effective_against": Array(effective_against),
			"staff": Staff.find_key(staff) as String,
			"staff_amount": staff_amount,
		}

	## A record from [method capture] output, also after a trip through JSON. Returns
	## [code]null[/code] when a field is missing, not a whole number where one belongs, or names
	## an unknown enum value.
	static func from_capture(data: Dictionary) -> WeaponStats:
		var profile_name: String = str(data.get("profile", ""))
		var type_name: String = str(data.get("damage_type", ""))
		var staff_name: String = str(data.get("staff", ""))
		var effective: Variant = data.get("effective_against", null)
		var crit_multiplier: Variant = data.get("crit_x", null)
		if (
				not data.get("id", null) is String
				or not data.get("label", null) is String
				or not data.get("weapon_type", null) is String
				or not WeaponTriangle.Profile.has(profile_name)
				or not CombatFact.DamageType.has(type_name)
				or not Staff.has(staff_name)
				or not effective is Array
				or not (crit_multiplier is float or crit_multiplier is int)
		):
			return null
		var numbers: Dictionary[String, int] = {}
		for field: String in [
			"damage", "atk_x", "range_min", "range_max", "hit", "crit", "weight", "staff_amount",
		]:
			var number: Variant = _whole_number(data.get(field, null))
			if number == null:
				return null
			numbers[field] = number
		var record: WeaponStats = WeaponStats.new()
		record.id = data["id"]
		record.label = data["label"]
		record.weapon_type = data["weapon_type"]
		# Untyped: the parts come from JSON and are checked entry by entry.
		for tag: Variant in effective:
			if not tag is String:
				return null
			record.effective_against.append(tag as String)
		var profile_value: int = WeaponTriangle.Profile[profile_name]
		record.profile = profile_value as WeaponTriangle.Profile
		var type_value: int = CombatFact.DamageType[type_name]
		record.damage_type = type_value as CombatFact.DamageType
		var staff_value: int = Staff[staff_name]
		record.staff = staff_value as Staff
		var multiplier: float = crit_multiplier
		record.crit_x = multiplier
		record.damage = numbers["damage"]
		record.atk_x = numbers["atk_x"]
		record.range_min = numbers["range_min"]
		record.range_max = numbers["range_max"]
		record.hit = numbers["hit"]
		record.crit = numbers["crit"]
		record.weight = numbers["weight"]
		record.staff_amount = numbers["staff_amount"]
		return record

	# value as an int, or null: the outer class's _whole() rule, which an inner class can't call
	# unqualified.
	# NOTE: Keep in step with CombatState._whole().
	static func _whole_number(value: Variant) -> Variant:
		if value is int:
			return value
		if not value is float:
			return null
		var number: float = value
		if number != floorf(number) or absf(number) > CombatFact.MAX_EXACT_JSON_INT:
			return null
		return int(number)
