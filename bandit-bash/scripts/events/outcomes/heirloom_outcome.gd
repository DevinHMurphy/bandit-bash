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
## Gives a named heirloom ("gain a rare heirloom", once drawn). Curses go through [CurseOutcome].
##
## The draw of a random heirloom from a tier happens when the event is made, with the curse
## draw, so this block only ever applies a named one. A second copy of an owned heirloom is a
## second entry, and both apply. Records [constant CampaignFact.Kind.GAINED].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## Content id of the [HeirloomDefinition] given; never a curse.
@export var heirloom_id: String = ""


func validate(ctx: EventContext, _index: int) -> String:
	var heirloom: HeirloomDefinition = ctx.catalog.heirloom(heirloom_id)
	if heirloom == null or heirloom is CurseDefinition:
		return "heirloom \"%s\" isn't in the catalog" % [heirloom_id]
	return ""


func apply(ctx: EventContext, _index: int) -> void:
	ctx.seat_run().add_heirloom(heirloom_id)
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, ctx.seat)
	gained.definition_id = heirloom_id
	ctx.run.record(gained)
