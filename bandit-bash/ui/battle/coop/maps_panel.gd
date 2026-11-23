# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     maps_panel.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name MapsPanel
extends PanelContainer
## A co-op battle's maps, as one seat sees them: a [MapStatusRow] per map (its own first), whose
## press views that map; under them the seat's call for aid ([AidButton], while its map is
## fought), Send units (while it may send) and Close. Opened by [CoopBattle], which holds turn
## input off meanwhile and acts on what it asks. Viewing a map where the seat has no units is
## read-only, since the rules refuse every command there; one where they stand is played.
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI unless noted):
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick   (focus between the rows and buttons)
#   "ui_accept"            -> Enter, Space; pad A [Cross] (press the focused row or button)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (read in _input while shown,
#                             before the pause menu: close, as Close does)
#   Mouse: a click on a row or button.
# Hint context: MAPS ([CoopBattle.LIVE_ACTIONS]).
# ============================================================

## A row was pressed: view the map [param session_id].
signal view_requested(session_id: int)

## The call for aid was pressed: [param is_raised] the flag asked for.
signal aid_requested(is_raised: bool)

## Send units was pressed.
signal send_requested()

## Close or Back was pressed.
signal closed()

## The row scene ([MapStatusRow]).[br]
## [b]Unset:[/b] no map rows show and an error is reported.
@export var row_scene: PackedScene = preload("res://ui/battle/coop/map_status_row.tscn")

@onready var _rows: VBoxContainer = %Rows
@onready var _aid_button: AidButton = %AidButton
@onready var _send_button: Button = %SendButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_aid_button.aid_requested.connect(_on_aid_button_aid_requested)
	_send_button.pressed.connect(_on_send_button_pressed)
	_close_button.pressed.connect(_on_close_button_pressed)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()


## Shows [param maps] (the seat's own first), [param viewed_id] the map viewed now; the seat's
## call for aid as [param is_aid_raised] while [param is_own_open] (its map still fought),
## disabled while [param is_aid_waiting]; Send units while [param can_send]. Rows are rebuilt;
## focus is kept on the row or button it was on, else goes to the viewed map's row.
func show_maps(
		maps: Array[CoopViewModel.MapStatus],
		viewed_id: int,
		is_aid_raised: bool,
		is_own_open: bool,
		is_aid_waiting: bool,
		can_send: bool
) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_map: int = -1
	if focused != null and _rows.is_ancestor_of(focused) and focused.get_parent() is MapStatusRow:
		focused_map = (focused.get_parent() as MapStatusRow).session_id
	_build_rows(maps.size())
	for i: int in maps.size():
		var row: MapStatusRow = _rows.get_child(i) as MapStatusRow
		row.show_status(maps[i], maps[i].session_id == viewed_id)
	_aid_button.show_flag(is_aid_raised, is_own_open, is_aid_waiting)
	_send_button.visible = can_send
	visible = true
	_link_focus()
	if focused_map >= 0:
		_focus_map(focused_map)
	elif focused == null or not is_ancestor_of(focused) or not focused.is_visible_in_tree():
		_focus_map(viewed_id)


## Hides the panel and gives up focus.
func close() -> void:
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	visible = false


## Every map row, in order, for tests.
func get_rows() -> Array[MapStatusRow]:
	var found: Array[MapStatusRow] = []
	for child: Node in _rows.get_children():
		if child is MapStatusRow and not child.is_queued_for_deletion():
			found.append(child as MapStatusRow)
	return found


## The call for aid, for tests.
func get_aid_button() -> AidButton:
	return _aid_button


## Send units, for tests.
func get_send_button() -> Button:
	return _send_button


## Close, for tests.
func get_close_button() -> Button:
	return _close_button


# Keeps exactly count rows, adding and freeing at the end.
func _build_rows(count: int) -> void:
	if row_scene == null:
		push_error("MapsPanel: no row scene")
		return
	while _rows.get_child_count() > count:
		var last: Node = _rows.get_child(_rows.get_child_count() - 1)
		_rows.remove_child(last)
		last.queue_free()
	while _rows.get_child_count() < count:
		var row: MapStatusRow = row_scene.instantiate() as MapStatusRow
		_rows.add_child(row)
		row.pressed.connect(_on_row_pressed)


# Links focus in a fixed order: down the rows, then to the first button shown, which sit side by
# side; up from a button to the last row. Geometry alone could skip a row or a button.
func _link_focus() -> void:
	var buttons: Array[Button] = []
	for button: Button in [_aid_button, _send_button, _close_button]:
		if button.visible:
			buttons.append(button)
	var rows: Array[MapStatusRow] = get_rows()
	for i: int in rows.size():
		var button: Button = rows[i].get_button()
		var below: Control = rows[i + 1].get_button() if i + 1 < rows.size() else buttons[0]
		var above: Control = rows[i - 1].get_button() if i > 0 else button
		button.focus_neighbor_bottom = button.get_path_to(below)
		button.focus_neighbor_top = button.get_path_to(above)
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
	var last_row: Control = rows[rows.size() - 1].get_button() if not rows.is_empty() else null
	for i: int in buttons.size():
		var button: Button = buttons[i]
		var left: Button = buttons[i - 1] if i > 0 else button
		var right: Button = buttons[i + 1] if i + 1 < buttons.size() else button
		button.focus_neighbor_left = button.get_path_to(left)
		button.focus_neighbor_right = button.get_path_to(right)
		button.focus_neighbor_bottom = button.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(last_row if last_row != null else button)


# Focuses the row of session_id, else the first focusable control.
func _focus_map(session_id: int) -> void:
	for row: MapStatusRow in get_rows():
		if row.session_id == session_id:
			row.get_button().grab_focus()
			return
	var rows: Array[MapStatusRow] = get_rows()
	if not rows.is_empty():
		rows[0].get_button().grab_focus()
	else:
		_close_button.grab_focus()


func _on_row_pressed(session_id: int) -> void:
	view_requested.emit(session_id)


func _on_aid_button_aid_requested(is_raised: bool) -> void:
	aid_requested.emit(is_raised)


func _on_send_button_pressed() -> void:
	send_requested.emit()


func _on_close_button_pressed() -> void:
	closed.emit()
