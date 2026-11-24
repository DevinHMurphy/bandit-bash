# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name RunScreen
extends RefCounted
## Which screen the run this machine holds belongs on, from its stage: the one place that decides,
## so the loading gate, the battle screen and every campaign screen route alike, and a continued
## run reopens where it was saved. Solo and co-op route alike, by the local seat
## ([method CampaignService.local_seat]).
##
## On the map: the starting heirloom offer while the local seat's is open ([StartingOffer]), else
## the campaign map. Inside a node, by the type it plays as ([method CampaignRunState.node_type]):
## a combat on the battle screen; a Treasure, Camp, Armory or Guildhall on its own screen; an
## Unknown with an event open on the event screen, or the battle screen once the event chose a
## surprise combat; an Unknown with none, the placeholder. At a combat's results, solo or co-op:
## the combat results screen, for the local seat. With no run: the battle screen. A screen opened
## at the wrong stage sends the run on with [method go], which first settles an Unknown's entry.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Whether [param session] is a solo run with its campaign state. A won battle's end plays the
## victory sequence over the board only then; a co-op battle's end goes to the combat results
## screen at once ([method of] routes both).
static func is_solo_run(session: CampaignSession) -> bool:
	return session != null and session.run != null and session.mode == CampaignData.Mode.SOLO


## Whether a node of [param type] is fought on the battle screen.
static func is_combat(type: CampaignGraph.NodeType) -> bool:
	return (
			type == CampaignGraph.NodeType.STANDARD
			or type == CampaignGraph.NodeType.KEY
			or type == CampaignGraph.NodeType.BOSS
	)


## The screen [param session]'s run belongs on for the local seat (see the class doc).
static func of(session: CampaignSession) -> SceneRouter.Screen:
	if not _has_run(session):
		return SceneRouter.Screen.GAMEPLAY
	var run: CampaignRunState = session.run
	match run.flow.stage:
		RunFlow.Stage.MAP:
			if StartingOffer.is_open(run.seat_run(CampaignService.local_seat())):
				return SceneRouter.Screen.STARTING_HEIRLOOM
			return SceneRouter.Screen.CAMPAIGN_MAP
		RunFlow.Stage.RESULTS:
			return SceneRouter.Screen.COMBAT_RESULTS
	if run.graph != null and run.graph.has_node_id(run.node):
		var type: CampaignGraph.NodeType = run.node_type()
		if type == CampaignGraph.NodeType.TREASURE:
			return SceneRouter.Screen.TREASURE
		if type == CampaignGraph.NodeType.CAMP:
			return SceneRouter.Screen.CAMP
		if type == CampaignGraph.NodeType.ARMORY:
			return SceneRouter.Screen.ARMORY
		if type == CampaignGraph.NodeType.GUILDHALL:
			return SceneRouter.Screen.GUILDHALL
		if type == CampaignGraph.NodeType.UNKNOWN:
			if not run.events.is_open_at(run.floor_number, run.node):
				return SceneRouter.Screen.NODE_PLACEHOLDER
			if run.events.is_combat_pending_at(run.floor_number, run.node):
				return SceneRouter.Screen.GAMEPLAY
			return SceneRouter.Screen.EVENT
	return SceneRouter.Screen.GAMEPLAY


## Goes to the screen the run in progress belongs on ([method of]), for everyone, after settling
## the entry of an Unknown node a solo run is in ([method enter_unknown]).
static func go() -> void:
	var session: CampaignSession = CampaignService.session
	enter_unknown(session)
	SceneRouter.goto_screen_for_everyone(of(session))


## Settles the entry of the Unknown node [param session]'s run is in, each step through
## [method CampaignService.submit_command], which saves it: rolls what the node becomes while it
## is due ([method ResolveUnknownCommand.is_due]), then opens an event outcome's event
## ([method EventNode.open]). With no event to draw, that is refused and the node stays on the
## placeholder. Does nothing elsewhere, so it is safe on every route.
static func enter_unknown(session: CampaignSession) -> void:
	if not _has_run(session):
		return
	if ResolveUnknownCommand.is_due(session.run):
		var resolve: ResolveUnknownCommand = ResolveUnknownCommand.for_session(session)
		if resolve != null:
			CampaignService.submit_command(resolve)
	if UnknownResolution.needs_event(session.run):
		var open: OpenEventCommand = EventNode.open(session)
		if open != null:
			CampaignService.submit_command(open)


# Whether session holds its campaign state: a solo run, a co-op host's, or a co-op client's mirror
# of the host's run (ClientMirror). The battle screen's co-op paths still test is_solo_run().
static func _has_run(session: CampaignSession) -> bool:
	return session != null and session.run != null
