# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_panel.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SwapPanel
extends Control
## The viewer's co-op unit swaps, over the campaign map that opened it from the army view: a
## [SwapRow] per teammate, then Close. Propose opens the [SwapPicker] (the viewer's unit, then
## the teammate's); a proposal made to the viewer is accepted or declined; the viewer's own
## proposal, or an accepted swap, is withdrawn. Only asks: [signal command_ready] goes to the
## screen, which sends it; the screen calls [method refresh] after any batch and
## [method show_refusal] with the reason of a refused one, shown with the teammate named
## ([method SwapText.refusal]). Sets [member hints]' context while open and gives back the
## context and focus it found when it closes.
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions):
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick   (through the GUI: between the rows and
#                             Close, or the picker's units and Back; the ends stop)
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick   (through the GUI: between a row's
#                             buttons, such as Accept and Decline; the ends stop)
#   "ui_accept"            -> Enter, Space; pad A [Cross] (through the GUI: press the focused
#                             button)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (read in _input while shown:
#                             the picker steps back, else the panel closes; taken first, so the
#                             army view under it and the pause menu don't see it)
#   Mouse: clicks on every button; the backdrop takes clicks outside the panel.
# ============================================================

## The viewer chose a swap command; the screen sends it.
signal command_ready(command: CampaignCommand)

## The panel closed.
signal closed()

## The hint context while the panel shows.
const HINT_SWAPS: StringName = &"SWAPS"

const ROW_SCENE: PackedScene = preload("res://ui/campaign/swap_row.tscn")

## How dark the backdrop over the screen is.[br]
## [b]0.0:[/b] no dimming; [b]1.0:[/b] the screen hidden. 0.6 matches the [TeamPanel]'s.
@export_range(0.0, 1.0, 0.05) var backdrop_alpha: float = 0.6

## The screen's hints, whose context follows the panel. [b]Unset:[/b] the hints stay as they are.
@export var hints: ScreenHints = null

var _session: CampaignSession = null
var _seat: int = CampaignData.HOST_SEAT
# The teammate of the last command chosen here, named by a refusal of it.
var _acting_partner: int = -1
var _context_before: StringName = &""
var _focus_before: Control = null

@onready var _backdrop: ColorRect = %Backdrop
@onready var _rows: VBoxContainer = %Rows
@onready var _picker: SwapPicker = %SwapPicker
@onready var _status_label: Label = %Status
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_picker.visible = false
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, backdrop_alpha)
	_close_button.pressed.connect(close)
	_picker.picked.connect(_on_picker_picked)
	_picker.cancelled.connect(_on_picker_cancelled)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _picker.visible:
		_picker.back()
		return
	close()


## Opens over the screen with every teammate of seat [param seat] in [param session]'s run,
## focusing the first row.
func open(session: CampaignSession, seat: int) -> void:
	_session = session
	_seat = seat
	_acting_partner = -1
	_status_label.text = ""
	_focus_before = get_viewport().gui_get_focus_owner()
	if hints != null:
		_context_before = hints.context
		hints.context = HINT_SWAPS
	_picker.visible = false
	_rows.visible = true
	visible = true
	refresh()
	_focus_row(0)


## Shows the run as it is now, keeping focus on the same row. While the picker shows it stays as
## it is, so a choice made against what it showed is sent and refused with its reason. Does
## nothing while closed.
func refresh() -> void:
	if not visible or _session == null or _session.run == null:
		return
	var focused: int = _focused_row()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	for partner: int in _session.run.seat_numbers():
		if partner == _seat:
			continue
		var row: SwapRow = ROW_SCENE.instantiate()
		_rows.add_child(row)
		row.show_swap(_session.run, _seat, partner, catalog)
		row.propose_pressed.connect(_on_row_propose_pressed)
		row.answer_pressed.connect(_on_row_answer_pressed)
		row.withdraw_pressed.connect(_on_row_withdraw_pressed)
	_link_rows()
	if focused >= 0 and not _picker.visible:
		_focus_row(focused)


## Shows the refusal of the last command chosen here, its [param reason] as [CampaignLink] names
## seats, with the teammate and units named.
func show_refusal(reason: String) -> void:
	if _session == null or _session.run == null:
		return
	_status_label.text = SwapText.refusal(
			reason, _session.run, _seat, _acting_partner, EffectCatalog.index()
	)


## Hides the panel, gives back the focus and hint context it found, and reports [signal closed].
func close() -> void:
	if not visible:
		return
	visible = false
	_picker.visible = false
	if hints != null:
		hints.context = _context_before
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null
	closed.emit()


## Each teammate's row, in seat order, for tests.
func get_rows() -> Array[SwapRow]:
	var found: Array[SwapRow] = []
	for child: Node in _rows.get_children():
		if child is SwapRow and not child.is_queued_for_deletion():
			found.append(child as SwapRow)
	return found


## The row of teammate [param partner]; null when there is none.
func get_row(partner: int) -> SwapRow:
	for row: SwapRow in get_rows():
		if row.partner == partner:
			return row
	return null


## The picker, for tests.
func get_picker() -> SwapPicker:
	return _picker


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


## The Close button, for tests.
func get_close_button() -> Button:
	return _close_button


# Gives focus to row index's first button, else the last row's, else Close.
func _focus_row(index: int) -> void:
	var rows: Array[SwapRow] = get_rows()
	if rows.is_empty():
		_close_button.grab_focus()
		return
	rows[clampi(index, 0, rows.size() - 1)].get_buttons()[0].grab_focus()


# The index of the row holding the focus; -1 for none.
func _focused_row() -> int:
	var rows: Array[SwapRow] = get_rows()
	for i: int in rows.size():
		for button: Button in rows[i].get_buttons():
			if button.has_focus():
				return i
	return -1


# Up and down move between the rows' first buttons and Close, the ends stopping; left and right
# move along a row's buttons, the ends stopping. Close's left and right stay.
func _link_rows() -> void:
	var lines: Array[Array] = []
	for row: SwapRow in get_rows():
		lines.append(row.get_buttons())
	lines.append([_close_button])
	for i: int in lines.size():
		var line: Array = lines[i]
		var above: Button = lines[maxi(i - 1, 0)][0]
		var below: Button = lines[mini(i + 1, lines.size() - 1)][0]
		for j: int in line.size():
			var button: Button = line[j]
			var left: Button = line[maxi(j - 1, 0)]
			var right: Button = line[mini(j + 1, line.size() - 1)]
			button.focus_neighbor_top = button.get_path_to(above)
			button.focus_neighbor_bottom = button.get_path_to(below)
			button.focus_neighbor_left = button.get_path_to(left)
			button.focus_neighbor_right = button.get_path_to(right)
			button.focus_previous = button.focus_neighbor_top
			button.focus_next = button.focus_neighbor_bottom


func _on_row_propose_pressed(partner: int) -> void:
	_acting_partner = partner
	_status_label.text = ""
	_rows.visible = false
	_picker.visible = true
	_picker.start(_session.run, _seat, partner, EffectCatalog.index())


func _on_row_answer_pressed(
		partner: int, accepts: bool, partner_unit: String, own_unit: String
) -> void:
	_acting_partner = partner
	_status_label.text = ""
	command_ready.emit(AnswerSwapCommand.new(_seat, partner, accepts, partner_unit, own_unit))


func _on_row_withdraw_pressed(partner: int) -> void:
	_acting_partner = partner
	_status_label.text = ""
	command_ready.emit(WithdrawSwapCommand.new(_seat, partner))


func _on_picker_picked(own_unit: String, partner_unit: String) -> void:
	var partner: int = _picker.get_partner()
	_picker.visible = false
	_rows.visible = true
	refresh()
	_focus_row(get_rows().find(get_row(partner)))
	command_ready.emit(ProposeSwapCommand.new(_seat, own_unit, partner, partner_unit))


func _on_picker_cancelled() -> void:
	var partner: int = _picker.get_partner()
	_picker.visible = false
	_rows.visible = true
	refresh()
	_focus_row(get_rows().find(get_row(partner)))
