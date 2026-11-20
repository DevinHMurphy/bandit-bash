# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     open_treasure_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name OpenTreasureCommand
extends CampaignCommand
## Rolls every seat's chest at the Treasure node the run is in ([method TreasureChest.roll]), each
## from its own [code]REWARD[/code] stream, and saves them in the seats' pending offers: the
## Treasure screen's entry point, as [OpenEventCommand] is an Unknown node's.
##
## Valid only inside a Treasure node where no seat has a chest yet, so a continued run shows the
## chests it saved and never rolls again. Records no fact: rolling an offer changes no state a
## player sees until it is taken. Everything is rolled before anything shows, and the command's
## save ([method CampaignService.submit_command]) keeps it.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Content the chests draw from.
var catalog: EffectCatalog.Index = null

## Mints each Legendary item's instance id: the session's allocator.
var ids: InstanceIdAllocator = null

## Each seat's [code]REWARD[/code] stream at the node, by seat.
var streams: Dictionary[int, RngStream] = {}


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "open treasure"


func validate(run: CampaignRunState) -> String:
	if not is_at_treasure(run):
		return "the run isn't inside a Treasure node"
	if catalog == null or ids == null:
		return "the catalog or id allocator is missing"
	for seat_number: int in run.seat_numbers():
		if run.seat_run(seat_number).pending_offers.has(TreasureChest.OFFER_KEY):
			return "seat %d's chest is already rolled" % [seat_number]
		if streams.get(seat_number, null) == null:
			return "seat %d has no reward stream" % [seat_number]
	return ""


func resolve(run: CampaignRunState) -> void:
	var is_coop: bool = run.seat_numbers().size() > 1
	for seat_number: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat_number)
		TreasureChest.roll(streams[seat_number], seat_run, catalog, ids, is_coop).store(seat_run)


## The command that rolls the chests at the Treasure node [param session]'s run is in, with each
## seat's [code]REWARD[/code] stream there and the session's allocator, sent from the host seat.
## [param catalog_used] null: the loaded one. Null, reported, with no run.
static func for_session(
		session: CampaignSession, catalog_used: EffectCatalog.Index = null
) -> OpenTreasureCommand:
	if session == null or session.run == null:
		push_error("OpenTreasureCommand: no run to open a Treasure in")
		return null
	var run: CampaignRunState = session.run
	var command: OpenTreasureCommand = OpenTreasureCommand.new(CampaignData.HOST_SEAT)
	command.catalog = catalog_used if catalog_used != null else EffectCatalog.index()
	command.ids = session.ids
	for seat_number: int in run.seat_numbers():
		command.streams[seat_number] = session.rng.stream(RngKey.new(
				RngKey.RngPurpose.REWARD, run.floor_number, run.node, seat_number
		))
	return command


## Whether [param run] is inside a Treasure node.
static func is_at_treasure(run: CampaignRunState) -> bool:
	return (
			run.flow.stage == RunFlow.Stage.NODE
			and run.graph != null and run.graph.has_node_id(run.node)
			and run.graph.type_of(run.node) == CampaignGraph.NodeType.TREASURE
	)
