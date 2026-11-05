# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     move_preview_marks.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name MovePreviewMarks
extends Node2D
## The move preview's darkness damage on the board (combat UI plan, question 9): the HP a unit
## would lose ending its move on the hovered tile, as a number on that tile. The same preview's
## re-planned intents are the [IntentDisplay]'s.
##
## A child of the board ([BattleView]), so positions are the board's
## ([method BattleView.tile_to_position]). [BattleController] calls [method show_preview] with a
## [MovePreview] and the tile's position, and [method clear] when the preview no longer applies.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: a dry tile shows nothing, so the number reads as a warning; no basis for either.
## Whether a tile the darkness doesn't touch shows a 0. Off: a dry tile shows no number.
@export var shows_zero: bool = false

## The number's text; [code]%d[/code] is the HP the darkness would take.
@export var damage_text: String = "-%d"

var _shown: MovePreview = null

@onready var _tile_mark: Node2D = %TileMark
@onready var _damage_label: Label = %DamageLabel


func _ready() -> void:
	clear()


## Shows [param preview]'s darkness damage at [param tile_position], the tile's centre in the
## board's space.
func show_preview(preview: MovePreview, tile_position: Vector2) -> void:
	_shown = preview
	_tile_mark.position = tile_position
	_damage_label.text = damage_text % [preview.darkness_damage]
	_tile_mark.visible = preview.darkness_damage > 0 or shows_zero


## Hides the number.
func clear() -> void:
	_shown = null
	if not is_node_ready():
		return
	_tile_mark.visible = false


## The preview shown; null after [method clear].
func get_shown() -> MovePreview:
	return _shown


## The number on the tile, or empty when none shows, for tests.
func get_damage_text() -> String:
	return _damage_label.text if _tile_mark.visible else ""
