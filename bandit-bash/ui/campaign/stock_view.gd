# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stock_view.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name StockView
extends VBoxContainer
## The Armory's stock as rows of categories ([member row_layout]), each a label over its
## [StockCard]s, priced for one seat; a sold or refused entry says why on its card.
##
## Pressing a card asks to buy its entry ([signal entry_pressed]); the screen opens the purchase.
## Focus moves between the enabled cards by the GUI's own neighbours (key, d-pad, stick), so a
## refused card is skipped. It reads no input action itself.

## The player pressed the card of stock entry [param index].
signal entry_pressed(index: int)

const _CARD_SCENE: PackedScene = preload("res://ui/campaign/stock_card.tscn")

## Which categories share each row, top to bottom, by [ArmoryStock]'s category ids. A category in
## no row isn't shown. [b]Empty:[/b] nothing is shown.
@export var row_layout: Array[PackedStringArray] = [
	PackedStringArray([ArmoryStock.CATEGORY_WEAPON]),
	PackedStringArray([ArmoryStock.CATEGORY_EQUIPMENT, ArmoryStock.CATEGORY_TRINKET]),
	PackedStringArray([ArmoryStock.CATEGORY_CONSUMABLE, ArmoryStock.CATEGORY_HEIRLOOM]),
]

## The gap between two categories on one row, and between cards.[br]
## [b]Units:[/b] base units. [b]0:[/b] touching.
@export_range(0.0, 64.0, 1.0) var gap: float = 16.0

var _cards: Array[StockCard] = []


## Shows the stock of [param run]'s Armory for seat [param seat], from [param catalog]: each
## entry's card, refused for [method Armory.entry_problem]. Nothing for no stock.
func show_stock(run: CampaignRunState, seat: int, catalog: EffectCatalog.Index) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_cards.clear()
	var stock: ArmoryStock = ArmoryStock.pending(run)
	if stock == null:
		return
	var seat_run: SeatRun = run.seat_run(seat)
	for categories: PackedStringArray in row_layout:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", roundi(gap))
		for category: String in categories:
			var indexes: PackedInt32Array = stock.indexes_of(category)
			if indexes.is_empty():
				continue
			row.add_child(_section(category, indexes, stock, run, seat, seat_run, catalog))
		if row.get_child_count() > 0:
			add_child(row)
		else:
			row.free()


## The cards shown, in stock order of the rows.
func get_cards() -> Array[StockCard]:
	return _cards.duplicate()


## The card of stock entry [param index]; null when none shows it.
func card_for(index: int) -> StockCard:
	for card: StockCard in _cards:
		if card.entry_index == index:
			return card
	return null


## The first card that can be pressed; null when every entry is refused.
func first_enabled() -> StockCard:
	for card: StockCard in _cards:
		if not card.disabled:
			return card
	return null


func _section(
		category: String,
		indexes: PackedInt32Array,
		stock: ArmoryStock,
		run: CampaignRunState,
		seat: int,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index
) -> VBoxContainer:
	var section: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.theme_type_variation = &"HeaderLabel"
	label.text = ArmoryModel.CATEGORY_NAMES.get(category, category.capitalize())
	section.add_child(label)
	var cards: HBoxContainer = HBoxContainer.new()
	cards.add_theme_constant_override(&"separation", roundi(gap))
	section.add_child(cards)
	for index: int in indexes:
		var entry: ArmoryStock.Entry = stock.entries[index]
		var card: StockCard = _CARD_SCENE.instantiate()
		cards.add_child(card)
		card.show_entry(
				index,
				ArmoryModel.entry_name(entry, catalog),
				ArmoryModel.entry_details(entry, catalog),
				ArmoryModel.price_text(seat_run, entry, catalog),
				ArmoryModel.entry_icon(entry, catalog),
				Armory.entry_problem(run, seat, index, catalog)
		)
		card.pressed.connect(_on_card_pressed.bind(index))
		_cards.append(card)
	return section


func _on_card_pressed(index: int) -> void:
	entry_pressed.emit(index)
