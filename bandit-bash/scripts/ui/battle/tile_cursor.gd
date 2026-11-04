# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     tile_cursor.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name TileCursor
extends Node2D
## The board's tile cursor: an outlined square on one tile, drawn over the unit tokens.
##
## [BattleController] moves it with the mouse and the arrow keys ([method show_at]); while a
## target is being picked it shows in [member target_color]. It holds no rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The outline's colour while picking a tile.
# ASSUMPTION: greybox colour; the combat UI plan sets no palette (Design Basis, Gaps).
@export var color: Color = Color(1.0, 0.95, 0.4, 1.0):
	set(value):
		color = value
		queue_redraw()

## The outline's colour while picking a target.
# ASSUMPTION: greybox colour, as above.
@export var target_color: Color = Color(1.0, 0.35, 0.3, 1.0):
	set(value):
		target_color = value
		queue_redraw()

## The outline's width, drawn inside the tile.[br]
## [b]Units:[/b] pixels.
# ASSUMPTION: greybox value, as above.
@export_range(1.0, 8.0, 0.5) var line_width: float = 2.0:
	set(value):
		line_width = value
		queue_redraw()

## The size of one tile. Set by [BattleView] from the map's tile set.[br]
## [b]Units:[/b] pixels.
var tile_size: Vector2 = Vector2(32.0, 32.0):
	set(value):
		tile_size = value
		queue_redraw()

## The tile the cursor is on; [constant CombatFact.NO_TILE] before [method show_at].
var tile: Vector2i = CombatFact.NO_TILE

## Whether it shows in [member target_color].
var is_targeting: bool = false:
	set(value):
		if is_targeting == value:
			return
		is_targeting = value
		queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(-tile_size * 0.5, tile_size).grow(-line_width * 0.5)
	draw_rect(rect, target_color if is_targeting else color, false, line_width)


## Puts the cursor on [param at_tile], whose centre is [param at_position] in the parent's space.
func show_at(at_tile: Vector2i, at_position: Vector2) -> void:
	tile = at_tile
	position = at_position
	visible = true
