# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leave_node_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name LeaveNodeCommand
extends CampaignCommand
## The team leaves its current node for the map, recording
## [constant CampaignFact.Kind.NODE_LEFT]. The node stays visited and its floor locked.
##
## Valid only inside a node, and only once every seat has settled what the node waits on: at a
## combat's results its [ItemPick] and a Key combat's [KeyHeirloom]; at a Treasure its rolled
## [TreasureChest]; at a Camp its choice ([Camp]); an Armory or a Guildhall never waits. It runs
## no node rules: each node's screen settles them and then sends it. Leaving clears those offers
## from every seat's pending offers, and the Armory's [ArmoryStock] and the Guildhall's
## [GuildhallStock] from the run's shop stock.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "leave node"


func validate(run: CampaignRunState) -> String:
	if run.is_on_map():
		return "the run is on the map"
	for seat_number: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat_number)
		if run.flow.stage == RunFlow.Stage.RESULTS:
			var pick: ItemPick = ItemPick.pending(seat_run)
			if pick != null and not pick.is_resolved:
				return "seat %d hasn't taken or skipped its item pick" % [seat_number]
			if KeyHeirloom.is_open(seat_run):
				return "seat %d hasn't taken or given up its heirloom" % [seat_number]
		elif OpenTreasureCommand.is_at_treasure(run) and TreasureChest.is_open(seat_run):
			return "seat %d hasn't taken or given up its chest" % [seat_number]
		elif Camp.is_at_camp(run) and Camp.choice_of(seat_run) == Camp.Choice.NONE:
			return "seat %d hasn't chosen Feast or Train" % [seat_number]
	return ""


func resolve(run: CampaignRunState) -> void:
	for seat_number: int in run.seat_numbers():
		var offers: Dictionary = run.seat_run(seat_number).pending_offers
		if run.flow.stage == RunFlow.Stage.RESULTS:
			offers.erase(CampaignRunState.COMBAT_REPORT_KEY)
			offers.erase(ItemPick.OFFER_KEY)
			offers.erase(KeyHeirloom.OFFER_KEY)
		offers.erase(TreasureChest.OFFER_KEY)
		offers.erase(Camp.OFFER_KEY)
	run.flow.shop_stock.erase(ArmoryStock.OFFER_KEY)
	run.flow.shop_stock.erase(GuildhallStock.OFFER_KEY)
	run.flow.stage = RunFlow.Stage.MAP
	var left: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_LEFT, seat)
	left.amount = run.node
	run.record(left)
