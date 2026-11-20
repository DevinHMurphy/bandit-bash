# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stock_card.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name StockCard
extends Button
## One entry of the Armory's stock: a pressable card with its icon, name, details and price for
## the seat ([ArmoryModel]).
##
## An entry the seat can't buy at all ([method Armory.entry_problem]: sold, owned, too little gold,
## no unit can use it) says why on the card, and is disabled and out of the focus order, as
## [HeirloomOfferCard] treats a refused heirloom. Pressing it (click, or accept while focused)
## asks to buy it; [StockView] passes that on. It reads no input action itself.

## The card's width and least height: wide enough for a weapon's numbers on one line, narrow
## enough for four in a row at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its text alone.
@export var card_size: Vector2 = Vector2(296.0, 72.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		custom_minimum_size = card_size

## The entry's index in [member ArmoryStock.entries], by [method show_entry]; -1 before it.
var entry_index: int = -1

## The entry's name, by [method show_entry]; empty before it.
var entry_name: String = ""

## Why the seat can't buy it, by [method show_entry]. [b]Empty:[/b] it can.
var problem: String = ""


func _ready() -> void:
	custom_minimum_size = card_size


## Shows entry [param index] of the stock: [param title], [param details] and [param price] under
## [param entry_icon], refused for [param refusal] when that isn't empty.
func show_entry(
		index: int,
		title: String,
		details: String,
		price: String,
		entry_icon: Texture2D,
		refusal: String
) -> void:
	entry_index = index
	entry_name = title
	problem = refusal
	var lines: PackedStringArray = [title, details, price]
	if not refusal.is_empty():
		lines.append("Can't buy: %s." % [refusal])
	text = "\n".join(lines)
	icon = entry_icon
	disabled = not refusal.is_empty()
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
