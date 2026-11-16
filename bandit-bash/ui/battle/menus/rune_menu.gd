# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_menu.gd
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================

class_name RuneMenu
extends BattlePanel
## The runes the seat can cast now, one row each in slot order, with the focused rune's text under
## them (combat UI plan, UI13 row).
##
## Opened by [BattleController] through [PanelHost] from the action menu's Rune with an
## [code]Array[TurnInputModel.RuneOption][/code], each with at least one target
## ([method TurnInputModel.rune_options]). Focusing a row shows its text and emits
## [signal BattlePanel.highlighted] with its option; choosing one emits
## [signal BattlePanel.confirmed]. Rows are [member row_scene] instances; the rest is authored in
## the scene. It holds no rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The row placed for each rune: a [Button] scene.[br]
## [b]Unset:[/b] no rows are shown and an error is reported.
@export var row_scene: PackedScene = null

var _options: Array[TurnInputModel.RuneOption] = []
var _rows: Array[Button] = []

# The row that last had focus, which restore_focus() returns to.
var _last_focused: int = 0

@onready var _row_box: VBoxContainer = %Rows
@onready var _text: Label = %RuneText


## [param payload]: the [code]Array[TurnInputModel.RuneOption][/code] to list.
func open_with(payload: Variant) -> void:
	var listed: Array = payload
	_options.assign(listed)
	_rows.clear()
	if row_scene == null:
		push_error("RuneMenu: no row scene set")
		return
	for i: int in _options.size():
		var row: Button = row_scene.instantiate()
		row.text = _options[i].label
		row.pressed.connect(_on_row_pressed.bind(i))
		row.focus_entered.connect(_on_row_focus_entered.bind(i))
		_row_box.add_child(row)
		_rows.append(row)
	BattlePanel.chain_focus(_rows)
	_show_text(0)


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


## Focuses the row that last had focus, so a lost focus comes back on the rune shown.
func restore_focus() -> void:
	if not _rows.is_empty():
		_rows[clampi(_last_focused, 0, _rows.size() - 1)].grab_focus()


## The runes listed, in row order.
func get_options() -> Array[TurnInputModel.RuneOption]:
	return _options.duplicate()


## The rows, for tests that press them.
func get_rows() -> Array[Button]:
	return _rows.duplicate()


## The text shown under the rows: the focused rune's, for tests.
func get_text() -> String:
	return _text.text


func _show_text(index: int) -> void:
	if index >= 0 and index < _options.size():
		_text.text = _options[index].text


func _on_row_pressed(index: int) -> void:
	confirmed.emit(_options[index])


func _on_row_focus_entered(index: int) -> void:
	_last_focused = index
	_show_text(index)
	highlighted.emit(_options[index])
