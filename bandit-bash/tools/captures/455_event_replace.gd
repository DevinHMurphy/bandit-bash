# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     455_event_replace.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The event screen's "which unit leaves?" step, over the event screen tests' test-only camp and
## shrine (no real content). The camp opens at the run's next node made an Unknown one, as
## 450_event_screen opens its events; the shots stage their armies on runs built in memory, shown
## on the same screen (its header stays the camp's), so the throwaway run's roster is untouched:
## the camp's hire into a full army, the commander and a unit whose items the convoy can't take
## greyed; the shrine's fallen chooser in a full army, ungreyed; then its leaving step. Walk Away
## and Leave return to the map for the next group.[br]
## Needs: the map left by the event shots' Leave (450_event_screen).

const EventScreenFixture = preload("res://tests/ui/events/event_screen_fixture.gd")

# SceneRouter.Screen.EVENT (the script can't name the autoload; see the base).
const SCREEN_EVENT: int = 13


func run() -> bool:
	var screens: EventScreenFixture = EventScreenFixture.new(tree.root)
	var camp: EventDefinition = EventScreenFixture.camp()
	if not await _open_test_event(camp):
		return true
	var panel: EventPanel = scene().call(&"get_panel")

	var hiring: CampaignSession = screens.session_with(camp)
	screens.overload_convoy(hiring, screens.base.soldier(hiring.run.seat_run(0)))
	panel.open(hiring, 0, screens.pool, screens.base.catalog)
	panel.get_cards()[EventScreenFixture.HIRE].pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("event_leaving_recruit")

	var praying: CampaignSession = screens.session_with(EventScreenFixture.shrine(), 1, true)
	screens.fill_army(praying, praying.run.seat_run(0))
	praying.submit(EventNode.open_chooser(
			praying, 0, EventScreenFixture.PRAYER, screens.pool, screens.base.catalog
	))
	panel.open(praying, 0, screens.pool, screens.base.catalog)
	await frames(SETTLE_FRAMES)
	await capture("event_leaving_fallen")
	panel.get_chooser().get_choice_buttons()[0].pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("event_leaving_revive")

	scene().call(&"reopen", EventPool.new([camp]), EffectCatalog.index())
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
		fail("the leaving shots need the run on the map (screen %d)" % [router_screen()])
		return false
	var run: CampaignRunState = session.run
	var next: PackedInt32Array = run.graph.children_of(run.node)
	if next.is_empty():
		note("no next node for the leaving shots")
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
	note("the leaving shots' armies are runs built in memory: the throwaway run's is untouched")
	node(^"SceneRouter").call(&"goto_screen", SCREEN_EVENT)
	await frames(SETTLE_FRAMES)
	scene().call(&"reopen", pool, EffectCatalog.index())
	await frames(SETTLE_FRAMES)
	return true
