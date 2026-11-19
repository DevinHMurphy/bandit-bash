# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_rule_tooltip.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name IntentRuleTooltip
extends Node2D
## The hovered enemy's target rule beside its intent icon (combat UI plan, question 10), such as
## "Nearest foe it can hit", or the darkness's "Nearest foe" once it has arrived
## ([member EnemyIntent.target_rule_text]).
##
## A [GameTooltip] authored in the scene: [member heading_text] as its name, the rule as its body,
## at most 320 units wide at the HUD's scale whatever the camera's zoom; its origin is the enemy's
## tile centre, and it sits centred above it.
## [IntentDisplay] shows and hides it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The tooltip's name line, over the rule.[br]
## [b]Empty:[/b] only the rule shows.
@export var heading_text: String = "Target rule"

## How far above the enemy's tile centre the tooltip's bottom edge sits, clear of its token.[br]
## [b]Units:[/b] pixels on the board.
@export_range(0.0, 128.0, 1.0) var lift: float = 32.0

## The enemy whose rule shows; empty while hidden.
var enemy_id: String = ""

var _text: String = ""

@onready var _tip: GameTooltip = %Tip


func _ready() -> void:
	_tip.resized.connect(_on_tip_resized)
	hide_rule()


## Shows [param text], the rule of [param shown_id], at [param board_position], the enemy's tile
## centre in the board's space.
func show_rule(shown_id: String, text: String, board_position: Vector2) -> void:
	enemy_id = shown_id
	_text = text
	_tip.show_tip(heading_text, text)
	position = board_position
	_place_tip()
	visible = true


## Hides the tooltip.
func hide_rule() -> void:
	enemy_id = ""
	visible = false


## The text shown; empty while hidden.
func get_text() -> String:
	return _text if visible else ""


## The tooltip, for tests that read its lines and width.
func get_tip() -> GameTooltip:
	return _tip


# The tooltip sits centred above its anchor, however wide or tall the text makes it. It lives on
# the board, so it undoes the camera's zoom to draw at the HUD's size, its 320-unit cap included.
func _place_tip() -> void:
	var zoom: Vector2 = get_viewport().get_canvas_transform().get_scale() if is_inside_tree() else (
			Vector2.ONE
	)
	_tip.scale = Vector2(1.0 / maxf(zoom.x, 0.01), 1.0 / maxf(zoom.y, 0.01))
	var shown: Vector2 = _tip.size * _tip.scale
	_tip.position = Vector2(-shown.x * 0.5, -lift - shown.y)


# A wrapped tooltip refits a frame later; it stays centred above its anchor.
func _on_tip_resized() -> void:
	_place_tip()
