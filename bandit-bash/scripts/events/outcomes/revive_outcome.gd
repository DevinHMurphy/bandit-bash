# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     revive_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name ReviveOutcome
extends EventOutcome
## The revive shrine's prayer: one chosen fallen unit returns at critical health (events.md,
## Broken Shrine of Valor). The only way back from permadeath.
##
## The unit leaves the fallen list for the end of the army, keeping the items it still holds, at
## [member hp_percent] of its max HP, halves up, at least 1. The only block whose chosen unit is a
## fallen one. Into a full army it works like recruiting past the max: the living unit the player
## names ([member EventChoice.replaced_id]) is dismissed first, its items handed over
## ([method EventOutcome.join_problem], [EventHandOver]), and those given the revived unit go on
## it once it is back. Records [constant CampaignFact.Kind.UNIT_DISMISSED] for that, then
## [constant CampaignFact.Kind.UNIT_REVIVED] with its HP.
##
## @tutorial(Events): docs/design/events.md

## The fewest HP a revived unit returns with.
const MIN_HP: int = 1

## The share of max HP the unit returns with (events.md: 10%).[br]
## [b]Units:[/b] percent of max HP. [b]100:[/b] full health.
@export_range(1, 100) var hp_percent: int = 10


func chooser() -> EventOutcome.Chooser:
	return EventOutcome.Chooser.FALLEN_UNIT


func validate(ctx: EventContext, index: int) -> String:
	var seat_run: SeatRun = ctx.seat_run()
	if ctx.choice.unit_id.is_empty():
		return "choose a fallen unit"
	if _fallen(seat_run, ctx.choice.unit_id) == null:
		return "%s isn't a fallen unit of the army" % [ctx.choice.unit_id]
	return EventOutcome.join_problem(ctx, joining(ctx, index))


func apply(ctx: EventContext, _index: int) -> void:
	var seat_run: SeatRun = ctx.seat_run()
	var unit: UnitInstance = _fallen(seat_run, ctx.choice.unit_id)
	var taken: PackedStringArray = EventHandOver.set_aside(
			ctx.run, ctx.seat, ctx.choice.replaced_id, ctx.choice.hand_over, ctx.catalog
	)
	EventOutcome.make_room(ctx, unit.instance_id)
	seat_run.fallen.erase(unit)
	seat_run.army.append(unit)
	var unit_max: int = EventOutcome.max_hp(unit, ctx.catalog)
	var hp: int = maxi(EventOutcome.percent_of(unit_max, hp_percent), MIN_HP)
	unit.hp = UnitInstance.FULL_HP if hp >= unit_max else hp
	EventOutcome.record(ctx, CampaignFact.Kind.UNIT_REVIVED, unit.instance_id, hp)
	EventHandOver.hand_to(ctx.run, ctx.seat, unit, taken, ctx.catalog)


## The chosen fallen unit with the items it still holds, as it would return; null with none chosen.
## Read only: the unit is the run's own, not a copy.
func joining(ctx: EventContext, _index: int) -> RecruitOffer:
	var seat_run: SeatRun = ctx.seat_run()
	var unit: UnitInstance = _fallen(seat_run, ctx.choice.unit_id)
	if unit == null:
		return null
	var returning: RecruitOffer = RecruitOffer.new()
	returning.unit = unit
	for item_id: String in unit.item_ids():
		if seat_run.items.has(item_id):
			returning.items[item_id] = seat_run.items[item_id]
	return returning


static func _fallen(seat_run: SeatRun, unit_id: String) -> UnitInstance:
	for unit: UnitInstance in seat_run.fallen:
		if unit.instance_id == unit_id:
			return unit
	return null
