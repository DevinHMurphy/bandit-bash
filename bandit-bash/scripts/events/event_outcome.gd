# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventOutcome
extends Resource
## One block of an event option's outcome on the campaign layer: gold, a heal, a stat change, an
## item, a curse. Each kind is its own subclass in [code]scripts/events/outcomes/[/code].
##
## [EventResolver] drives every block of an option in three passes: [method roll] before the
## option shows (its random parts, saved by the caller), [method validate] against the seat's
## run and the player's [EventChoice], then [method apply], which records a [CampaignFact] for
## every change. A block reads and writes only the [EventContext] it is handed: no nodes, no
## autoloads, no global RNG. Read-only at runtime, like every content definition.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md
##
## @todo: TOD-001 - Recruit, upgrade and max army size blocks (EV1F), on RN6's run operations.

## Which units a block acts on.
enum Target {
	## The unit the player picks after choosing the option, from the living army.
	CHOSEN = 0,
	## Every unit in the living army.
	EVERY = 1,
	## The army's commander.
	COMMANDER = 2,
}

## What the player must pick after choosing the option, if anything.
enum Chooser {
	## Nothing.
	NONE = 0,
	## A living unit ([member EventChoice.unit_id]).
	UNIT = 1,
	## A weapon or staff on a living unit or in the convoy ([member EventChoice.weapon_id]).
	WEAPON = 2,
	## A fallen unit ([member EventChoice.unit_id]); only the revive shrine asks for one.
	FALLEN_UNIT = 3,
}

const _PERCENT: float = 100.0

# TODO(TOD-001): EV1F's recruit, upgrade and max army size blocks extend this class here.


## What the player must pick for this block. [constant Chooser.NONE] by default.
func chooser() -> Chooser:
	return Chooser.NONE


## Whether [method roll] draws this block's content at random. False by default.
func draws() -> bool:
	return false


## This block's random part, drawn from [param stream] for [param seat_run]: a content id, such
## as a random item's, which [EventRolls] keeps by the block's index. Empty when the block draws
## nothing ([method draws]) or its pool is empty. [param rules] supplies the item pick odds.
func roll(
		_stream: RngStream,
		_seat_run: SeatRun,
		_catalog: EffectCatalog.Index,
		_rules: CombatRewardRules
) -> String:
	return ""


## Why the option can't be offered for this block, at [param index], whatever the player picks:
## an empty reward pool. Empty when it can.
func offer_problem(_ctx: EventContext, _index: int) -> String:
	return ""


## Why this block, at [param index] in its option, can't apply to [param ctx] now. Empty when it
## can. Changes nothing.
func validate(_ctx: EventContext, _index: int) -> String:
	return ""


## Applies this block, at [param index] in its option, to [param ctx], once [method validate]
## passed, recording a fact for every change.
func apply(_ctx: EventContext, _index: int) -> void:
	pass


## The units [param target] names in [param ctx]'s seat, in roster order. Empty when a chosen or
## commander target is missing; [method target_problem] says why.
static func targets(ctx: EventContext, target: Target) -> Array[UnitInstance]:
	var seat_run: SeatRun = ctx.seat_run()
	var found: Array[UnitInstance] = []
	match target:
		Target.EVERY:
			found.append_array(seat_run.army)
		Target.CHOSEN:
			var unit: UnitInstance = living_unit(seat_run, ctx.choice.unit_id)
			if unit != null:
				found.append(unit)
		Target.COMMANDER:
			var commander: UnitInstance = living_unit(seat_run, seat_run.commander_id)
			if commander != null:
				found.append(commander)
	return found


## Why [param target] names no unit in [param ctx]'s seat; empty when it names one, or the army.
## A fallen unit can't be chosen.
static func target_problem(ctx: EventContext, target: Target) -> String:
	var seat_run: SeatRun = ctx.seat_run()
	match target:
		Target.CHOSEN:
			if ctx.choice.unit_id.is_empty():
				return "choose a unit"
			if living_unit(seat_run, ctx.choice.unit_id) == null:
				return "%s isn't a living unit of the army" % [ctx.choice.unit_id]
		Target.COMMANDER:
			if living_unit(seat_run, seat_run.commander_id) == null:
				return "the army has no living commander"
	return ""


## The unit [param unit_id] in [param seat_run]'s living army; null for a fallen or unknown one.
static func living_unit(seat_run: SeatRun, unit_id: String) -> UnitInstance:
	if unit_id.is_empty():
		return null
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == unit_id:
			return unit
	return null


## [param unit]'s max HP outside battle, as [Loadout] loads it.
static func max_hp(unit: UnitInstance, catalog: EffectCatalog.Index) -> int:
	return unit.stats(catalog).get_int(CombatValue.Key.HP)


## [param unit]'s current HP as a number, reading [constant UnitInstance.FULL_HP] as
## [param unit_max].
static func current_hp(unit: UnitInstance, unit_max: int) -> int:
	return unit_max if unit.hp == UnitInstance.FULL_HP else unit.hp


## Sets [param unit]'s HP to [param hp] out of [param unit_max], storing a full unit as
## [constant UnitInstance.FULL_HP], and records [constant CampaignFact.Kind.HP_CHANGED] for a
## change from [param before].
static func set_hp(
		ctx: EventContext, unit: UnitInstance, hp: int, unit_max: int, before: int
) -> void:
	unit.hp = UnitInstance.FULL_HP if hp >= unit_max else hp
	if hp != before:
		record(ctx, CampaignFact.Kind.HP_CHANGED, unit.instance_id, hp - before)


## Brings [param unit]'s current HP in line with a max HP that moved from [param old_max]: a
## gain raises it by as much, a loss lowers it only where it is above the new max.
static func follow_max_hp(ctx: EventContext, unit: UnitInstance, old_max: int) -> void:
	var new_max: int = max_hp(unit, ctx.catalog)
	var before: int = current_hp(unit, old_max)
	var after: int = before + maxi(new_max - old_max, 0)
	set_hp(ctx, unit, mini(after, new_max), new_max, before)


## Records a fact of [param kind] for [param ctx]'s seat about [param actor_id], sourced to the
## event ([member CampaignFact.definition_id]), with [param amount].
static func record(
		ctx: EventContext, kind: CampaignFact.Kind, actor_id: String, amount: int = 0
) -> CampaignFact:
	var fact: CampaignFact = CampaignFact.new(kind, ctx.seat, actor_id)
	fact.definition_id = ctx.event_id()
	fact.amount = amount
	ctx.run.record(fact)
	return fact


## [param value] percent of [param whole], halves up.
static func percent_of(whole: int, value: float) -> int:
	return ValueBreakdown.round_to_int(whole * value / _PERCENT, ValueBreakdown.Rounding.HALF_UP)
