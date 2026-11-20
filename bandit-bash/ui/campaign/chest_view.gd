# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     chest_view.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name ChestView
extends PanelContainer
## One seat's Treasure chest as the [TreasureScreen] shows it: its size (its heirloom's tier, so
## the chest shows what's inside; heirlooms.md), its heirloom as an [HeirloomOfferCard] or its
## Legendary item as an [ItemOfferCard], the gold it adds, and whether it was taken or given up.
## The cards only show here: they take no focus and no clicks, as the screen's Open button takes
## the chest, so the screen calls [method show_names_tip] while Open has focus: the item's
## wielders by name, for a keyboard or pad player. Reads no input.
##
## @tutorial(RF-034): docs/design/rebalance-and-features.md

## The least width of the chest's panel, so a card and its lines fit at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its content.
@export var panel_width: float = 360.0:
	set(value):
		panel_width = value
		if not is_node_ready():
			return
		custom_minimum_size.x = panel_width

# ASSUMPTION: beside the card; RF-034 says only that the tooltip shows. Below, it would cover
# the gold line while Open has focus, which it has on entry.
## Which side of the item card's who-can-use row the wielders' names open on
## ([member ItemUsableBy.tooltip_side]). [b]Bottom:[/b] over the gold and state lines.
@export var names_side: Side = SIDE_RIGHT:
	set(value):
		names_side = value
		if not is_node_ready():
			return
		_item_card.get_usable_by().tooltip_side = names_side

@onready var _size_label: Label = %SizeLabel
@onready var _heirloom_card: HeirloomOfferCard = %HeirloomCard
@onready var _item_card: ItemOfferCard = %ItemCard
@onready var _gold_label: Label = %GoldLabel
@onready var _state_label: Label = %StateLabel


func _ready() -> void:
	custom_minimum_size.x = panel_width
	_item_card.get_usable_by().tooltip_side = names_side
	for card: Button in [_heirloom_card, _item_card]:
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows [param chest] from [param catalog]; nothing for null. Its item's card shows who of
## [param seat_run]'s living units can use it, named through [param ids]; [param seat_run] null
## shows no one.
func show_chest(
		chest: TreasureChest,
		catalog: EffectCatalog.Index,
		seat_run: SeatRun = null,
		ids: InstanceIdAllocator = null,
) -> void:
	if chest == null:
		_size_label.text = "No chest"
		_heirloom_card.visible = false
		_item_card.visible = false
		_gold_label.visible = false
		_state_label.text = ""
		return
	_size_label.text = "%s chest (%s)" % [chest.size_name(), chest.tier.capitalize()]
	_heirloom_card.visible = not chest.heirloom_id.is_empty()
	if _heirloom_card.visible:
		_heirloom_card.show_heirloom(catalog.heirloom(chest.heirloom_id), chest.heirloom_id, "")
	_item_card.visible = chest.item != null
	if chest.item != null:
		_item_card.show_item(
				catalog.item(chest.item.definition_id), chest.item.definition_id, seat_run, catalog,
				ids
		)
	_gold_label.visible = chest.gold > 0
	_gold_label.text = "+%d gold" % [chest.gold]
	if not chest.is_resolved:
		_state_label.text = ""
	else:
		_state_label.text = "Taken." if chest.is_taken else "Left closed."
	if chest.heirloom_id.is_empty() and chest.item == null and chest.gold <= 0:
		_state_label.text = "It's empty."


## Names every unit that can wield the chest's Legendary weapon in a tooltip by its card, for the
## screen's Open button's focus. Does nothing when the chest holds no item, or one any unit can
## use, whose card says so in words ([method ItemUsableBy.show_names_tip]).
func show_names_tip() -> void:
	if _item_card.is_visible_in_tree():
		_item_card.get_usable_by().show_names_tip()


## Hides the wielders' tooltip.
func hide_names_tip() -> void:
	_item_card.get_usable_by().hide_tip()


## The size line as shown, such as [code]Large chest (Rare)[/code], for tests.
func get_size_text() -> String:
	return _size_label.text


## The gold line as shown; empty when the chest adds none.
func get_gold_text() -> String:
	return _gold_label.text if _gold_label.visible else ""


## The heirloom card, for tests; hidden when the chest holds an item instead.
func get_heirloom_card() -> HeirloomOfferCard:
	return _heirloom_card


## The Legendary item's card, for tests; hidden when the chest holds none.
func get_item_card() -> ItemOfferCard:
	return _item_card
