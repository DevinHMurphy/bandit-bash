# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     area.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name Area
extends TargetSelector
## Selects units around a center: "adjacent units, friend or foe" (Cleave), "allies within 2 tiles".
##
## Radius 1 is the four orthogonal neighbors; larger radii use walking distance (effect-triggers.md,
## Position and movement). Never reaches across parallel maps.
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
}

## The unit the area is centered on.
@export var center: Center = Center.OWNER

## How far the area reaches. [b]Units:[/b] tiles. [b]1:[/b] adjacent only.
@export_range(1, 20) var radius: int = 1

## Which units count, relative to the effect's owner.
@export var side: EffectDefinition.UnitSide = EffectDefinition.UnitSide.ALLY

## Whether the center unit itself is selected too. [b]Off:[/b] only the units around it.
@export var include_center: bool = false


func describe() -> String:
	var noun: String = "units"
	match side:
		EffectDefinition.UnitSide.ALLY:
			noun = "allies"
		EffectDefinition.UnitSide.ENEMY:
			noun = "enemies"
	var place: String = "adjacent %s" % [noun]
	if radius > 1:
		place = "%s within %d tiles" % [noun, radius]
	match center:
		Center.FACT_ACTOR:
			place += " of that unit"
		Center.FACT_TARGET:
			place += " of the other unit"
	if side == EffectDefinition.UnitSide.ANY:
		place += ", friend or foe"
	if include_center:
		var center_name: String = "this unit"
		if center == Center.FACT_ACTOR:
			center_name = "that unit"
		elif center == Center.FACT_TARGET:
			center_name = "the other unit"
		return "%s and %s" % [center_name, place]
	return place


## Units around the center, in the state's order, on [member side] relative to the owner's side.
## Radius 1 is the orthogonal neighbors; a larger radius is walking distance. An owner center that
## has left the map since the reaction was queued (a Brute defeated by the counter, a keg that just
## broke) is measured from the tile it stood on then, by tile distance.
func select(ctx: EffectContext) -> PackedStringArray:
	var engine: EffectEngine = ctx.engine
	var center_id: String = _center_id(ctx)
	var picked: PackedStringArray = []
	var on_map: bool = engine.state.has_unit(center_id)
	var center_tile: Vector2i = engine.state.tile_of(center_id)
	if not on_map and center == Center.OWNER:
		center_tile = ctx.owner_tile
	if center_tile == CombatFact.NO_TILE:
		return picked
	for unit_id: String in engine.state.unit_ids():
		if unit_id == center_id:
			if include_center:
				picked.append(unit_id)
			continue
		if not engine.matches_side(ctx.instance.owner.side, unit_id, side):
			continue
		var delta: Vector2i = engine.state.tile_of(unit_id) - center_tile
		var distance: int = absi(delta.x) + absi(delta.y)
		if radius > 1 and on_map:
			distance = engine.state.walking_distance(center_id, unit_id)
		if distance >= 1 and distance <= radius:
			picked.append(unit_id)
	return picked


func _center_id(ctx: EffectContext) -> String:
	if ctx.fact != null:
		if center == Center.FACT_ACTOR:
			return ctx.fact.actor_id
		if center == Center.FACT_TARGET:
			return ctx.fact.target_id
	return ctx.owner_unit_id() if center == Center.OWNER else ""
