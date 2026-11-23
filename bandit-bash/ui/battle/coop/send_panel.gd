# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     send_panel.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SendPanel
extends PanelContainer
## A co-op winner's send ([SendUnitsCommand]): the units it could send ([SendUnitRow]s, none
## picked at first), every map with its status ([MapStatusRow]s, one picked as the target), and
## Send, Send none and Close. While any map is frozen its [FrozenBanner] states the rule, Send none
## hides and only frozen maps can be picked. Send and Send none each ask first, since both are
## final, naming the units, the map and the turn they land at ([method CoopViewModel.arrival_turn]).
## [CoopBattle] opens it, holds turn input off, and sends what it confirms; the encounter checks it
## again when it resolves. Units on another won map than the seat's own go from there, so picking
## one drops picks from any other map.
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI unless noted):
#   "ui_up" / "ui_down" /   -> arrows; d-pad, left  (focus between the rows and buttons; the
#   "ui_left" / "ui_right"     stick                   buttons sit side by side)
#   "ui_accept"             -> Enter, Space; pad A   (a unit row: pick or drop it; a map row: pick
#                              [Cross]                 it; a button: press it)
#   "ui_cancel"             -> Esc; pad B [Circle],  (read in _input while shown, before the pause
#                              Menu [Options]          menu: from the question, back to the picks;
#                                                      from the picks, close, as Close does)
#   Mouse: a click on a row or button; the wheel scrolls the unit list.
# Hint contexts: SEND, SEND_CONFIRM ([CoopBattle.LIVE_ACTIONS]).
# ============================================================

## The seat confirmed a send: [param unit_ids] from the won map [param source_id] to the map
## [param target_id]; no units and [constant SendUnitsCommand.NO_TARGET] for Send none.
signal send_confirmed(unit_ids: PackedStringArray, source_id: int, target_id: int)

## Close, or Back from the picks, was pressed.
signal closed()

# ASSUMPTION: the panel's wordings; no design doc words them.
const _PICK_HINT: String = "Pick units, then one map to send them to."
const _NONE_QUESTION: String = "Send no units? You can't send later, unless a map freezes."
const _SENDING: String = "Sending…"

## The unit row scene ([SendUnitRow]).[br]
## [b]Unset:[/b] no unit rows show and an error is reported.
@export var unit_row_scene: PackedScene = preload("res://ui/battle/coop/send_unit_row.tscn")

## The map row scene ([MapStatusRow]).[br]
## [b]Unset:[/b] no map rows show and an error is reported.
@export var map_row_scene: PackedScene = preload("res://ui/battle/coop/map_status_row.tscn")

## The tallest the unit list grows before it scrolls, so the panel fits at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] the list never shows a row.
@export_range(0.0, 600.0, 1.0) var max_unit_list_height: float = 160.0

## One unit row's height in the list, for its size.[br]
## [b]Units:[/b] base units.
@export_range(16.0, 80.0, 1.0) var unit_row_height: float = 40.0

var _encounter: CombatEncounter = null
var _seat: int = -1
var _picked: PackedStringArray = []
var _source_id: int = -1
var _target_id: int = SendUnitsCommand.NO_TARGET
# The send asked about on the question page: units, source, target.
var _asked_units: PackedStringArray = []
var _asked_source: int = -1
var _asked_target: int = SendUnitsCommand.NO_TARGET
var _is_sending: bool = false

@onready var _rule: FrozenBanner = %Rule
@onready var _pick_page: Control = %PickPage
@onready var _unit_scroll: ScrollContainer = %UnitScroll
@onready var _unit_rows: VBoxContainer = %UnitRows
@onready var _map_rows: VBoxContainer = %MapRows
@onready var _status: Label = %Status
@onready var _send_button: Button = %SendButton
@onready var _none_button: Button = %SendNoneButton
@onready var _close_button: Button = %CloseButton
@onready var _confirm_page: Control = %ConfirmPage
@onready var _question: Label = %Question
@onready var _confirm_button: Button = %ConfirmButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	visible = false
	_send_button.pressed.connect(_on_send_button_pressed)
	_none_button.pressed.connect(_on_send_none_button_pressed)
	_close_button.pressed.connect(_on_close_button_pressed)
	_confirm_button.pressed.connect(_on_confirm_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _confirm_page.visible:
		_show_picks()
	else:
		closed.emit()


## Opens on [param seat]'s send in [param encounter], nothing picked, focus on the first row.
func open(encounter: CombatEncounter, seat: int) -> void:
	_encounter = encounter
	_seat = seat
	_picked = []
	_source_id = -1
	_target_id = SendUnitsCommand.NO_TARGET
	_is_sending = false
	_status.text = _PICK_HINT
	visible = true
	refresh()
	_show_picks()


## Reads the encounter again, keeping each pick that is still allowed; called as the battle moves.
func refresh() -> void:
	if _encounter == null or not visible:
		return
	var units: Array[CoopViewModel.SendableUnit] = CoopViewModel.sendable(_encounter, _seat)
	var kept: PackedStringArray = []
	for unit: CoopViewModel.SendableUnit in units:
		if _picked.has(unit.unit_id) and unit.source_session_id == _source_id:
			kept.append(unit.unit_id)
	_picked = kept
	if _picked.is_empty():
		_source_id = CoopViewModel.send_source(_encounter, _seat)
	if not CoopViewModel.target_reason(_encounter, _target_id, _source_id).is_empty():
		_target_id = SendUnitsCommand.NO_TARGET
	_show_units(units)
	_show_maps()
	var is_frozen: bool = CoopViewModel.is_any_frozen(_encounter)
	_rule.visible = is_frozen
	if is_frozen:
		_rule.show_rule()
	_none_button.visible = CoopViewModel.can_send_none(_encounter, _seat)
	_none_button.disabled = _is_sending
	_send_button.disabled = _is_sending or _picked.is_empty() or _target_id < 0
	_link_focus()


## Shows [param reason], a refusal of the send, and lets the seat pick again.
func show_refusal(reason: String) -> void:
	_is_sending = false
	_status.text = "Can't send: %s." % [CampaignLink.name_seats(reason)]
	refresh()
	_show_picks()


## Hides the panel and gives up focus.
func close() -> void:
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	visible = false
	_encounter = null


## Whether the question before a send is showing.
func is_confirming() -> bool:
	return visible and _confirm_page.visible


## The units picked, in the order picked.
func get_picked() -> PackedStringArray:
	return _picked.duplicate()


## The target picked; [constant SendUnitsCommand.NO_TARGET] for none.
func get_target() -> int:
	return _target_id


## Every unit row, for tests.
func get_unit_rows() -> Array[SendUnitRow]:
	var found: Array[SendUnitRow] = []
	for child: Node in _unit_rows.get_children():
		if child is SendUnitRow and not child.is_queued_for_deletion():
			found.append(child as SendUnitRow)
	return found


## Every map row, for tests.
func get_map_rows() -> Array[MapStatusRow]:
	var found: Array[MapStatusRow] = []
	for child: Node in _map_rows.get_children():
		if child is MapStatusRow and not child.is_queued_for_deletion():
			found.append(child as MapStatusRow)
	return found


## Send, for tests.
func get_send_button() -> Button:
	return _send_button


## Send none, for tests.
func get_send_none_button() -> Button:
	return _none_button


## Close, for tests.
func get_close_button() -> Button:
	return _close_button


## The question's Confirm, for tests.
func get_confirm_button() -> Button:
	return _confirm_button


## The question's Back, for tests.
func get_back_button() -> Button:
	return _back_button


## The status line, for tests.
func get_status_text() -> String:
	return _status.text


## The question, for tests.
func get_question() -> String:
	return _question.text


## The frozen rule's banner, for tests.
func get_rule() -> FrozenBanner:
	return _rule


## The question for a send of [param names] from [param source_id] to [param target_id] in
## [param encounter], as [param seat] sees the maps.
static func question_for(
		encounter: CombatEncounter,
		seat: int,
		names: PackedStringArray,
		source_id: int,
		target_id: int
) -> String:
	var target: CombatSession = encounter.get_session(target_id)
	var title: String = CoopViewModel.map_title(target, seat) if target != null else "?"
	var turn: int = CoopViewModel.arrival_turn(encounter, source_id, target_id)
	var when: String = "at once" if turn == CoopViewModel.AT_ONCE else (
			"at the start of its turn %d" % [turn]
	)
	var who: String = ", ".join(names)
	if names.size() > 1:
		who = "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]
	var they: String = "They arrive" if names.size() > 1 else "It arrives"
	return "Send %s to %s? %s %s." % [who, title, they, when]


func _show_units(units: Array[CoopViewModel.SendableUnit]) -> void:
	if unit_row_scene == null:
		push_error("SendPanel: no unit row scene")
		return
	var rows: Array[SendUnitRow] = get_unit_rows()
	var is_same: bool = rows.size() == units.size()
	for i: int in mini(rows.size(), units.size()):
		is_same = is_same and rows[i].unit_id == units[i].unit_id
	if not is_same:
		for row: SendUnitRow in rows:
			_unit_rows.remove_child(row)
			row.queue_free()
		for unit: CoopViewModel.SendableUnit in units:
			var row: SendUnitRow = unit_row_scene.instantiate() as SendUnitRow
			_unit_rows.add_child(row)
			row.picked.connect(_on_unit_row_picked)
	rows = get_unit_rows()
	for i: int in units.size():
		var source_title: String = ""
		var own: CombatSession = _encounter.session_of_seat(_seat)
		if own == null or units[i].source_session_id != own.session_id:
			source_title = CoopViewModel.map_title(
					_encounter.get_session(units[i].source_session_id), _seat
			)
		rows[i].show_unit(units[i], source_title)
		rows[i].set_picked(_picked.has(units[i].unit_id))
		rows[i].disabled = _is_sending
	_unit_scroll.custom_minimum_size.y = minf(
			max_unit_list_height, unit_row_height * float(units.size())
	)


func _show_maps() -> void:
	if map_row_scene == null:
		push_error("SendPanel: no map row scene")
		return
	var maps: Array[CoopViewModel.MapStatus] = []
	for shown: CoopViewModel.MapStatus in CoopViewModel.maps(_encounter, _seat):
		if shown.session_id != _source_id:
			maps.append(shown)
	while _map_rows.get_child_count() > maps.size():
		var last: Node = _map_rows.get_child(_map_rows.get_child_count() - 1)
		_map_rows.remove_child(last)
		last.queue_free()
	while _map_rows.get_child_count() < maps.size():
		var row: MapStatusRow = map_row_scene.instantiate() as MapStatusRow
		row.is_pickable = true
		_map_rows.add_child(row)
		row.pressed.connect(_on_map_row_pressed)
	var rows: Array[MapStatusRow] = get_map_rows()
	# While a map is frozen the rule's banner says why the others can't be picked.
	var shows_refusals: bool = not CoopViewModel.is_any_frozen(_encounter)
	for i: int in maps.size():
		var reason: String = CoopViewModel.target_reason(
				_encounter, maps[i].session_id, _source_id
		)
		rows[i].show_status(
				maps[i], false, reason, maps[i].session_id == _target_id, shows_refusals
		)
		if _is_sending:
			rows[i].get_button().disabled = true


# Links focus in a fixed order, past anything disabled: down the unit rows, then the map rows,
# then to the first button shown, which sit side by side; up from a button to the last row.
# Geometry alone could skip one. Close is always shown and enabled, so a button is always there.
func _link_focus() -> void:
	var column: Array[Control] = []
	for row: SendUnitRow in get_unit_rows():
		if not row.disabled:
			column.append(row)
	for row: MapStatusRow in get_map_rows():
		if not row.get_button().disabled:
			column.append(row.get_button())
	var buttons: Array[Button] = []
	for button: Button in [_send_button, _none_button, _close_button]:
		if button.visible and not button.disabled:
			buttons.append(button)
	for i: int in column.size():
		var control: Control = column[i]
		var below: Control = column[i + 1] if i + 1 < column.size() else buttons[0]
		var above: Control = column[i - 1] if i > 0 else control
		control.focus_neighbor_bottom = control.get_path_to(below)
		control.focus_neighbor_top = control.get_path_to(above)
		control.focus_neighbor_left = control.get_path_to(control)
		control.focus_neighbor_right = control.get_path_to(control)
	var last: Control = column[column.size() - 1] if not column.is_empty() else null
	for i: int in buttons.size():
		var button: Button = buttons[i]
		button.focus_neighbor_left = button.get_path_to(buttons[i - 1] if i > 0 else button)
		button.focus_neighbor_right = button.get_path_to(
				buttons[i + 1] if i + 1 < buttons.size() else button
		)
		button.focus_neighbor_bottom = button.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(last if last != null else button)


func _show_picks() -> void:
	_confirm_page.visible = false
	_pick_page.visible = true
	_focus_first_pick()


func _focus_first_pick() -> void:
	if not is_visible_in_tree() or _confirm_page.visible:
		return
	var rows: Array[SendUnitRow] = get_unit_rows()
	if not rows.is_empty() and not rows[0].disabled:
		rows[0].grab_focus()
		return
	for row: MapStatusRow in get_map_rows():
		if not row.get_button().disabled:
			row.get_button().grab_focus()
			return
	_close_button.grab_focus()


func _ask(question: String, units: PackedStringArray, source_id: int, target_id: int) -> void:
	_asked_units = units
	_asked_source = source_id
	_asked_target = target_id
	_question.text = question
	_pick_page.visible = false
	_confirm_page.visible = true
	_confirm_button.grab_focus()


func _name_of(unit_id: String) -> String:
	for unit: CoopViewModel.SendableUnit in CoopViewModel.sendable(_encounter, _seat):
		if unit.unit_id == unit_id:
			return unit.name
	return unit_id


func _on_unit_row_picked(unit_id: String, is_picked: bool) -> void:
	if _encounter == null:
		return
	var row_source: int = -1
	for row: SendUnitRow in get_unit_rows():
		if row.unit_id == unit_id:
			row_source = row.source_session_id
	if is_picked:
		if row_source != _source_id:
			_picked = []
			_source_id = row_source
		if not _picked.has(unit_id):
			_picked.append(unit_id)
	else:
		var index: int = _picked.find(unit_id)
		if index >= 0:
			_picked.remove_at(index)
	refresh()


# A map picked with units already picked hands focus to Send, the next step.
func _on_map_row_pressed(session_id: int) -> void:
	_target_id = session_id
	refresh()
	if not _send_button.disabled:
		_send_button.grab_focus()


func _on_send_button_pressed() -> void:
	if _picked.is_empty() or _target_id < 0:
		return
	var names: PackedStringArray = []
	for unit_id: String in _picked:
		names.append(_name_of(unit_id))
	_ask(question_for(_encounter, _seat, names, _source_id, _target_id), _picked.duplicate(),
			_source_id, _target_id)


func _on_send_none_button_pressed() -> void:
	_ask(_NONE_QUESTION, PackedStringArray(), CoopViewModel.send_source(_encounter, _seat),
			SendUnitsCommand.NO_TARGET)


func _on_confirm_button_pressed() -> void:
	_is_sending = true
	_status.text = _SENDING
	_show_picks()
	refresh()
	send_confirmed.emit(_asked_units, _asked_source, _asked_target)


func _on_back_button_pressed() -> void:
	_show_picks()


func _on_close_button_pressed() -> void:
	closed.emit()
