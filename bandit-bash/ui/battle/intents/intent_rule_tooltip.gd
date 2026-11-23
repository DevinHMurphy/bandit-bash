# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_rule_tooltip.gd
# Author:
# Created:  November 5, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name IntentRuleTooltip
extends Node2D
## The hovered enemy's target rule beside its intent icon (combat UI plan, question 10), such as
## "Nearest foe it can hit", or the darkness's "Nearest foe" once it has arrived
## ([member EnemyIntent.target_rule_text]).
##
## A [GameTooltip] authored in the scene: [member heading_text] as its name, the rule as its body,
## at most 320 units wide at the HUD's scale whatever the camera's zoom; its origin is the enemy's
## tile centre, and it sits centred above it. It stays inside the viewport's visible rect: where
## the top would leave it (an enemy in the top row) it sits below instead, [member lift] under the
## centre, and it slides sideways at the left and right edges. [IntentDisplay] shows and hides it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The tooltip's name line, over the rule.[br]
## [b]Empty:[/b] only the rule shows.
@export var heading_text: String = "Target rule"

## How far above the enemy's tile centre the tooltip's bottom edge sits, clear of its token; below
## it instead, the top edge sits as far under the centre.[br]
## [b]Units:[/b] pixels on the board.
@export_range(0.0, 128.0, 1.0) var lift: float = 32.0

## The enemy whose rule shows; empty while hidden.
var enemy_id: String = ""

var _text: String = ""

# The canvas transform the tip was last placed for: the camera moving while it shows (a pan, a
# zoom on a resize) places it again.
var _placed_for: Transform2D = Transform2D()

@onready var _tip: GameTooltip = %Tip


func _ready() -> void:
	_tip.resized.connect(_on_tip_resized)
	hide_rule()


func _process(_delta: float) -> void:
	if is_inside_tree() and get_viewport().get_canvas_transform() != _placed_for:
		_place_tip()


## Shows [param text], the rule of [param shown_id], at [param board_position], the enemy's tile
## centre in the board's space.
func show_rule(shown_id: String, text: String, board_position: Vector2) -> void:
	enemy_id = shown_id
	_text = text
	_tip.show_tip(heading_text, text)
	position = board_position
	visible = true
	set_process(true)
	_place_tip()


## Hides the tooltip.
func hide_rule() -> void:
	enemy_id = ""
	visible = false
	set_process(false)


## The text shown; empty while hidden.
func get_text() -> String:
	return _text if visible else ""


## The tooltip, for tests that read its lines and width.
func get_tip() -> GameTooltip:
	return _tip


# The tooltip sits centred above its anchor, however wide or tall the text makes it, or below it
# where the top would leave the visible rect, then is clamped inside that rect. It lives on the
# board, so it undoes the camera's zoom to draw at the HUD's size, its 320-unit cap included;
# the rect is judged in the viewport's canvas space, where the tip is as large as its own size.
func _place_tip() -> void:
	if not is_inside_tree():
		_tip.scale = Vector2.ONE
		_tip.position = Vector2(-_tip.size.x * 0.5, -lift - _tip.size.y)
		return
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	_placed_for = canvas
	var zoom: Vector2 = canvas.get_scale()
	zoom = Vector2(maxf(zoom.x, 0.01), maxf(zoom.y, 0.01))
	_tip.scale = Vector2(1.0 / zoom.x, 1.0 / zoom.y)
	var tip_size: Vector2 = _tip.size
	var visible_rect: Rect2 = get_viewport().get_visible_rect()
	var anchor: Vector2 = get_global_transform_with_canvas().origin
	var top_left: Vector2 = Vector2(
			anchor.x - tip_size.x * 0.5, anchor.y - lift * zoom.y - tip_size.y
	)
	if top_left.y < visible_rect.position.y:
		top_left.y = anchor.y + lift * zoom.y
	# A tip larger than the rect keeps its top-left corner inside.
	var far_corner: Vector2 = visible_rect.end - tip_size
	top_left.x = maxf(minf(top_left.x, far_corner.x), visible_rect.position.x)
	top_left.y = maxf(minf(top_left.y, far_corner.y), visible_rect.position.y)
	_tip.position = (top_left - anchor) / zoom


# A wrapped tooltip refits a frame later; it is placed again for its new size.
func _on_tip_resized() -> void:
	_place_tip()
