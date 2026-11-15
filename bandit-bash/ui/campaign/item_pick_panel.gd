# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_pick_panel.gd
# Author:
# Created:  November 14, 2026
# Modified: November 15, 2026
# ==============================================================================

class_name ItemPickPanel
extends VBoxContainer
## Results' item pick: its slot kind, one [ItemOfferCard] per offer and Skip; once the pick is
## taken or skipped, what became of it instead.
##
## The cards and Skip sit in one row, linked left and right and stopping at its ends; up and down
## stay put, as nothing else takes focus while the pick is open. It only asks: the screen sends
## the command on [signal offer_chosen] or [signal skip_chosen]. Reads no input action itself.

## The player chose offer [param index] of the pick to take.
signal offer_chosen(index: int)

## The player chose to skip the pick.
signal skip_chosen()

const CARD_SCENE: PackedScene = preload("res://ui/campaign/item_offer_card.tscn")

## The heading of each slot kind's pick.
const SLOT_TITLES: Dictionary[ItemPick.Slot, String] = {
	ItemPick.Slot.WEAPON: "Item pick: a weapon",
	ItemPick.Slot.EQUIPMENT: "Item pick: equipment",
	ItemPick.Slot.POUCH: "Item pick: a pouch item",
}

@onready var _title_label: Label = %Title
@onready var _cards: HBoxContainer = %Cards
@onready var _skip_button: Button = %SkipButton
@onready var _outcome_label: Label = %Outcome


func _ready() -> void:
	_skip_button.pressed.connect(_on_skip_button_pressed)


## Shows [param model]'s pick: the offers to choose from while it is open, else its outcome
## ([method CombatResultsModel.pick_outcome]) and [param note] when not empty. Hidden with no pick.
func show_pick(model: CombatResultsModel, note: String = "") -> void:
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var pick: ItemPick = model.pick
	visible = pick != null
	if pick == null:
		return
	_title_label.text = SLOT_TITLES.get(pick.slot, "Item pick")
	var is_open: bool = not pick.is_resolved
	_cards.visible = is_open
	_skip_button.visible = is_open
	_outcome_label.visible = not is_open
	_outcome_label.text = model.pick_outcome() if note.is_empty() else note
	if not is_open:
		return
	for index: int in pick.offers.size():
		var card: ItemOfferCard = CARD_SCENE.instantiate()
		_cards.add_child(card)
		card.show_item(model.offers[index], pick.offers[index].definition_id)
		card.pressed.connect(_on_card_pressed.bind(index))
	_link_focus()


## Gives focus to the first offer; returns whether one took it.
func focus_first() -> bool:
	var cards: Array[ItemOfferCard] = get_offer_cards()
	if cards.is_empty() or not _cards.visible:
		return false
	cards[0].grab_focus()
	return true


## The offer cards shown, in offer order, for the screen and tests.
func get_offer_cards() -> Array[ItemOfferCard]:
	var cards: Array[ItemOfferCard] = []
	for child: Node in _cards.get_children():
		if child is ItemOfferCard and not child.is_queued_for_deletion():
			cards.append(child as ItemOfferCard)
	return cards


## The Skip button, for tests.
func get_skip_button() -> Button:
	return _skip_button


## The outcome line as shown, for tests; empty while the pick is open.
func get_outcome_text() -> String:
	return _outcome_label.text if _outcome_label.visible else ""


# The cards then Skip as one row: left and right step along it and stop at its ends.
func _link_focus() -> void:
	var row: Array[Control] = []
	for card: ItemOfferCard in get_offer_cards():
		row.append(card)
	row.append(_skip_button)
	for i: int in row.size():
		var control: Control = row[i]
		var self_path: NodePath = control.get_path_to(control)
		control.focus_neighbor_left = control.get_path_to(row[maxi(i - 1, 0)])
		control.focus_neighbor_right = control.get_path_to(row[mini(i + 1, row.size() - 1)])
		control.focus_neighbor_top = self_path
		control.focus_neighbor_bottom = self_path
		control.focus_previous = control.focus_neighbor_left
		control.focus_next = control.focus_neighbor_right


func _on_card_pressed(index: int) -> void:
	offer_chosen.emit(index)


func _on_skip_button_pressed() -> void:
	skip_chosen.emit()
