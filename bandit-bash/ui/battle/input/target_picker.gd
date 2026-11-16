# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     target_picker.gd
# Author:
# Created:  November 4, 2026
# Modified: November 16, 2026
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
## list's current target ([method focus_row]) and also picks a target clicked on the board. A
## rune's refused units follow, greyed with their reason ([member Request.refused]): they take no
## focus and no press, so no device can pick them.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The row placed for each target: a [Button] scene.[br]
## [b]Unset:[/b] no rows are shown and an error is reported.
@export var row_scene: PackedScene = null

## A refused unit's row text: the first [code]%s[/code] its name, the second its reason, such as
## "Archer: has acted". Both must stay, in that order.
@export var refused_text: String = "%s: %s"

var _options: Array[TurnInputModel.TargetOption] = []
var _rows: Array[Button] = []
var _refused_rows: Array[Button] = []

# The row that last had focus, which restore_focus() returns to.
var _last_focused: int = 0

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
	_refused_rows.clear()
	for refused: TurnInputModel.TargetOption in request.refused:
		var row: Button = row_scene.instantiate()
		row.text = refused_text % [refused.label, refused.reason]
		row.disabled = true
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row_box.add_child(row)
		_refused_rows.append(row)
	BattlePanel.chain_focus(_rows)


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


## Focuses the row that last had focus, so a lost focus comes back on the current target rather
## than making the first target current.
func restore_focus() -> void:
	focus_row(clampi(_last_focused, 0, _rows.size() - 1))


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


## The refused units' greyed rows, after the targets', for tests.
func get_refused_rows() -> Array[Button]:
	return _refused_rows.duplicate()


func _on_row_pressed(index: int) -> void:
	confirmed.emit(_options[index])


func _on_row_focus_entered(index: int) -> void:
	_last_focused = index
	highlighted.emit(_options[index])


## What a target picker shows.
class Request:
	extends RefCounted

	## The heading: the action being aimed, such as "Attack".
	var title: String = ""
	## The targets, each with its legal command.
	var targets: Array[TurnInputModel.TargetOption] = []
	## A rune's refused units, shown greyed with their reason after the targets; empty for an
	## action ([member TurnInputModel.RuneOption.refused]).
	var refused: Array[TurnInputModel.TargetOption] = []
