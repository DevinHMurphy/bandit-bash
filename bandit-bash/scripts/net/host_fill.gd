# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     host_fill.gd
# Author:
# Created:  November 22, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name HostFill
extends RefCounted
## Gives a campaign command that arrived over the wire the host-side objects its type needs
## (streams, allocator, event pool), as the host's own screens give theirs.
##
## A wire form carries only the sender's input ([method CampaignCommand.from_wire]), so the host
## rebuilds each [constant FILLED] type through that type's own public builder
## ([code]for_session()[/code], [EventNode]) from the input that arrived: what a command needs
## stays with the command, and a remote command is the one the host's screen would have sent.
## [constant NOTHING_TO_FILL] types resolve as they arrive (a null catalog is the loaded one).
## A new command type joins one of the two lists; the net suite fails a wire type in neither.
##
## @tutorial(Net transport plan): docs/plans/2026-11-19-net-transport.md

## The wire types [method complete] rebuilds through their builders.
const FILLED: PackedStringArray = [
	ArmoryPurchaseCommand.WIRE_TYPE,
	OpenArmoryCommand.WIRE_TYPE,
	OpenGuildhallCommand.WIRE_TYPE,
	OpenTreasureCommand.WIRE_TYPE,
	PrefixRerollCommand.WIRE_TYPE,
	ResolveUnknownCommand.WIRE_TYPE,
	RouteVoteCommand.WIRE_TYPE,
	OpenEventCommand.WIRE_TYPE,
	EventChooserCommand.WIRE_TYPE,
	EventVoteCommand.WIRE_TYPE,
	EventOptionCommand.WIRE_TYPE,
]

## The wire types whose commands hold nothing the host fills, or only a catalog whose null means
## the loaded one.
const NOTHING_TO_FILL: PackedStringArray = [
	ChooseNodeCommand.WIRE_TYPE,
	LeaveNodeCommand.WIRE_TYPE,
	StartingHeirloomCommand.WIRE_TYPE,
	ItemPickCommand.WIRE_TYPE,
	KeyHeirloomCommand.WIRE_TYPE,
	TreasureCommand.WIRE_TYPE,
	FeastCommand.WIRE_TYPE,
	TrainCommand.WIRE_TYPE,
	RegearCommand.WIRE_TYPE,
	GiftItemCommand.WIRE_TYPE,
	ScrapItemCommand.WIRE_TYPE,
	GuildhallPurchaseCommand.WIRE_TYPE,
	ProposeSwapCommand.WIRE_TYPE,
	AnswerSwapCommand.WIRE_TYPE,
	WithdrawSwapCommand.WIRE_TYPE,
]


## [param command] ready to resolve on [param session]'s run: a [constant FILLED] type rebuilt by
## its builder with the same input and [member CampaignCommand.seat], any other type as it is.
## Null, reported, for a null argument, a session with no run, a type in neither list, or a
## builder that refused.
static func complete(command: CampaignCommand, session: CampaignSession) -> CampaignCommand:
	if command == null or session == null or session.run == null:
		push_error("HostFill: no command or no run to fill it for.")
		return null
	var wire_type: String = command.get_wire_type()
	if NOTHING_TO_FILL.has(wire_type):
		return command
	if not FILLED.has(wire_type):
		push_error("HostFill: wire type \"%s\" is in neither list." % [wire_type])
		return null
	var filled: CampaignCommand = _rebuilt(command, session)
	if filled == null:
		push_error("HostFill: \"%s\" couldn't be rebuilt." % [wire_type])
		return null
	filled.seat = command.seat
	return filled


# command rebuilt by its type's builder from its own input; null when the builder refused.
static func _rebuilt(command: CampaignCommand, session: CampaignSession) -> CampaignCommand:
	if command is ArmoryPurchaseCommand:
		var purchase: ArmoryPurchaseCommand = command
		return ArmoryPurchaseCommand.for_session(
				session, purchase.seat, purchase.entry, purchase.unit_id, purchase.is_traded_in
		)
	if command is OpenArmoryCommand:
		return OpenArmoryCommand.for_session(session)
	if command is OpenGuildhallCommand:
		return OpenGuildhallCommand.for_session(session)
	if command is OpenTreasureCommand:
		return OpenTreasureCommand.for_session(session)
	if command is PrefixRerollCommand:
		var reroll: PrefixRerollCommand = command
		return PrefixRerollCommand.for_session(session, reroll.seat, reroll.unit_id)
	if command is ResolveUnknownCommand:
		return ResolveUnknownCommand.for_session(session)
	if command is RouteVoteCommand:
		var vote: RouteVoteCommand = command
		return RouteVoteCommand.for_session(session, vote.seat, vote.node_id)
	if command is OpenEventCommand:
		return EventNode.open(session)
	if command is EventChooserCommand:
		var chooser: EventChooserCommand = command
		return EventNode.open_chooser(session, chooser.seat, chooser.option_index)
	if command is EventVoteCommand:
		var event_vote: EventVoteCommand = command
		return EventNode.vote(session, event_vote.seat, event_vote.option_index)
	if command is EventOptionCommand:
		var option: EventOptionCommand = command
		return EventNode.choose(session, option.seat, option.option_index, option.choice)
	return null
