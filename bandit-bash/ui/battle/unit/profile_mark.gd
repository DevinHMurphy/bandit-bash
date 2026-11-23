# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     profile_mark.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name ProfileMark
extends Control
## A unit's held weapon's triangle profile by its shape, and the unit's side by its style, so both
## read without colour (RF-039; ui-style.md, Profile marks): Power a square, Balance a circle,
## Nimble an upward triangle, None a short bar; the player side's filled in its colour, the
## enemy's a thick hollow outline in its colour, each edged in [member edge_color] so it reads on
## any tile. A unit on neither side shows nothing. It sits at the end of each [UnitInfo]'s HP bar,
## in the unit detail's weapon rows and in the [BoardKey]. Drawn in a [member mark_size] square
## centred in its rect, its edge just outside that, so a hollow keeps all its room; no rules.
##
## @tutorial(UI lift, UL11): docs/design/ui-lift.md

## The shape drawn for a profile ([method shape_of]).
enum Shape {
	## A square: Power.
	SQUARE = 0,
	## A circle: Balance.
	CIRCLE = 1,
	## An upward triangle: Nimble.
	TRIANGLE = 2,
	## A short horizontal bar: None, outside the triangle.
	BAR = 3,
}

# Points in a drawn circle: smooth at any mark size.
const _CIRCLE_POINTS: int = 32

## The side of the square the shape is drawn in, centred in the mark's rect; the mark asks for at
## least this much room.[br]
## [b]Units:[/b] screen pixels at info scale 1.0 (base units in a panel).
@export_range(6.0, 48.0, 1.0) var mark_size: float = 14.0:
	set(value):
		mark_size = value
		if not is_node_ready():
			return
		custom_minimum_size = Vector2(mark_size, mark_size)
		queue_redraw()

## The None bar's height; it is [member mark_size] wide.[br]
## [b]Units:[/b] as [member mark_size]. At or above [member mark_size] the bar is a square.
@export_range(2.0, 48.0, 0.5) var bar_height: float = 7.0:
	set(value):
		bar_height = value
		queue_redraw()

## The enemy side's hollow outline, from the shape's own edge inward.[br]
## [b]Units:[/b] as [member mark_size]. [b]0.0:[/b] an enemy's mark is the edge alone. An
## outline that leaves no hollow (the bar, at small sizes) fills the shape.
@export_range(0.0, 8.0, 0.5) var outline_width: float = 2.0:
	set(value):
		outline_width = value
		queue_redraw()

## The [member edge_color] edge round either style, drawn outside the shape, past
## [member mark_size] on each side, so leave that much room beside the mark.[br]
## [b]Units:[/b] as [member mark_size]. [b]0.0:[/b] no edge.
@export_range(0.0, 4.0, 0.5) var edge_width: float = 1.0:
	set(value):
		edge_width = value
		queue_redraw()

## The player side's fill. Defaults to the [code]block[/code] token, the player side's colour.
@export var player_color: Color = UiTokens.color(UiTokens.BLOCK):
	set(value):
		player_color = value
		queue_redraw()

## The enemy side's outline. Defaults to the [code]danger[/code] token: brighter than
## [code]danger_fill[/code], so a thin line still reads on dark tiles.
@export var enemy_color: Color = UiTokens.color(UiTokens.DANGER):
	set(value):
		enemy_color = value
		queue_redraw()

## The edge round either style, so it reads on any tile. Defaults to the [code]bg[/code] token.
@export var edge_color: Color = UiTokens.color(UiTokens.BG):
	set(value):
		edge_color = value
		queue_redraw()

## The side shown, set by [method show_mark] or [method show_side]: the player side filled, the
## enemy hollow, any other side nothing.
var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE

## The profile shown, set by [method show_mark] or [method show_profile]; picks the shape.
var profile: WeaponTriangle.Profile = WeaponTriangle.Profile.NONE


func _ready() -> void:
	custom_minimum_size = Vector2(mark_size, mark_size)


func _draw() -> void:
	if not is_shown():
		return
	var shape: Shape = shape_of(profile)
	var centre: Vector2 = size * 0.5
	var half: float = mark_size * 0.5
	var hollow_depth: float = -1.0 if is_filled() else outline_width
	var side_color: Color = player_color if is_filled() else enemy_color
	if shape == Shape.CIRCLE:
		_draw_circle_mark(centre, half, side_color, hollow_depth)
		return
	var outline: PackedVector2Array = _outline_of(shape, centre, half)
	if edge_width > 0.0:
		_draw_ring(_inset(outline, -edge_width), outline, edge_color)
	if hollow_depth < 0.0 or hollow_depth >= _depth_limit(shape, half):
		draw_colored_polygon(outline, side_color)
		return
	_draw_ring(outline, _inset(outline, hollow_depth), side_color)


## Shows [param of_side]'s style and [param of_profile]'s shape.
func show_mark(of_side: CombatFact.CombatSide, of_profile: WeaponTriangle.Profile) -> void:
	side = of_side
	profile = of_profile
	queue_redraw()


## Shows [param of_side]'s style, keeping the shape.
func show_side(of_side: CombatFact.CombatSide) -> void:
	show_mark(of_side, profile)


## Shows [param of_profile]'s shape, keeping the style.
func show_profile(of_profile: WeaponTriangle.Profile) -> void:
	show_mark(side, of_profile)


## Whether anything is drawn: the unit is on the player or the enemy side.
func is_shown() -> bool:
	return side == CombatFact.CombatSide.PLAYER or side == CombatFact.CombatSide.ENEMY


## Whether the mark is drawn filled (the player side); an enemy's is hollow.
func is_filled() -> bool:
	return side == CombatFact.CombatSide.PLAYER


## The shape drawn now ([method shape_of] the profile shown).
func get_shape() -> Shape:
	return shape_of(profile)


# A circle of radius half, its edge outside it: filled, or a hollow_depth-wide ring.
func _draw_circle_mark(
		centre: Vector2, half: float, side_color: Color, hollow_depth: float
) -> void:
	if hollow_depth < 0.0 or hollow_depth >= half:
		if edge_width > 0.0:
			draw_circle(centre, half + edge_width, edge_color)
		draw_circle(centre, half, side_color)
		return
	if edge_width > 0.0:
		draw_arc(centre, half + edge_width * 0.5, 0.0, TAU, _CIRCLE_POINTS, edge_color,
				edge_width, true)
	if hollow_depth > 0.0:
		draw_arc(centre, half - hollow_depth * 0.5, 0.0, TAU, _CIRCLE_POINTS, side_color,
				hollow_depth, true)


# The outer corners of shape in the mark_size square around centre, clockwise on screen.
func _outline_of(shape: Shape, centre: Vector2, half: float) -> PackedVector2Array:
	match shape:
		Shape.SQUARE:
			return PackedVector2Array([
				centre + Vector2(-half, -half), centre + Vector2(half, -half),
				centre + Vector2(half, half), centre + Vector2(-half, half),
			])
		Shape.TRIANGLE:
			return PackedVector2Array([
				centre + Vector2(0.0, -half), centre + Vector2(half, half),
				centre + Vector2(-half, half),
			])
	var bar_half: float = minf(bar_height, mark_size) * 0.5
	return PackedVector2Array([
		centre + Vector2(-half, -bar_half), centre + Vector2(half, -bar_half),
		centre + Vector2(half, bar_half), centre + Vector2(-half, bar_half),
	])


# How deep an inset of shape may go and still leave a hollow.
func _depth_limit(shape: Shape, half: float) -> float:
	match shape:
		Shape.BAR:
			return minf(bar_height, mark_size) * 0.5
		Shape.TRIANGLE:
			# The inradius of the triangle _outline_of() gives (base and height 2 × half): its
			# area, 2 × half², over half its perimeter, half + slant.
			var slant: float = half * sqrt(5.0)
			return 2.0 * half * half / (half + slant)
	return half


# The band between the convex outlines outer and inner (inner inside outer, corner for corner).
func _draw_ring(outer: PackedVector2Array, inner: PackedVector2Array, color: Color) -> void:
	var count: int = outer.size()
	for index: int in count:
		var next: int = (index + 1) % count
		draw_colored_polygon(PackedVector2Array([
			outer[index], outer[next], inner[next], inner[index],
		]), color)


# The convex outline points moved depth inward (outward when negative), each edge kept parallel
# (mitred corners).
static func _inset(points: PackedVector2Array, depth: float) -> PackedVector2Array:
	if is_zero_approx(depth):
		return points.duplicate()
	var middle: Vector2 = Vector2.ZERO
	for point: Vector2 in points:
		middle += point
	middle /= float(points.size())
	var count: int = points.size()
	var normals: PackedVector2Array = []
	for index: int in count:
		var along: Vector2 = (points[(index + 1) % count] - points[index]).normalized()
		var normal: Vector2 = Vector2(-along.y, along.x)
		if normal.dot(middle - points[index]) < 0.0:
			normal = -normal
		normals.append(normal)
	var inset: PackedVector2Array = []
	for index: int in count:
		var before: int = (index + count - 1) % count
		var from_before: Vector2 = points[before] + normals[before] * depth
		var from_here: Vector2 = points[index] + normals[index] * depth
		var meet: Variant = Geometry2D.line_intersects_line(
				from_before, points[index] - points[before],
				from_here, points[(index + 1) % count] - points[index],
		)
		var corner: Vector2 = from_here
		if meet is Vector2:
			corner = meet
		inset.append(corner)
	return inset


## The shape [param of_profile] is drawn with: Power a square, Balance a circle, Nimble an upward
## triangle, None (or any other value) a bar.
static func shape_of(of_profile: WeaponTriangle.Profile) -> Shape:
	match of_profile:
		WeaponTriangle.Profile.POWER:
			return Shape.SQUARE
		WeaponTriangle.Profile.BALANCE:
			return Shape.CIRCLE
		WeaponTriangle.Profile.NIMBLE:
			return Shape.TRIANGLE
	return Shape.BAR
