# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_offer_card.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ItemOfferCard
extends Button
## One offer of an item pick: a pressable card with the item's icon
## ([member ItemDefinition.icon]), name, rarity and kind, and a weapon's numbers
## ([method CombatResultsModel.item_details]).
##
## Pressing it (click, or accept while focused) asks to take the item; [ItemPickPanel] passes that
## on. It reads no input action itself.

## The card's name text, by [method show_item]; empty before it.
var item_name: String = ""


## Shows the item of [param definition], content id [param definition_id] (its name when the
## catalog lacks it).
func show_item(definition: ItemDefinition, definition_id: String) -> void:
	item_name = CombatResultsModel.item_name(definition, definition_id)
	text = "%s\n%s" % [item_name, CombatResultsModel.item_details(definition)]
	icon = null if definition == null else definition.icon
