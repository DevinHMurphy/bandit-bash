# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name RuneDefinition
extends EffectCarrierDefinition
## A rune: a single-use ability in its own slots, cast on the player turn outside the action
## economy (game-vision.md, Run-wide resources; items.md, Runes).
##
## Lives in [code]res://data/runes/[/code]. [member target_kind] says how the player aims it; its
## [member EffectCarrierDefinition.effects] are what it does. Runes cost a flat price
## ([constant Prices.RUNE_PRICE]).
##
## @tutorial(Items, Runes): docs/design/items.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## How it is aimed, from [constant ContentIds.RUNE_TARGET_KINDS]. [b]area:[/b] the player picks any
## tile and [member shape_id] covers it. [b]random:[/b] its own selector picks, with no aiming.
## [b]pair:[/b] two of your units (Recall).
@export var target_kind: String = ""

## Content id of the [TargetShape] an [code]area[/code] rune covers around the chosen tile.
## [b]Empty:[/b] none; only area runes name a shape.
@export var shape_id: String = ""


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "target_kind":
		ContentIds.apply_hint(property, ContentIds.RUNE_TARGET_KINDS)
