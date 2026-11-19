# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stat_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

@tool
class_name StatOutcome
extends EventOutcome
## Permanently changes a stat, max HP or Hit: "+2 MGT", "loses 4 max HP", "+10 Hit".
##
## The change is a sourced delta on the unit, named after the event in breakdowns, the same data
## [ChangeBaseStat] writes in battle. A max HP gain raises current HP by as much; a loss lowers
## current HP only where it is above the new max, and never takes max HP below 1. Records
## [constant CampaignFact.Kind.UNIT_CHANGED] per unit, and
## [constant CampaignFact.Kind.HP_CHANGED] when its current HP moved.
##
## @tutorial(Events): docs/design/events.md

## The lowest max HP a loss leaves.
const MIN_MAX_HP: int = 1

## Which units it acts on.
@export var target: EventOutcome.Target = EventOutcome.Target.CHOSEN

## The stat changed: a [enum CombatValue.Stat] (HP is max HP), or
## [constant CombatValue.HIT_STAT] for Hit ([constant CombatValue.PERMANENT_KEYS]).
@export var stat: int = CombatValue.Stat.MGT

## The change; negative lowers it.[br]
## [b]Units:[/b] the stat's own (HP, points, or Hit percent). [b]0:[/b] nothing changes.
@export_range(-20, 20) var amount: int = 0


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "stat":
		var names: PackedStringArray = []
		for each: int in CombatValue.PERMANENT_KEYS:
			var key: Variant = CombatValue.Stat.find_key(each)
			names.append("%s:%d" % ["HIT" if key == null else key as String, each])
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = ",".join(names)


func chooser() -> EventOutcome.Chooser:
	if target == EventOutcome.Target.CHOSEN:
		return EventOutcome.Chooser.UNIT
	return EventOutcome.Chooser.NONE


func validate(ctx: EventContext, _index: int) -> String:
	if not CombatValue.PERMANENT_KEYS.has(stat):
		return "stat %d can't change permanently" % [stat]
	return EventOutcome.target_problem(ctx, target)


func apply(ctx: EventContext, _index: int) -> void:
	for unit: UnitInstance in EventOutcome.targets(ctx, target):
		var old_max: int = EventOutcome.max_hp(unit, ctx.catalog)
		var change: int = amount
		if stat == CombatValue.Stat.HP:
			change = maxi(amount, MIN_MAX_HP - old_max)
		if change == 0:
			continue
		unit.stat_deltas.append(ItemInstance.StatDelta.new(
				CombatValue.PERMANENT_KEYS[stat], float(change), ctx.event_id(), ctx.label()
		))
		EventOutcome.record(ctx, CampaignFact.Kind.UNIT_CHANGED, unit.instance_id, change)
		if stat == CombatValue.Stat.HP:
			EventOutcome.follow_max_hp(ctx, unit, old_max)
