# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     tile_overlay.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name TileOverlay
extends Node2D
## A set of board tiles drawn as translucent squares: a unit's move, attack or support tiles, an
## enemy's range, or the danger zone.
##
## The script of scenes that differ only in their colours: [code]move_overlay.tscn[/code], the
## red [code]attack_overlay.tscn[/code], [code]enemy_range_overlay.tscn[/code] and
## [code]danger_overlay.tscn[/code], and their purple support twins
## [code]support_overlay.tscn[/code], [code]enemy_support_overlay.tscn[/code] and
## [code]danger_support_overlay.tscn[/code] (combat UI plan, question 23). [BattleView] sets
## [member tile_size] and [member origin] from the map; [BattleController] says which tiles
## ([method show_tiles]). It holds no rules and sits under the unit tokens.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: the support scenes' purple is Godot's Color.PURPLE, at their red twins' alphas; the
# plan's question 23 says purple and Godot_FE drew no support range.
## The fill of each tile. Its alpha is how strongly the terrain is covered. Each scene sets
## Godot_FE's [code]CController.gd[/code] value: move BLUE at 0.5, attack CRIMSON at 0.5
## ([code]draw_hover_movement_ranges[/code]), enemy range CRIMSON at 0.35
## ([code]draw_enemy_ranges[/code]); each support twin PURPLE at its red twin's alpha.[br]
## [b]Alpha 0.0:[/b] invisible. [b]1.0:[/b] the terrain is hidden.
@export var fill_color: Color = Color(0.0, 0.0, 1.0, 0.5):
	set(value):
		fill_color = value
		queue_redraw()

## The outline of each tile, drawn inside it.[br]
## [b]Alpha 0.0:[/b] no outline.
# ASSUMPTION: greybox outline; Godot_FE's tile textures carried their own edge.
@export var edge_color: Color = Color(0.0, 0.0, 1.0, 0.8):
	set(value):
		edge_color = value
		queue_redraw()

## The outline's width.[br]
## [b]Units:[/b] pixels. [b]0.0:[/b] no outline.
# ASSUMPTION: greybox value, as above.
@export_range(0.0, 8.0, 0.5) var edge_width: float = 1.0:
	set(value):
		edge_width = value
		queue_redraw()

## The size of one tile. Set by [BattleView] from the map's tile set.[br]
## [b]Units:[/b] pixels.
var tile_size: Vector2 = Vector2(32.0, 32.0)

## Where tile (0, 0)'s top-left corner is, in this node's space. Set by [BattleView].[br]
## [b]Units:[/b] pixels.
var origin: Vector2 = Vector2.ZERO

var _tiles: Array[Vector2i] = []


func _draw() -> void:
	for tile: Vector2i in _tiles:
		var rect: Rect2 = Rect2(origin + Vector2(tile) * tile_size, tile_size)
		draw_rect(rect, fill_color)
		if edge_width > 0.0 and edge_color.a > 0.0:
			draw_rect(rect.grow(-edge_width * 0.5), edge_color, false, edge_width)


## Draws [param tiles] in place of what was drawn.
func show_tiles(tiles: Array[Vector2i]) -> void:
	_tiles = tiles.duplicate()
	queue_redraw()


## Draws nothing.
func clear() -> void:
	show_tiles([])


## The tiles drawn, in the order given.
func shown_tiles() -> Array[Vector2i]:
	return _tiles.duplicate()
