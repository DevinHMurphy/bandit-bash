# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     gold_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name GoldOutcome
extends EventOutcome
## Gains or pays gold: "gain 40 gold", "pay the toll: lose 30 gold".
##
## A payment the seat can't afford is refused, never taken down to 0; the option's
## [EventRequirements] usually greys it out first. Records
## [constant CampaignFact.Kind.GOLD_CHANGED].
##
## @tutorial(Events): docs/design/events.md

## Gold gained; negative pays it.[br]
## [b]Units:[/b] gold. [b]0:[/b] nothing changes.
@export_range(-1000, 1000, 1, "or_greater", "or_less") var amount: int = 0


func validate(ctx: EventContext, _index: int) -> String:
	var gold: int = ctx.seat_run().gold
	if gold + amount < 0:
		return "needs %d gold, has %d" % [-amount, gold]
	return ""


func apply(ctx: EventContext, _index: int) -> void:
	if amount == 0:
		return
	ctx.seat_run().gold += amount
	EventOutcome.record(ctx, CampaignFact.Kind.GOLD_CHANGED, "", amount)
