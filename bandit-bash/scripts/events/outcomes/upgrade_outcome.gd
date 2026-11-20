# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     upgrade_outcome.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name UpgradeOutcome
extends EventOutcome
## Upgrades a unit as a Camp's Train does ("Archer+"): "upgrade a chosen unit" (events.md, The
## Clockwork Hermit's Augment Unit).
##
## Goes through [method RunOperations.upgrade], so the rules are Train's: a commander is never
## upgraded, nor a unit upgraded already, and a max-HP gain raises a hurt unit's HP by as much.
## [constant EventOutcome.Target.EVERY] upgrades each living unit that can be and is refused only
## when none can. Records [constant CampaignFact.Kind.UNIT_UPGRADED] per unit, and
## [constant CampaignFact.Kind.HP_CHANGED] when its current HP moved.
##
## @tutorial(Events): docs/design/events.md

## Which units it upgrades. [constant EventOutcome.Target.COMMANDER] is always refused.
@export var target: EventOutcome.Target = EventOutcome.Target.CHOSEN


func chooser() -> EventOutcome.Chooser:
	if target == EventOutcome.Target.CHOSEN:
		return EventOutcome.Chooser.UNIT
	return EventOutcome.Chooser.NONE


func validate(ctx: EventContext, _index: int) -> String:
	var problem: String = EventOutcome.target_problem(ctx, target)
	if not problem.is_empty():
		return problem
	var units: Array[UnitInstance] = EventOutcome.targets(ctx, target)
	if target == EventOutcome.Target.EVERY:
		for unit: UnitInstance in units:
			if _problem(ctx, unit).is_empty():
				return ""
		return "no unit can be upgraded"
	for unit: UnitInstance in units:
		var unit_problem: String = _problem(ctx, unit)
		if not unit_problem.is_empty():
			return unit_problem
	return ""


func apply(ctx: EventContext, _index: int) -> void:
	for unit: UnitInstance in EventOutcome.targets(ctx, target):
		# ASSUMPTION: "every unit" skips the commander and units upgraded already.
		if _problem(ctx, unit).is_empty():
			RunOperations.upgrade(ctx.run, ctx.seat, unit.instance_id, ctx.catalog, ctx.event_id())


func _problem(ctx: EventContext, unit: UnitInstance) -> String:
	return RunOperations.upgrade_problem(ctx.run, ctx.seat, unit.instance_id, ctx.catalog)
