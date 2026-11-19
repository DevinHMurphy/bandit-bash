# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reward_icon.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name RewardIcon
extends Control
## A reward row's icon: the reward's texture, or the style guide's placeholder mark (a flat
## [code]accent[/code] symbol on a dark circle: [code]panel[/code] fill, 1-unit [code]border[/code]
## edge) while it has none. Colours come from [UiTokens].
##
## @tutorial(UI style guide): docs/design/ui-style.md

# The symbol's size within the circle, as a share of its diameter.
const _SYMBOL_SHARE: float = 0.6

# ASSUMPTION: a reward with no art shows "?" until the art pass (rebalance-and-features.md RF-008).
## The placeholder's symbol, drawn while there is no texture. [b]Empty:[/b] the circle alone.
@export var symbol: String = "?":
	set(value):
		symbol = value
		queue_redraw()

## The placeholder's edge width.[br]
## [b]Units:[/b] base units. [b]0.0:[/b] no edge.
@export_range(0.0, 4.0, 0.5) var edge_width: float = 1.0:
	set(value):
		edge_width = value
		queue_redraw()

## The icon shown; null shows the placeholder.
var texture: Texture2D = null:
	set(value):
		texture = value
		queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if texture != null:
		draw_texture_rect(texture, rect, false)
		return
	var radius: float = minf(size.x, size.y) * 0.5
	var centre: Vector2 = size * 0.5
	draw_circle(centre, radius, UiTokens.color(UiTokens.PANEL))
	if edge_width > 0.0:
		draw_arc(centre, radius - edge_width * 0.5, 0.0, TAU, 32, UiTokens.color(UiTokens.BORDER),
				edge_width, true)
	if symbol.is_empty():
		return
	var font: Font = get_theme_default_font()
	var font_size: int = maxi(roundi(radius * 2.0 * _SYMBOL_SHARE), 1)
	var text_size: Vector2 = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline: Vector2 = Vector2(
			centre.x - text_size.x * 0.5,
			centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	)
	draw_string(font, baseline, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			UiTokens.color(UiTokens.ACCENT))
