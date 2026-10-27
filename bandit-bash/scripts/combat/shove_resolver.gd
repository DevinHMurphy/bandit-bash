# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     shove_resolver.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name ShoveResolver
extends RefCounted
## Shove: a unit pushes an orthogonally adjacent unit directly away from itself (game-vision.md,
## Shove; combat core plan, Shove).
##
## Legal on an ally (always willing) or an Exposed foe that hasn't been shoved this phase, isn't
## denied [constant CombatValue.Permission.CAN_BE_SHOVED], and would actually be affected: moved at
## least one tile, bumped into a unit or pushed into a spiked wall (question 8). The target moves
## tile by tile up to the shover's [constant CombatValue.Key.SHOVE_DISTANCE]. Off the map, a wall,
## an object or a tile its movement type can't stand on stops it with no damage; a unit stops it
## and both take [constant BUMP_DAMAGE]; a spiked wall stops it and it takes
## [constant SPIKE_DAMAGE], all as splash ([SplashResolver]). Landing on oil keeps it sliding the
## same way, past the Shove distance, until it lands off the oil or is stopped. It isn't an attack:
## no hit roll, no counter, no Stance loss, and the darkness never damages on the spot.[br]
## Pure and static; the caller starts the resolution step.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## Why a shove stopped. [b]Append only[/b], with explicit values.
enum Stop {
	## It moved its full Shove distance and isn't on oil.
	DISTANCE = 0,
	## The next tile is off the map.
	EDGE = 1,
	## A wall, a door, an object or a tile its movement type can't stand on.
	BLOCKED = 2,
	## Another unit: a bump.
	BUMP = 3,
	## A spiked wall.
	SPIKE = 4,
}

## Damage a bump deals to the shoved unit and to the unit it runs into (game-vision.md, "first
## pass").
const BUMP_DAMAGE: int = 2

## Damage a spiked wall deals to the shoved unit (game-vision.md, "first pass").
const SPIKE_DAMAGE: int = 4


## Shoves [param target_id] away from [param shover_id]: Shoved a unit, Shoved, Unit moved (when it
## moved) on its final tile, then any bump or spike damage, then the drain. Marks the target as
## shoved this phase and the shover as having acted. An illegal shove records nothing.
static func resolve(
		engine: EffectEngine, state: CombatState, shover_id: String, target_id: String
) -> Result:
	var result: Result = Result.new()
	result.reason = check(engine, state, shover_id, target_id)
	if not result.reason.is_empty():
		return result
	result.is_legal = true
	var path: Path = trace(engine, state, shover_id, target_id)
	result.path = path
	state.unit(shover_id).has_acted = true
	state.unit(target_id).has_been_shoved = true

	engine.record(CombatFact.new(CombatFact.Kind.SHOVED_A_UNIT, shover_id, target_id))
	engine.record(CombatFact.new(CombatFact.Kind.SHOVED, target_id, shover_id))
	if path.tiles_moved > 0:
		state.move_unit(target_id, path.final_tile)
		var moved: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, target_id)
		moved.tile = path.final_tile
		engine.record(moved)
	# Bump and spike damage is credited to the shover, who caused it, so a lethal bump
	# counts as its defeat of an enemy.
	match path.stop:
		Stop.BUMP:
			SplashResolver.deal(
					engine, state, shover_id, target_id, BUMP_DAMAGE, CombatFact.Source.BUMP
			)
			SplashResolver.deal(
					engine, state, shover_id, path.bumped_id, BUMP_DAMAGE, CombatFact.Source.BUMP
			)
		Stop.SPIKE:
			SplashResolver.deal(
					engine, state, shover_id, target_id, SPIKE_DAMAGE, CombatFact.Source.SPIKE
			)
	engine.drain()
	return result


## Why [param shover_id] can't shove [param target_id] now; empty when it can.
static func check(
		engine: EffectEngine, state: CombatState, shover_id: String, target_id: String
) -> String:
	if not state.has_unit(shover_id) or not state.has_unit(target_id) or shover_id == target_id:
		return "not on the map"
	if state.grid.distance(state.tile_of(shover_id), state.tile_of(target_id)) != 1:
		return "not adjacent"
	var shover_side: CombatFact.CombatSide = state.side_of(shover_id)
	var is_ally: bool = engine.matches_side(shover_side, target_id, EffectDefinition.UnitSide.ALLY)
	var is_foe: bool = engine.matches_side(shover_side, target_id, EffectDefinition.UnitSide.ENEMY)
	if not is_ally and not is_foe:
		return "not a unit"
	if is_foe and state.get_stance(target_id) > 0:
		return "a foe must be Exposed"
	if state.unit(target_id).has_been_shoved:
		return "already shoved this phase"
	if not engine.stats(target_id).is_allowed(CombatValue.Permission.CAN_BE_SHOVED):
		return "can't be shoved"
	var path: Path = trace(engine, state, shover_id, target_id)
	if path.tiles_moved == 0 and path.stop != Stop.BUMP and path.stop != Stop.SPIKE:
		return "nothing would happen"
	return ""


## Where a shove of [param target_id] by [param shover_id] would take it, without changing
## anything: tile by tile away from the shover, up to the Shove distance, sliding on past it while
## it lands on oil.
static func trace(
		engine: EffectEngine, state: CombatState, shover_id: String, target_id: String
) -> Path:
	var path: Path = Path.new()
	var tile: Vector2i = state.tile_of(target_id)
	var direction: Vector2i = tile - state.tile_of(shover_id)
	var reach: int = engine.stats(shover_id).get_int(CombatValue.Key.SHOVE_DISTANCE)
	var movement: CombatGrid.MovementType = state.unit(target_id).movement_type
	path.final_tile = tile
	path.stop = Stop.DISTANCE
	var sliding: bool = false
	while path.tiles_moved < reach or sliding:
		var next: Vector2i = state.grid.step(tile, direction)
		if next == CombatFact.NO_TILE:
			path.stop = Stop.EDGE
			break
		var blocker: CombatGrid.Blocker = state.blocker_at(next)
		if blocker == CombatGrid.Blocker.UNIT:
			path.stop = Stop.BUMP
			path.bumped_id = state.occupant_at(next)
			break
		if blocker == CombatGrid.Blocker.SPIKED_WALL:
			path.stop = Stop.SPIKE
			break
		if blocker != CombatGrid.Blocker.NONE or not state.grid.can_stand(next, movement):
			path.stop = Stop.BLOCKED
			break
		tile = next
		path.tiles_moved += 1
		path.final_tile = tile
		sliding = state.grid.is_slick(tile)
		path.slid = path.slid or (sliding and path.tiles_moved >= reach)
	return path


## Where a shove takes its target and why it stops.
class Path:
	extends RefCounted

	## The tile it ends on.
	var final_tile: Vector2i = CombatFact.NO_TILE
	## Tiles it moved, oil slides included.
	var tiles_moved: int = 0
	## Why it stopped.
	var stop: Stop = Stop.DISTANCE
	## The unit it ran into, for [constant Stop.BUMP]; empty otherwise.
	var bumped_id: String = ""
	## Whether oil carried it past its Shove distance.
	var slid: bool = false


## What a shove did, for its caller.
class Result:
	extends RefCounted

	## Whether the shove was legal and resolved.
	var is_legal: bool = false
	## Why it wasn't; empty when it was.
	var reason: String = ""
	## Where it took the target; null when illegal.
	var path: Path = null
