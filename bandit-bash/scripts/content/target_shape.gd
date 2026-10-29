# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     target_shape.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name TargetShape
extends EffectCarrierDefinition
## The tiles an area covers around a center: one shared shape for area staves, splash, keg blasts
## and runes (content catalog plan, question 17).
##
## Lives in [code]res://data/shapes/[/code], reused by [member EffectCarrierDefinition.id]; its
## effects stay empty. A size change at runtime (a future rune prefix) applies as a delta on the
## caster's side and never edits a shape file. [method tiles] is pure: it knows nothing of the map,
## so tiles off the map or behind walls are the caller's to drop. Distance is always grid
## distance, tiles up plus tiles across: "within N movable tiles" was cut (P04 question 12).
##
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## The shape, from [constant ContentIds.SHAPE_KINDS]. [b]tile:[/b] the center only.
## [b]radius:[/b] within [member size] by grid distance. [b]square:[/b] within [member size]
## along both axes. [b]cross:[/b] the center's row and column, [member size] each way.
@export var kind: String = ContentIds.SHAPE_TILE

## How far the shape reaches from the center; [code]tile[/code] ignores it.[br]
## [b]Units:[/b] tiles. [b]0:[/b] the center only. [b]1:[/b] radius 1 is the four neighbors.
@export_range(0, 20, 1, "or_greater") var size: int = 0

## Whether the center tile is covered too. [b]Off:[/b] only the tiles around it, as Cleave hits
## the units adjacent to the Brute and not the Brute.
@export var includes_center: bool = true


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "kind":
		ContentIds.apply_hint(property, ContentIds.SHAPE_KINDS)


## The tiles the shape covers around [param center], each once, in row order (top row first, left
## to right). An unknown [member kind] covers nothing; the content test rejects it.
func tiles(center: Vector2i) -> Array[Vector2i]:
	var covered: Array[Vector2i] = []
	if not ContentIds.SHAPE_KINDS.has(kind):
		return covered
	var reach: int = 0 if kind == ContentIds.SHAPE_TILE else maxi(size, 0)
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			if dx == 0 and dy == 0 and not includes_center:
				continue
			if _covers(Vector2i(dx, dy), reach):
				covered.append(center + Vector2i(dx, dy))
	return covered


# Whether [param offset] from the center, inside the square [param reach] each way, is covered.
func _covers(offset: Vector2i, reach: int) -> bool:
	match kind:
		ContentIds.SHAPE_RADIUS:
			return absi(offset.x) + absi(offset.y) <= reach
		ContentIds.SHAPE_CROSS:
			return offset.x == 0 or offset.y == 0
	return true
