# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     team_panel.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name TeamPanel
extends Control
## A co-op run's teammates, over the campaign screen that opened it on request: a [TeammateRow]
## per seat but the screen's own, each with their gold, army and heirlooms as the run saved them,
## then Close. Reading only; the dimmed backdrop takes every click outside the panel.
##
## The screen calls [method open] from its Team button and [method refresh] after any batch while
## it shows. It sets [member hints]' context to TEAM while open, TEAM_HEIRLOOMS while a row's
## heirlooms have focus, and gives back the context and the focus it found when it closes.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions):
#   "ui_up" / "ui_down" -> arrows; d-pad, left stick   (through the GUI: along the rows and Close;
#                          the ends stop)
#   "ui_accept"         -> Enter, Space; pad A [Cross] (through the GUI: a row's heirlooms, or
#                          Close)
#   "ui_cancel"         -> Esc; pad B [Circle], Menu [Options] (read in _input while shown: closes,
#                          after a row with focus on its heirlooms has taken it; taken first, so
#                          the pause menu doesn't open over the panel)
#   Mouse: clicks on the rows' buttons and Close; hovering a heirloom shows its tooltip.
# ============================================================

## The panel closed.
signal closed()

## The hint context while the rows show.
const HINT_TEAM: StringName = &"TEAM"

## The hint context while a row's heirlooms have focus.
const HINT_HEIRLOOMS: StringName = &"TEAM_HEIRLOOMS"

const ROW_SCENE: PackedScene = preload("res://ui/campaign/teammate_row.tscn")

## How dark the backdrop over the screen is.[br]
## [b]0.0:[/b] no dimming; [b]1.0:[/b] the screen hidden. 0.6 matches the [ArmyView]'s.
@export_range(0.0, 1.0, 0.05) var backdrop_alpha: float = 0.6

## The screen's hints, whose context follows the panel. [b]Unset:[/b] the hints stay as they are.
@export var hints: ScreenHints = null

var _session: CampaignSession = null
var _seat: int = CampaignData.HOST_SEAT
var _notes: Dictionary[int, String] = {}
# The hint context and the focus found at open(), given back at close().
var _context_before: StringName = &""
var _focus_before: Control = null

@onready var _backdrop: ColorRect = %Backdrop
@onready var _rows: VBoxContainer = %Rows
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, backdrop_alpha)
	_close_button.pressed.connect(close)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	close()


## Opens over the screen with every teammate of seat [param seat] in [param session]'s run,
## [param notes] (by seat) under their heirlooms, focusing the first row.
func open(
		session: CampaignSession, seat: int, notes: Dictionary[int, String] = {}
) -> void:
	_session = session
	_seat = seat
	_notes = notes.duplicate()
	_focus_before = get_viewport().gui_get_focus_owner()
	if hints != null:
		_context_before = hints.context
		hints.context = HINT_TEAM
	visible = true
	refresh()
	var rows: Array[TeammateRow] = get_rows()
	(rows[0].get_name_button() if not rows.is_empty() else _close_button).grab_focus()


## Shows the run as saved again, [param notes] (by seat) replacing the rows' notes when given.
## Keeps focus on the same row. Does nothing while closed.
func refresh(notes: Dictionary[int, String] = {}) -> void:
	if not visible or _session == null or _session.run == null:
		return
	if not notes.is_empty():
		_notes = notes.duplicate()
	var focused: int = _focused_row()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	for seat: int in _session.seats:
		if seat == _seat:
			continue
		var note: String = _notes.get(seat, "")
		var row: TeammateRow = ROW_SCENE.instantiate()
		_rows.add_child(row)
		row.show_seat(_session.run, seat, catalog, note)
		row.heirlooms_opened.connect(_on_row_heirlooms_opened)
		row.heirlooms_closed.connect(_on_row_heirlooms_closed)
	_link_column()
	var rows: Array[TeammateRow] = get_rows()
	if focused >= 0 and focused < rows.size():
		rows[focused].get_name_button().grab_focus()


## Hides the panel, gives back the focus and hint context it found, and reports [signal closed].
func close() -> void:
	if not visible:
		return
	visible = false
	if hints != null:
		hints.context = _context_before
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null
	closed.emit()


## Each teammate's row, in seat order, for tests.
func get_rows() -> Array[TeammateRow]:
	var found: Array[TeammateRow] = []
	for child: Node in _rows.get_children():
		if child is TeammateRow and not child.is_queued_for_deletion():
			found.append(child as TeammateRow)
	return found


## The Close button, for tests.
func get_close_button() -> Button:
	return _close_button


# The index of the row whose button has focus; -1 for none.
func _focused_row() -> int:
	var rows: Array[TeammateRow] = get_rows()
	for i: int in rows.size():
		if rows[i].get_name_button().has_focus():
			return i
	return -1


# The rows' buttons and Close as one column: up and down, the ends stop; left and right stay.
func _link_column() -> void:
	var column: Array[Button] = []
	for row: TeammateRow in get_rows():
		column.append(row.get_name_button())
	column.append(_close_button)
	for i: int in column.size():
		var button: Button = column[i]
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = self_path
		button.focus_neighbor_right = self_path


func _on_row_heirlooms_opened() -> void:
	if hints != null:
		hints.context = HINT_HEIRLOOMS


func _on_row_heirlooms_closed() -> void:
	if hints != null and visible:
		hints.context = HINT_TEAM
