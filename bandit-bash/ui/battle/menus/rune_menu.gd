# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_menu.gd
# Author:
# Created:  November 16, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name RuneMenu
extends BattlePanel
## The runes the seat can cast now, one row each in slot order, with the focused rune's text under
## them, keywords marked ([EffectText]) (combat UI plan, UI13 row).
##
## Opened by [BattleController] through [PanelHost] from the action menu's Rune with an
## [code]Array[TurnInputModel.RuneOption][/code], each with at least one target
## ([method TurnInputModel.rune_options]). Focusing a row shows its text and emits
## [signal BattlePanel.highlighted] with its option; choosing one emits
## [signal BattlePanel.confirmed]. While a row holds key or pad focus, the text's keywords show as
## one column of tooltips beside the menu; with mouse focus, hovering a keyword shows its own. Rows
## are [member row_scene] instances; the rest is authored in the scene. It holds no rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The row placed for each rune: a [Button] scene.[br]
## [b]Unset:[/b] no rows are shown and an error is reported.
@export var row_scene: PackedScene = null

var _options: Array[TurnInputModel.RuneOption] = []
var _rows: Array[Button] = []

# The row that last had focus, which restore_focus() returns to.
var _last_focused: int = 0

# Whether the text shows its keyword column for key or pad focus on a row.
var _is_column_shown: bool = false

@onready var _row_box: VBoxContainer = %Rows
@onready var _text: EffectText = %RuneText


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_viewport_gui_focus_changed)
	visibility_changed.connect(_refresh_keywords)
	# The host's column moves the menu as panels stack; the keyword column follows.
	item_rect_changed.connect(_text.place_tooltips)


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


## The text shown under the rows: the focused rune's words, without keyword tags, for tests.
func get_text() -> String:
	return _text.get_plain_text()


## The focused rune's text as shown, for tests of its keywords and tooltip column.
func get_effect_text() -> EffectText:
	return _text


func _show_text(index: int) -> void:
	if index >= 0 and index < _options.size():
		_text.marked_text = _options[index].marked_text
	_refresh_keywords()


# Shows the text's keywords as one column beside the menu while a row holds key or pad focus, and
# hides it once none does; meanwhile a hovered keyword, already in the column, adds none. Rebuilds
# only when the text changed (its new text hid the column).
func _refresh_keywords() -> void:
	if not is_node_ready():
		return
	if not _has_key_focus():
		if _is_column_shown:
			_is_column_shown = false
			_text.hide_tooltips()
		return
	if _is_column_shown and (
			_text.get_shown_tooltips().size() == _text.get_keyword_ids().size()
	):
		return
	_text.show_all_keywords()
	_is_column_shown = true


# Whether a row of the shown menu holds focus a key or pad gave (not a click's hidden focus).
func _has_key_focus() -> bool:
	if not is_visible_in_tree():
		return false
	var row: Button = get_viewport().gui_get_focus_owner() as Button
	return row != null and _rows.has(row) and row.has_focus(true)


func _on_row_pressed(index: int) -> void:
	confirmed.emit(_options[index])


func _on_row_focus_entered(index: int) -> void:
	_last_focused = index
	_show_text(index)
	highlighted.emit(_options[index])


func _on_viewport_gui_focus_changed(_control: Control) -> void:
	_refresh_keywords()
