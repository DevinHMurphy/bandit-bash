# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_context.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventContext
extends RefCounted
## Everything one event option needs to resolve for one seat: the run, the event and option, the
## player's [EventChoice], the option's [EventRolls], and the content, id allocator and
## [code]EVENT_OUTCOME[/code] stream it draws from.
##
## Built by the caller and handed to [method EventResolver.resolve]; outcome blocks read and write
## only through it. Nothing here is global.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md
##
## @todo: TOD-001 - Read the seat's healing-received percent from the campaign's values (Cursed
## Blood, Cleansed Goblet) once the campaign layer reads them; the caller hands it in until then.

## A seat's healing received with nothing changing it.[br]
## [b]Units:[/b] percent.
const FULL_HEALING_PERCENT: int = 100

## The run the option changes.
var run: CampaignRunState = null

## The seat choosing.
var seat: int = 0

## The event shown.
var event: EventDefinition = null

## The index of the chosen option in [member EventDefinition.options].
var option_index: int = 0

## What the player picked after choosing it.
var choice: EventChoice = EventChoice.new()

## The option's random parts, rolled before it showed.
var rolls: EventRolls = EventRolls.new()

## Content the run's units and items come from.
var catalog: EffectCatalog.Index = null

## Mints the instance ids of new items and runes.
var ids: InstanceIdAllocator = null

## The seat's [code]EVENT_OUTCOME[/code] stream, for draws made as the option applies (a prefix
## re-roll).
var stream: RngStream = null

# TODO(TOD-001): from the campaign's HEALING_RECEIVED_PERCENT once the campaign reads its values.
## Healing the seat's units receive, which scales event heals (Cursed Blood: 50).[br]
## [b]Units:[/b] percent. [b]100:[/b] unchanged. [b]0:[/b] event heals restore nothing.
var healing_percent: int = FULL_HEALING_PERCENT

## Filled in by [EventResolver] as the option applies.
var result: EventResult = EventResult.new()


## The seat's part of the run; null for a seat not in it.
func seat_run() -> SeatRun:
	return null if run == null else run.seat_run(seat)


## The chosen option; null for an index outside the event's options.
func option() -> EventOption:
	if event == null or option_index < 0 or option_index >= event.options.size():
		return null
	return event.options[option_index]


## The event's content id, the source of every fact and delta the option makes.
func event_id() -> String:
	return "" if event == null else event.id


## The event's name, as breakdowns show the changes it makes.
func label() -> String:
	return "" if event == null else event.title


## A context for [param for_seat]'s option [param index] of [param open_event], the event open in
## [param in_run]: its rolls are the seat's saved ones ([member CampaignRunState.events]), the rest
## as given. [param picked] null: nothing picked.
static func of(
		in_run: CampaignRunState,
		for_seat: int,
		open_event: EventDefinition,
		index: int,
		contents: EffectCatalog.Index,
		allocator: InstanceIdAllocator = null,
		outcome_stream: RngStream = null,
		picked: EventChoice = null
) -> EventContext:
	var ctx: EventContext = EventContext.new()
	ctx.run = in_run
	ctx.seat = for_seat
	ctx.event = open_event
	ctx.option_index = index
	ctx.catalog = contents
	ctx.ids = allocator
	ctx.stream = outcome_stream
	ctx.choice = picked if picked != null else EventChoice.new()
	var part: EventRunState.SeatEvent = (
			null if in_run == null else in_run.events.seat_event(for_seat)
	)
	if part != null:
		ctx.rolls = part.rolls_of(index)
	return ctx
