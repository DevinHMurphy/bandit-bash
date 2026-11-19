# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pending_gain_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name PendingGainOutcome
extends EventOutcome
## Adds a guaranteed gain to a unit's next level-ups: "its next two level-ups each gain +1 MGT".
##
## Stored as a [UnitInstance.PendingGain] sourced to the event, which [LevelUp] adds on top of
## its rolls and spends one level-up at a time. Records [constant CampaignFact.Kind.UNIT_CHANGED]
## per unit.
##
## @tutorial(Events): docs/design/events.md

## Which units it acts on.
@export var target: EventOutcome.Target = EventOutcome.Target.CHOSEN

## The stat each level-up gains.
@export var stat: CombatValue.Stat = CombatValue.Stat.MGT

## Points each level-up adds.[br]
## [b]Units:[/b] stat points. [b]0:[/b] nothing is added.
@export_range(0, 10) var amount: int = 1

## How many of the unit's next level-ups add it.[br]
## [b]Units:[/b] level-ups. [b]0:[/b] nothing is added.
@export_range(0, 10) var level_ups: int = 1


func chooser() -> EventOutcome.Chooser:
	if target == EventOutcome.Target.CHOSEN:
		return EventOutcome.Chooser.UNIT
	return EventOutcome.Chooser.NONE


func validate(ctx: EventContext, _index: int) -> String:
	return EventOutcome.target_problem(ctx, target)


func apply(ctx: EventContext, _index: int) -> void:
	if amount <= 0 or level_ups <= 0:
		return
	for unit: UnitInstance in EventOutcome.targets(ctx, target):
		var gain: UnitInstance.PendingGain = UnitInstance.PendingGain.new()
		gain.stat = stat
		gain.amount = amount
		gain.remaining = level_ups
		gain.source_id = ctx.event_id()
		gain.label = ctx.label()
		unit.pending_gains.append(gain)
		EventOutcome.record(ctx, CampaignFact.Kind.UNIT_CHANGED, unit.instance_id)
