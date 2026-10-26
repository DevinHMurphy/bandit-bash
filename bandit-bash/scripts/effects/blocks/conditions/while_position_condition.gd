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


func _side_noun() -> String:
	match side:
		EffectDefinition.UnitSide.ALLY:
			return "an ally"
		EffectDefinition.UnitSide.ENEMY:
			return "an enemy"
	return "a unit"
