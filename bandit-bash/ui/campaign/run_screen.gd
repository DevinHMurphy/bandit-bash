# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 15, 2026
# ==============================================================================

class_name RunScreen
extends RefCounted
## Which screen a solo run belongs on, from its stage: the one place that decides, so the loading
## gate, the battle screen and every campaign screen route alike, and a continued run reopens
## where it was saved.
##
## On the map: the campaign map. Inside a combat node (Standard, Key, Boss): the battle screen.
## Inside any other node: the placeholder, until its own screen exists. At a combat's results:
## Results. Outside a solo run (none, or co-op): the battle screen, which shows the co-op
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
			return SceneRouter.Screen.CAMPAIGN_MAP
		RunFlow.Stage.RESULTS:
			return SceneRouter.Screen.COMBAT_RESULTS
	if run.graph != null and run.graph.has_node_id(run.node):
		if not is_combat(run.graph.type_of(run.node)):
			return SceneRouter.Screen.NODE_PLACEHOLDER
	return SceneRouter.Screen.GAMEPLAY


## Goes to the screen the run in progress belongs on ([method of]), for everyone.
static func go() -> void:
	SceneRouter.goto_screen_for_everyone(of(CampaignService.session))
