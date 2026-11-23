# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hand_over_row.gd
# Author:
# Created:  November 20, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name HandOverRow
extends HBoxContainer
## One item in a recruit's hand-over (unit-roster.md, Recruiting and item transfer): its name and
## a button per place it can go ([enum Guildhall.HandOver]: onto the recruit, the convoy or
## scrapped), the chosen one pressed. A place it can't go is greyed out, out of the focus order,
## and says why under the name, as [PlacementPanel] greys out gear a unit can't use.
##
## Pressing a place emits [signal place_chosen]; [GuildhallPanel] keeps the choices and shows the
## row again. It reads no input action itself: the GUI moves focus between the buttons.

## The player chose [param place] ([enum Guildhall.HandOver]) for the item [param item_id].
signal place_chosen(item_id: String, place: int)

## The name label's least width, so the rows' buttons line up at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export_range(0.0, 600.0, 1.0) var name_width: float = 300.0

## Each place button's least width.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export_range(0.0, 200.0, 1.0) var button_width: float = 96.0

## The text on a place's button, by [enum Guildhall.HandOver], as the next [method show_item]
## shows it, such as "Revived" for the unit an event brings back. [b]Missing:[/b] the Guildhall's
## ([constant GuildhallModel.PLACE_NAMES]).
@export var place_names: Dictionary[int, String] = {}

## The item this row places, by [method show_item]; empty before it.
var item_id: String = ""

## The place chosen, by [method show_item]: a [enum Guildhall.HandOver].
var place: int = Guildhall.HandOver.CONVOY

var _buttons: Dictionary[int, Button] = {}

@onready var _name_label: Label = %ItemName
@onready var _places: HBoxContainer = %Places


func _ready() -> void:
	_name_label.custom_minimum_size.x = name_width


## Shows the item [param shown_item_id] named [param title] at [param chosen], each place in
## [param refusals] (a [enum Guildhall.HandOver] to its reason) greyed out with its reason.
func show_item(
		shown_item_id: String, title: String, chosen: int, refusals: Dictionary[int, String]
) -> void:
	item_id = shown_item_id
	place = chosen
	var reasons: PackedStringArray = []
	for child: Node in _places.get_children():
		_places.remove_child(child)
		child.queue_free()
	_buttons.clear()
	for each: int in Guildhall.HandOver.values():
		var button: Button = Button.new()
		button.text = place_names.get(each, GuildhallModel.PLACE_NAMES.get(each, str(each)))
		button.custom_minimum_size.x = button_width
		button.toggle_mode = true
		button.button_pressed = each == chosen
		var refusal: String = refusals.get(each, "")
		button.disabled = not refusal.is_empty()
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		if not refusal.is_empty():
			reasons.append("%s: %s" % [button.text, refusal])
		button.pressed.connect(_on_place_pressed.bind(each))
		_places.add_child(button)
		_buttons[each] = button
	_name_label.text = title if reasons.is_empty() else "%s\n%s" % [title, "; ".join(reasons)]


## The button of [param shown_place] ([enum Guildhall.HandOver]); null before [method show_item].
func button_for(shown_place: int) -> Button:
	return _buttons.get(shown_place, null)


func _on_place_pressed(chosen: int) -> void:
	place = chosen
	for each: int in _buttons:
		_buttons[each].set_pressed_no_signal(each == chosen)
	place_chosen.emit(item_id, chosen)
