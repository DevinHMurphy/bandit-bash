# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     500_campaign_after_battle.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Back on the map after the victory: the pause menu over it (with the run's seed), the node
## placeholder, then the run ended as lost (as a lost battle ends it), so the run's end shot shows
## a lost run and its seed.[br]
## The placeholder shows only for an Unknown that became an event when no event can be drawn,
## which the game's events never give, so it is staged: a reachable Unknown entered by command
## and marked as an event with none open, as [code]unknown_screen_cases.gd[/code] stages it.[br]
## Needs: the map reached by the victory's Leave (400_victory).

# SceneRouter.Screen.NODE_PLACEHOLDER (see the base's class doc).
const SCREEN_PLACEHOLDER: int = 11


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
	await _node_placeholder()
	var err: Error = node(^"SaveService").call(&"end_run", false)
	if err != OK:
		fail("the run did not end as lost for the run's end: %s" % [error_string(err)])
	return true


# The event fallback on the first reachable Unknown, then Continue back to the map. Shoots
# nothing, with a NOTE, when no Unknown is reachable.
func _node_placeholder() -> void:
	var view: CampaignMapView = scene().call(&"get_map_view")
	var unknown_id: int = -1
	for node_id: int in view.get_reachable():
		if view.get_node_button(node_id).node_type == CampaignGraph.NodeType.UNKNOWN:
			unknown_id = node_id
			break
	if unknown_id < 0:
		note("no Unknown node is reachable, so node_placeholder isn't shot")
		return
	var batch: CampaignBatch = node(^"CampaignService").call(
			&"submit_command", ChooseNodeCommand.new(0, unknown_id)
	)
	if batch == null or batch.is_rejected():
		fail("the Unknown node %d couldn't be entered for the placeholder" % [unknown_id])
		return
	campaign().run.flow.unknown = UnknownResolution.EVENT
	note("node_placeholder: an Unknown staged as an event with none drawn")
	await goto(SCREEN_PLACEHOLDER, "node_placeholder")
	if router_screen() != SCREEN_PLACEHOLDER:
		fail("the staged Unknown didn't show the placeholder (screen %d)" % [router_screen()])
		return
	(scene().call(&"get_continue_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
