# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     open_event_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name OpenEventCommand
extends CampaignCommand
## Opens an event at the Unknown node the run is in: draws it ([method EventDraw.draw]) and rolls
## every seat's options from its own stream ([method EventDraw.roll_seat]), recording
## [constant CampaignFact.Kind.EVENT_DRAWN]. The Unknown node's entry point, built by
## [method EventNode.open].
##
## Valid only inside an Unknown node with no event open there yet, so a continued run shows the
## event it saved and never draws again; rejected when no event is eligible, and the node goes
## on without one. Everything is rolled before anything shows, and the command's save
## ([method CampaignService.submit_command]) keeps it.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The events to draw from.
var pool: EventPool = null

## Content the rolls draw from.
var catalog: EffectCatalog.Index = null

## The item pick odds random items roll with.
var rules: CombatRewardRules = null

## The node's shared [code]EVENT_DRAW[/code] stream.
var draw_stream: RngStream = null

## Each seat's [code]EVENT_OUTCOME[/code] stream at the node, by seat.
var outcome_streams: Dictionary[int, RngStream] = {}


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "open event"


func validate(run: CampaignRunState) -> String:
	if run.flow.stage != RunFlow.Stage.NODE or run.graph == null:
		return "the run isn't inside a node"
	if run.graph.type_of(run.node) != CampaignGraph.NodeType.UNKNOWN:
		return "node %d isn't an Unknown node" % [run.node]
	if run.events.is_open_at(run.floor_number, run.node):
		return "an event is already open at node %d" % [run.node]
	if pool == null or catalog == null or rules == null or draw_stream == null:
		return "the pool, catalog, rules or draw stream is missing"
	for seat_number: int in run.seat_numbers():
		if outcome_streams.get(seat_number, null) == null:
			return "seat %d has no event outcome stream" % [seat_number]
	if EventDraw.eligible(pool, run).is_empty():
		return "no event can be drawn here"
	return ""


func resolve(run: CampaignRunState) -> void:
	var events: EventRunState = run.events
	if EventDraw.is_refill(pool, run, events.seen):
		events.seen = PackedStringArray()
	var event: EventDefinition = EventDraw.draw(pool, run, events.seen, draw_stream)
	var rolls: Dictionary[int, Array] = {}
	for seat_number: int in run.seat_numbers():
		rolls[seat_number] = EventDraw.roll_seat(
				event, run, seat_number, outcome_streams[seat_number], catalog, rules
		)
	events.open(event.id, run.floor_number, run.node, run.seat_numbers(), rolls)
	EventCommand.record_event(run, CampaignFact.Kind.EVENT_DRAWN, CampaignFact.NO_SEAT, run.node)
