# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     target_picker.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name TargetPicker
extends BattlePanel
## The targets a chosen action can be aimed at, one row each (combat UI plan, question 6).
##
## Opened by [BattleController] through [PanelHost] with an
## [code]Array[TurnInputModel.TargetOption][/code], each target's command already legal. Focusing
## a row emits [signal BattlePanel.highlighted] with its option, so the board cursor follows the
## keyboard; choosing one emits [signal BattlePanel.confirmed]. Rows are [member row_scene]
## instances, one per target, in the [TargetList]'s order; the controller keeps the focus on the
## list's current target ([method focus_row]) and also picks a target clicked on the board.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The row placed for each target: a [Button] scene.[br]
## [b]Unset:[/b] no rows are shown and an error is reported.
@export var row_scene: PackedScene = null

var _options: Array[TurnInputModel.TargetOption] = []
var _rows: Array[Button] = []

@onready var _title: Label = %Title
@onready var _row_box: VBoxContainer = %Rows


## [param payload]: a [TargetPicker.Request].
func open_with(payload: Variant) -> void:
	var request: Request = payload
	_title.text = request.title
	_options.assign(request.targets)
	_rows.clear()
	if row_scene == null:
		push_error("TargetPicker: no row scene set")
		return
	for i: int in _options.size():
		var row: Button = row_scene.instantiate()
		row.text = _options[i].label
		row.pressed.connect(_on_row_pressed.bind(i))
		row.focus_entered.connect(_on_row_focus_entered.bind(i))
		_row_box.add_child(row)
		_rows.append(row)
	BattlePanel.chain_focus(_rows)


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


## Focuses row [param index], so accept presses it: the controller keeps the focused row on the
## current target of its [TargetList] as Q / E and the mouse move it. Focusing emits
## [signal BattlePanel.highlighted] as the keyboard does. Does nothing out of range.
func focus_row(index: int) -> void:
	if index >= 0 and index < _rows.size() and not _rows[index].has_focus():
		_rows[index].grab_focus()


## The targets listed, in row order.
func get_options() -> Array[TurnInputModel.TargetOption]:
	return _options.duplicate()


## The rows, for tests that press them.
func get_rows() -> Array[Button]:
	return _rows.duplicate()


func _on_row_pressed(index: int) -> void:
	confirmed.emit(_options[index])


func _on_row_focus_entered(index: int) -> void:
	highlighted.emit(_options[index])


## What a target picker shows.
class Request:
	extends RefCounted

	## The heading: the action being aimed, such as "Attack".
	var title: String = ""
	## The targets, each with its legal command.
	var targets: Array[TurnInputModel.TargetOption] = []
