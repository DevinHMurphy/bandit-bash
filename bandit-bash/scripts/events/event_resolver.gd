# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_resolver.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventResolver
extends RefCounted
## Applies one event option to one seat's part of the run, recording [CampaignFact]s.
##
## Three steps, each pure and static: [method roll] draws the option's random parts before it
## shows; [method unmet_reason] says why it is greyed out (an unmet [EventRequirements], or an
## empty reward pool); [method resolve] checks the requirements, every block and the curse
## against the player's [EventChoice], then applies the blocks in order and the curse last. An
## option applies all or nothing: a refusal changes nothing. Draws come only from the stream
## handed in, never the global RNG; no nodes, autoloads or disk.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md


## Draws [param option]'s random parts for [param seat_run] from [param stream], its seat's
## [code]EVENT_OUTCOME[/code] stream, block by block in order ([method EventOutcome.roll]):
## random items with [param rules]' pick odds, random runes. [EventDraw] then draws the tier
## heirlooms and the tier curse.
static func roll(
		option: EventOption,
		seat_run: SeatRun,
		stream: RngStream,
		catalog: EffectCatalog.Index,
		rules: CombatRewardRules
) -> EventRolls:
	var rolls: EventRolls = EventRolls.new()
	if option == null or seat_run == null or stream == null or catalog == null or rules == null:
		push_error("EventResolver: a roll needs the option, seat, stream, catalog and rules")
		return rolls
	for index: int in option.outcomes.size():
		var outcome: EventOutcome = option.outcomes[index]
		if outcome != null and outcome.draws():
			rolls.picks[index] = outcome.roll(stream, seat_run, catalog, rules)
	return rolls


## Why [param ctx]'s option can't be chosen whatever the player picks: an unmet requirement or an
## empty reward pool, as the greyed-out option shows it. Empty when it can be chosen.
static func unmet_reason(ctx: EventContext) -> String:
	var option: EventOption = ctx.option()
	var seat_run: SeatRun = ctx.seat_run()
	if option == null or seat_run == null or ctx.catalog == null:
		return "the option, the seat or the catalog is missing"
	if option.requirements != null:
		var unmet: String = option.requirements.unmet_reason(seat_run, ctx.catalog)
		if not unmet.is_empty():
			return unmet
	for index: int in option.outcomes.size():
		var outcome: EventOutcome = option.outcomes[index]
		if outcome == null:
			return "block %d is missing" % [index]
		var problem: String = outcome.offer_problem(ctx, index)
		if not problem.is_empty():
			return problem
	return ""


## Why [param ctx]'s option can't apply now, as [method resolve] would refuse it: the seat, the
## requirements, every block and the curse against the player's [EventChoice]. Empty when it can.
## Changes nothing, so a command can check every seat before applying any.
static func refusal(ctx: EventContext) -> String:
	return _problem(ctx)


## Applies [param ctx]'s option to its seat, once every check passes (see the class doc). Returns
## the [EventResult]: the facts recorded and any surprise combat, or the reason it was refused.
static func resolve(ctx: EventContext) -> EventResult:
	var result: EventResult = EventResult.new()
	result.seat = ctx.seat
	ctx.result = result
	result.rejected_reason = _problem(ctx)
	if result.is_rejected():
		return result
	var option: EventOption = ctx.option()
	var first: int = ctx.run.fact_log.size()
	for index: int in option.outcomes.size():
		option.outcomes[index].apply(ctx, index)
	var curse: CurseOutcome = _curse_of(ctx)
	if curse != null:
		curse.apply(ctx, option.outcomes.size())
	result.facts = ctx.run.fact_log.slice(first)
	return result


# The first reason ctx's option can't apply now; empty when it can.
static func _problem(ctx: EventContext) -> String:
	if ctx.run == null or ctx.seat_run() == null:
		return "seat %d isn't in the run" % [ctx.seat]
	if ctx.ids == null:
		return "no id allocator for new items and runes"
	var unmet: String = unmet_reason(ctx)
	if not unmet.is_empty():
		return unmet
	var option: EventOption = ctx.option()
	for index: int in option.outcomes.size():
		var problem: String = option.outcomes[index].validate(ctx, index)
		if not problem.is_empty():
			return problem
	if option.has_curse():
		var curse: CurseOutcome = _curse_of(ctx)
		if curse == null:
			return "the option's %s curse isn't named yet" % [option.curse_tier]
		var problem: String = curse.validate(ctx, option.outcomes.size())
		if not problem.is_empty():
			return problem
		var drawn: CurseDefinition = ctx.catalog.curse(curse.curse_id)
		if option.curse_id.is_empty() and drawn.tier != option.curse_tier:
			return "%s isn't a %s curse" % [drawn.display_name, option.curse_tier]
	return ""


# The option's curse as a block: its named curse, else the one drawn for its tier; null when it
# has none, or its tier's isn't drawn yet.
static func _curse_of(ctx: EventContext) -> CurseOutcome:
	var option: EventOption = ctx.option()
	var curse_id: String = option.curse_id
	if curse_id.is_empty() and not option.curse_tier.is_empty():
		curse_id = ctx.rolls.curse_id
	return null if curse_id.is_empty() else CurseOutcome.new(curse_id)
