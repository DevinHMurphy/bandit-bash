# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     equipment_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name EquipmentDefinition
extends ItemDefinition
## One piece of Equipment-slot gear, shields included: build-defining and never swapped mid-combat
## (game-vision.md, Weapons and equipment).
##
## Lives in [code]res://data/items/equipment/[/code]. Its
## [member EffectCarrierDefinition.effects] are the gear's bonuses; its
## [member ItemDefinition.weight] counts toward Attack Speed. No MVP equipment is restricted to a
## unit type.
##
## @tutorial(Items, Equipment): docs/design/items.md

## The equipment category, from [constant ContentIds.EQUIPMENT_CATEGORIES], such as
## [code]shield[/code]. Traits and effects can test it.
@export var category: String = ""


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "category":
		ContentIds.apply_hint(property, ContentIds.EQUIPMENT_CATEGORIES)


func _get_kind() -> String:
	return ContentIds.ITEM_EQUIPMENT
