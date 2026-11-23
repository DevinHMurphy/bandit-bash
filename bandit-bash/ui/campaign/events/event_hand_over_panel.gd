# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_hand_over_panel.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventHandOverPanel
extends VBoxContainer
## Where each item of the unit leaving a full army goes when an event's recruit or revived unit
## takes its place (unit-roster.md, Recruiting and item transfer): one [HandOverRow] per item
## (onto the unit joining, the convoy, or scrapped), greyed as the Guildhall greys them
## ([method EventScreenModel.hand_over_refusals]), the unit's own items it displaces, then Best
## fit, Confirm and Back. It opens with every item going to the convoy, so Confirm alone keeps
## that.
##
## Rows step left and right along their places and up and down between rows; the buttons below
## are one column. It only asks: [signal hand_over_chosen] and [signal cancelled] go to
## [EventPanel], which builds the command. It reads no input action.

## The player confirmed [param hand_over] (item id to [enum Guildhall.HandOver]), the convoy's
## entries left out ([method EventHandOver.compact]).
signal hand_over_chosen(hand_over: Dictionary)

## The player pressed Back.
signal cancelled()

const ROW_SCENE: PackedScene = preload("res://ui/campaign/hand_over_row.tscn")

## The least width of the question, the notes and each button below the rows, so they line up
## with the rows at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as their text.
@export_range(0.0, 900.0, 1.0) var text_width: float = 608.0

var _seat_run: SeatRun = null
var _leaving: UnitInstance = null
var _joining: RecruitOffer = null
var _catalog: EffectCatalog.Index = null
var _noun: String = EventScreenModel.RECRUIT_NOUN
var _place_names: Dictionary[int, String] = {}
var _hand_over: Dictionary[String, int] = {}

@onready var _question_label: Label = %Question
@onready var _rows: VBoxContainer = %Rows
@onready var _notes_label: Label = %Notes
@onready var _choices: VBoxContainer = %Choices


func _ready() -> void:
	# A wrapping label needs a width, or its least height grows a line per word.
	_question_label.custom_minimum_size.x = text_width
	_notes_label.custom_minimum_size.x = text_width


## Asks where each item of [param leaving] goes as [param joining] (null while it isn't known)
## takes its place in [param seat_run]'s army, read with [param catalog]; [param is_revive] names
## the unit joining as revived. Opens with every item to the convoy, focus on the first row.
func show_hand_over(
		seat_run: SeatRun,
		leaving: UnitInstance,
		joining: RecruitOffer,
		is_revive: bool,
		catalog: EffectCatalog.Index
) -> void:
	_seat_run = seat_run
	_leaving = leaving
	_joining = joining
	_catalog = catalog
	_noun = EventScreenModel.REVIVED_NOUN if is_revive else EventScreenModel.RECRUIT_NOUN
	_place_names.clear()
	if is_revive:
		_place_names[Guildhall.HandOver.RECRUIT] = EventScreenModel.REVIVED_PLACE
	_hand_over = {}
	_question_label.text = EventScreenModel.hand_over_question(leaving, joining, catalog)
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for item_id: String in leaving.item_ids():
		var row: HandOverRow = ROW_SCENE.instantiate()
		row.place_names = _place_names
		_rows.add_child(row)
		row.place_chosen.connect(choose_place)
	_render()
	if is_visible_in_tree():
		focus_first()


## Places the item [param item_id] at [param place] ([enum Guildhall.HandOver]), as pressing its
## row's button does; focus stays on the row.
func choose_place(item_id: String, place: int) -> void:
	_hand_over[item_id] = place
	_render()


## Places every item as Best fit suggests ([method EventHandOver.best_fit]).
func best_fit() -> void:
	_hand_over = EventHandOver.best_fit(_seat_run, _leaving, _joining, _catalog)
	_render()


## The hand-over chosen so far, every item named: item id to [enum Guildhall.HandOver].
func get_hand_over() -> Dictionary[String, int]:
	var shown: Dictionary[String, int] = {}
	for item_id: String in _leaving.item_ids():
		shown[item_id] = EventHandOver.place_of(_hand_over, item_id)
	return shown


## Why Confirm can't be pressed ([method EventHandOver.problem]); empty when it can.
func get_problem() -> String:
	if _leaving == null:
		return "no unit leaves"
	return EventHandOver.problem(_seat_run, _leaving, _joining, _hand_over, _catalog)


## The rows shown, one per item of the leaving unit, in its slot order.
func get_rows() -> Array[HandOverRow]:
	var rows: Array[HandOverRow] = []
	for child: Node in _rows.get_children():
		if child is HandOverRow and not child.is_queued_for_deletion():
			rows.append(child as HandOverRow)
	return rows


## Best fit, Confirm and Back, in order, for the panel and tests.
func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


## The question shown, for tests.
func get_question() -> String:
	return _question_label.text


## The lines under the rows (the unit's own items sent to the convoy), for tests.
func get_notes() -> String:
	return _notes_label.text


## Focuses the first row's chosen place, else the first button that can be pressed; returns
## whether one took it.
func focus_first() -> bool:
	for row: HandOverRow in get_rows():
		var button: Button = row.button_for(row.place)
		if button != null and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return true
	for button: Button in get_choice_buttons():
		if not button.disabled:
			button.grab_focus()
			return true
	return false


# Shows every row, the notes and the buttons as the hand-over stands, linking focus and keeping
# it on the row place or button that held it.
func _render() -> void:
	var held: Array[int] = _focused_spot()
	var rows: Array[HandOverRow] = get_rows()
	var items: PackedStringArray = _leaving.item_ids()
	for index: int in mini(rows.size(), items.size()):
		var item_id: String = items[index]
		rows[index].show_item(
				item_id,
				EventScreenModel.hand_over_item_name(_seat_run, _leaving, item_id, _catalog),
				EventHandOver.place_of(_hand_over, item_id),
				EventScreenModel.hand_over_refusals(
						_seat_run, _leaving, _joining, _hand_over, item_id, _noun, _catalog
				)
		)
	var notes: PackedStringArray = EventScreenModel.hand_over_notes(
			_seat_run, _leaving, _joining, _hand_over, _noun, _catalog
	)
	_notes_label.text = "\n".join(notes)
	_notes_label.visible = not notes.is_empty()
	_show_choices()
	_link_focus()
	_restore_focus(held)


func _show_choices() -> void:
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_add_choice("Best fit", true, best_fit)
	var problem: String = get_problem()
	var confirm_text: String = "Confirm" if problem.is_empty() else "Confirm - can't: %s" % [
		problem,
	]
	_add_choice(confirm_text, problem.is_empty(), _on_confirm_pressed)
	_add_choice("Back", true, _on_back_pressed)


func _add_choice(text: String, is_enabled: bool, chosen: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(text_width, 0.0)
	button.disabled = not is_enabled
	button.focus_mode = Control.FOCUS_ALL if is_enabled else Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(chosen)
	_choices.add_child(button)


# Each row's enabled places as a line that stops at its ends; up and down go to the same place in
# the row above or below (else its chosen one), the last row down to the first button; the
# buttons are one column, up from the first to the last row.
func _link_focus() -> void:
	var rows: Array[HandOverRow] = get_rows()
	var column: Array[Button] = []
	for button: Button in get_choice_buttons():
		if not button.disabled:
			column.append(button)
	for i: int in rows.size():
		var line: Array[Button] = _enabled_places(rows[i])
		for j: int in line.size():
			var button: Button = line[j]
			button.focus_neighbor_left = button.get_path_to(line[maxi(j - 1, 0)])
			button.focus_neighbor_right = button.get_path_to(line[mini(j + 1, line.size() - 1)])
			var above: Control = button if i == 0 else _nearest(_enabled_places(rows[i - 1]), button)
			var below: Control = column[0]
			if i + 1 < rows.size():
				below = _nearest(_enabled_places(rows[i + 1]), button)
			button.focus_neighbor_top = button.get_path_to(above if above != null else button)
			button.focus_neighbor_bottom = button.get_path_to(below if below != null else button)
	var last_row: Control = null
	if not rows.is_empty():
		last_row = _nearest(_enabled_places(rows[-1]), null)
	for i: int in column.size():
		var button: Button = column[i]
		var self_path: NodePath = button.get_path_to(button)
		var above: Control = column[i - 1] if i > 0 else last_row
		button.focus_neighbor_top = button.get_path_to(above) if above != null else self_path
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = self_path
		button.focus_neighbor_right = self_path


# The row's place buttons that can be pressed, in place order.
func _enabled_places(row: HandOverRow) -> Array[Button]:
	var found: Array[Button] = []
	for place: int in Guildhall.HandOver.values():
		var button: Button = row.button_for(place)
		if button != null and button.focus_mode != Control.FOCUS_NONE:
			found.append(button)
	return found


# The button of line in the same place as from (null: none), else the line's first; null for an
# empty line.
func _nearest(line: Array[Button], from: Button) -> Control:
	for button: Button in line:
		if from != null and button.text == from.text:
			return button
	return null if line.is_empty() else line[0]


# Where focus is: [row index, place] on a row, [-1, button index] on a button below; [] for
# anywhere else.
func _focused_spot() -> Array[int]:
	var spot: Array[int] = []
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused == null or not is_ancestor_of(focused):
		return spot
	var rows: Array[HandOverRow] = get_rows()
	for index: int in rows.size():
		for place: int in Guildhall.HandOver.values():
			if rows[index].button_for(place) == focused:
				spot.assign([index, place])
				return spot
	var buttons: Array[Button] = get_choice_buttons()
	if buttons.has(focused):
		spot.assign([-1, buttons.find(focused)])
	return spot


# Focuses spot again (see _focused_spot), or the row's chosen place, or the first control when it
# can't take focus now. Nothing for an empty spot.
func _restore_focus(spot: Array[int]) -> void:
	if spot.is_empty():
		return
	var target: Control = null
	if spot[0] >= 0:
		var rows: Array[HandOverRow] = get_rows()
		if spot[0] < rows.size():
			var row: HandOverRow = rows[spot[0]]
			target = row.button_for(spot[1])
			if target == null or target.focus_mode == Control.FOCUS_NONE:
				target = row.button_for(row.place)
	else:
		var buttons: Array[Button] = get_choice_buttons()
		if spot[1] < buttons.size():
			target = buttons[spot[1]]
	if target != null and target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus()
	else:
		focus_first()


func _on_confirm_pressed() -> void:
	hand_over_chosen.emit(EventHandOver.compact(_hand_over))


func _on_back_pressed() -> void:
	cancelled.emit()
