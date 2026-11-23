# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     458_coop_events.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The event screen in a 2-seat host run, for seat 0 and for seat 1, over the game's events
## (data/events/). The Dark Goblet, which each seat chooses alone: seat 0's options with the
## teammate still choosing, seat 0 waiting after Pour It Away, seat 1's options with seat 0's
## choice shown, and seat 1's outcome. The Bandit Toll, a team vote: seat 0's vote view with seat
## 1's vote, the draw, seat 0 waiting after taking Fight, seat 1's drawn view with seat 0 taken,
## then seat 1's Fight once both have, and its Team panel.[br]
## A seeded 2-seat session stands in for the solo run's in CampaignService while the shots are
## taken, every command submitted on it directly, which saves nothing. The solo session then comes
## back and the group ends on its map, as it found it, so 460 starts where 455 left it.[br]
## Needs: the map left by the event shots' Leave (455_event_replace).

# SceneRouter.Screen.EVENT (the script can't name the autoload; see the base).
const SCREEN_EVENT: int = 13

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const FACTION: String = "mercenary"

# The teammate's seat beside the host's.
const TEAMMATE: int = 1

# The events shot, and the options taken (their index in data/events/).
const DARK_GOBLET: String = "dark_goblet"
const POUR: int = 2
const BANDIT_TOLL: String = "bandit_toll"
const FIGHT: int = 1

var _coop: CampaignSession = null
var _solo: CampaignSession = null
var _events: EventPool = null
var _catalog: EffectCatalog.Index = null


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the co-op event shots need the map (screen %d)" % [router_screen()])
		return true
	_events = EventPool.load_default()
	_catalog = EffectCatalog.index()
	_solo = campaign()
	_coop = _new_coop()
	if _coop == null:
		fail("the 2-seat run for the event shots couldn't be built")
		return true
	node(^"CampaignService").set(&"session", _coop)
	note("co-op event shots: a 2-seat run seeded %X stands in for the solo run" % [RUN_SEED])
	await _alone()
	await _team()
	node(^"CampaignService").set(&"session", _solo)
	node(^"CampaignService").call(&"set_local_seat", CampaignData.HOST_SEAT)
	_coop.close()
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# The goblet: seat 0 chooses first and waits, then seat 1 sees that and chooses.
func _alone() -> void:
	if not _stage(_events.event(DARK_GOBLET)):
		return
	await _show(CampaignData.HOST_SEAT, "coop_event_alone_seat0")
	_coop.submit(EventNode.choose(_coop, CampaignData.HOST_SEAT, POUR, null, _events, _catalog))
	await frames(SETTLE_FRAMES)
	await capture("coop_event_alone_seat0_waiting")
	await _show(TEAMMATE, "coop_event_alone_seat1")
	_coop.submit(EventNode.choose(_coop, TEAMMATE, POUR, null, _events, _catalog))
	await frames(SETTLE_FRAMES)
	await capture("coop_event_alone_seat1_outcome")
	# The shown seat's own Leave, sent from here: it rebuilds the screen but never moves it.
	_coop.submit(LeaveNodeCommand.new(TEAMMATE))


# The toll: seat 1 votes Fight, seat 0's vote draws it, each seat takes it in turn, then Fight.
func _team() -> void:
	if not _stage(_events.event(BANDIT_TOLL)):
		return
	_coop.submit(EventNode.vote(_coop, TEAMMATE, FIGHT, _events, _catalog))
	await _show(CampaignData.HOST_SEAT, "coop_event_vote_seat0")
	_coop.submit(EventNode.vote(_coop, CampaignData.HOST_SEAT, FIGHT, _events, _catalog))
	await frames(SETTLE_FRAMES)
	await capture("coop_event_drawn_seat0")
	_coop.submit(EventNode.choose(_coop, CampaignData.HOST_SEAT, FIGHT, null, _events, _catalog))
	await frames(SETTLE_FRAMES)
	await capture("coop_event_team_seat0_waiting")
	await _show(TEAMMATE, "coop_event_drawn_seat1")
	_coop.submit(EventNode.choose(_coop, TEAMMATE, FIGHT, null, _events, _catalog))
	await frames(SETTLE_FRAMES)
	await capture("coop_event_team_seat1_fight")
	var panel: EventPanel = scene().call(&"get_panel")
	panel.get_team_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_event_team_panel")
	(scene().call(&"get_team_panel") as TeamPanel).close()


# The event screen opened for seat, as the router opens it, and shot as shot_name.
func _show(seat: int, shot_name: String) -> void:
	node(^"CampaignService").call(&"set_local_seat", seat)
	await goto(SCREEN_EVENT, shot_name)


# A new 2-seat run on RUN_SEED, as CampaignService builds one, both starting offers put aside.
func _new_coop() -> CampaignSession:
	var made: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, TEAMMATE])
	)
	var factions: Dictionary[int, String] = {0: FACTION, TEAMMATE: FACTION}
	var start: RunStart = RunStart.build(
			load(RULES_PATH) as CampaignMapRules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			EffectCatalog.index(),
			factions,
			made.ids,
			made.starting_offer_streams()
	)
	if start.run == null:
		return null
	made.run = start.run
	for seat: int in made.seats:
		made.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	return made


# Puts the 2-seat run inside its next node (a floor 1 node to start) made an Unknown one rolled
# as an event, and opens event there from a pool of it alone. Returns whether it opened.
func _stage(event: EventDefinition) -> bool:
	if event == null:
		fail("the co-op event shots need %s and %s in data/events/" % [DARK_GOBLET, BANDIT_TOLL])
		return false
	var run: CampaignRunState = _coop.run
	var next: PackedInt32Array = (
			run.graph.nodes_on_floor(1) if run.visited.is_empty()
			else run.graph.children_of(run.node)
	)
	if next.is_empty():
		note("no next node on the 2-seat map for %s" % [event.id])
		return false
	run.graph.set_node_type(next[0], CampaignGraph.NodeType.UNKNOWN)
	run.visited.append(next[0])
	run.floor_number = run.visited.size()
	run.node = next[0]
	run.flow.stage = RunFlow.Stage.NODE
	run.flow.unknown = UnknownResolution.EVENT
	var batch: CampaignBatch = _coop.submit(EventNode.open(
			_coop, EventPool.new([event]), _catalog, CombatRewardRules.load_default()
	))
	if batch == null or batch.is_rejected():
		fail("%s didn't open on the 2-seat run: %s" % [
			event.id, "no batch" if batch == null else batch.rejected_reason,
		])
		return false
	return true
