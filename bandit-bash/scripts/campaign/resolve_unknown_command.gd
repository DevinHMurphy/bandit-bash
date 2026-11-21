# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     resolve_unknown_command.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name ResolveUnknownCommand
extends CampaignCommand
## Rolls what the Unknown node the run is in becomes ([method UnknownResolution.roll]) from the
## node's shared [code]UNKNOWN_RESOLUTION[/code] stream, keeping the outcome and the new odds in
## the run's flow, and records [constant CampaignFact.Kind.UNKNOWN_RESOLVED]: the Unknown node's
## entry point, sent by [method RunScreen.go] before it routes. An event outcome's event then
## opens through [method EventNode.open].
##
## Valid only while [method is_due], so a continued run keeps its outcome and never rolls again.
## Nothing else draws the stream, and the odds change only here, so a quit after the node is
## entered but before this command's save rolls the same outcome on Continue.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]). It has no fields of its own:
## the rules and the stream are the host's.
const WIRE_TYPE: String = "resolve_unknown"

## The base chances the roll reads.
var rules: CampaignMapRules = null

## The node's shared [code]UNKNOWN_RESOLUTION[/code] stream ([method resolution_stream]).
var stream: RngStream = null


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "resolve unknown"


func validate(run: CampaignRunState) -> String:
	if not UnknownResolution.is_at_unknown(run):
		return "the run isn't inside an Unknown node"
	if not run.flow.unknown.is_empty():
		return "node %d already became %s" % [run.node, run.flow.unknown]
	if run.events.is_open_at(run.floor_number, run.node):
		return "an event is already open at node %d" % [run.node]
	if rules == null or stream == null:
		return "the map rules or the resolution stream is missing"
	return ""


func resolve(run: CampaignRunState) -> void:
	var resolved: CampaignFact = CampaignFact.new(CampaignFact.Kind.UNKNOWN_RESOLVED)
	resolved.definition_id = UnknownResolution.roll(run.flow, rules, stream)
	resolved.amount = run.node
	run.record(resolved)


func get_wire_type() -> String:
	return WIRE_TYPE


## The command that rolls the Unknown node [param session]'s run is in, with the node's stream,
## sent from the host seat. [param rules_used] null: the game's map rules. Null, reported, with no
## run or no rules.
static func for_session(
		session: CampaignSession, rules_used: CampaignMapRules = null
) -> ResolveUnknownCommand:
	if session == null or session.run == null:
		push_error("ResolveUnknownCommand: no run to resolve an Unknown node in")
		return null
	var command: ResolveUnknownCommand = ResolveUnknownCommand.new(CampaignData.HOST_SEAT)
	command.rules = rules_used if rules_used != null else CampaignMapRules.load_default()
	if command.rules == null:
		return null
	command.stream = resolution_stream(session)
	return command


## The shared [code]UNKNOWN_RESOLUTION[/code] stream of the node [param session]'s run is in.
static func resolution_stream(session: CampaignSession) -> RngStream:
	return session.rng.stream(RngKey.new(
			RngKey.RngPurpose.UNKNOWN_RESOLUTION, session.run.floor_number, session.run.node
	))


## Whether [param run] is inside an Unknown node that isn't rolled yet and has no event open (one
## opened without a roll already made it an event): this command is due.
static func is_due(run: CampaignRunState) -> bool:
	return (
			UnknownResolution.is_at_unknown(run) and run.flow.unknown.is_empty()
			and not run.events.is_open_at(run.floor_number, run.node)
	)
