# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_overlay.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name DarknessOverlay
extends Node2D
## Draws the darkness over the terrain: one translucent square per flooded tile, darker for each
## layer (Dusk, Gloom, Abyss; combat UI plan, question 4).
##
## [BattleView] gives it the layers ([method show_layers]) and each tile that deepens
## ([method show_layer]); it holds no rules. It sits under the unit tokens, so the darkness never
## hides a unit (the-darkness.md).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @tutorial(The darkness): docs/design/the-darkness.md

## The darkness's colour; each layer draws it at its own alpha ([member dusk_alpha],
## [member gloom_alpha], [member abyss_alpha]). This colour's own alpha is ignored.
# ASSUMPTION: greybox colour; no palette is set (combat UI plan, Design Basis, Gaps).
@export var tint: Color = Color(0.08, 0.02, 0.15, 1.0):
	set(value):
		tint = value
		queue_redraw()

## How strongly a Dusk tile is covered.[br]
## [b]0.0:[/b] invisible. [b]1.0:[/b] the terrain is hidden.
# ASSUMPTION: greybox value, as above.
@export_range(0.0, 1.0, 0.01) var dusk_alpha: float = 0.3:
	set(value):
		dusk_alpha = value
		queue_redraw()

## How strongly a Gloom tile is covered.[br]
## [b]0.0:[/b] invisible. [b]1.0:[/b] the terrain is hidden.
# ASSUMPTION: greybox value, as above.
@export_range(0.0, 1.0, 0.01) var gloom_alpha: float = 0.5:
	set(value):
		gloom_alpha = value
		queue_redraw()

## How strongly an Abyss tile is covered.[br]
## [b]0.0:[/b] invisible. [b]1.0:[/b] the terrain is hidden.
# ASSUMPTION: greybox value, as above.
@export_range(0.0, 1.0, 0.01) var abyss_alpha: float = 0.7:
	set(value):
		abyss_alpha = value
		queue_redraw()

## The size of one tile. Set by [BattleView] from the map's tile set.[br]
## [b]Units:[/b] pixels.
var tile_size: Vector2 = Vector2(32.0, 32.0)

## Where tile (0, 0)'s top-left corner is, in this node's space. Set by [BattleView].[br]
## [b]Units:[/b] pixels.
var origin: Vector2 = Vector2.ZERO

# The layer drawn on each flooded tile; a dry tile is absent.
var _layers: Dictionary[Vector2i, int] = {}


func _draw() -> void:
	for tile: Vector2i in _layers:
		var rect: Rect2 = Rect2(origin + Vector2(tile) * tile_size, tile_size)
		draw_rect(rect, color_of(_layers[tile]))


## Draws [param layers] (tile to [enum WhileLayerCondition.Layer]) in place of what was drawn.
func show_layers(layers: Dictionary[Vector2i, int]) -> void:
	_layers.clear()
	for tile: Vector2i in layers:
		show_layer(tile, layers[tile])


## Draws [param tile] at [param layer]; [constant WhileLayerCondition.Layer.DRY] clears it.
func show_layer(tile: Vector2i, layer: int) -> void:
	if layer <= WhileLayerCondition.Layer.DRY:
		_layers.erase(tile)
	else:
		_layers[tile] = mini(layer, WhileLayerCondition.Layer.ABYSS)
	queue_redraw()


## The layer drawn on [param tile]; [constant WhileLayerCondition.Layer.DRY] when none is.
func layer_at(tile: Vector2i) -> int:
	return _layers.get(tile, WhileLayerCondition.Layer.DRY)


## Every tile drawn, row-major.
func drawn_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(_layers.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


## The colour drawn for [param layer]: [member tint] at that layer's alpha; transparent for
## [constant WhileLayerCondition.Layer.DRY].
func color_of(layer: int) -> Color:
	var alpha: float = 0.0
	match layer:
		WhileLayerCondition.Layer.DUSK:
			alpha = dusk_alpha
		WhileLayerCondition.Layer.GLOOM:
			alpha = gloom_alpha
		WhileLayerCondition.Layer.ABYSS:
			alpha = abyss_alpha
	return Color(tint, alpha)
