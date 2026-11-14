# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leave_node_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name LeaveNodeCommand
extends CampaignCommand
## The team leaves its current node for the map, recording
## [constant CampaignFact.Kind.NODE_LEFT]. The node stays visited and its floor locked.
##
## Valid only inside a node, and at a combat's results only once every seat has taken or skipped
## its [ItemPick]. It runs no node rules: each node's rules decide when the node is done and then
## send it. Leaving a combat's results clears every seat's combat report and item pick from its
## pending offers.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "leave node"


func validate(run: CampaignRunState) -> String:
	if run.is_on_map():
		return "the run is on the map"
	if run.flow.stage != RunFlow.Stage.RESULTS:
		return ""
	for seat_number: int in run.seat_numbers():
		var pick: ItemPick = ItemPick.pending(run.seat_run(seat_number))
		if pick != null and not pick.is_resolved:
			return "seat %d hasn't taken or skipped its item pick" % [seat_number]
	return ""


func resolve(run: CampaignRunState) -> void:
	if run.flow.stage == RunFlow.Stage.RESULTS:
		for seat_number: int in run.seat_numbers():
			var offers: Dictionary = run.seat_run(seat_number).pending_offers
			offers.erase(CampaignRunState.COMBAT_REPORT_KEY)
			offers.erase(ItemPick.OFFER_KEY)
	run.flow.stage = RunFlow.Stage.MAP
	var left: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_LEFT, seat)
	left.amount = run.node
	run.record(left)
