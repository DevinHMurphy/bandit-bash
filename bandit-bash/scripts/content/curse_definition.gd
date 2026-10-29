# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     curse_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name CurseDefinition
extends HeirloomDefinition
## A curse: a negative heirloom that lasts the rest of the run, charged by events as the price of a
## strong reward (events.md, Curses).
##
## Lives in [code]res://data/curses/[/code]. Its effects carry the
## [constant EffectDefinition.Tag.CURSE] tag, so they resolve last among reactions. Its
## [member HeirloomDefinition.tier] holds a curse tier from [constant ContentIds.CURSE_TIERS],
## matched to the size of the reward it is paired with; its kind stays empty, and it is never sold.
## No curse touches the economy.
##
## @tutorial(Events, Curses): docs/design/events.md


func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property["name"] == "tier":
		ContentIds.apply_hint(property, ContentIds.CURSE_TIERS)
