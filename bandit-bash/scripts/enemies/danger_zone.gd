# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     danger_zone.gd
# Author:
# Created:  November 3, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name DangerZone
extends RefCounted
## Every tile each enemy could attack next phase, per enemy and combined, as Fire Emblem shows it
## (game-vision.md, Enemy intentions; enemies and AI plan, Intents and the danger zone).
##
## An enemy's tiles are its reach next phase, with its full movement from where it stands now
## (units block as they stand), plus the range of each weapon it could attack with there: the one
## in hand, and the stowed one while a free Sidearm swap is allowed, plus the blast of every powder
## keg those tiles reach, chained through the kegs it breaks (map-objects.md: a keg an enemy can
## use shows in the danger zone). Heal and Block staves attack nothing, so a Hedge Healer has no
## tiles. Only tiles on the map count. Built by [Intents]; P07
## draws it. Plain data, pure to build: it reads the board and changes nothing.[br]
## A move preview rebuilds it from the latest zone ([method compute] with a base), recomputing
## only the enemies indexed at a changed tile (move-preview.md, layer 4).
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

## Every tile some enemy could attack, with the enemies that could, in state order.
var combined: Dictionary[Vector2i, PackedStringArray] = {}

## Every enemy on the map when it was built, in state order, those with no tiles included.
var enemy_ids: PackedStringArray = []

# Each enemy's tiles, in row-major order (an Array[Vector2i] per enemy id); shared with the zones
# built on this one, so never changed once built.
var _by_enemy: Dictionary[String, Array] = {}

# Each enemy's tile and MOVEMENT when built, as (x, y, movement): its tiles depend only on who
# stands within its movement (Godot_FE's absolute range) and on its own stats.
var _reaches: Dictionary[String, Vector3i] = {}

# From each tile to the enemies whose movement, or _index_margin, covers it; built on first use
# with that margin, on the main thread only.
var _index: Dictionary[Vector2i, PackedStringArray] = {}
var _index_margin: int = -1


## The tiles [param enemy_id] could attack, in row-major order; empty for an enemy with none or
## one not in the zone.
func tiles_of(enemy_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if _by_enemy.has(enemy_id):
		tiles.assign(_by_enemy[enemy_id])
	return tiles


## Whether any enemy could attack [param tile] next phase.
func is_threatened(tile: Vector2i) -> bool:
	return combined.has(tile)


## The danger zone of every enemy on [param engine]'s map as it stands now. With [param base], the
## zone of a board [param engine]'s differs from only on [param touched] (a unit entering,
## leaving or changing there): an enemy keeps its tiles from [param base] unless its movement, or
## [param margin] (the effect margin, how far an effect reads positions), reaches a touched tile;
## a negative margin, or a different set of enemies, recomputes every one. The result equals a
## full rebuild. Call it with a base on the main thread only.
static func compute(
		engine: EffectEngine,
		base: DangerZone = null,
		touched: Array[Vector2i] = [],
		margin: int = 0
) -> DangerZone:
	var zone: DangerZone = DangerZone.new()
	var state: CombatState = engine.state
	var enemies: PackedStringArray = state.units_of(CombatFact.CombatSide.ENEMY)
	var redone: Dictionary[String, bool] = {}
	var keeps: bool = base != null and margin >= 0 and base.enemy_ids == enemies
	if keeps:
		for tile: Vector2i in touched:
			for enemy_id: String in base._enemies_at(tile, margin):
				redone[enemy_id] = true
	for enemy_id: String in enemies:
		zone.enemy_ids.append(enemy_id)
		var tiles: Array[Vector2i] = []
		if keeps and not redone.has(enemy_id):
			tiles = base._by_enemy[enemy_id]
			zone._reaches[enemy_id] = base._reaches[enemy_id]
		else:
			tiles = tiles_for(engine, enemy_id)
			var at: Vector2i = state.tile_of(enemy_id)
			zone._reaches[enemy_id] = Vector3i(
					at.x, at.y, engine.stats(enemy_id).get_int(CombatValue.Key.MOVEMENT)
			)
		zone._by_enemy[enemy_id] = tiles
		for tile: Vector2i in tiles:
			if not zone.combined.has(tile):
				zone.combined[tile] = PackedStringArray()
			zone.combined[tile].append(enemy_id)
	return zone


## The tiles [param unit_id] could attack next phase on [param engine]'s map, in row-major order:
## every free tile it could end on with its full movement, plus each attacking weapon's range,
## plus the blasts of the powder kegs in that range ([method MapObjects.explode]'s tiles).
static func tiles_for(engine: EffectEngine, unit_id: String) -> Array[Vector2i]:
	var state: CombatState = engine.state
	var found: Array[Vector2i] = []
	var spans: Array[Vector2i] = attack_ranges(engine, unit_id)
	if spans.is_empty():
		return found
	var mover: CombatUnitState = state.unit(unit_id)
	# NOTE: next phase's full movement, not what is left of this one's; the Phase Start refresh
	# clears movement spent, as PhaseRunner's refresh does.
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			engine.stats(unit_id).get_int(CombatValue.Key.MOVEMENT),
			mover.movement_type,
			mover.side
	)
	var covered: Dictionary[Vector2i, bool] = {}
	for end: Vector2i in walked:
		var occupant: String = state.occupant_at(end)
		if not occupant.is_empty() and occupant != unit_id:
			continue
		for span: Vector2i in spans:
			for tile: Vector2i in tiles_within(end, span):
				if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
					covered[tile] = true
	_add_keg_blasts(state, covered)
	found.assign(covered.keys())
	found.sort_custom(EnemyPlan.tile_precedes)
	return found


## Each range [param unit_id] could attack at, as (shortest, longest), each read by
## [method ExchangeResolver.weapon_range]: the weapon in hand's, and the stowed weapon's while a
## free Sidearm swap is allowed. Empty when it holds nothing that attacks.
static func attack_ranges(engine: EffectEngine, unit_id: String) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	var state: CombatState = engine.state
	var holder: CombatUnitState = state.unit(unit_id)
	var held: CombatState.WeaponStats = state.weapon(holder.equipped_weapon_id)
	if held != null and _attacks_with(held):
		spans.append(ExchangeResolver.weapon_range(engine, unit_id, held.id))
	var stowed: CombatState.WeaponStats = state.weapon(holder.stowed_weapon_id)
	# Only the permission: WeaponSwap.check also refuses a unit that acted this phase, and the
	# Phase Start refresh clears that and the Sidearm already used.
	var is_free: bool = engine.stats(unit_id).is_allowed(CombatValue.Permission.FREE_WEAPON_SWAP)
	if stowed != null and _attacks_with(stowed) and is_free:
		spans.append(ExchangeResolver.weapon_range(engine, unit_id, stowed.id))
	return spans


## Every tile whose tile distance from [param center] is within [param span] (shortest, longest),
## on the map or not.
static func tiles_within(center: Vector2i, span: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for dy: int in range(-span.y, span.y + 1):
		var across: int = span.y - absi(dy)
		for dx: int in range(-across, across + 1):
			if absi(dx) + absi(dy) >= span.x:
				found.append(center + Vector2i(dx, dy))
	return found


# The enemies whose tiles a change on tile can change: those within their movement of it, whose
# walk it can block or free, or within margin, where an effect can change their stats. The index
# is built with the first margin asked, then again for a larger one.
func _enemies_at(tile: Vector2i, margin: int) -> PackedStringArray:
	if margin > _index_margin:
		_index.clear()
		_index_margin = margin
		for enemy_id: String in enemy_ids:
			var reach: Vector3i = _reaches[enemy_id]
			var center: Vector2i = Vector2i(reach.x, reach.y)
			for near: Vector2i in tiles_within(center, Vector2i(0, maxi(reach.z, margin))):
				if not _index.has(near):
					_index[near] = PackedStringArray()
				_index[near].append(enemy_id)
	return _index.get(tile, PackedStringArray())


# Adds to covered the blast of every unbroken powder keg on a covered tile, then of every keg
# such a blast reaches, until no new keg is caught (kegs chain with no limit).
static func _add_keg_blasts(state: CombatState, covered: Dictionary[Vector2i, bool]) -> void:
	var waiting: Array[MapState.ObjectState] = []
	for keg: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.POWDER_KEG):
		if not keg.is_destroyed:
			waiting.append(keg)
	var is_growing: bool = true
	while is_growing:
		is_growing = false
		for keg: MapState.ObjectState in waiting.duplicate():
			if not covered.has(keg.tile):
				continue
			waiting.erase(keg)
			is_growing = true
			for tile: Vector2i in MapObjects.KEG_BLAST.tiles(keg.tile):
				if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
					covered[tile] = true


# Whether held attacks: any weapon but a Block or heal staff, as EnemyAI reads it.
static func _attacks_with(held: CombatState.WeaponStats) -> bool:
	return not held.is_staff() or held.staff == CombatState.WeaponStats.Staff.ATTACK
