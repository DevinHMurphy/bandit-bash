# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventOutcome
extends Resource
## One block of an event option's outcome on the campaign layer: gold, a heal, a stat change, an
## item, a recruit, a curse. Each kind is its own subclass in [code]scripts/events/outcomes/[/code];
## the ones that change the army go through [RunOperations].
##
## [EventResolver] drives every block of an option in three passes: [method roll] before the
## option shows (its random parts, saved by the caller), [method validate] against the seat's
## run and the player's [EventChoice], then [method apply], which records a [CampaignFact] for
## every change. A block reads and writes only the [EventContext] it is handed: no nodes, no
## autoloads, no global RNG. Read-only at runtime, like every content definition.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

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


## The unit this block, at [param index], brings into [param ctx]'s army as it would join now, with
## its own items, for a full army's hand-over ([EventHandOver]); a recruit's ids are throwaway,
## never the run's. Null for a block that brings none, or one not known until it applies.
func joining(_ctx: EventContext, _index: int) -> RecruitOffer:
	return null


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


## Why one more unit, [param newcomer] ([method joining]; null while unknown), can't join
## [param ctx]'s army now. With room, no unit may be named to dismiss
## ([member EventChoice.replaced_id]) or hand over; in a full army one must be, able to leave: with
## no hand-over as [method RunOperations.dismiss_problem] says, else as
## [method EventHandOver.problem] settles its items. Empty when it can join.
static func join_problem(ctx: EventContext, newcomer: RecruitOffer = null) -> String:
	var seat_run: SeatRun = ctx.seat_run()
	var limit: int = RunOperations.max_army_size(seat_run, ctx.catalog)
	var replaced_id: String = ctx.choice.replaced_id
	if seat_run.army.size() < limit:
		if not replaced_id.is_empty():
			# With room, naming a unit to dismiss is refused rather than ignored.
			return "the army has room (%d of %d), so no unit is dismissed" % [
				seat_run.army.size(), limit,
			]
		if not ctx.choice.hand_over.is_empty():
			return "no unit is dismissed, so nothing is handed over"
		return ""
	if replaced_id.is_empty():
		return "the army is full (%d of %d): choose a unit to dismiss" % [
			seat_run.army.size(), limit,
		]
	if ctx.choice.hand_over.is_empty():
		return RunOperations.dismiss_problem(ctx.run, ctx.seat, replaced_id, ctx.catalog)
	var problem: String = EventHandOver.leave_problem(ctx.run, ctx.seat, replaced_id)
	if not problem.is_empty():
		return problem
	return EventHandOver.problem(
			seat_run, living_unit(seat_run, replaced_id), newcomer, ctx.choice.hand_over,
			ctx.catalog
	)


## Dismisses the unit [param ctx]'s player named to make room ([method join_problem]) for
## [param joining_id], by the event, the items it still holds to the convoy (after
## [method EventHandOver.set_aside]); nothing when none was named.
static func make_room(ctx: EventContext, joining_id: String) -> void:
	if ctx.choice.replaced_id.is_empty():
		return
	RunOperations.dismiss(ctx.run, ctx.seat, ctx.choice.replaced_id, ctx.event_id(), joining_id)


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
