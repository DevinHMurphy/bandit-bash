# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 24, 2026
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
## [b]Seat moves:[/b] each seat settles its starting offer on its own and waits on the map, so a
## move out of the offer, or from the map into it, is this machine's alone; a move for everyone
## names the map there, and each machine opens its own seat's screen for it
## ([method for_local_seat]). Otherwise a teammate's open offer would send everyone back to it.
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


## Goes to the screen the run in progress belongs on ([method of]), after settling the entry of an
## Unknown node a solo run is in ([method enter_unknown]): on this machine alone for a seat move
## (see the class doc), else for everyone.
static func go() -> void:
	var session: CampaignSession = CampaignService.session
	enter_unknown(session)
	var screen: SceneRouter.Screen = of(session)
	if _is_seat_move(SceneRouter.current_screen, screen):
		SceneRouter.goto_screen(screen)
		return
	SceneRouter.goto_screen_for_everyone(_for_everyone(screen))


## Goes to the screen the run belongs on for everyone, never as a seat move: the host's answer to
## a client's route request, so its own open offer never chooses where everyone goes.
static func go_for_everyone() -> void:
	var session: CampaignSession = CampaignService.session
	enter_unknown(session)
	SceneRouter.goto_screen_for_everyone(_for_everyone(of(session)))


## The screen this machine opens when everyone is sent to [param screen]: the local seat's
## starting offer in place of the map while that offer is open in [param session]'s run, else
## [param screen].
static func for_local_seat(
		session: CampaignSession, screen: SceneRouter.Screen
) -> SceneRouter.Screen:
	if (
			screen == SceneRouter.Screen.CAMPAIGN_MAP
			and of(session) == SceneRouter.Screen.STARTING_HEIRLOOM
	):
		return SceneRouter.Screen.STARTING_HEIRLOOM
	return screen


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


# Whether going from screen from to screen to is the local seat's own move, made on this machine
# alone: any move out of its starting offer, or from the map into it. From anywhere else (Loading,
# a node) the move is everyone's, though it may land on the offer.
static func _is_seat_move(from: SceneRouter.Screen, to: SceneRouter.Screen) -> bool:
	return (
			from == SceneRouter.Screen.STARTING_HEIRLOOM
			or (
					from == SceneRouter.Screen.CAMPAIGN_MAP
					and to == SceneRouter.Screen.STARTING_HEIRLOOM
			)
	)


# screen as a move for everyone names it: the map in place of a seat's starting offer, which each
# machine opens for its own seat instead (for_local_seat()).
static func _for_everyone(screen: SceneRouter.Screen) -> SceneRouter.Screen:
	if screen == SceneRouter.Screen.STARTING_HEIRLOOM:
		return SceneRouter.Screen.CAMPAIGN_MAP
	return screen
