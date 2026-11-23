# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leave_node_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name LeaveNodeCommand
extends CampaignCommand
## The team leaves its current node for the map, recording
## [constant CampaignFact.Kind.NODE_LEFT]. The node stays visited and its floor locked.
##
## Valid only inside a node, and only once every seat has settled what the node waits on: at a
## combat's results its [ItemPick] and a Key combat's [KeyHeirloom]; at a Treasure its rolled
## [TreasureChest]; at a Camp its choice ([Camp]); at an open event its choice, and then the
## surprise combat it chose, which leaves through that combat's results ([EventRunState]); an
## Armory or a Guildhall never waits. It runs no node rules: each node's screen settles them and
## then sends it. Leaving clears those offers from every seat's pending offers, the Armory's
## [ArmoryStock] and the Guildhall's [GuildhallStock] from the run's shop stock, and an Unknown
## node's outcome ([member RunFlow.unknown]); the Unknown odds stay for the next one.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]). It has no fields of its own.
const WIRE_TYPE: String = "leave_node"


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "leave node"


func validate(run: CampaignRunState) -> String:
	if run.is_on_map():
		return "the run is on the map"
	var event_problem: String = _event_problem(run)
	if not event_problem.is_empty():
		return event_problem
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
	run.flow.unknown = ""
	run.flow.stage = RunFlow.Stage.MAP
	var left: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_LEFT, seat)
	left.amount = run.node
	run.record(left)


func get_wire_type() -> String:
	return WIRE_TYPE


# Why the event open at the run's node keeps the team there: a seat still to choose, or the
# surprise combat it chose not yet fought. Once fought, the run stands at that combat's results,
# where the event no longer waits. Empty with no event open here.
func _event_problem(run: CampaignRunState) -> String:
	var events: EventRunState = run.events
	# ASSUMPTION: an open event whose id this build's pool lacks (the screen's "can't be shown"
	# step) holds the team too; rules code has no pool to tell.
	if run.flow.stage == RunFlow.Stage.RESULTS or not events.is_open_at(run.floor_number, run.node):
		return ""
	for seat_number: int in events.seats:
		if events.seat_event(seat_number).chosen == EventRunState.NO_OPTION:
			return "seat %d hasn't chosen at the event" % [seat_number]
	if events.is_combat_pending:
		return "the event's surprise combat hasn't been fought"
	return ""
