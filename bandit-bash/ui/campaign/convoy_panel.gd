# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     convoy_panel.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ConvoyPanel
extends VBoxContainer
## The convoy in the [ArmyView]: how full it is, then each item with a Scrap button showing the
## gold it gives at the seat's rate ([method ItemPlacement.held_scrap_value]; items.md, Scrapping:
## one step, showing the gold). While re-gearing, each item can be picked up too, and "Put it in
## the convoy" takes the item being moved.
##
## Presses are reported ([signal item_pressed], [signal scrap_pressed],
## [signal to_convoy_pressed]); the view decides what they mean. Every Scrap button is always
## live, as scrapping is allowed anywhere. It reads no input action itself.

## A convoy item was pressed (re-gearing only).
signal item_pressed(item_id: String)

## A convoy item's Scrap button was pressed.
signal scrap_pressed(item_id: String)

## "Put it in the convoy" was pressed (re-gearing, while an item is being moved).
signal to_convoy_pressed()

## Each item button's least width, so an item's name fits at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export var item_width: float = 200.0

@onready var _title_label: Label = %ConvoyTitle
@onready var _to_convoy_button: Button = %ToConvoyButton
@onready var _rows: VBoxContainer = %Rows
@onready var _empty_label: Label = %EmptyLabel


func _ready() -> void:
	_to_convoy_button.pressed.connect(_on_to_convoy_button_pressed)


## Shows [param seat_run]'s convoy ([param catalog] its content); its items pick up when
## [param can_move], and "Put it in the convoy" shows while [param is_carrying].
func show_convoy(
		seat_run: SeatRun, catalog: EffectCatalog.Index, can_move: bool, is_carrying: bool
) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_title_label.text = "Convoy %d / %d" % [
		seat_run.convoy.size(), ItemPlacement.convoy_capacity(seat_run, catalog),
	]
	_to_convoy_button.visible = can_move and is_carrying
	_empty_label.visible = seat_run.convoy.is_empty()
	for item_id: String in seat_run.convoy:
		var item: ItemInstance = seat_run.items[item_id]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var item_button: Button = Button.new()
		item_button.text = CombatResultsModel.item_name(catalog.item(item.definition_id), item_id)
		item_button.custom_minimum_size = Vector2(item_width, 36.0)
		item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_button.clip_text = true
		item_button.disabled = not can_move
		item_button.focus_mode = Control.FOCUS_ALL if can_move else Control.FOCUS_NONE
		item_button.pressed.connect(_on_item_pressed.bind(item_id))
		var scrap_button: Button = Button.new()
		scrap_button.text = "Scrap +%d gold" % [
			ItemPlacement.held_scrap_value(item, catalog, seat_run),
		]
		scrap_button.custom_minimum_size = Vector2(0.0, 36.0)
		scrap_button.pressed.connect(_on_scrap_pressed.bind(item_id))
		row.add_child(item_button)
		row.add_child(scrap_button)
		_rows.add_child(row)


## The convoy line as shown, such as [code]Convoy 2 / 4[/code], for tests.
func get_title_text() -> String:
	return _title_label.text


## Each item's button, in convoy order, for the view and tests.
func get_item_buttons() -> Array[Button]:
	return _buttons_at(0)


## Each item's Scrap button, in convoy order, for the view and tests.
func get_scrap_buttons() -> Array[Button]:
	return _buttons_at(1)


## "Put it in the convoy", for the view and tests.
func get_to_convoy_button() -> Button:
	return _to_convoy_button


func _buttons_at(column: int) -> Array[Button]:
	var found: Array[Button] = []
	for row: Node in _rows.get_children():
		if row.is_queued_for_deletion():
			continue
		found.append(row.get_child(column) as Button)
	return found


func _on_item_pressed(item_id: String) -> void:
	item_pressed.emit(item_id)


func _on_scrap_pressed(item_id: String) -> void:
	scrap_pressed.emit(item_id)


func _on_to_convoy_button_pressed() -> void:
	to_convoy_pressed.emit()
