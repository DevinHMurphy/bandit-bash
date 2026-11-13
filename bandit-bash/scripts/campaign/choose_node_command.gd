# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     choose_node_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name ChooseNodeCommand
extends CampaignCommand
## The team moves to a node on the next floor: it locks that floor and enters the node
## ([method CampaignRunState.enter_node]), recording [constant CampaignFact.Kind.NODE_CHOSEN].
##
## Valid only on the map, for a node on the floor above the current one that the current node leads
## to (any node on floor 1 before the first). Once one resolves the run is inside a node, so a
## second choice for the same floor, from any seat, is rejected: the first arrival wins. In co-op
## this carries the route the host drew from the votes. The node's own rules are not run here.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The node chosen, by its [CampaignGraph] id.
var node_id: int = CampaignGraph.NO_NODE


func _init(sender: int = -1, node: int = CampaignGraph.NO_NODE) -> void:
	seat = sender
	node_id = node


func get_label() -> String:
	return "choose node %d" % [node_id]


func validate(run: CampaignRunState) -> String:
	if not run.is_on_map():
		return "the run is inside node %d" % [run.node]
	if not run.graph.has_node_id(node_id):
		return "the map has no node %d" % [node_id]
	if run.graph.floor_of(node_id) != run.floor_number + 1:
		return "node %d isn't on floor %d" % [node_id, run.floor_number + 1]
	if run.node != CampaignGraph.NO_NODE and not run.graph.children_of(run.node).has(node_id):
		return "node %d doesn't lead to node %d" % [run.node, node_id]
	return ""


func resolve(run: CampaignRunState) -> void:
	run.enter_node(node_id)
	var chosen: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_CHOSEN, seat)
	chosen.amount = node_id
	run.record(chosen)
