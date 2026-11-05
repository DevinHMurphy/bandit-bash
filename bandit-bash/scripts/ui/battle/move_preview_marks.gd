# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     move_preview_marks.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name MovePreviewMarks
extends Node2D
## The move preview on the board (combat UI plan, question 9): the darkness damage a unit would
## take ending its move on the hovered tile, as a number on that tile, and an [IntentChangeMark] on
## each enemy whose intent would change. Simple on purpose: UI4 draws the full intent display.
##
## A child of the board ([BattleView]), so positions are the board's
## ([method BattleView.tile_to_position]). [BattleController] calls [method show_preview] with a
## [MovePreview] and the positions it needs, and [method clear] when the preview no longer applies.
## Marks are [member mark_scene] instances, reused from hover to hover.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The mark placed over each enemy whose intent changes: an [IntentChangeMark] scene.[br]
## [b]Unset:[/b] no enemy is marked and an error is reported once.
@export var mark_scene: PackedScene = null

# ASSUMPTION: a dry tile shows nothing, so the number reads as a warning; no basis for either.
## Whether a tile the darkness doesn't touch shows a 0. Off: a dry tile shows no number.
@export var shows_zero: bool = false

## The number's text; [code]%d[/code] is the HP the darkness would take.
@export var damage_text: String = "-%d"

var _marks: Array[IntentChangeMark] = []
var _has_reported: bool = false
var _shown: MovePreview = null

@onready var _tile_mark: Node2D = %TileMark
@onready var _damage_label: Label = %DamageLabel


func _ready() -> void:
	clear()


## Shows [param preview]: its darkness damage at [param tile_position] and a mark at each of
## [param enemy_positions], one per [member MovePreview.changed_enemies] in the same order.
func show_preview(
		preview: MovePreview, tile_position: Vector2, enemy_positions: Array[Vector2]
) -> void:
	_shown = preview
	_tile_mark.position = tile_position
	_damage_label.text = damage_text % [preview.darkness_damage]
	_tile_mark.visible = preview.darkness_damage > 0 or shows_zero
	if mark_scene == null:
		if not _has_reported and not preview.changed_enemies.is_empty():
			push_error("MovePreviewMarks: no mark scene set")
			_has_reported = true
		return
	while _marks.size() < preview.changed_enemies.size():
		var added: IntentChangeMark = mark_scene.instantiate()
		add_child(added)
		_marks.append(added)
	for i: int in _marks.size():
		if i < preview.changed_enemies.size():
			_marks[i].show_for(preview.changed_enemies[i], enemy_positions[i])
		else:
			_marks[i].visible = false
			_marks[i].enemy_id = ""


## Hides every mark.
func clear() -> void:
	_shown = null
	if not is_node_ready():
		return
	_tile_mark.visible = false
	for mark: IntentChangeMark in _marks:
		mark.visible = false
		mark.enemy_id = ""


## The preview shown; null after [method clear].
func get_shown() -> MovePreview:
	return _shown


## The number on the tile, or empty when none shows, for tests.
func get_damage_text() -> String:
	return _damage_label.text if _tile_mark.visible else ""


## The enemies marked, in mark order, for tests.
func get_marked_enemies() -> PackedStringArray:
	var marked: PackedStringArray = []
	for mark: IntentChangeMark in _marks:
		if mark.visible:
			marked.append(mark.enemy_id)
	return marked
