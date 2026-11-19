# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     curse_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name CurseOutcome
extends EventOutcome
## Gives a named curse: a permanent negative heirloom, even one the seat already holds, which
## adds a copy (copies stack).
##
## Drawing a curse from a tier happens when the event is made, never here, so the curse is
## always named before the player chooses; an option's tier curse resolves through this block
## once drawn. Records [constant CampaignFact.Kind.GAINED].
##
## @tutorial(Events, Curses): docs/design/events.md

## Content id of the [CurseDefinition] given.
@export var curse_id: String = ""


func _init(named_curse_id: String = "") -> void:
	curse_id = named_curse_id


func validate(ctx: EventContext, _index: int) -> String:
	if ctx.catalog.curse(curse_id) == null:
		return "curse \"%s\" isn't in the catalog" % [curse_id]
	return ""


func apply(ctx: EventContext, _index: int) -> void:
	ctx.seat_run().add_heirloom(curse_id)
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, ctx.seat)
	gained.definition_id = curse_id
	ctx.run.record(gained)
