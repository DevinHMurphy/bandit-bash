# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     250_campaign_map.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The campaign map with its heirloom bar, then its first reachable Standard combat node entered;
## ends the whole run if no battle opens.[br]
## Needs: the run's map open (200_run_start).


func run() -> bool:
	await capture("campaign_map")
	var view: CampaignMapView = scene().call(&"get_map_view")
	for node_id: int in view.get_reachable():
		var button: MapNodeButton = view.get_node_button(node_id)
		if button.node_type == CampaignGraph.NodeType.STANDARD:
			button.pressed.emit()
			await frames(SETTLE_FRAMES)
			return router_screen() == SCREEN_GAMEPLAY
	fail("no reachable Standard combat node on the map")
	return false
