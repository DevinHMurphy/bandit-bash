# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     tile_overlay.gd
# Author:
# Created:  November 4, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name TileOverlay
extends Node2D
## A set of board tiles drawn as translucent squares: a unit's move, attack or support tiles, an
## enemy's range, the danger zone, or the objective's tiles.
##
## The script of scenes that differ only in their colours: [code]move_overlay.tscn[/code], the
## red [code]attack_overlay.tscn[/code], [code]enemy_range_overlay.tscn[/code] and
## [code]danger_overlay.tscn[/code], and their purple support twins
## [code]support_overlay.tscn[/code], [code]enemy_support_overlay.tscn[/code] and
## [code]danger_support_overlay.tscn[/code] (combat UI plan, question 23); and the objective's
## [code]seize_overlay.tscn[/code], [code]defend_overlay.tscn[/code] and
## [code]reinforcement_overlay.tscn[/code] (UI11). [BattleView] sets [member tile_size] and
## [member origin] from the map; [BattleController] says which tiles for turn input's, the
## [BattleHud] for the objective's ([method show_tiles]). It holds no rules and sits under the
## unit tokens.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The style guide's colour token ([UiTokens]) the fill and outline take, each keeping the alpha
## of [member fill_color] and [member edge_color]: [code]block[/code] for move, [code]danger[/code]
## for attack, enemy range and the danger zone.[br]
## [b]Empty:[/b] [member fill_color] and [member edge_color] are drawn as they are.
@export var color_token: StringName = &"":
	set(value):
		color_token = value
		queue_redraw()

## The fill of each tile. Its alpha is how strongly the terrain is covered: Godot_FE's
## [code]CController.gd[/code] values, move and attack 0.5, enemy range 0.35; each support twin
## at its red twin's alpha. Its colour counts only while [member color_token] is empty.[br]
## [b]Alpha 0.0:[/b] invisible. [b]1.0:[/b] the terrain is hidden.
@export var fill_color: Color = Color(0.0, 0.0, 1.0, 0.5):
	set(value):
		fill_color = value
		queue_redraw()

# ASSUMPTION: greybox outline; Godot_FE's tile textures carried their own edge.
# ASSUMPTION: the support twins' opaque lavender 2 px edge, for readability (plan, question 27).
## The outline of each tile, drawn inside it. The purple support twins draw an opaque lavender
## one, which red ranges lack, so purple over grass isn't read as gray, nor red over water as
## purple. Its colour counts only while [member color_token] is empty.[br]
## [b]Alpha 0.0:[/b] no outline.
@export var edge_color: Color = Color(0.0, 0.0, 1.0, 0.8):
	set(value):
		edge_color = value
		queue_redraw()

# ASSUMPTION: greybox value, as above.
## The outline's width.[br]
## [b]Units:[/b] pixels. [b]0.0:[/b] no outline.
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
	var fill: Color = drawn_fill_color()
	var edge: Color = drawn_edge_color()
	for tile: Vector2i in _tiles:
		var rect: Rect2 = Rect2(origin + Vector2(tile) * tile_size, tile_size)
		draw_rect(rect, fill)
		if edge_width > 0.0 and edge.a > 0.0:
			draw_rect(rect.grow(-edge_width * 0.5), edge, false, edge_width)


## The fill drawn: [member color_token]'s colour at [member fill_color]'s alpha, else
## [member fill_color].
func drawn_fill_color() -> Color:
	if color_token.is_empty():
		return fill_color
	return UiTokens.with_alpha(color_token, fill_color.a)


## The outline drawn: [member color_token]'s colour at [member edge_color]'s alpha, else
## [member edge_color].
func drawn_edge_color() -> Color:
	if color_token.is_empty():
		return edge_color
	return UiTokens.with_alpha(color_token, edge_color.a)


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
