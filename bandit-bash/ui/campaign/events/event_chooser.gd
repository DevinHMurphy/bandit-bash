# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_chooser.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventChooser
extends VBoxContainer
## What an event option acts on, or which rune makes room: one column of choices
## ([EventScreenModel.Entry]: a living unit, a fallen one, a weapon, a rune slot), then Back. An
## entry that can't be chosen is greyed out with its reason and left out of the focus order, as
## [UnitChoicePanel]'s are.
##
## The column links up and down and stops at its ends; left and right stay put. It scrolls once
## it outgrows [member list_height], following focus. It only asks: [signal entry_chosen] and
## [signal cancelled] go to [EventPanel], which builds the command. It reads no input action.

## The player chose the entry [param entry_id].
signal entry_chosen(entry_id: String)

## The player pressed Back.
signal cancelled()

## Each choice's least width, so a unit's name, HP and reason fit on one line at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export var choice_width: float = 560.0

## The most height the column takes before it scrolls: eight units' choices and Back.[br]
## [b]Units:[/b] base units. [b]0:[/b] the column takes no room and always scrolls.
@export var list_height: float = 300.0:
	set(value):
		list_height = value
		if not is_node_ready():
			return
		_scroll.custom_minimum_size.y = list_height

@onready var _question_label: Label = %Question
@onready var _scroll: ScrollContainer = %Scroll
@onready var _choices: VBoxContainer = %Choices


func _ready() -> void:
	_scroll.custom_minimum_size = Vector2(choice_width, list_height)
	# A wrapping label needs a width, or its least height grows a line per word.
	_question_label.custom_minimum_size.x = choice_width


## Asks [param question] over [param entries], in order, then Back. Focuses the first that can be
## chosen, else Back.
func show_entries(question: String, entries: Array[EventScreenModel.Entry]) -> void:
	_question_label.text = question
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	for entry: EventScreenModel.Entry in entries:
		var text: String = entry.text
		if not entry.is_available():
			text += " (%s)" % [entry.reason]
		_add_choice(text, entry.is_available(), _on_entry_pressed.bind(entry.id))
	_add_choice("Back", true, _on_back_pressed)
	var column: Array[Button] = []
	for button: Button in get_choice_buttons():
		if not button.disabled:
			column.append(button)
	for i: int in column.size():
		var button: Button = column[i]
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = self_path
		button.focus_neighbor_right = self_path
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom
	if is_visible_in_tree():
		column[0].grab_focus()


## Every choice button shown, entries then Back, for the panel and tests.
func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


## The question shown, for tests.
func get_question() -> String:
	return _question_label.text


## Focuses the first choice that can be pressed, Back at worst; returns whether one took it.
func focus_first() -> bool:
	for button: Button in get_choice_buttons():
		if not button.disabled:
			button.grab_focus()
			return true
	return false


func _add_choice(text: String, is_enabled: bool, chosen: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(choice_width, 0.0)
	button.disabled = not is_enabled
	button.focus_mode = Control.FOCUS_ALL if is_enabled else Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(chosen)
	_choices.add_child(button)


func _on_entry_pressed(entry_id: String) -> void:
	entry_chosen.emit(entry_id)


func _on_back_pressed() -> void:
	cancelled.emit()
