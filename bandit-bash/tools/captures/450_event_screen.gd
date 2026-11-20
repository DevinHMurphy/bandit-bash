# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     450_event_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The event screen over the event screen tests' test-only events (none is real content: EV4
## authors the 13), each opened at the run's next node made an Unknown one, as RN10 will open
## them: the trials' option list, its weapon chooser and its outcome, then Leave; the rune stone's
## greyed Pay the Tithe; and the vote view of a two-seat run built in memory with one vote cast,
## shown on the same screen (its header stays the solo run's). Walk Away and Leave return to the
## map for the next group.[br]
## Needs: the map reached by the victory's Leave (400_victory).

const EventScreenFixture = preload("res://tests/ui/events/event_screen_fixture.gd")

# SceneRouter.Screen.EVENT (the script can't name the autoload; see the base).
const SCREEN_EVENT: int = 13

# Seats in the vote view's run.
const VOTE_SEATS: int = 2


func run() -> bool:
	var screens: EventScreenFixture = EventScreenFixture.new(tree.root)
	if not await _open_test_event(EventScreenFixture.trials()):
		return true
	await capture("event_options")
	var panel: EventPanel = scene().call(&"get_panel")
	panel.get_cards()[EventScreenFixture.TEMPER].pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("event_chooser")
	panel.get_chooser().get_choice_buttons()[0].pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("event_outcome")
	panel.get_leave_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	var stone: EventDefinition = EventScreenFixture.runes()
	if not await _open_test_event(stone):
		return true
	await capture("event_greyed")
	var team: CampaignSession = screens.session_with(EventScreenFixture.toll(), VOTE_SEATS)
	team.submit(EventNode.vote(
			team, 1, EventScreenFixture.FIGHT, screens.pool, screens.base.catalog
	))
	panel = scene().call(&"get_panel")
	panel.open(team, 0, screens.pool, screens.base.catalog)
	await frames(SETTLE_FRAMES)
	await capture("event_vote")
	scene().call(&"reopen", EventPool.new([stone]), EffectCatalog.index())
	await frames(SETTLE_FRAMES)
	panel.get_cards()[EventScreenFixture.WALK_AWAY].pressed.emit()
	await frames(SETTLE_FRAMES)
	panel.get_leave_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	if router_screen() != SCREEN_MAP:
		fail("the event's Leave didn't return to the map (screen %d)" % [router_screen()])
	return true


# Makes the run's next node an Unknown one, enters it, opens event there, and shows it on the
# event screen, re-opened on the event's own pool. Returns whether the screen opened.
func _open_test_event(event: EventDefinition) -> bool:
	var service: Node = node(^"CampaignService")
	var session: CampaignSession = campaign()
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
	var pool: EventPool = EventPool.new([event])
	var batch: CampaignBatch = service.call(&"submit_command", EventNode.open(
			session, pool, EffectCatalog.index(), CombatRewardRules.load_default()
	))
	if batch == null or batch.is_rejected():
		fail("%s didn't open: %s" % [
			event.id, "no batch" if batch == null else batch.rejected_reason,
		])
		return false
	note("%s opened at node %d, made an Unknown node for the shot" % [event.id, next[0]])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_EVENT)
	await frames(SETTLE_FRAMES)
	scene().call(&"reopen", pool, EffectCatalog.index())
	await frames(SETTLE_FRAMES)
	return true
