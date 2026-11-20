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
## The event screen's "which unit leaves?" step, over the game's events (data/events/). The Mirror
## of Doubt opens at the run's next node made an Unknown one, as 450_event_screen opens its
## events; the shots are runs built in memory, shown on the same screen (its header stays the
## solo run's), so the throwaway run's roster is untouched: the Mercenary Camp's free volunteer
## into a full army, the commander and a unit whose items the convoy can't take greyed; the Broken
## Shrine of Valor's fallen chooser in a full army, ungreyed; then its leaving step. The mirror's
## Walk Away and Leave return to the map for the next group.[br]
## Needs: the map left by the event shots' Leave (450_event_screen).

# SceneRouter.Screen.EVENT (the script can't name the autoload; see the base).
const SCREEN_EVENT: int = 13

# CampaignService.MAP_RULES_PATH, for the runs built in memory (the autoload can't be named).
const MAP_RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

# The events shot, and the options pressed (their index in data/events/).
const MERCENARY_CAMP: String = "mercenary_camp"
const VOLUNTEER: int = 1
const SHRINE: String = "broken_shrine_of_valor"
const PRAYER: int = 0

# The event the throwaway run opens, so the screen shows, and its option that changes nothing.
const MIRROR: String = "mirror_of_doubt"
const WALK_AWAY: int = 2

# The unit type that fills an in-memory army, and the source its recruits are logged under.
const FILL_TYPE: String = "archer"
const FILL_SOURCE: String = "capture"

# The Equipment item given to the unit whose items the convoy can't take.
const EQUIPMENT_ID: String = "buckler"


func run() -> bool:
	var events: EventPool = EventPool.load_default()
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	if not await _open_event(events.event(MIRROR)):
		return true
	var panel: EventPanel = scene().call(&"get_panel")

	var hiring: CampaignSession = _session_with(events.event(MERCENARY_CAMP), false)
	if hiring != null:
		var seat_run: SeatRun = hiring.run.seat_run(0)
		_fill_army(hiring, seat_run)
		_overload_convoy(hiring, _soldier(seat_run))
		panel.open(hiring, 0, events, catalog)
		panel.get_cards()[VOLUNTEER].pressed.emit()
		await frames(SETTLE_FRAMES)
		await capture("event_leaving_recruit")

	var praying: CampaignSession = _session_with(events.event(SHRINE), true)
	if praying != null:
		_fill_army(praying, praying.run.seat_run(0))
		praying.submit(EventNode.open_chooser(praying, 0, PRAYER, events, catalog))
		panel.open(praying, 0, events, catalog)
		await frames(SETTLE_FRAMES)
		await capture("event_leaving_fallen")
		panel.get_chooser().get_choice_buttons()[0].pressed.emit()
		await frames(SETTLE_FRAMES)
		await capture("event_leaving_revive")

	scene().call(&"reopen", events, catalog)
	await frames(SETTLE_FRAMES)
	panel.get_cards()[WALK_AWAY].pressed.emit()
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
		fail("the leaving shots need %s in data/events/" % [MIRROR])
		return false
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
	note("the leaving shots' armies are runs built in memory: the throwaway run's is untouched")
	node(^"SceneRouter").call(&"goto_screen", SCREEN_EVENT)
	await frames(SETTLE_FRAMES)
	return true


# A new solo run built in memory on the throwaway run's faction, standing in its first node made
# an Unknown one with event open there; with fallen, its first soldier fell first, as the
# shrine needs. Null, with a FAIL line, when it can't be built.
func _session_with(event: EventDefinition, fallen: bool) -> CampaignSession:
	var map_rules: CampaignMapRules = load(MAP_RULES_PATH) as CampaignMapRules
	if event == null or map_rules == null:
		fail("an in-memory event run needs its event and %s" % [MAP_RULES_PATH])
		return null
	var factions: Dictionary[int, String] = {0: campaign().run.seat_run(0).faction_id}
	var made: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
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
	var unit: UnitInstance = _soldier(made.run.seat_run(0))
	if fallen and unit != null:
		var seat_run: SeatRun = made.run.seat_run(0)
		seat_run.army.erase(unit)
		seat_run.fallen.append(unit)
		unit.hp = 0
	var first: int = made.run.graph.nodes_on_floor(1)[0]
	made.run.graph.set_node_type(first, CampaignGraph.NodeType.UNKNOWN)
	made.submit(ChooseNodeCommand.new(0, first))
	var batch: CampaignBatch = made.submit(EventNode.open(
			made, EventPool.new([event]), EffectCatalog.index(), CombatRewardRules.load_default()
	))
	if batch == null or batch.is_rejected():
		fail("%s didn't open in memory: %s" % [
			event.id, "no batch" if batch == null else batch.rejected_reason,
		])
		return null
	note("%s shown on a run built in memory" % [event.id])
	return made


# Recruits FILL_TYPE units into seat_run's army until it is full, as the Guildhall would.
func _fill_army(made: CampaignSession, seat_run: SeatRun) -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	while seat_run.army.size() < RunOperations.max_army_size(seat_run, catalog):
		var joining: RecruitOffer = RecruitOffer.make(catalog, FILL_TYPE, "", 1, made.ids)
		if joining == null:
			fail("no %s to fill the army with" % [FILL_TYPE])
			return
		RunOperations.recruit(made.run, seat_run.seat, joining, FILL_SOURCE)


# Gives unit one more item, in its Equipment slot, and fills the convoy until unit's items are
# one too many for it: a unit carrying one item fewer can still leave, unit can't.
func _overload_convoy(made: CampaignSession, unit: UnitInstance) -> void:
	if unit == null:
		note("no soldier to overload the convoy with, so no unit is greyed for it")
		return
	var seat_run: SeatRun = made.run.seat_run(0)
	var item: ItemInstance = ItemInstance.new(made.ids.next_item_id(EQUIPMENT_ID), EQUIPMENT_ID)
	seat_run.items[item.instance_id] = item
	ItemPlacement.put_item(unit, Loadout.Slot.EQUIPMENT, item.instance_id)
	var capacity: int = ItemPlacement.convoy_capacity(seat_run, EffectCatalog.index())
	while seat_run.convoy.size() < capacity - unit.item_ids().size() + 1:
		var filler: ItemInstance = ItemInstance.new(
				made.ids.next_item_id(EQUIPMENT_ID), EQUIPMENT_ID
		)
		seat_run.items[filler.instance_id] = filler
		seat_run.convoy.append(filler.instance_id)


# The seat's living unit that isn't the commander, first in roster order; null for none.
func _soldier(seat_run: SeatRun) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id:
			return unit
	return null
