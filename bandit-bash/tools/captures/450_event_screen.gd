# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     450_event_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The event screen over the game's events (data/events/). The Dark Goblet opens at the run's next
## node made an Unknown one: its option list, Infuse's weapon chooser and its outcome. The Clockwork Hermit's greyed Augment Unit and the Bandit Toll's vote view (two seats,
## one vote cast) are runs built in memory, shown on the same screen (its header stays the solo
## run's), so the throwaway run's gold is untouched for later groups. Then the goblet's outcome
## again, and Leave returns to the map for the next group.[br]
## Needs: the map reached by the victory's Leave (400_victory).

# SceneRouter.Screen.EVENT (the script can't name the autoload; see the base).
const SCREEN_EVENT: int = 13

# CampaignService.MAP_RULES_PATH, for the runs built in memory (the autoload can't be named).
const MAP_RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

# The events shot, and the options pressed (their index in data/events/).
const DARK_GOBLET: String = "dark_goblet"
const INFUSE: int = 1
const CLOCKWORK_HERMIT: String = "clockwork_hermit"
const BANDIT_TOLL: String = "bandit_toll"
const FIGHT: int = 1

# The greyed run's gold: below Augment Unit's 40, which the throwaway run is well above.
const NO_GOLD: int = 0

# Seats in the vote view's run, and the seat whose vote is cast.
const VOTE_SEATS: int = 2
const VOTING_SEAT: int = 1


func run() -> bool:
	var events: EventPool = EventPool.load_default()
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	if not await _open_event(events.event(DARK_GOBLET)):
		return true
	await capture("event_options")
	var panel: EventPanel = scene().call(&"get_panel")
	panel.get_cards()[INFUSE].pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("event_chooser")
	panel.get_chooser().get_choice_buttons()[0].pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("event_outcome")

	var poor: CampaignSession = _session_with(events.event(CLOCKWORK_HERMIT), 1)
	if poor != null:
		poor.run.seat_run(0).gold = NO_GOLD
		panel.open(poor, 0, events, catalog)
		await frames(SETTLE_FRAMES)
		await capture("event_greyed")
	var team: CampaignSession = _session_with(events.event(BANDIT_TOLL), VOTE_SEATS)
	if team != null:
		team.submit(EventNode.vote(team, VOTING_SEAT, FIGHT, events, catalog))
		panel.open(team, 0, events, catalog)
		await frames(SETTLE_FRAMES)
		await capture("event_vote")

	scene().call(&"reopen", events)
	await frames(SETTLE_FRAMES)
	panel.get_leave_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	if router_screen() != SCREEN_MAP:
		fail("the event's Leave didn't return to the map (screen %d)" % [router_screen()])
	return true


# Makes the run's next node an Unknown one, enters it, opens event there from a pool of it alone,
# and goes to the event screen, which shows it from the game's pool. Returns whether it opened.
func _open_event(event: EventDefinition) -> bool:
	var service: Node = node(^"CampaignService")
	var session: CampaignSession = campaign()
	if event == null:
		fail("the event shots need %s in data/events/" % [DARK_GOBLET])
		return false
	if router_screen() != SCREEN_MAP or session == null or session.run == null:
		fail("the event shots need the run on the map (screen %d)" % [router_screen()])
		return false
	var run: CampaignRunState = session.run
	var next: PackedInt32Array = run.graph.children_of(run.node)
	if next.is_empty():
		note("no next node for the event shots")
		return false
	run.graph.set_node_type(next[0], CampaignGraph.NodeType.UNKNOWN)
	service.call(&"submit_command", ChooseNodeCommand.new(0, next[0]))
	var batch: CampaignBatch = service.call(&"submit_command", EventNode.open(
			session, EventPool.new([event]), EffectCatalog.index(),
			CombatRewardRules.load_default()
	))
	if batch == null or batch.is_rejected():
		fail("%s didn't open: %s" % [
			event.id, "no batch" if batch == null else batch.rejected_reason,
		])
		return false
	note("%s opened at node %d, made an Unknown node for the shot" % [event.id, next[0]])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_EVENT)
	await frames(SETTLE_FRAMES)
	return true


# A new run of seat_count seats built in memory, every seat on the throwaway run's faction,
# standing in its first node made an Unknown one (entered by every seat's vote in co-op) with
# event open there. Null, with a FAIL line, when it can't be built.
func _session_with(event: EventDefinition, seat_count: int) -> CampaignSession:
	var map_rules: CampaignMapRules = load(MAP_RULES_PATH) as CampaignMapRules
	if event == null or map_rules == null:
		fail("an in-memory event run needs its event and %s" % [MAP_RULES_PATH])
		return null
	var faction_id: String = campaign().run.seat_run(0).faction_id
	var seats: PackedInt32Array = []
	var factions: Dictionary[int, String] = {}
	for seat: int in seat_count:
		seats.append(seat)
		factions[seat] = faction_id
	var mode: CampaignData.Mode = (
			CampaignData.Mode.SOLO if seat_count == 1 else CampaignData.Mode.MULTIPLAYER
	)
	var made: CampaignSession = CampaignSession.new(mode, RUN_SEED, seats)
	var start: RunStart = RunStart.build(
			map_rules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			EffectCatalog.index(),
			factions,
			made.ids
	)
	if start.run == null:
		fail("an in-memory run for %s couldn't be built: %s" % [event.id, start.problems])
		return null
	made.run = start.run
	var first: int = made.run.graph.nodes_on_floor(1)[0]
	made.run.graph.set_node_type(first, CampaignGraph.NodeType.UNKNOWN)
	# Solo chooses the node; in co-op every seat votes for it, so the last vote draws it.
	if seat_count == 1:
		made.submit(ChooseNodeCommand.new(0, first))
	else:
		for seat: int in seats:
			made.submit(RouteVoteCommand.for_session(made, seat, first))
	var batch: CampaignBatch = made.submit(EventNode.open(
			made, EventPool.new([event]), EffectCatalog.index(), CombatRewardRules.load_default()
	))
	if batch == null or batch.is_rejected():
		fail("%s didn't open in memory: %s" % [
			event.id, "no batch" if batch == null else batch.rejected_reason,
		])
		return null
	note("%s shown on a %d-seat run built in memory" % [event.id, seat_count])
	return made
