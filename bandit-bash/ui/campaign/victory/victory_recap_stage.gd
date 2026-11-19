# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     victory_recap_stage.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name VictoryRecapStage
extends Control
## The victory's second stage: a [UnitRecapRow] per unit (the standing ones in roster order, then
## the fallen), their XP bars filling one after another, then each level-up on a [LevelUpCard]
## over the list, in the order reached.
##
## The [VictoryOverlay] drives it: [method begin_fill], then [method step] with playback time each
## frame, [method finish_fill] to skip, [method show_level_up] per level-up. The rows take focus in
## one column, so its scroll follows a pad; the last row leads down to the overlay's button
## ([method link_focus]). Reads no input itself.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

const ROW_SCENE: PackedScene = preload("res://ui/campaign/victory/unit_recap_row.tscn")

var _model: CombatResultsModel = null

# The row whose bar fills now; -1 when no fill plays.
var _filling: int = -1

@onready var _scroll: ScrollContainer = %Scroll
@onready var _rows: VBoxContainer = %Rows
@onready var _card: LevelUpCard = %LevelUpCard


func _ready() -> void:
	_card.visible = false


## Shows a row per unit of [param model], each bar still at the XP it has now.
func show_recap(model: CombatResultsModel) -> void:
	_model = model
	_filling = -1
	_card.visible = false
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for line: CombatResultsModel.XpLine in model.xp_lines + model.fallen_lines:
		var row: UnitRecapRow = ROW_SCENE.instantiate()
		_rows.add_child(row)
		row.show_line(line, model.xp_per_level)


## Sets every bar back to its XP before the combat and starts the first fill.
func begin_fill() -> void:
	for row: UnitRecapRow in get_rows():
		row.prepare_fill(_model.xp_per_level)
	_filling = _next_bar(-1)


## Plays [param delta] seconds of playback time on the bar filling now, then the next; returns
## whether any fill still plays.
func step(delta: float) -> bool:
	if _filling < 0:
		return false
	var rows: Array[UnitRecapRow] = get_rows()
	if not rows[_filling].get_xp_bar().step(delta):
		_filling = _next_bar(_filling)
	return _filling >= 0


## Ends every fill at once, each bar at the XP its unit has now.
func finish_fill() -> void:
	for row: UnitRecapRow in get_rows():
		if row.get_line() != null and row.get_line().award != null:
			row.get_xp_bar().finish()
	_filling = -1


## Whether a fill plays.
func is_filling() -> bool:
	return _filling >= 0


## Shows the [param index]-th level-up (from 0) over the list; false when there is no such one.
func show_level_up(index: int) -> bool:
	if _model == null or index < 0 or index >= _model.level_up_lines.size():
		_card.visible = false
		return false
	_card.show_level_up(_model.level_up_lines[index], index, _model.level_up_lines.size())
	_card.visible = true
	return true


## Hides the level-up card.
func hide_level_up() -> void:
	_card.visible = false


## The level-up card, for tests.
func get_level_up_card() -> LevelUpCard:
	return _card


## The rows shown, in order.
func get_rows() -> Array[UnitRecapRow]:
	var rows: Array[UnitRecapRow] = []
	for child: Node in _rows.get_children():
		if child is UnitRecapRow and not child.is_queued_for_deletion():
			rows.append(child as UnitRecapRow)
	return rows


## The list's scroll, for tests.
func get_scroll() -> ScrollContainer:
	return _scroll


## Links the rows as one column: up and down step along it, the last row's down goes to
## [param below] and [param below]'s up to the last row; left and right stay put.
func link_focus(below: Control) -> void:
	var rows: Array[UnitRecapRow] = get_rows()
	for i: int in rows.size():
		var row: UnitRecapRow = rows[i]
		var self_path: NodePath = row.get_path_to(row)
		row.focus_neighbor_top = row.get_path_to(rows[maxi(i - 1, 0)])
		row.focus_neighbor_bottom = (
				row.get_path_to(below) if i == rows.size() - 1 else row.get_path_to(rows[i + 1])
		)
		row.focus_neighbor_left = self_path
		row.focus_neighbor_right = self_path
		row.focus_previous = row.focus_neighbor_top
		row.focus_next = row.focus_neighbor_bottom
	if not rows.is_empty():
		below.focus_neighbor_top = below.get_path_to(rows[rows.size() - 1])


# The first row after index whose bar fills; -1 when none.
func _next_bar(index: int) -> int:
	var rows: Array[UnitRecapRow] = get_rows()
	for i: int in range(index + 1, rows.size()):
		if rows[i].get_line() != null and rows[i].get_line().award != null:
			return i
	return -1
