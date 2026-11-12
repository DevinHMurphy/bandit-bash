# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     area.gd
# Author:
# Created:  October 26, 2026
# Modified: November 12, 2026
# ==============================================================================

@tool
class_name Area
extends TargetSelector
## Selects units around a center: "adjacent units, friend or foe" (Cleave), "the target and adjacent
## allies of the target" (Sanctuary), "allies within 2 tiles".
##
## Which tiles count is a shared [TargetShape] from [code]res://data/shapes/[/code], so staves,
## splash, keg blasts and runes describe areas one way; the content test rejects a shape that isn't
## one of those files. Grid distance only, ignoring walls and terrain. The center unit counts when
## the shape covers the center, whatever its side; no other unit on the center tile ever does.
## Never reaches across parallel maps.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## The unit the area is centered on. Saved as an int: [b]append only[/b].
enum Center {
	## The effect's owner.
	OWNER = 0,
	## The triggering fact's actor.
	FACT_ACTOR = 1,
	## The triggering fact's other party.
	FACT_TARGET = 2,
	## The unit a command targets: the ally an area staff (Sanctuary) is used on. Outside a
	## command there is none, and the area selects nothing.
	COMMAND_TARGET = 3,
}

## The unit the area is centered on.
@export var center: Center = Center.OWNER

## The tiles covered around the center, and whether the center unit counts
## ([member TargetShape.includes_center]). [b]Null:[/b] the area selects nothing.
@export var shape: TargetShape = null

## Which units count, relative to the effect's owner.
@export var side: EffectTerms.UnitSide = EffectTerms.UnitSide.ALLY


func describe() -> String:
	var noun: String = "units"
	match side:
		EffectTerms.UnitSide.ALLY:
			noun = "allies"
		EffectTerms.UnitSide.ENEMY:
			noun = "enemies"
	var place: String = _place(noun)
	if place.is_empty():
		return _center_name() if shape != null and shape.includes_center else "no units"
	match center:
		Center.FACT_ACTOR:
			place += " of that unit"
		Center.FACT_TARGET:
			place += " of the other unit"
		Center.COMMAND_TARGET:
			place += " of the target"
	if side == EffectTerms.UnitSide.ANY:
		place += ", friend or foe"
	if shape.includes_center:
		return "%s and %s" % [_center_name(), place]
	return place


## Units around the center, in the state's order, on [member side] relative to the owner's side,
## on the tiles [member shape] covers. An owner center that has left the map since the reaction
## was queued (a Brute defeated by the counter, a keg that just broke) is measured from the tile
## it stood on then.
func select(ctx: EffectContext) -> PackedStringArray:
	var picked: PackedStringArray = []
	if shape == null:
		return picked
	var engine: EffectEngine = ctx.engine
	var center_id: String = _center_id(ctx)
	var center_tile: Vector2i = engine.state.tile_of(center_id)
	if not engine.state.has_unit(center_id) and center == Center.OWNER:
		center_tile = ctx.owner_tile
	if center_tile == CombatFact.NO_TILE:
		return picked
	for unit_id: String in engine.state.unit_ids():
		if unit_id == center_id:
			if shape.covers(center_tile, center_tile):
				picked.append(unit_id)
			continue
		if not engine.matches_side(ctx.instance.owner.side, unit_id, side):
			continue
		var tile: Vector2i = engine.state.tile_of(unit_id)
		if tile == CombatFact.NO_TILE or tile == center_tile:
			continue
		if shape.covers(center_tile, tile):
			picked.append(unit_id)
	return picked


func _center_id(ctx: EffectContext) -> String:
	if ctx.fact != null:
		if center == Center.FACT_ACTOR:
			return ctx.fact.actor_id
		if center == Center.FACT_TARGET:
			return ctx.fact.target_id
	if center == Center.COMMAND_TARGET:
		return ctx.command_target_id
	return ctx.owner_unit_id() if center == Center.OWNER else ""


# The tiles around the center as a phrase about noun, such as "adjacent allies"; empty when the
# shape covers nothing around its center (no shape, a tile, size 0).
func _place(noun: String) -> String:
	if shape == null or shape.kind == ContentIds.SHAPE_TILE or shape.size <= 0:
		return ""
	var reach: String = (
			"adjacent %s" % [noun] if shape.size == 1
			else "%s within %d tiles" % [noun, shape.size]
	)
	# ASSUMPTION: square and cross wording; no content uses either kind yet.
	match shape.kind:
		ContentIds.SHAPE_SQUARE:
			return "%s, diagonals included" % [reach]
		ContentIds.SHAPE_CROSS:
			return reach if shape.size == 1 else "%s in a straight line" % [reach]
	return reach


func _center_name() -> String:
	match center:
		Center.FACT_ACTOR:
			return "that unit"
		Center.FACT_TARGET:
			return "the other unit"
		Center.COMMAND_TARGET:
			return "the target"
	return "this unit"
