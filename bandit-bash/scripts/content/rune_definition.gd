# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: November 15, 2026
# ==============================================================================

@tool
class_name RuneDefinition
extends EffectCarrierDefinition
## A rune: a single-use ability in its own slots, cast on the player turn outside the action
## economy, on anything anywhere on the map (game-vision.md, Run-wide resources; items.md, Runes).
##
## Lives in [code]res://data/runes/[/code]. [member target_kind], [member target_side] and
## [member needs_unacted_target] say what it may be cast on ([method RuneResolver.target_reason]);
## its [member EffectCarrierDefinition.effects] are what it does on a unit. Combat finds a cast
## rune's definition by its effect ([method RuneResolver.definition_of]), so every rune carries
## one: Recall's and Spark's hold only their wording, in a [CustomOperation], and the resolver or
## the map does the work. Runes cost a flat price ([constant Prices.RUNE_PRICE]).
##
## @tutorial(Items, Runes): docs/design/items.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## How it is aimed, from [constant ContentIds.RUNE_TARGET_KINDS]. [b]unit:[/b] one unit; its
## effects act on it. [b]pair:[/b] two of the caster's own units swap tiles (Recall).
## [b]object:[/b] the map object on a tile the player picks (Spark). Empty is a content error.
@export var target_kind: String = ""

## Which side a [code]unit[/code] rune's unit is on, from [constant ContentIds.RUNE_TARGET_SIDES]:
## [b]player[/b] (the caster's units or a teammate's) or [b]enemy[/b]. Ignored by the other kinds;
## empty on a [code]unit[/code] rune is a content error.
@export var target_side: String = ""

## Whether a [code]unit[/code] rune's unit must not have acted this turn (Haste). Moving without
## acting doesn't count as acting. [b]Off:[/b] any unit of [member target_side].
@export var needs_unacted_target: bool = false


func _validate_property(property: Dictionary) -> void:
	match property["name"]:
		"target_kind":
			ContentIds.apply_hint(property, ContentIds.RUNE_TARGET_KINDS)
		"target_side":
			ContentIds.apply_hint(property, ContentIds.RUNE_TARGET_SIDES)
