# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     choose_node_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name ChooseNodeCommand
extends CampaignCommand
## A solo run moves to a node on the next floor: it locks that floor and enters the node
## ([method CampaignRunState.enter_node]), recording [constant CampaignFact.Kind.NODE_CHOSEN].
##
## Valid for a node [method route_problem] accepts. Once one resolves the run is inside a node, so
## a second choice for the same floor is rejected. In co-op it is refused, even for a node it would
## accept: the team votes ([RouteVoteCommand]), and the vote that completes the set enters the
## drawn node. The node's own rules are not run here.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the node id travels.
const WIRE_TYPE: String = "choose_node"

## The node chosen, by its [CampaignGraph] id.
var node_id: int = CampaignGraph.NO_NODE


func _init(sender: int = -1, node: int = CampaignGraph.NO_NODE) -> void:
	seat = sender
	node_id = node


func get_label() -> String:
	return "choose node %d" % [node_id]


func validate(run: CampaignRunState) -> String:
	var problem: String = ChooseNodeCommand.route_problem(run, node_id)
	if not problem.is_empty():
		return problem
	if run.seats.size() > 1:
		return "the team votes on its route in co-op"
	return ""


func resolve(run: CampaignRunState) -> void:
	run.enter_node(node_id)
	var chosen: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_CHOSEN, seat)
	chosen.amount = node_id
	run.record(chosen)


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [node_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1:
		return false
	var node: Variant = _wire_at_least(values[0], CampaignGraph.NO_NODE)
	if node == null:
		return false
	node_id = node
	return true


## Why [param run] can't move to [param node] now; empty when it can. A move is valid only on the
## map, for a node on the floor above the current one that the current node leads to (any node on
## floor 1 before the first), once every seat has resolved its [StartingOffer] (heirlooms.md: the
## pick comes before the first node). [RouteVoteCommand] votes under the same rule.
static func route_problem(run: CampaignRunState, node: int) -> String:
	if not run.is_on_map():
		return "the run is inside node %d" % [run.node]
	for waiting: int in run.seat_numbers():
		if StartingOffer.is_open(run.seat_run(waiting)):
			return "seat %d hasn't taken its starting heirloom" % [waiting]
	if not run.graph.has_node_id(node):
		return "the map has no node %d" % [node]
	if run.graph.floor_of(node) != run.floor_number + 1:
		return "node %d isn't on floor %d" % [node, run.floor_number + 1]
	if run.node != CampaignGraph.NO_NODE and not run.graph.children_of(run.node).has(node):
		return "node %d doesn't lead to node %d" % [run.node, node]
	return ""
