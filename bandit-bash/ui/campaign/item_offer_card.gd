# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_offer_card.gd
# Author:
# Created:  November 14, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name ItemOfferCard
extends Button
## One offer of an item pick, the Treasure chest or the starting offer: a pressable card with the
## item's icon ([member ItemDefinition.icon]), name, rarity and kind, a weapon's numbers
## ([method CombatResultsModel.item_details]), one line per effect
## ([method EffectCarrierDefinition.describe_marked], keywords coloured and explained by an
## [EffectText]) and, at its bottom right, who can use it
## ([ItemUsableBy]). Long text wraps; the card grows to fit, and a row's cards share the tallest
## height, as their row container fills them.[br]
## Pressing it (click, or accept while focused) asks to take the item; its screen passes that on.
## Keyboard or pad focus lists the units that can wield it ([method ItemUsableBy.show_names_tip]).
## It reads no input action itself.
##
## @tutorial(RF-031, RF-032): docs/design/rebalance-and-features.md

## The card's width and least height: wide enough for a weapon's numbers on one line, as the
## Armory's [StockCard], with three cards and Skip in a row at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its content alone.
@export var card_size: Vector2 = Vector2(296.0, 72.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		fit_content()

## The card's name text, by [method show_item]; empty before it.
var item_name: String = ""

@onready var _content: MarginContainer = %Content
@onready var _item_icon: TextureRect = %ItemIcon
@onready var _name_label: Label = %ItemName
@onready var _details_label: Label = %Details
@onready var _numbers_label: Label = %Numbers
@onready var _effects_text: EffectText = %Effects
@onready var _usable_by: ItemUsableBy = %UsableBy


func _ready() -> void:
	_content.minimum_size_changed.connect(fit_content)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	fit_content()


## Shows the item of [param definition], content id [param definition_id] (its name when the
## catalog lacks it), and who of [param seat_run]'s living units can use it, read from
## [param catalog] and named through [param ids]. [param seat_run] null: no one is shown. Call it
## once the card is in the tree.
func show_item(
		definition: ItemDefinition,
		definition_id: String,
		seat_run: SeatRun = null,
		catalog: EffectCatalog.Index = null,
		ids: InstanceIdAllocator = null,
) -> void:
	if not is_node_ready():
		push_error("ItemOfferCard: show_item before the card is in the tree - %s" % [
			definition_id,
		])
		return
	item_name = CombatResultsModel.item_name(definition, definition_id)
	_name_label.text = item_name
	var details: PackedStringArray = CombatResultsModel.item_details(definition).split("\n")
	_details_label.text = details[0]
	_numbers_label.text = "\n".join(details.slice(1))
	_numbers_label.visible = details.size() > 1
	var effects: PackedStringArray = (
			PackedStringArray() if definition == null else definition.describe_marked()
	)
	_effects_text.marked_text = "\n".join(effects)
	_effects_text.visible = not effects.is_empty()
	_item_icon.texture = null if definition == null else definition.icon
	_usable_by.show_users(definition, seat_run, catalog, ids)
	if has_focus():
		_usable_by.show_names_tip()


## Its lines as shown, for tests: name, rarity and kind, then a weapon's numbers and each effect.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = [_name_label.text, _details_label.text]
	if _numbers_label.visible:
		lines.append_array(_numbers_label.text.split("\n"))
	if _effects_text.visible:
		lines.append_array(_effects_text.get_plain_text().split("\n"))
	return lines


## The icon shown; null for an item with none.
func get_item_icon() -> Texture2D:
	return _item_icon.texture


## Who can use the item, at the card's bottom right.
func get_usable_by() -> ItemUsableBy:
	return _usable_by


## Sizes the card to its content now: [member card_size]'s width, and its height or the content's,
## whichever is taller. The button doesn't lay its content out itself, so a change to the content's
## least size calls this a frame later; a layout read in the same frame (as tests do) calls it.
func fit_content() -> void:
	custom_minimum_size = Vector2(
			card_size.x, maxf(card_size.y, _content.get_combined_minimum_size().y)
	)


func _on_focus_entered() -> void:
	_usable_by.show_names_tip()


func _on_focus_exited() -> void:
	_usable_by.hide_tip()
