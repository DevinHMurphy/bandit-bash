# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     trinket_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name TrinketDefinition
extends ItemDefinition
## A trinket: a small passive Pouch item that competes with a consumable for the slot (items.md,
## Trinkets).
##
## Lives in [code]res://data/items/trinkets/[/code]. It has nothing beyond the base: its
## [member EffectCarrierDefinition.effects] are the trinket. Weightless, like every Pouch item.
##
## @tutorial(Items, Trinkets): docs/design/items.md


func _get_kind() -> String:
	return ContentIds.ITEM_TRINKET
