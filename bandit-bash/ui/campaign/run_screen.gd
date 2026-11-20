# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name RunScreen
extends RefCounted
## Which screen a solo run belongs on, from its stage: the one place that decides, so the loading
## gate, the battle screen and every campaign screen route alike, and a continued run reopens
## where it was saved.
##
## On the map: the starting heirloom offer while the seat's is open ([StartingOffer]), else the
## campaign map. Inside a combat node (Standard, Key, Boss): the battle screen. Inside a Treasure,
## a Camp or an Armory: its own screen. Inside an Unknown node with an event open: the event screen, or the
## battle screen once the event chose a surprise combat. Inside any other node: the placeholder,
## until its own screen exists. At a combat's results: Results. Outside a solo run (none, or
## co-op): the battle screen, which shows the co-op
## placeholder. Each campaign screen opened at the wrong stage sends the run on with [method go].
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Whether [param session] is a solo run with its campaign state: the runs these screens serve.
static func is_solo_run(session: CampaignSession) -> bool:
	return session != null and session.run != null and session.mode == CampaignData.Mode.SOLO


## Whether a node of [param type] is fought on the battle screen.
static func is_combat(type: CampaignGraph.NodeType) -> bool:
	return (
			type == CampaignGraph.NodeType.STANDARD
			or type == CampaignGraph.NodeType.KEY
			or type == CampaignGraph.NodeType.BOSS
	)


## The screen [param session]'s run belongs on (see the class doc).
static func of(session: CampaignSession) -> SceneRouter.Screen:
	if not is_solo_run(session):
		return SceneRouter.Screen.GAMEPLAY
	var run: CampaignRunState = session.run
	match run.flow.stage:
		RunFlow.Stage.MAP:
			if StartingOffer.is_open(run.seat_run(session.seats[0])):
				return SceneRouter.Screen.STARTING_HEIRLOOM
			return SceneRouter.Screen.CAMPAIGN_MAP
		RunFlow.Stage.RESULTS:
			return SceneRouter.Screen.COMBAT_RESULTS
	if run.graph != null and run.graph.has_node_id(run.node):
		var type: CampaignGraph.NodeType = run.graph.type_of(run.node)
		if type == CampaignGraph.NodeType.TREASURE:
			return SceneRouter.Screen.TREASURE
		if type == CampaignGraph.NodeType.CAMP:
			return SceneRouter.Screen.CAMP
		if type == CampaignGraph.NodeType.ARMORY:
			return SceneRouter.Screen.ARMORY
		if (
				type == CampaignGraph.NodeType.UNKNOWN
				and run.events.is_open_at(run.floor_number, run.node)
		):
			if run.events.is_combat_pending_at(run.floor_number, run.node):
				return SceneRouter.Screen.GAMEPLAY
			return SceneRouter.Screen.EVENT
		if not is_combat(type):
			return SceneRouter.Screen.NODE_PLACEHOLDER
	return SceneRouter.Screen.GAMEPLAY


## Goes to the screen the run in progress belongs on ([method of]), for everyone.
static func go() -> void:
	SceneRouter.goto_screen_for_everyone(of(CampaignService.session))
