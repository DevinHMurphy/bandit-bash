# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_vote_badge.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name MapVoteBadge
extends Control
## Who voted for one node of the co-op campaign map: a pip per voting seat, numbered as its
## player (seat + 1), in a grid of [member columns] beside the node. The viewer's own pip is
## filled with [member own_color]; hovering names every voter. Sizes itself to its pips; placed
## by [CampaignMapView]. Reads no input. Drawn, not built from labels, so its pips fit a map row
## (about 36 base units tall at 1280×720) with no theme override.

## Each pip's size.[br]
## [b]Units:[/b] base units. At least the number's text height at [member font_size].
@export var pip_size: Vector2 = Vector2(18.0, 18.0):
	set(value):
		pip_size = value
		if not is_node_ready():
			return
		_resize()

## The gap between pips.[br]
## [b]Units:[/b] base units. [b]0:[/b] pips touch.
@export_range(0.0, 8.0, 1.0) var pip_gap: float = 2.0:
	set(value):
		pip_gap = value
		if not is_node_ready():
			return
		_resize()

## Pips per row: 2 fits four seats in two rows beside a 32-unit node.[br]
## [b]1:[/b] one column.
@export_range(1, 4, 1) var columns: int = 2:
	set(value):
		columns = value
		if not is_node_ready():
			return
		_resize()

## The number's font size: the style guide's 14-unit floor.[br]
## [b]Units:[/b] base units.
@export_range(14, 24, 1) var font_size: int = 14

## The viewer's own pip. Defaults to the [code]accent[/code] token.
@export var own_color: Color = UiTokens.color(UiTokens.ACCENT)

## A teammate's pip. Defaults to the [code]panel_raised[/code] token.
@export var teammate_color: Color = UiTokens.color(UiTokens.PANEL_RAISED)

## Every pip's outline. Defaults to the [code]border[/code] token.
@export var outline_color: Color = UiTokens.color(UiTokens.BORDER)

## The number on a teammate's pip. Defaults to the [code]text[/code] token.
@export var text_color: Color = UiTokens.color(UiTokens.TEXT)

## The number on the viewer's own pip, on [member own_color]. Defaults to the [code]bg[/code]
## token.
@export var own_text_color: Color = UiTokens.color(UiTokens.BG)

var _seats: PackedInt32Array = []
var _viewer: int = CampaignData.HOST_SEAT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_resize()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	for i: int in _seats.size():
		var seat: int = _seats[i]
		var is_own: bool = seat == _viewer
		var box: Rect2 = Rect2(_pip_origin(i), pip_size)
		draw_rect(box, own_color if is_own else teammate_color, true)
		draw_rect(box, outline_color, false, 1.0)
		var number: String = str(seat + 1)
		var width: float = font.get_string_size(
				number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
		).x
		var baseline: float = (
				box.position.y + (pip_size.y + font.get_ascent(font_size)
				- font.get_descent(font_size)) * 0.5
		)
		draw_string(
				font, Vector2(box.position.x + (pip_size.x - width) * 0.5, baseline), number,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
				own_text_color if is_own else text_color
		)


## Shows [param seats] (ascending) as the voters, [param viewer] being the one who reads it.
func show_seats(seats: PackedInt32Array, viewer: int) -> void:
	_seats = seats.duplicate()
	_seats.sort()
	_viewer = viewer
	var names: PackedStringArray = []
	for seat: int in _seats:
		var shown_name: String = CampaignLink.seat_name(seat)
		names.append(shown_name + (" (you)" if seat == viewer else ""))
	tooltip_text = "Voted for it: %s" % [", ".join(names)]
	_resize()
	queue_redraw()


## The seats shown, ascending, for tests.
func get_seats() -> PackedInt32Array:
	return _seats.duplicate()


# The top-left of pip index i.
func _pip_origin(index: int) -> Vector2:
	return Vector2(
			(index % columns) * (pip_size.x + pip_gap),
			floori(float(index) / float(columns)) * (pip_size.y + pip_gap)
	)


func _resize() -> void:
	var count: int = maxi(_seats.size(), 1)
	var used_columns: int = mini(count, columns)
	var rows: int = ceili(float(count) / float(columns))
	var grid: Vector2 = Vector2(
			used_columns * pip_size.x + (used_columns - 1) * pip_gap,
			rows * pip_size.y + (rows - 1) * pip_gap
	)
	custom_minimum_size = grid
	size = grid
