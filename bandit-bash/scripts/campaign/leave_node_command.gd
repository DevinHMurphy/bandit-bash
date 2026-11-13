# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leave_node_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name LeaveNodeCommand
extends CampaignCommand
## The team leaves its current node for the map, recording
## [constant CampaignFact.Kind.NODE_LEFT]. The node stays visited and its floor locked.
##
## Valid only inside a node. It runs no node rules: each node's rules decide when the node is done
## and then send it.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "leave node"


func validate(run: CampaignRunState) -> String:
	if run.is_on_map():
		return "the run is on the map"
	return ""


func resolve(run: CampaignRunState) -> void:
	run.flow.stage = RunFlow.Stage.MAP
	var left: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_LEFT, seat)
	left.amount = run.node
	run.record(left)
