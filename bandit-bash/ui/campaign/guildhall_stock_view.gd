# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_stock_view.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name GuildhallStockView
extends VBoxContainer
## The Guildhall's stock for one seat: a row of [RecruitOfferCard]s, each previewing the recruit as
## it would join that seat's army ([method Guildhall.recruit_for]), over a row of rune
## [StockCard]s, each card priced; a sold or refused entry says why on its card.
##
## Pressing a card asks to buy its entry ([signal entry_pressed]); the screen opens the purchase.
## The rows wrap when the stock is wide (Guild Charter, co-op). Focus moves between the enabled
## cards by the GUI's own neighbours (key, d-pad, stick), so a refused card is skipped. It reads
## no input action itself.

## The player pressed the card of stock entry [param index].
signal entry_pressed(index: int)

const _RECRUIT_SCENE: PackedScene = preload("res://ui/campaign/recruit_offer_card.tscn")
const _RUNE_SCENE: PackedScene = preload("res://ui/campaign/stock_card.tscn")

## The gap between two cards, and between a row's label and its cards.[br]
## [b]Units:[/b] base units. [b]0:[/b] touching.
@export_range(0.0, 64.0, 1.0) var gap: float = 16.0

## Each rune's icon on its card, by its [RuneDefinition] id ([code]mend[/code]).[br]
## [b]Empty, or a rune missing:[/b] its card shows no icon.
@export var rune_icons: Dictionary[String, Texture2D] = {}

var _cards: Array[Button] = []
var _indexes: Dictionary[Button, int] = {}


## Shows the stock of [param run]'s Guildhall for seat [param seat], from [param catalog]: each
## entry's card, refused for [method Guildhall.entry_problem]. Nothing for no stock.
func show_stock(run: CampaignRunState, seat: int, catalog: EffectCatalog.Index) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_cards.clear()
	_indexes.clear()
	var stock: GuildhallStock = GuildhallStock.pending(run)
	if stock == null:
		return
	var recruits: HFlowContainer = _row("Recruits")
	for index: int in stock.indexes_of(GuildhallStock.CATEGORY_RECRUIT):
		var offer: RecruitOffer = Guildhall.recruit_for(run, seat, index, catalog)
		if offer == null:
			continue
		var card: RecruitOfferCard = _RECRUIT_SCENE.instantiate()
		recruits.add_child(card)
		card.show_recruit(offer, catalog)
		card.show_price(
				GuildhallModel.entry_price_text(run, seat, index, catalog),
				Guildhall.entry_problem(run, seat, index, catalog)
		)
		_add(card, index)
	var runes: HFlowContainer = _row("Runes")
	for index: int in stock.indexes_of(GuildhallStock.CATEGORY_RUNE):
		var entry: GuildhallStock.Entry = stock.entries[index]
		var icon: Texture2D = rune_icons.get(entry.definition_id, null)
		var card: StockCard = _RUNE_SCENE.instantiate()
		runes.add_child(card)
		card.show_entry(
				index,
				GuildhallModel.rune_name(entry.definition_id, catalog),
				GuildhallModel.rune_details(entry.definition_id, catalog),
				GuildhallModel.entry_price_text(run, seat, index, catalog),
				icon,
				Guildhall.entry_problem(run, seat, index, catalog)
		)
		_add(card, index)


## The cards shown, recruits then runes, in stock order.
func get_cards() -> Array[Button]:
	return _cards.duplicate()


## The card of stock entry [param index]; null when none shows it.
func card_for(index: int) -> Button:
	for card: Button in _cards:
		if _indexes[card] == index:
			return card
	return null


## The first card that can be pressed; null when every entry is refused.
func first_enabled() -> Button:
	for card: Button in _cards:
		if not card.disabled:
			return card
	return null


# A labelled row of wrapping cards, added to this view; returns the cards' container.
func _row(title: String) -> HFlowContainer:
	var label: Label = Label.new()
	label.theme_type_variation = &"HeaderLabel"
	label.text = title
	add_child(label)
	var cards: HFlowContainer = HFlowContainer.new()
	cards.add_theme_constant_override(&"h_separation", roundi(gap))
	cards.add_theme_constant_override(&"v_separation", roundi(gap))
	add_child(cards)
	return cards


func _add(card: Button, index: int) -> void:
	card.pressed.connect(_on_card_pressed.bind(index))
	_cards.append(card)
	_indexes[card] = index


func _on_card_pressed(index: int) -> void:
	entry_pressed.emit(index)
