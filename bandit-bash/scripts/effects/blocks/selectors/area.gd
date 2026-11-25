# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     area.gd
# Author:
# Created:  October 26, 2026
# Modified: November 24, 2026
# ==============================================================================

@tool
class_name Area
extends TargetSelector
## Selects units around a center: "every other adjacent unit, friend or foe" (Cleave), "the target
## and adjacent allies of the target" (Sanctuary), "your commander and your units within 2 tiles of
## your commander" (Commander's Standard).
##
## Which tiles count is a shared [TargetShape] from [code]res://data/shapes/[/code], so staves,
## splash, keg blasts and runes describe areas one way; the content test rejects a shape that isn't
## one of those files. Grid distance only, ignoring walls and terrain. The center unit counts when
## the shape covers the center, whatever its side, unless [member is_fact_target_excluded] spares
## it; no other unit on the center tile ever does. Never reaches across parallel maps.
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
	## The commander of the owner's seat on this map ([method SandboxState.commander_of]). With
	## none, or once it is defeated, the area selects nothing.
	COMMANDER = 4,
}

## The unit the area is centered on.
@export var center: Center = Center.OWNER

## The tiles covered around the center, and whether the center unit counts
## ([member TargetShape.includes_center]). [b]Null:[/b] the area selects nothing.
@export var shape: TargetShape = null

## Which units count, relative to the effect's owner.
@export var side: EffectTerms.UnitSide = EffectTerms.UnitSide.ALLY

## Whether only units the owner's player controls count (Your Units), so a co-op partner's unit in
## the area never does; the center still counts as [member shape] says. [b]Off:[/b] every unit on
## [member side].
@export var is_your_units_only: bool = false

## Whether the triggering fact's other party never counts: the unit a Cleave hit strikes takes the
## hit, not the splash. It counts nowhere, the center included. Outside a reaction (no fact) and on
## a fact with no other party, nothing is left out. [b]Off:[/b] every unit the area covers.
@export var is_fact_target_excluded: bool = false


func describe() -> String:
	var noun: String = "units"
	match side:
		EffectTerms.UnitSide.ALLY:
			noun = "allies"
		EffectTerms.UnitSide.ENEMY:
			noun = "enemies"
	var place: String = _place("units" if is_your_units_only else noun)
	if is_fact_target_excluded and not place.is_empty():
		# ASSUMPTION: "your other ..." wording with Your Units; no content combines the two yet.
		place = (
				"your other %s" % [place] if is_your_units_only
				else "every other %s" % [_place(_singular(noun))]
		)
	elif is_your_units_only and not place.is_empty():
		place = "your %s" % [place]
	var counts_center: bool = (
			shape != null
			and shape.includes_center
			and not (is_fact_target_excluded and center == Center.FACT_TARGET)
	)
	if place.is_empty():
		return _center_name() if counts_center else "no units"
	match center:
		Center.FACT_ACTOR:
			place += " of that unit"
		Center.FACT_TARGET:
			place += " of the other unit"
		Center.COMMAND_TARGET:
			place += " of the target"
		Center.COMMANDER:
			place += " of your commander"
	if side == EffectTerms.UnitSide.ANY:
		place += ", friend or foe"
	if counts_center:
		return "%s and %s" % [_center_name(), place]
	return place


## Units around the center, in the state's order, on [member side] relative to the owner's side
## (and the owner's player's own with [member is_your_units_only]), on the tiles [member shape]
## covers, less the fact's other party with [member is_fact_target_excluded]. A center that has
## left the map since the reaction was queued (a Brute defeated by the counter, the target a
## Trample hit defeated, a keg that just broke) is measured from the tile it stood on then; a
## command target and a commander have no such tile.
func select(ctx: EffectContext) -> PackedStringArray:
	var picked: PackedStringArray = []
	if shape == null:
		return picked
	var engine: EffectEngine = ctx.engine
	var center_id: String = _center_id(ctx)
	var center_tile: Vector2i = engine.state.tile_of(center_id)
	if not engine.state.has_unit(center_id):
		center_tile = _tile_when_queued(ctx)
	if center_tile == CombatFact.NO_TILE:
		return picked
	var spared_id: String = ""
	if is_fact_target_excluded and ctx.fact != null:
		spared_id = ctx.fact.target_id
	for unit_id: String in engine.state.unit_ids():
		if not spared_id.is_empty() and unit_id == spared_id:
			continue
		if unit_id == center_id:
			if shape.covers(center_tile, center_tile):
				picked.append(unit_id)
			continue
		if not engine.matches_side(ctx.instance.owner.side, unit_id, side):
			continue
		if is_your_units_only and not engine.in_scope(
				ctx.instance.owner, unit_id, EffectTerms.Scope.YOUR_UNIT
		):
			continue
		var tile: Vector2i = engine.state.tile_of(unit_id)
		if tile == CombatFact.NO_TILE or tile == center_tile:
			continue
		if shape.covers(center_tile, tile):
			picked.append(unit_id)
	return picked


# Where the center stood when the reaction was queued ([member EffectContext.owner_tile] and the
# fact's tiles); NO_TILE for a command target or a commander, or outside a reaction.
func _tile_when_queued(ctx: EffectContext) -> Vector2i:
	match center:
		Center.OWNER:
			return ctx.owner_tile
		Center.FACT_ACTOR:
			return ctx.fact_actor_tile
		Center.FACT_TARGET:
			return ctx.fact_target_tile
	return CombatFact.NO_TILE


func _center_id(ctx: EffectContext) -> String:
	if ctx.fact != null:
		if center == Center.FACT_ACTOR:
			return ctx.fact.actor_id
		if center == Center.FACT_TARGET:
			return ctx.fact.target_id
	if center == Center.COMMAND_TARGET:
		return ctx.command_target_id
	if center == Center.COMMANDER:
		return ctx.engine.state.commander_of(ctx.instance.owner.seat)
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


# One of noun, the plural units, allies or enemies describe() names.
func _singular(noun: String) -> String:
	match noun:
		"allies":
			return "ally"
		"enemies":
			return "enemy"
	return "unit"


func _center_name() -> String:
	match center:
		Center.FACT_ACTOR:
			return "that unit"
		Center.FACT_TARGET:
			return "the other unit"
		Center.COMMAND_TARGET:
			return "the target"
		Center.COMMANDER:
			return "your commander"
	return "this unit"
