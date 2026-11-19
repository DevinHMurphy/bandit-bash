# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     prefix_reroll_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name PrefixRerollOutcome
extends EventOutcome
## Re-rolls a chosen unit's prefix for free: it can come out worse, never the same
## ([method UnitPrefixDefinition.reroll], the Guildhall's roll).
##
## Drawn as the option applies, from the seat's [code]EVENT_OUTCOME[/code] stream, since the unit
## is picked after the option. A commander never has a prefix, so it can't be chosen. Current HP
## follows the new max HP as a stat change's does. Records
## [constant CampaignFact.Kind.UNIT_CHANGED], and [constant CampaignFact.Kind.HP_CHANGED] when
## current HP moved.
##
## @tutorial(Unit roster, Prefixes): docs/design/unit-roster.md


func chooser() -> EventOutcome.Chooser:
	return EventOutcome.Chooser.UNIT


func validate(ctx: EventContext, _index: int) -> String:
	var problem: String = EventOutcome.target_problem(ctx, EventOutcome.Target.CHOSEN)
	if not problem.is_empty():
		return problem
	var unit: UnitInstance = EventOutcome.living_unit(ctx.seat_run(), ctx.choice.unit_id)
	var unit_type: UnitTypeDefinition = unit.definition(ctx.catalog)
	if unit_type == null:
		return "%s's unit type isn't in the catalog" % [unit.instance_id]
	if unit_type.is_commander:
		return "%s is a commander, which never has a prefix" % [unit.instance_id]
	if ctx.stream == null:
		return "no stream to re-roll the prefix from"
	return ""


func apply(ctx: EventContext, _index: int) -> void:
	var unit: UnitInstance = EventOutcome.living_unit(ctx.seat_run(), ctx.choice.unit_id)
	var old_max: int = EventOutcome.max_hp(unit, ctx.catalog)
	unit.prefix_id = UnitPrefixDefinition.reroll(ctx.stream, ctx.catalog, unit.prefix_id)
	EventOutcome.record(ctx, CampaignFact.Kind.UNIT_CHANGED, unit.instance_id)
	EventOutcome.follow_max_hp(ctx, unit, old_max)
