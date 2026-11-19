# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name HeirloomOutcome
extends EventOutcome
## Gives an heirloom: a named one, or one drawn from a tier ("gain a rare heirloom"). Curses go
## through [CurseOutcome].
##
## A tier's heirloom is drawn when the event is made, with the curse draw ([EventDraw]), into
## [member EventRolls.picks], so the player sees which one before choosing; an empty pool greys
## the option out. A second copy of an owned heirloom is a second entry, and both apply. Records
## [constant CampaignFact.Kind.GAINED].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## Content id of the [HeirloomDefinition] given; never a curse. [b]Empty:[/b] one drawn from
## [member tier].
@export var heirloom_id: String = ""

## The tier the heirloom is drawn from when [member heirloom_id] is empty, from
## [constant ContentIds.HEIRLOOM_TIERS], such as [code]rare[/code]. [b]Empty:[/b] none drawn.
@export var tier: String = ""


## Whether the heirloom is drawn from [member tier] when the event is made.
func is_tier_draw() -> bool:
	return heirloom_id.is_empty() and not tier.is_empty()


func offer_problem(ctx: EventContext, index: int) -> String:
	if is_tier_draw() and ctx.rolls.pick(index).is_empty():
		return "no heirloom is left to give"
	return ""


func validate(ctx: EventContext, index: int) -> String:
	var given: String = _picked(ctx, index)
	var heirloom: HeirloomDefinition = ctx.catalog.heirloom(given)
	if heirloom == null or heirloom is CurseDefinition:
		return "heirloom \"%s\" isn't in the catalog" % [given]
	return ""


func apply(ctx: EventContext, index: int) -> void:
	var given: String = _picked(ctx, index)
	ctx.seat_run().add_heirloom(given)
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, ctx.seat)
	gained.definition_id = given
	ctx.run.record(gained)


func _picked(ctx: EventContext, index: int) -> String:
	return ctx.rolls.pick(index) if is_tier_draw() else heirloom_id
