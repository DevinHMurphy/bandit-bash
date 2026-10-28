# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_grant.gd
# Author:
# Created:  October 26, 2026
# Modified: October 28, 2026
# ==============================================================================

@tool
class_name CampaignGrant
extends EffectOperation
## Grants the owner's player something on the campaign layer: gold, a heirloom, a recruit or a rune
## ("gain 50 gold", "gain the rune mend").
##
## Queued. Used by Gained effects (War Chest, Family Relic) and by narrative event outcomes. In
## combat it adds to [member EffectEngine.grants] when its reaction resolves; the [CombatSession]
## hands each one to the [CampaignSession], which records it, and the run flow applies it.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## What is granted. Saved as an int: [b]append only[/b].
enum Grant {
	## [member amount] gold.
	GOLD = 0,
	## A heirloom.
	HEIRLOOM = 1,
	## A recruit for the army.
	RECRUIT = 2,
	## A rune for the player's rune slots.
	RUNE = 3,
}

## What is granted.
@export var grant: Grant = Grant.GOLD

## Gold granted, for [constant GOLD]; ignored otherwise.
@export_range(0, 9999) var amount: int = 0

## Content id of the heirloom, unit type or rune granted. Ignored for [constant GOLD].
##
## [b]Empty:[/b] the text says "a heirloom" without naming one; who picks it is the operation's
## runtime rule.
@export var definition_id: String = ""


func describe() -> String:
	match grant:
		Grant.HEIRLOOM:
			return _grant_text("an heirloom", "the heirloom")
		Grant.RECRUIT:
			return "recruit a unit" if definition_id.is_empty() else "recruit %s" % [definition_id]
		Grant.RUNE:
			return _grant_text("a rune", "the rune")
	return "gain %d gold" % [amount]


## Adds the grant, for the owner's seat, to [member EffectEngine.grants]. A sandbox's engine keeps
## its own list, so a forecast grants nothing.
func apply(ctx: EffectContext) -> void:
	var record: EffectEngine.Grant = EffectEngine.Grant.new()
	record.seat = ctx.instance.owner.seat
	record.grant = grant
	record.amount = amount
	record.definition_id = definition_id
	record.source_effect_id = ctx.instance.instance_id
	ctx.engine.grants.append(record)


func _grant_text(unnamed: String, named: String) -> String:
	if definition_id.is_empty():
		return "gain %s" % [unnamed]
	return "gain %s %s" % [named, definition_id]
