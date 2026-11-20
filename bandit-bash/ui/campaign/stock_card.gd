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
## One shop entry: a pressable card with its icon, name, details and price for the seat
## ([ArmoryModel], [GuildhallModel]), and for an item, who can use it ([ItemUsableBy]) at its
## bottom right, as on an [ItemOfferCard]; an heirloom or rune shows no such row. The row shares
## the price's line, so the Armory's three rows of cards fit at 1280×720.[br]
## An entry the seat can't buy ([method Armory.entry_problem]) says why, its lines muted, and is
## disabled and out of the focus order, as [HeirloomOfferCard] treats a refused heirloom.
## Pressing it (click, or accept while focused) asks to buy it; its view passes that on. Keyboard
## or pad focus lists the units that can wield it ([method ItemUsableBy.show_names_tip]). It
## reads no input action itself.
##
## @tutorial(RF-034): docs/design/rebalance-and-features.md

# The look of a refused entry's lines, in place of each label's own.
const _REFUSED_STYLE: StringName = &"MutedLabel"

## The card's width and least height: wide enough for a weapon's numbers on one line, narrow
## enough for four in a row at 1280×720. Taller content makes it taller.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its content alone.
@export var card_size: Vector2 = Vector2(296.0, 72.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		fit_content()

## The entry's index in its stock's entries, by [method show_entry]; -1 before it.
var entry_index: int = -1

## The entry's name, by [method show_entry]; empty before it.
var entry_name: String = ""

## Why the seat can't buy it, by [method show_entry]. [b]Empty:[/b] it can.
var problem: String = ""

# Each line's look as the scene sets it, put back when an entry can be bought again.
var _styles: Dictionary[Label, StringName] = {}

@onready var _content: MarginContainer = %Content
@onready var _entry_icon: TextureRect = %EntryIcon
@onready var _name_label: Label = %EntryName
@onready var _details_label: Label = %Details
@onready var _price_label: Label = %Price
@onready var _problem_label: Label = %Problem
@onready var _usable_by: ItemUsableBy = %UsableBy


func _ready() -> void:
	for label: Label in _lines():
		_styles[label] = label.theme_type_variation
	_content.minimum_size_changed.connect(fit_content)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	fit_content()


## Shows entry [param index] of the stock: [param title], [param details] and [param price] by
## [param entry_icon], refused for [param refusal] when that isn't empty. Call it once the card
## is in the tree.
func show_entry(
		index: int,
		title: String,
		details: String,
		price: String,
		entry_icon: Texture2D,
		refusal: String
) -> void:
	if not is_node_ready():
		push_error("StockCard: show_entry before the card is in the tree - %s" % [title])
		return
	entry_index = index
	entry_name = title
	problem = refusal
	_name_label.text = title
	_details_label.text = details
	_details_label.visible = not details.is_empty()
	_price_label.text = price
	_problem_label.text = "Can't buy: %s." % [refusal]
	_problem_label.visible = not refusal.is_empty()
	_entry_icon.texture = entry_icon
	disabled = not refusal.is_empty()
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	for label: Label in _lines():
		label.theme_type_variation = _REFUSED_STYLE if disabled else _styles[label]


## Shows who of [param seat_run]'s living units can use the item [param definition], read from
## [param catalog] and named through [param ids] (null: by unit type), as an offer card does.
## Not called, or called with a null [param definition]: no row, as for an heirloom or rune.
func show_users(
		definition: ItemDefinition,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator = null,
) -> void:
	if not is_node_ready():
		push_error("StockCard: show_users before the card is in the tree - %s" % [entry_name])
		return
	_usable_by.show_users(definition, seat_run, catalog, ids)
	if has_focus():
		_usable_by.show_names_tip()


## Its lines as shown, for tests: name, then each line of its details, its price and why it
## can't be bought.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for label: Label in _lines():
		if label.visible:
			lines.append_array(label.text.split("\n"))
	return lines


## The icon shown; null for an entry with none.
func get_entry_icon() -> Texture2D:
	return _entry_icon.texture


## Who can use the item, at the card's bottom right; hidden for an heirloom or rune.
func get_usable_by() -> ItemUsableBy:
	return _usable_by


## Sizes the card to its content now: [member card_size]'s width, and its height or the content's,
## whichever is taller. The button doesn't lay its content out itself, so a change to the content's
## least size calls this a frame later; a layout read in the same frame (as tests do) calls it.
func fit_content() -> void:
	custom_minimum_size = Vector2(
			card_size.x, maxf(card_size.y, _content.get_combined_minimum_size().y)
	)


func _lines() -> Array[Label]:
	return [_name_label, _details_label, _price_label, _problem_label]


func _on_focus_entered() -> void:
	_usable_by.show_names_tip()


func _on_focus_exited() -> void:
	_usable_by.hide_tip()
