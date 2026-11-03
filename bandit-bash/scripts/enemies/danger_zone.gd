# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     danger_zone.gd
# Author:
# Created:  November 3, 2026
# Modified: November 3, 2026
# ==============================================================================

class_name DangerZone
extends RefCounted
## Every tile each enemy could attack next phase, per enemy and combined, as Fire Emblem shows it
## (game-vision.md, Enemy intentions; enemies and AI plan, Intents and the danger zone).
##
## An enemy's tiles are its reach next phase, with its full movement from where it stands now
## (units block as they stand), plus the range of each weapon it could attack with there: the one
## in hand, and the stowed one while a free Sidearm swap is allowed. Heal and Block staves attack
## nothing, so a Hedge Healer has no tiles. Only tiles on the map count. Built by [Intents]; P07
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
## every free tile it could end on with its full movement, plus each attacking weapon's range.
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
	found.assign(covered.keys())
	found.sort_custom(EnemyPlan.tile_precedes)
	return found


## Each range [param unit_id] could attack at, as (shortest, longest): the weapon in hand's from
## its values, and the stowed weapon's own while a free Sidearm swap is allowed. Empty when it
## holds nothing that attacks.
static func attack_ranges(engine: EffectEngine, unit_id: String) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	var state: CombatState = engine.state
	var holder: CombatUnitState = state.unit(unit_id)
	var held: CombatState.WeaponStats = state.weapon(holder.equipped_weapon_id)
	if held != null and _attacks_with(held):
		var sheet: StatSheet = engine.stats(unit_id)
		spans.append(Vector2i(
				sheet.get_int(CombatValue.Key.RANGE_MIN), sheet.get_int(CombatValue.Key.RANGE_MAX)
		))
	var stowed: CombatState.WeaponStats = state.weapon(holder.stowed_weapon_id)
	# Only the permission: WeaponSwap.check also refuses a unit that acted this phase, and the
	# Phase Start refresh clears that and the Sidearm already used.
	var is_free: bool = engine.stats(unit_id).is_allowed(CombatValue.Permission.FREE_WEAPON_SWAP)
	if stowed != null and _attacks_with(stowed) and is_free:
		spans.append(Vector2i(stowed.range_min, stowed.range_max))
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


# Whether held attacks: any weapon but a Block or heal staff, as EnemyAI reads it.
static func _attacks_with(held: CombatState.WeaponStats) -> bool:
	return not held.is_staff() or held.staff == CombatState.WeaponStats.Staff.ATTACK
