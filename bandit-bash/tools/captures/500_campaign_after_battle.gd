# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     500_campaign_after_battle.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Back on the map after the victory: the pause menu over it (with the run's seed), a node
## placeholder when a node that isn't a combat, a Treasure or a Camp is reachable, then the run
## ended as lost (as a lost battle ends it), so the run's end shot shows a lost run and its
## seed.[br]
## Needs: the map reached by the victory's Leave (400_victory).


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the victory's Leave didn't reach the map (screen %d)" % [router_screen()])
		return true
	await frames(SETTLE_FRAMES)
	var pause: Node = scene().get_node(^"PauseMenu")
	pause.call(&"open")
	await frames(SETTLE_FRAMES)
	await capture("campaign_map_pause")
	pause.call(&"close")
	await frames(SETTLE_FRAMES)
	var view: CampaignMapView = scene().call(&"get_map_view")
	for node_id: int in view.get_reachable():
		var button: MapNodeButton = view.get_node_button(node_id)
		if _is_placeholder_type(button.node_type):
			button.pressed.emit()
			await frames(SETTLE_FRAMES)
			await capture("node_placeholder")
			(scene().call(&"get_continue_button") as Button).pressed.emit()
			await frames(SETTLE_FRAMES)
			break
	var err: Error = node(^"SaveService").call(&"end_run", false)
	if err != OK:
		fail("the run did not end as lost for the run's end: %s" % [error_string(err)])
	return true


# Whether a node of type opens the placeholder: not a combat, and not a Treasure or a Camp, which
# have their own screens (460_treasure_and_camp shoots them).
func _is_placeholder_type(type: CampaignGraph.NodeType) -> bool:
	return (
			not FactCueMap.COMBAT_NODE_TYPES.has(type)
			and type != CampaignGraph.NodeType.TREASURE
			and type != CampaignGraph.NodeType.CAMP
	)
