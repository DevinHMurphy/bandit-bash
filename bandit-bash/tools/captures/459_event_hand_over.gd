# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     459_event_hand_over.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The event screen's hand-over and the outcome's keyword column, over the game's events
## (data/events/). The Mirror of Doubt opens at the run's next node made an Unknown one; the shots
## are runs built in memory, shown on the same screen, so the throwaway run's roster is untouched:
## the Mercenary Camp's volunteer replacing a soldier carrying a buckler, as the hand-over opens
## and after Best fit; the Broken Shrine of Valor's revived unit taking the leaving archer's Pouch
## item, its own noted for the convoy; then the volunteer's outcome with Leave focused as by a
## pad, its curse's keywords as one column beside the summary. The mirror's Walk Away and Leave
## return to the map for the next group.[br]
## Needs: the map left by the co-op event shots (458_coop_events).

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

# The unit type that fills an in-memory army and leaves it at the shrine, and the source its
# recruits are logged under.
const FILL_TYPE: String = "archer"
const FILL_SOURCE: String = "capture"

# The Equipment item the leaving soldier carries, so the hand-over shows all three slots.
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
		var leaving: UnitInstance = _soldier(seat_run)
		_give_equipment(hiring, leaving)
		panel.open(hiring, 0, events, catalog)
		panel.get_cards()[VOLUNTEER].pressed.emit()
		await frames(SETTLE_FRAMES)
		panel.get_chooser().get_choice_buttons()[seat_run.army.find(leaving)].pressed.emit()
		await frames(SETTLE_FRAMES)
		if panel.get_step() != EventPanel.Step.HAND_OVER:
			fail("the volunteer's hand-over didn't open: %s" % [panel.get_status_text()])
		else:
			panel.focus_first()
			await capture("event_hand_over_recruit")
			var hand_over: EventHandOverPanel = panel.get_hand_over_panel()
			_press(hand_over, "Best fit")
			await frames(SETTLE_FRAMES)
			await capture("event_hand_over_best_fit")
			# Confirm would send through the screen's link to the throwaway run, so the choice is
			# submitted to the in-memory run here and the panel shown on it again.
			var choice: EventChoice = EventChoice.new()
			choice.replaced_id = leaving.instance_id
			choice.hand_over = EventHandOver.compact(hand_over.get_hand_over())
			var batch: CampaignBatch = hiring.submit(EventNode.choose(
					hiring, 0, VOLUNTEER, choice, events, catalog
			))
			panel.open(hiring, 0, events, catalog)
			await frames(SETTLE_FRAMES)
			if batch == null or batch.is_rejected() or panel.get_step() != EventPanel.Step.OUTCOME:
				fail("the volunteer's hand-over didn't apply: %s" % [
					"no batch" if batch == null else batch.rejected_reason,
				])
			else:
				panel.get_leave_button().grab_focus()
				await frames(SETTLE_FRAMES)
				await capture("event_outcome_keywords")

	var praying: CampaignSession = _session_with(events.event(SHRINE), true)
	if praying != null:
		var seat_run: SeatRun = praying.run.seat_run(0)
		var leaving: UnitInstance = _first_of_type(seat_run, FILL_TYPE)
		_fill_army(praying, seat_run)
		praying.submit(EventNode.open_chooser(praying, 0, PRAYER, events, catalog))
		panel.open(praying, 0, events, catalog)
		await frames(SETTLE_FRAMES)
		panel.get_chooser().get_choice_buttons()[0].pressed.emit()
		await frames(SETTLE_FRAMES)
		if leaving != null:
			panel.get_chooser().get_choice_buttons()[seat_run.army.find(leaving)].pressed.emit()
			await frames(SETTLE_FRAMES)
		var rows: Array[HandOverRow] = panel.get_hand_over_panel().get_rows()
		if panel.get_step() != EventPanel.Step.HAND_OVER or rows.is_empty():
			fail("the shrine's hand-over didn't open")
		else:
			rows[-1].button_for(Guildhall.HandOver.RECRUIT).pressed.emit()
			await frames(SETTLE_FRAMES)
			await capture("event_hand_over_revive")

	scene().call(&"reopen", events, catalog)
	await frames(SETTLE_FRAMES)
	panel.get_cards()[WALK_AWAY].pressed.emit()
	await frames(SETTLE_FRAMES)
	panel.get_leave_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	if router_screen() != SCREEN_MAP:
		fail("the event's Leave didn't return to the map (screen %d)" % [router_screen()])
	return true


# Presses the hand-over's button whose text starts with prefix; a NOTE when there is none.
func _press(hand_over: EventHandOverPanel, prefix: String) -> void:
	for button: Button in hand_over.get_choice_buttons():
		if button.text.begins_with(prefix) and not button.disabled:
			button.pressed.emit()
			return
	note("no %s to press on the hand-over" % [prefix])


# Makes the run's next node an Unknown one, enters it, opens event there from a pool of it alone,
# and goes to the event screen, which shows it from the game's pool. Returns whether it opened.
func _open_event(event: EventDefinition) -> bool:
	var service: Node = node(^"CampaignService")
	var session: CampaignSession = campaign()
	if event == null:
		fail("the hand-over shots need %s in data/events/" % [MIRROR])
		return false
	if router_screen() != SCREEN_MAP or session == null or session.run == null:
		fail("the hand-over shots need the run on the map (screen %d)" % [router_screen()])
		return false
	var run: CampaignRunState = session.run
	var next: PackedInt32Array = run.graph.children_of(run.node)
	if next.is_empty():
		note("no next node for the hand-over shots")
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
	note("the hand-over shots' armies are runs built in memory: the throwaway run's is untouched")
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


# Gives unit a new EQUIPMENT_ID item in its Equipment slot; a NOTE for no unit.
func _give_equipment(made: CampaignSession, unit: UnitInstance) -> void:
	if unit == null:
		note("no soldier to give a %s, so the hand-over shows fewer rows" % [EQUIPMENT_ID])
		return
	var seat_run: SeatRun = made.run.seat_run(0)
	var item: ItemInstance = ItemInstance.new(made.ids.next_item_id(EQUIPMENT_ID), EQUIPMENT_ID)
	seat_run.items[item.instance_id] = item
	ItemPlacement.put_item(unit, Loadout.Slot.EQUIPMENT, item.instance_id)


# The seat's living unit that isn't the commander, first in roster order; null for none.
func _soldier(seat_run: SeatRun) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id:
			return unit
	return null


# The seat's first living unit of unit_type_id; null for none.
func _first_of_type(seat_run: SeatRun, unit_type_id: String) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		if unit.unit_type_id == unit_type_id:
			return unit
	return null
