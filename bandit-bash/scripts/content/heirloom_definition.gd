# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name HeirloomDefinition
extends EffectCarrierDefinition
## An heirloom: an army-wide passive in one shared collection, with no per-unit assignment
## (heirlooms.md).
##
## Lives in [code]res://data/heirlooms/[/code], starting and Commander Heirlooms included; curses
## are [CurseDefinition]s. Its [member EffectCarrierDefinition.effects] use the Your Unit scope or
## wider, never This unit. An heirloom whose effects reach other players' units carries the
## [constant EffectDefinition.Tag.UNIQUE] tag on them: one owner per co-op campaign.
##
## @tutorial(Heirlooms): docs/design/heirlooms.md

## Tier, from [constant ContentIds.HEIRLOOM_TIERS]: the pool tier it is offered from, or Shop,
## starting or commander. Sets its price ([method Prices.heirloom_price]).
@export var tier: String = ""

# ASSUMPTION: heirlooms whose heirlooms.md table has no Kind column (Shop, starting, commander)
# leave the kind empty.
## What it rewards, from [constant ContentIds.HEIRLOOM_KINDS], such as [code]profile[/code].
## [b]Empty:[/b] no kind.
@export var kind: String = ""

## Whether it is offered only in co-op campaigns, since it does nothing in solo (Brothers in Arms).
@export var is_coop_only: bool = false


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "tier":
		ContentIds.apply_hint(property, ContentIds.HEIRLOOM_TIERS)
	elif property["name"] == "kind":
		ContentIds.apply_hint(property, ContentIds.HEIRLOOM_KINDS)


## Whether any of its effects carries [param tag], such as [constant EffectDefinition.Tag.UNIQUE].
func has_effect_tag(tag: EffectDefinition.Tag) -> bool:
	for effect: EffectDefinition in effects:
		if effect != null and effect.has_tag(tag):
			return true
	return false
