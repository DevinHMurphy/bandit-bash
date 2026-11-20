# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_choice_panel.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitChoicePanel
extends VBoxContainer
## Which of the army's living units a choice names: the one to upgrade, the one a recruit
## replaces. One column of buttons, a unit each in roster order, then Back; a unit that can't be
## named (the commander, one upgraded already) is greyed out with the reason and left out of the
## focus order, as [PlacementPanel]'s choices are.
##
## The column links up and down and stops at its ends; left and right stay put. It only asks:
## [signal unit_chosen] and [signal cancelled] go to [StartingOfferView], which builds the
## command. It reads no input action itself.

## The player chose the unit [param unit_id].
signal unit_chosen(unit_id: String)

## The player pressed Back.
signal cancelled()

## Each choice's least width, so a unit's name and its reason fit on one line at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export var choice_width: float = 420.0

@onready var _question_label: Label = %Question
@onready var _choices: VBoxContainer = %Choices


## Asks [param question] about [param seat_run]'s living units, each shown as [param verb] and
## its name ([method RecruitOfferCard.title_of]); only those in [param eligible] can be pressed,
## the rest show [param refusal]. Focuses the first that can.
func show_units(
		question: String,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		eligible: PackedStringArray,
		verb: String,
		refusal: String
) -> void:
	_question_label.text = question
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	for unit: UnitInstance in seat_run.army:
		var can: bool = eligible.has(unit.instance_id)
		var text: String = "%s %s" % [verb, RecruitOfferCard.title_of(unit, catalog)]
		if not can:
			text += " (%s)" % [refusal]
		_add_choice(text, can, _on_unit_pressed.bind(unit.instance_id))
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
	column[0].grab_focus()


## Every choice button shown, units then Back, for the view and tests.
func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


func _add_choice(text: String, is_enabled: bool, chosen: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(choice_width, 0.0)
	button.disabled = not is_enabled
	button.focus_mode = Control.FOCUS_ALL if is_enabled else Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(chosen)
	_choices.add_child(button)


func _on_unit_pressed(unit_id: String) -> void:
	unit_chosen.emit(unit_id)


func _on_back_pressed() -> void:
	cancelled.emit()
