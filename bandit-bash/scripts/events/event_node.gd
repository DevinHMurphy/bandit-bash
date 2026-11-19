# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_node.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventNode
extends RefCounted
## The hand-off between an Unknown node's event and the rest of the game, host side: the
## commands that open and drive it, filled from the run's session, and the view that shows it.
##
## The Unknown node sends [method open]'s command; the event screen reads [method view] (the
## team's tally included) and sends [method open_chooser]'s, [method vote]'s and
## [method choose]'s. Each command goes through
## [code]CampaignService.submit_command()[/code], which resolves and saves it. Nothing here
## touches an autoload; a null pool, catalog or rules is the game's own
## ([method EventPool.load_default], [method EffectCatalog.index],
## [method CombatRewardRules.load_default]).
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md


## The command that opens an event at the Unknown node [param session]'s run is in, with the
## node's [code]EVENT_DRAW[/code] stream and each seat's [code]EVENT_OUTCOME[/code] stream. Sent
## from the host seat. Null, reported, with no run.
static func open(
		session: CampaignSession,
		pool: EventPool = null,
		catalog: EffectCatalog.Index = null,
		rules: CombatRewardRules = null
) -> OpenEventCommand:
	if not _has_run(session):
		return null
	var run: CampaignRunState = session.run
	var command: OpenEventCommand = OpenEventCommand.new(CampaignData.HOST_SEAT)
	command.pool = _pool(pool)
	command.catalog = _catalog(catalog)
	command.rules = rules if rules != null else CombatRewardRules.load_default()
	command.draw_stream = session.rng.stream(RngKey.new(
			RngKey.RngPurpose.EVENT_DRAW, run.floor_number, run.node
	))
	command.outcome_streams = _outcome_streams(session)
	return command


## What [param seat] sees of the event open at [param session]'s node ([method EventView.build]);
## a closed view with no run.
static func view(
		session: CampaignSession,
		seat: int,
		pool: EventPool = null,
		catalog: EffectCatalog.Index = null
) -> EventView:
	if session == null or session.run == null:
		var closed: EventView = EventView.new()
		closed.seat = seat
		return closed
	return EventView.build(session.run, seat, _pool(pool), _catalog(catalog))


## The command by which [param seat] opens the chooser of option [param option_index], or closes
## it with [constant EventRunState.NO_OPTION]. Null, reported, with no run.
static func open_chooser(
		session: CampaignSession,
		seat: int,
		option_index: int,
		pool: EventPool = null,
		catalog: EffectCatalog.Index = null
) -> EventChooserCommand:
	if not _has_run(session):
		return null
	var command: EventChooserCommand = EventChooserCommand.new(seat, option_index)
	command.pool = _pool(pool)
	command.catalog = _catalog(catalog)
	return command


## The command by which [param seat] votes for option [param option_index] of a team choice of
## more than one seat, or changes its vote, with the node's shared [code]TEAM_CHOICE[/code]
## stream for the draw the last vote makes. [method view] reads the tally and the drawn option,
## which [method choose] then applies. Null, reported, with no run.
static func vote(
		session: CampaignSession,
		seat: int,
		option_index: int,
		pool: EventPool = null,
		catalog: EffectCatalog.Index = null
) -> EventVoteCommand:
	if not _has_run(session):
		return null
	var run: CampaignRunState = session.run
	var command: EventVoteCommand = EventVoteCommand.new(seat, option_index)
	command.pool = _pool(pool)
	command.catalog = _catalog(catalog)
	command.draw_stream = session.rng.stream(RngKey.new(
			RngKey.RngPurpose.TEAM_CHOICE, run.floor_number, run.node
	))
	return command


## The command by which [param seat] chooses option [param option_index] with its picks
## [param choice] (null: nothing picked), with the run's id allocator and each seat's
## [code]EVENT_OUTCOME[/code] stream. Add teammates' picks for a team choice to
## [member EventOptionCommand.team_choices]. Null, reported, with no run.
static func choose(
		session: CampaignSession,
		seat: int,
		option_index: int,
		choice: EventChoice = null,
		pool: EventPool = null,
		catalog: EffectCatalog.Index = null
) -> EventOptionCommand:
	if not _has_run(session):
		return null
	var command: EventOptionCommand = EventOptionCommand.new(seat, option_index, choice)
	command.pool = _pool(pool)
	command.catalog = _catalog(catalog)
	command.ids = session.ids
	command.streams = _outcome_streams(session)
	return command


static func _has_run(session: CampaignSession) -> bool:
	if session == null or session.run == null:
		push_error("EventNode: no run in progress for an event")
		return false
	return true


static func _pool(pool: EventPool) -> EventPool:
	return pool if pool != null else EventPool.load_default()


static func _catalog(catalog: EffectCatalog.Index) -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()


# Each seat's EVENT_OUTCOME stream at the run's node, by seat.
static func _outcome_streams(session: CampaignSession) -> Dictionary[int, RngStream]:
	var run: CampaignRunState = session.run
	var streams: Dictionary[int, RngStream] = {}
	for seat: int in run.seat_numbers():
		streams[seat] = session.rng.stream(RngKey.new(
				RngKey.RngPurpose.EVENT_OUTCOME, run.floor_number, run.node, seat
		))
	return streams
