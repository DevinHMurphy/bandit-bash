# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_draw.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventDraw
extends RefCounted
## Which event an Unknown node holds, and each seat's rolled options: pure and static, drawing
## only from the streams handed in.
##
## [b]Eligibility:[/b] an event may be drawn when every seat meets its condition (the shrine
## needs a fallen unit in every army, so it is never a free heirloom). [b]The draw[/b] picks
## evenly among the eligible events the run hasn't seen; when none is left, the pool refills, as
## map pools do: the seen list clears and every eligible event can be drawn again.
## [b]Rolls[/b] per seat, options in order: the blocks' items and runes
## ([method EventResolver.roll]), then each tier heirloom in block order, then the tier curse,
## drawn from the whole tier, held curses included.
##
## @tutorial(Events): docs/design/events.md
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md


## The events of [param pool] every seat of [param run] may be drawn for, in pool order.
static func eligible(pool: EventPool, run: CampaignRunState) -> Array[EventDefinition]:
	var found: Array[EventDefinition] = []
	if pool == null or run == null:
		return found
	for event: EventDefinition in pool.events:
		var is_open: bool = not run.seats.is_empty()
		for seat: int in run.seat_numbers():
			is_open = is_open and event.is_eligible(run.seat_run(seat))
		if is_open:
			found.append(event)
	return found


## What the draw picks from for [param run], given the [param seen] ids: the eligible events not
## seen, or every eligible one when none is left (a refill, [method is_refill]). Empty when
## nothing is eligible.
static func candidates(
		pool: EventPool, run: CampaignRunState, seen: PackedStringArray
) -> Array[EventDefinition]:
	var every: Array[EventDefinition] = eligible(pool, run)
	var unseen: Array[EventDefinition] = []
	for event: EventDefinition in every:
		if not seen.has(event.id):
			unseen.append(event)
	return every if unseen.is_empty() else unseen


## Whether drawing for [param run] refills the pool: something is eligible, but nothing unseen.
static func is_refill(pool: EventPool, run: CampaignRunState, seen: PackedStringArray) -> bool:
	for event: EventDefinition in eligible(pool, run):
		if not seen.has(event.id):
			return false
	return not eligible(pool, run).is_empty()


## One event drawn evenly from [method candidates] with [param stream], the node's shared
## [code]EVENT_DRAW[/code] stream; null when nothing is eligible. One candidate draws nothing.
static func draw(
		pool: EventPool, run: CampaignRunState, seen: PackedStringArray, stream: RngStream
) -> EventDefinition:
	var found: Array[EventDefinition] = candidates(pool, run, seen)
	if found.is_empty() or stream == null:
		return null
	return found[0 if found.size() == 1 else stream.pick_index(found.size())]


## Seat [param seat]'s rolls for every option of [param event], in option order, from
## [param stream], its own [code]EVENT_OUTCOME[/code] stream (see the class doc for the order).
## [param rules] supplies the item pick odds.
static func roll_seat(
		event: EventDefinition,
		run: CampaignRunState,
		seat: int,
		stream: RngStream,
		catalog: EffectCatalog.Index,
		rules: CombatRewardRules
) -> Array[EventRolls]:
	var rolled: Array[EventRolls] = []
	var seat_run: SeatRun = run.seat_run(seat)
	for option: EventOption in event.options:
		var rolls: EventRolls = EventResolver.roll(option, seat_run, stream, catalog, rules)
		_draw_heirlooms(option, rolls, run, seat_run, stream, catalog)
		if option.curse_id.is_empty() and not option.curse_tier.is_empty():
			rolls.curse_id = draw_curse(option.curse_tier, stream, catalog)
		rolled.append(rolls)
	return rolled


## A curse of [param tier] drawn evenly from [param stream], among every curse of the tier, held
## ones included (a repeat adds a copy); empty when the tier has none.
static func draw_curse(tier: String, stream: RngStream, catalog: EffectCatalog.Index) -> String:
	var tier_ids: PackedStringArray = []
	for definition: Resource in catalog.all_of(EffectCatalog.Kind.CURSE):
		var curse: CurseDefinition = definition as CurseDefinition
		if curse != null and curse.tier == tier:
			tier_ids.append(curse.id)
	tier_ids.sort()
	if tier_ids.is_empty():
		return ""
	return tier_ids[0 if tier_ids.size() == 1 else stream.pick_index(tier_ids.size())]


## The heirlooms of [param tier] [param seat_run] may be given: not curses, not owned, not in
## [param drawn] (the option's earlier draws) or [param excluded] (a unique one a teammate owns,
## [method UniqueClaims.owned_by_teammates]), and co-op-only ones only in a run of more than one
## seat ([param is_coop]). Sorted by id.
static func heirloom_candidates(
		tier: String,
		seat_run: SeatRun,
		drawn: PackedStringArray,
		is_coop: bool,
		catalog: EffectCatalog.Index,
		excluded: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	var owned: PackedStringArray = seat_run.heirloom_ids()
	var found: PackedStringArray = []
	for definition: Resource in catalog.all_of(EffectCatalog.Kind.HEIRLOOM):
		var heirloom: HeirloomDefinition = definition as HeirloomDefinition
		if heirloom == null or heirloom is CurseDefinition or heirloom.tier != tier:
			continue
		if owned.has(heirloom.id) or drawn.has(heirloom.id) or excluded.has(heirloom.id):
			continue
		if heirloom.is_coop_only and not is_coop:
			continue
		found.append(heirloom.id)
	found.sort()
	return found


# Each tier heirloom block of option draws into rolls.picks by its index, in block order, each
# different from the option's earlier ones; an empty pool leaves the pick empty.
static func _draw_heirlooms(
		option: EventOption,
		rolls: EventRolls,
		run: CampaignRunState,
		seat_run: SeatRun,
		stream: RngStream,
		catalog: EffectCatalog.Index
) -> void:
	var drawn: PackedStringArray = []
	var is_coop: bool = run.seats.size() > 1
	for index: int in option.outcomes.size():
		var block: HeirloomOutcome = option.outcomes[index] as HeirloomOutcome
		if block == null or not block.is_tier_draw():
			continue
		var found: PackedStringArray = heirloom_candidates(
				block.tier, seat_run, drawn, is_coop, catalog,
				UniqueClaims.owned_by_teammates(run, seat_run.seat, catalog)
		)
		var picked: String = ""
		if not found.is_empty():
			picked = found[0 if found.size() == 1 else stream.pick_index(found.size())]
			drawn.append(picked)
		rolls.picks[index] = picked
