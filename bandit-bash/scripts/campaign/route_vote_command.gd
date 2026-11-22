# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     route_vote_command.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name RouteVoteCommand
extends CampaignCommand
## In co-op, the seat votes for a node on the next floor, replacing its own earlier vote, recording
## [constant CampaignFact.Kind.ROUTE_VOTED]. The vote that completes the set draws the team's node
## ([method draw]) and enters it as [ChooseNodeCommand] does, recording
## [constant CampaignFact.Kind.NODE_CHOSEN] for no seat.
##
## A vote is valid for any node [ChooseNodeCommand] accepts
## ([method ChooseNodeCommand.route_problem]); with one seat there is no vote, and
## [ChooseNodeCommand] chooses. A vote changes until the draw and is never withdrawn. Votes stay in
## [member CampaignRunState.route_votes] after the draw, so the tally still shows, until the next
## floor's first vote; saved in [code]campaign_map[/code], so a quit mid-vote keeps them. Built by
## [method for_session].
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the node travels; the draw
## stream is the host's.
const WIRE_TYPE: String = "route_vote"

## The node voted for, by its [CampaignGraph] id.
var node_id: int = CampaignGraph.NO_NODE

## The next floor's shared [code]ROUTE_DRAW[/code] stream, drawn from once by the vote that
## completes the set.
var draw_stream: RngStream = null


func _init(sender: int = -1, node: int = CampaignGraph.NO_NODE) -> void:
	seat = sender
	node_id = node


func get_label() -> String:
	return "vote for node %d" % [node_id]


func validate(run: CampaignRunState) -> String:
	if run.seats.size() < 2:
		return "a route with one seat needs no vote"
	var problem: String = ChooseNodeCommand.route_problem(run, node_id)
	if not problem.is_empty():
		return problem
	if draw_stream == null:
		return "no route draw stream to draw from"
	return ""


func resolve(run: CampaignRunState) -> void:
	run.route_votes = run.open_route_votes()
	run.route_votes[seat] = node_id
	var voted: CampaignFact = CampaignFact.new(CampaignFact.Kind.ROUTE_VOTED, seat)
	voted.amount = node_id
	run.record(voted)
	for seat_number: int in run.seat_numbers():
		if not run.route_votes.has(seat_number):
			return
	var drawn: int = RouteVoteCommand.draw(run, draw_stream)
	if drawn == CampaignGraph.NO_NODE:
		return
	run.enter_node(drawn)
	var chosen: CampaignFact = CampaignFact.new(CampaignFact.Kind.NODE_CHOSEN)
	chosen.amount = drawn
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


## The vote of seat [param sender] for node [param node] on the floor after [param session]'s
## run, with that floor's [code]ROUTE_DRAW[/code] stream. Null, reported, with no run.
static func for_session(session: CampaignSession, sender: int, node: int) -> RouteVoteCommand:
	if session == null or session.run == null:
		push_error("RouteVoteCommand: no run to vote in")
		return null
	var command: RouteVoteCommand = RouteVoteCommand.new(sender, node)
	command.draw_stream = session.rng.stream(RngKey.new(
			RngKey.RngPurpose.ROUTE_DRAW, session.run.floor_number + 1
	))
	return command


## The open votes for each of [param run]'s next nodes ([method CampaignRunState.next_nodes]), in
## the same order. Only the run's own seats count.
static func tally(run: CampaignRunState) -> PackedInt32Array:
	var next: PackedInt32Array = run.next_nodes()
	var votes: Dictionary[int, int] = run.open_route_votes()
	var counts: PackedInt32Array = []
	counts.resize(next.size())
	for seat_number: int in run.seat_numbers():
		if not votes.has(seat_number):
			continue
		var index: int = next.find(votes[seat_number])
		if index >= 0:
			counts[index] += 1
	return counts


## The node [param run]'s open votes draw among its next nodes, from [param stream] with one
## weighted roll: each node's chance is its share of the votes, so 2 votes against 1 is a 2-in-3
## chance. [constant CampaignGraph.NO_NODE], reported and without drawing, with no vote.
static func draw(run: CampaignRunState, stream: RngStream) -> int:
	var picked: int = stream.pick_weighted(RouteVoteCommand.tally(run))
	return run.next_nodes()[picked] if picked >= 0 else CampaignGraph.NO_NODE
