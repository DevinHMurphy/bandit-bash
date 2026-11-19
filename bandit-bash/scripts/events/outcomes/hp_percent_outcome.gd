# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hp_percent_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name HpPercentOutcome
extends EventOutcome
## Heals or damages units by a share of their max HP: "every unit heals 20% of its max HP",
## "every unit takes damage equal to 20% of its max HP".
##
## Both round halves up. A heal is scaled by the seat's healing received
## ([member EventContext.healing_percent]: Cursed Blood halves it) and stops at max HP. Event
## damage never kills: it leaves at least 1 HP. Records [constant CampaignFact.Kind.HP_CHANGED]
## for each unit whose HP moved.
##
## @tutorial(Events): docs/design/events.md

## The fewest HP event damage leaves a unit.
const MIN_HP_LEFT: int = 1

## Which units it acts on.
@export var target: EventOutcome.Target = EventOutcome.Target.EVERY

## The share of each unit's max HP healed; negative deals it as damage.[br]
## [b]Units:[/b] percent of max HP. [b]0:[/b] nothing changes. [b]100:[/b] a full heal.
@export_range(-100, 100) var percent: int = 0


func chooser() -> EventOutcome.Chooser:
	if target == EventOutcome.Target.CHOSEN:
		return EventOutcome.Chooser.UNIT
	return EventOutcome.Chooser.NONE


func validate(ctx: EventContext, _index: int) -> String:
	return EventOutcome.target_problem(ctx, target)


func apply(ctx: EventContext, _index: int) -> void:
	for unit: UnitInstance in EventOutcome.targets(ctx, target):
		var unit_max: int = EventOutcome.max_hp(unit, ctx.catalog)
		var before: int = EventOutcome.current_hp(unit, unit_max)
		var after: int = before
		if percent > 0:
			var healed: int = EventOutcome.percent_of(
					unit_max, percent * ctx.healing_percent / _PERCENT
			)
			after = mini(before + maxi(healed, 0), unit_max)
		elif percent < 0:
			var damage: int = EventOutcome.percent_of(unit_max, -percent)
			after = maxi(before - damage, mini(MIN_HP_LEFT, before))
		EventOutcome.set_hp(ctx, unit, after, unit_max, before)
