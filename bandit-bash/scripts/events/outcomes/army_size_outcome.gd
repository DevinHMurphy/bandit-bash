# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     army_size_outcome.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name ArmySizeOutcome
extends EventOutcome
## Grows the army's max size: "+1 max army size" (events.md, Mercenary Camp's Sign a Company
## Charter). The convoy grows with it.
##
## Goes through [method RunOperations.grow_army]: a saved value change on the seat, read by
## [method RunOperations.max_army_size], never past the ceiling of 8; only the part that fits is
## added. Refused when the army is at the ceiling already (the Charter's requirement greys the
## option out first). Records [constant CampaignFact.Kind.ARMY_SIZE_CHANGED].
##
## @tutorial(Events): docs/design/events.md

## How much max army size grows.[br]
## [b]Units:[/b] units of army size. [b]1:[/b] one more unit (the Charter).
@export_range(1, 7) var amount: int = 1


func validate(ctx: EventContext, _index: int) -> String:
	return RunOperations.army_size_problem(ctx.run, ctx.seat, amount, ctx.catalog)


func apply(ctx: EventContext, _index: int) -> void:
	RunOperations.grow_army(ctx.run, ctx.seat, amount, ctx.catalog, ctx.event_id(), ctx.label())
