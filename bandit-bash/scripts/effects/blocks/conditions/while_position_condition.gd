# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_position_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name WhilePositionCondition
extends EffectCondition
## Passes while this unit's position or movement fits: at maximum range, moved N+ tiles, hasn't
## moved, no ally closer to an enemy, adjacent to or within N tiles of a unit.
##
## Terms follow effect-triggers.md, Position and movement: adjacent means the four orthogonal
## neighbors; "within N" is walking distance. Checked live. Never matches across parallel maps.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## The position test. Saved as an int: [b]append only[/b].
enum Kind {
	## The opponent is at the far end of this unit's weapon range.
	AT_MAXIMUM_RANGE = 0,
	## This unit moved at least [member tiles] tiles during its current turn.
	MOVED_AT_LEAST = 1,
	## This unit has moved 0 tiles this turn.
	HAS_NOT_MOVED = 2,
	## No ally of this unit is closer to its nearest enemy than this unit is; a tie still counts.
	NO_ALLY_CLOSER_TO_ENEMY = 3,
	## A unit of [member side] is on an orthogonally neighboring tile.
	ADJACENT_TO = 4,
	## A unit of [member side] is within [member tiles] tiles' walking distance.
	WITHIN = 5,
}

## The position test.
@export var kind: Kind = Kind.AT_MAXIMUM_RANGE

## Tiles for [constant MOVED_AT_LEAST] and [constant WITHIN]; ignored by the other kinds.
##
## [b]Units:[/b] tiles. [b]1 with WITHIN:[/b] the same as adjacent.
@export_range(0, 99) var tiles: int = 1

## Which units count for [constant ADJACENT_TO] and [constant WITHIN]; ignored by the others.
@export var side: EffectDefinition.UnitSide = EffectDefinition.UnitSide.ALLY


func describe() -> String:
	match kind:
		Kind.AT_MAXIMUM_RANGE:
			return "while at maximum range"
		Kind.MOVED_AT_LEAST:
			return "while this unit moved %d+ tiles this turn" % [tiles]
		Kind.HAS_NOT_MOVED:
			return "while it hasn't moved this turn"
		Kind.NO_ALLY_CLOSER_TO_ENEMY:
			return "while no ally is closer to an enemy than this unit"
		Kind.ADJACENT_TO:
			return "while adjacent to %s" % [_side_noun()]
		Kind.WITHIN:
			var unit_word: String = "tile" if tiles == 1 else "tiles"
			return "while within %d %s of %s" % [tiles, unit_word, _side_noun()]
	return "while in position"


func test(ctx: EffectContext) -> bool:
	var engine: EffectEngine = ctx.engine
	var unit_id: String = ctx.subject_id
	if not engine.state.has_unit(unit_id):
		return false
	match kind:
		Kind.AT_MAXIMUM_RANGE:
			if ctx.opponent_of(unit_id).is_empty():
				return false
			return ctx.distance == engine.stats(unit_id).get_int(CombatValue.Key.RANGE_MAX, ctx)
		Kind.MOVED_AT_LEAST:
			return engine.state.tiles_moved(unit_id) >= tiles
		Kind.HAS_NOT_MOVED:
			return engine.state.tiles_moved(unit_id) == 0
		Kind.NO_ALLY_CLOSER_TO_ENEMY:
			return _no_ally_closer(engine, unit_id)
		Kind.ADJACENT_TO:
			return _any_near(engine, unit_id, 1, false)
		Kind.WITHIN:
			return _any_near(engine, unit_id, tiles, true)
	return false


func _side_noun() -> String:
	match side:
		EffectDefinition.UnitSide.ALLY:
			return "an ally"
		EffectDefinition.UnitSide.ENEMY:
			return "an enemy"
	return "a unit"


# Whether a unit of `side` (relative to unit_id) is within `reach` tiles: orthogonally adjacent
# for 1 without walking, walking distance otherwise.
func _any_near(engine: EffectEngine, unit_id: String, reach: int, walking: bool) -> bool:
	var own_side: CombatFact.CombatSide = engine.state.side_of(unit_id)
	for other: String in engine.state.unit_ids():
		if other == unit_id or not engine.matches_side(own_side, other, side):
			continue
		var distance: int = (
				engine.state.walking_distance(unit_id, other) if walking
				else engine.tile_distance(unit_id, other)
		)
		if distance >= 1 and distance <= reach:
			return true
	return false


func _no_ally_closer(engine: EffectEngine, unit_id: String) -> bool:
	var own: int = _nearest_enemy(engine, unit_id)
	# ASSUMPTION: with no enemy on the map, no ally is closer, so the condition passes.
	if own < 0:
		return true
	var own_side: CombatFact.CombatSide = engine.state.side_of(unit_id)
	for ally: String in engine.state.unit_ids():
		if ally == unit_id:
			continue
		if not engine.matches_side(own_side, ally, EffectDefinition.UnitSide.ALLY):
			continue
		var theirs: int = _nearest_enemy(engine, ally)
		if theirs >= 0 and theirs < own:
			return false
	return true


# Tile distance from unit_id to its nearest enemy, or -1 when it has none.
static func _nearest_enemy(engine: EffectEngine, unit_id: String) -> int:
	var own_side: CombatFact.CombatSide = engine.state.side_of(unit_id)
	var nearest: int = -1
	for other: String in engine.state.unit_ids():
		if not engine.matches_side(own_side, other, EffectDefinition.UnitSide.ENEMY):
			continue
		var distance: int = engine.tile_distance(unit_id, other)
		if nearest < 0 or distance < nearest:
			nearest = distance
	return nearest
