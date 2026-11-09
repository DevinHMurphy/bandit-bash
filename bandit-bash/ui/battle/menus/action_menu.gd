# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     action_menu.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name ActionMenu
extends BattlePanel
## The actions a unit can take on the tile it is moving to, one row each, in menu order (combat UI
## plan, question 6).
##
## Opened by [BattleController] through [PanelHost] with an
## [code]Array[TurnInputModel.ActionOption][/code], which lists only legal actions
## ([method TurnInputModel.actions_at]). Choosing a row emits [signal BattlePanel.confirmed] with
## its option. Rows are [member row_scene] instances, one per action.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The row placed for each action: a [Button] scene.[br]
## [b]Unset:[/b] no rows are shown and an error is reported.
@export var row_scene: PackedScene = null

var _options: Array[TurnInputModel.ActionOption] = []
var _rows: Array[Button] = []

@onready var _row_box: VBoxContainer = %Rows


## [param payload]: the [code]Array[TurnInputModel.ActionOption][/code] to list.
func open_with(payload: Variant) -> void:
	var listed: Array = payload
	_options.assign(listed)
	_rows.clear()
	if row_scene == null:
		push_error("ActionMenu: no row scene set")
		return
	for i: int in _options.size():
		var row: Button = row_scene.instantiate()
		row.text = _options[i].label
		row.pressed.connect(_on_row_pressed.bind(i))
		_row_box.add_child(row)
		_rows.append(row)
	BattlePanel.chain_focus(_rows)


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


## The options listed, in row order.
func get_options() -> Array[TurnInputModel.ActionOption]:
	return _options.duplicate()


## The rows, for tests that press them.
func get_rows() -> Array[Button]:
	return _rows.duplicate()


func _on_row_pressed(index: int) -> void:
	confirmed.emit(_options[index])
