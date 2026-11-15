# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     danger_zone.gd
# Author:
# Created:  November 3, 2026
# Modified: November 15, 2026
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
## draws it. Plain data, pure to build: it reads the board and changes nothing.
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

## Every tile some enemy could attack, with the enemies that could, in state order.
var combined: Dictionary[Vector2i, PackedStringArray] = {}

## Every enemy on the map when it was built, in state order, those with no tiles included.
var enemy_ids: PackedStringArray = []

# Each enemy's tiles, in row-major order (an Array[Vector2i] per enemy id).
var _by_enemy: Dictionary[String, Array] = {}


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


## The danger zone of every enemy on [param engine]'s map as it stands now.
static func compute(engine: EffectEngine) -> DangerZone:
	var zone: DangerZone = DangerZone.new()
	var state: CombatState = engine.state
	for enemy_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
		zone.enemy_ids.append(enemy_id)
		var tiles: Array[Vector2i] = tiles_for(engine, enemy_id)
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
