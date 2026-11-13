# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_start.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name RunStart
extends RefCounted
## Builds a new run's [CampaignRunState]: the map from [CampaignMapGenerator], and per seat, in seat
## order, the faction's starting army ([StartingArmy]), its starting gold, its Commander Heirloom,
## three empty rune slots and the rare offset at its start.
##
## Pure: it draws only from the map stream and mints only from the allocator it is given, so the
## same seed and the same counter give the same run (the run's [code]MAP_GENERATION[/code] stream
## and its [InstanceIdAllocator] as a new run has them). Records
## [constant CampaignFact.Kind.RUN_STARTED] once per seat. Bad content is reported in
## [member problems], never guessed at; a map that can't be made leaves [member run] null.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The run built; null when the map couldn't be made.
var run: CampaignRunState = null

## What was wrong with the content, one line each. The run still builds without the bad part.
var problems: PackedStringArray = []


## A new run on [param rules], its map drawn from [param map_stream], for every seat of
## [param factions] (seat to faction content id), from [param catalog], ids from [param ids].
static func build(
		rules: CampaignMapRules,
		map_stream: RngStream,
		catalog: EffectCatalog.Index,
		factions: Dictionary[int, String],
		ids: InstanceIdAllocator
) -> RunStart:
	var start: RunStart = RunStart.new()
	var graph: CampaignGraph = CampaignMapGenerator.generate(rules, map_stream)
	if graph == null:
		start.problems.append("the campaign map couldn't be generated")
		return start
	var built: CampaignRunState = CampaignRunState.new()
	built.graph = graph
	var seat_order: Array[int] = []
	seat_order.assign(factions.keys())
	seat_order.sort()
	for seat: int in seat_order:
		built.seats[seat] = _seat_run(start, catalog, seat, factions[seat], ids)
		var started: CampaignFact = CampaignFact.new(CampaignFact.Kind.RUN_STARTED, seat)
		started.definition_id = factions[seat]
		built.record(started)
	start.run = built
	return start


# One seat's start: the faction's army and gold, its heirlooms (the Commander Heirloom), empty
# rune slots and the rare offset at its start.
static func _seat_run(
		start: RunStart,
		catalog: EffectCatalog.Index,
		seat: int,
		faction_id: String,
		ids: InstanceIdAllocator
) -> SeatRun:
	var seat_run: SeatRun = SeatRun.new(seat)
	seat_run.faction_id = faction_id
	var army: StartingArmy = StartingArmy.build(catalog, faction_id, ids)
	for problem: String in army.problems:
		start.problems.append("seat %d: %s" % [seat, problem])
	seat_run.army = army.units
	seat_run.items = army.items
	seat_run.commander_id = army.commander_id
	for heirloom_id: String in army.heirloom_ids:
		seat_run.add_heirloom(heirloom_id)
	var faction: FactionDefinition = catalog.faction(faction_id)
	seat_run.gold = faction.starting_gold if faction != null else 0
	return seat_run
