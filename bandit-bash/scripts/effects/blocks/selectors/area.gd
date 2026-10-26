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
@export var side: EffectDefinition.Side = EffectDefinition.Side.ALLY

## Whether the center unit itself is selected too. [b]Off:[/b] only the units around it.
@export var include_center: bool = false


func describe() -> String:
	var noun: String = "units"
	match side:
		EffectDefinition.Side.ALLY:
			noun = "allies"
		EffectDefinition.Side.ENEMY:
			noun = "enemies"
	var place: String = "adjacent %s" % [noun]
	if radius > 1:
		place = "%s within %d tiles" % [noun, radius]
	match center:
		Center.FACT_ACTOR:
			place += " of that unit"
		Center.FACT_TARGET:
			place += " of the other unit"
	if side == EffectDefinition.Side.ANY:
		place += ", friend or foe"
	if include_center:
		var center_name: String = "this unit"
		if center == Center.FACT_ACTOR:
			center_name = "that unit"
		elif center == Center.FACT_TARGET:
			center_name = "the other unit"
		return "%s and %s" % [center_name, place]
	return place
