# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     side_shape.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name SideShape
extends Control
## The shape at the left end of a unit's HP bar that says its side without colour (RF-026;
## ui-style.md: colour is never the only signal): a circle for the player side, a diamond for the
## enemy, each filled in its side's colour with an outline; nothing for a unit on neither side (a
## map object standing as a unit). Drawn in its own rect, so the scene sets its size. Holds no
## rules.
##
## @tutorial(UI lift, UL6): docs/design/ui-lift.md

## The shape drawn.
enum Shape {
	## Nothing: a unit on neither side.
	NONE = 0,
	## A circle: the player side.
	CIRCLE = 1,
	## A diamond: the enemy side.
	DIAMOND = 2,
}

## The player side's fill. Defaults to the [code]block[/code] token, the player side's colour.
@export var player_color: Color = UiTokens.color(UiTokens.BLOCK):
	set(value):
		player_color = value
		queue_redraw()

## The enemy side's fill. Defaults to the [code]danger_fill[/code] token.
@export var enemy_color: Color = UiTokens.color(UiTokens.DANGER_FILL):
	set(value):
		enemy_color = value
		queue_redraw()

## The outline round either shape, so it reads on any tile. Defaults to the [code]bg[/code] token.
@export var outline_color: Color = UiTokens.color(UiTokens.BG):
	set(value):
		outline_color = value
		queue_redraw()

## The outline's width.[br]
## [b]Units:[/b] screen pixels at info scale 1.0. [b]0.0:[/b] no outline.
@export_range(0.0, 4.0, 0.5) var outline_width: float = 1.0:
	set(value):
		outline_width = value
		queue_redraw()

## The shape shown; set by [method show_side].
var shape: Shape = Shape.NONE


func _draw() -> void:
	if shape == Shape.NONE:
		return
	var centre: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5
	if shape == Shape.CIRCLE:
		draw_circle(centre, radius, player_color)
		if outline_width > 0.0:
			draw_arc(centre, radius, 0.0, TAU, 24, outline_color, outline_width, true)
		return
	var points: PackedVector2Array = [
		centre + Vector2(0.0, -radius), centre + Vector2(radius, 0.0),
		centre + Vector2(0.0, radius), centre + Vector2(-radius, 0.0),
	]
	draw_colored_polygon(points, enemy_color)
	if outline_width > 0.0:
		var outline: PackedVector2Array = points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, outline_color, outline_width, true)


## Shows [param side]'s shape: a circle for the player side, a diamond for the enemy, nothing for
## neither.
func show_side(side: CombatFact.CombatSide) -> void:
	shape = shape_of(side)
	queue_redraw()


## The shape [param side] is drawn with.
static func shape_of(side: CombatFact.CombatSide) -> Shape:
	match side:
		CombatFact.CombatSide.PLAYER:
			return Shape.CIRCLE
		CombatFact.CombatSide.ENEMY:
			return Shape.DIAMOND
	return Shape.NONE
