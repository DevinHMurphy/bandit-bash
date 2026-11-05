# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     path_preview.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name PathPreview
extends Node2D
## The walk a selected unit would take to the hovered tile, drawn as a line through tile centres
## with a dot on its last tile.
##
## [BattleController] gives it the path the command will be sent with
## ([method TurnInputModel.path_to]) and the tile centres ([method show_path]); it holds no rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The line's colour.
# ASSUMPTION: greybox colour; the combat UI plan sets no palette (Design Basis, Gaps).
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.85):
	set(value):
		line_color = value
		queue_redraw()

## The line's width.[br]
## [b]Units:[/b] pixels.
# ASSUMPTION: greybox value, as above.
@export_range(1.0, 16.0, 0.5) var line_width: float = 4.0:
	set(value):
		line_width = value
		queue_redraw()

## The radius of the dot on the last tile.[br]
## [b]Units:[/b] pixels. [b]0.0:[/b] no dot.
# ASSUMPTION: greybox value, as above.
@export_range(0.0, 16.0, 0.5) var end_radius: float = 5.0:
	set(value):
		end_radius = value
		queue_redraw()

var _tiles: Array[Vector2i] = []
var _points: PackedVector2Array = []


func _draw() -> void:
	if _points.size() < 2:
		return
	draw_polyline(_points, line_color, line_width, true)
	if end_radius > 0.0:
		draw_circle(_points[_points.size() - 1], end_radius, line_color)


## Draws [param tiles], a walk, through [param points], each tile's centre in this node's space.
## Fewer than two tiles draws nothing.
func show_path(tiles: Array[Vector2i], points: PackedVector2Array) -> void:
	_tiles = tiles.duplicate()
	_points = points
	queue_redraw()


## Draws nothing.
func clear() -> void:
	show_path([], PackedVector2Array())


## The walk drawn; empty when none is.
func shown_tiles() -> Array[Vector2i]:
	return _tiles.duplicate()
