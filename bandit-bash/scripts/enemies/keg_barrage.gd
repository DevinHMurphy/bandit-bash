# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     keg_barrage.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

@tool
class_name KegBarrage
extends CustomOperation
## The Powder Baron's signature move, Keg Barrage: at its enemy Phase Start, every 2nd one, it
## throws a lit powder keg onto the tile within [constant REACH] that catches the most player units
## (enemy-roster.md, The boss).
##
## The operation itself does nothing: its effect's [constant CombatFact.Kind.EFFECT_ACTIVATED] is
## the signal, read by [method throw_hook] on [constant CombatHooks.Hook.PHASE_START_EFFECTS],
## since a throw needs the session's run seed, which the effect engine doesn't hold. The cadence is
## the effect's counter condition, as for every signature move, and [Intents] shows the throw the
## phase before. A sandbox crossing throws too, so the shown tile is the one thrown.
##
## @tutorial(Enemy roster): docs/design/enemy-roster.md
## @tutorial(Powder Baron plan): docs/plans/2026-11-18-powder-baron.md

## How far the Baron throws, by grid distance from its tile, walls ignored (enemy-roster.md: within
## 5 tiles). First pass, to tune (rebalance-and-features.md).[br]
## [b]Units:[/b] tiles.
const REACH: int = 5


## Does nothing: [method throw_hook] throws once this effect has fired.
func apply(_ctx: EffectContext) -> void:
	pass


## Registers the throw on [param session]'s [constant CombatHooks.Hook.PHASE_START_EFFECTS]. Once
## per session, with the AI ([method EnemyAI.register]).
static func register(session: CombatSession) -> void:
	session.hooks.add(CombatHooks.Hook.PHASE_START_EFFECTS, KegBarrage.throw_hook)


## [constant CombatHooks.Hook.PHASE_START_EFFECTS]: at the enemy Phase Start, each enemy whose Keg
## Barrage fired this Phase Start throws a keg onto its [method pick_tile]
## ([method MapObjects.throw_keg]), in the order they fired. With no legal tile it throws nothing
## and adds a diagnostic. Does nothing for [param side] other than the enemy's.
static func throw_hook(session: CombatSession, side: CombatFact.CombatSide) -> void:
	if side != CombatFact.CombatSide.ENEMY:
		return
	var engine: EffectEngine = session.engine
	var state: CombatState = session.state
	for thrower: String in _throwers(engine):
		if not state.has_unit(thrower):
			continue
		var tile: Vector2i = pick_tile(state, thrower, session.run_seed)
		if tile == CombatFact.NO_TILE:
			engine.diagnostics.append(
					"KegBarrage: no tile within %d for %s's keg" % [REACH, thrower]
			)
			continue
		MapObjects.throw_keg(session, tile, thrower)


## The tile [param thrower_id] throws its keg onto: of every tile within [constant REACH] where a
## keg may land ([method MapObjects.can_land]), the one whose blast
## ([constant MapObjects.KEG_BLAST]) covers the most player units, its own side's ignored
## (ruthless AI). Ties, all of them when none
## catches anyone, are broken by a stream fresh from [constant RngKey.RngPurpose.KEG_BARRAGE] for
## [param run_seed] and the turn, over the tied tiles in row-major order, so the same board picks
## the same tile. [constant CombatFact.NO_TILE] when no tile is legal.
static func pick_tile(state: CombatState, thrower_id: String, run_seed: int) -> Vector2i:
	var origin: Vector2i = state.tile_of(thrower_id)
	if origin == CombatFact.NO_TILE:
		return CombatFact.NO_TILE
	var targets: Array[Vector2i] = []
	for unit_id: String in state.units_of(CombatFact.CombatSide.PLAYER):
		targets.append(state.tile_of(unit_id))
	var best: int = -1
	var tied: Array[Vector2i] = []
	for dy: int in range(-REACH, REACH + 1):
		for dx: int in range(-REACH, REACH + 1):
			var tile: Vector2i = origin + Vector2i(dx, dy)
			if state.grid.distance(origin, tile) > REACH or not MapObjects.can_land(state, tile):
				continue
			var caught: int = 0
			for target: Vector2i in targets:
				if MapObjects.KEG_BLAST.covers(tile, target):
					caught += 1
			if caught > best:
				best = caught
				tied.clear()
			if caught == best:
				tied.append(tile)
	if tied.is_empty():
		return CombatFact.NO_TILE
	if tied.size() == 1:
		return tied[0]
	tied.sort_custom(EnemyPlan.tile_precedes)
	var stream: RngStream = RngStream.new(RngKey.derive_seed(
			run_seed, RngKey.RngPurpose.KEG_BARRAGE, -1, -1, -1, state.turn
	))
	return tied[stream.pick_index(tied.size())]


## Whether [param definition] is a Keg Barrage: one of its operations is this script's.
static func is_barrage(definition: EffectDefinition) -> bool:
	if definition == null:
		return false
	for operation: EffectOperation in definition.operations:
		if operation is KegBarrage:
			return true
	return false


# The units whose Keg Barrage fired since the last Phase Start in engine's fact log, in firing
# order.
static func _throwers(engine: EffectEngine) -> PackedStringArray:
	var found: PackedStringArray = []
	for index: int in range(engine.fact_log.size() - 1, -1, -1):
		var fact: CombatFact = engine.fact_log[index]
		if fact.kind == CombatFact.Kind.PHASE_START:
			break
		if fact.kind != CombatFact.Kind.EFFECT_ACTIVATED:
			continue
		var instance: EffectInstance = engine.get_instance(fact.source_effect_id)
		if instance == null or not is_barrage(instance.definition):
			continue
		var thrower: String = instance.owner.subject_id()
		if not found.has(thrower):
			found.insert(0, thrower)
	return found
