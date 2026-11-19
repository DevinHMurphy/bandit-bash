# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

@abstract
class_name EventCommand
extends CampaignCommand
## A seat's command on the event open at the run's node ([EventChooserCommand],
## [EventVoteCommand], [EventOptionCommand]): what each checks first, and the content each reads.
##
## [EventNode] fills [member pool] and [member catalog] on the host before sending, so resolving
## stays pure: nothing here loads a file or reads an autoload.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The events the open one is looked up in by its saved id.
var pool: EventPool = null

## Content the run's units and items come from.
var catalog: EffectCatalog.Index = null


## Why no event can be acted on in [param run] now: the run outside a node, no event open at its
## node, or the open event missing from [member pool]. Empty when one can.
func open_problem(run: CampaignRunState) -> String:
	if run.flow.stage != RunFlow.Stage.NODE:
		return "the run isn't inside a node"
	if not run.events.is_open_at(run.floor_number, run.node):
		return "no event is open at node %d" % [run.node]
	if pool == null or catalog == null:
		return "the event pool or the catalog is missing"
	if pool.event(run.events.event_id) == null:
		return "event \"%s\" isn't in the pool" % [run.events.event_id]
	return ""


## The event open in [param run], once [method open_problem] passed.
func open_event(run: CampaignRunState) -> EventDefinition:
	return pool.event(run.events.event_id)


## Why [param run]'s [param of_seat] can't choose in the open event: not in it, or already chosen.
## Empty when it can.
static func seat_problem(run: CampaignRunState, of_seat: int) -> String:
	var part: EventRunState.SeatEvent = run.events.seat_event(of_seat)
	if part == null:
		return "seat %d isn't in the event" % [of_seat]
	if part.chosen != EventRunState.NO_OPTION:
		return "seat %d already chose option %d" % [of_seat, part.chosen]
	return ""


## Records a fact of [param kind] for [param of_seat] about the event open in [param run], with
## [param amount] (an option index, or the node).
static func record_event(
		run: CampaignRunState, kind: CampaignFact.Kind, of_seat: int, amount: int
) -> void:
	var fact: CampaignFact = CampaignFact.new(kind, of_seat)
	fact.definition_id = run.events.event_id
	fact.amount = amount
	run.record(fact)
