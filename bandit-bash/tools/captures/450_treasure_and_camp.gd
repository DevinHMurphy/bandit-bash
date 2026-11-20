# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     450_treasure_and_camp.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## From the map: the army view; a Treasure (its chest, the leave question); a Camp (its choices,
## the Feast's ingredients, Train's units, re-gearing and an item being moved); a Key combat's
## Results at Rewards and its heirloom offer. Each node is staged on the run (the screens route by
## the run's stage), then left, so the group ends on the map.[br]
## Needs: the map reached by the victory's Leave (400_victory).

# SceneRouter.Screen values the base doesn't list (see the base's class doc).
const SCREEN_TREASURE: int = 13
const SCREEN_CAMP: int = 14

# VictoryOverlay.Stage's Rewards: the script can't name the overlay, whose script names autoloads.
const STAGE_REWARDS: int = 4

# The ingredient put in the convoy so the Feast's panel lists one.
const INGREDIENT: String = "heartbeet"


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the treasure and camp shots need the map (screen %d)" % [router_screen()])
		return true
	(scene().call(&"get_army_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("map_army_view")
	(scene().call(&"get_army_view") as ArmyView).close()
	await frames(SETTLE_FRAMES)
	await _treasure()
	await _camp()
	await _key_heirloom()
	if router_screen() != SCREEN_MAP:
		node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
		await frames(SETTLE_FRAMES)
	return true


# The chest as rolled on entry, then Leave's question, answered by giving the chest up.
func _treasure() -> void:
	if not _stage_node(CampaignGraph.NodeType.TREASURE):
		return
	await goto(SCREEN_TREASURE, "treasure")
	(scene().call(&"get_leave_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("treasure_leave_confirm")
	(scene().call(&"get_confirm_dialog") as LeaveConfirmDialog).confirmed.emit()
	await frames(SETTLE_FRAMES)


# The two choices, the Feast's ingredient (one staged in the convoy), Train's units, re-gearing
# and an item picked up; then a bare Feast and Leave.
func _camp() -> void:
	if not _stage_node(CampaignGraph.NodeType.CAMP):
		return
	var run: CampaignRunState = campaign().run
	var seat_run: SeatRun = run.seat_run(0)
	var beet: String = campaign().ids.next_item_id("Heartbeet")
	seat_run.items[beet] = ItemInstance.new(beet, INGREDIENT)
	seat_run.convoy.append(beet)
	note("camp shots: a Heartbeet staged in the convoy for the Feast's panel")
	await goto(SCREEN_CAMP, "camp")
	(scene().call(&"get_feast_card") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("camp_feast")
	(scene().call(&"get_ingredient_panel") as IngredientPanel).cancelled.emit()
	await frames(SETTLE_FRAMES)
	(scene().call(&"get_train_card") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("camp_train")
	(scene().call(&"get_unit_choice") as UnitChoicePanel).cancelled.emit()
	await frames(SETTLE_FRAMES)
	(scene().call(&"get_army_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("camp_army")
	var army: ArmyView = scene().call(&"get_army_view")
	army.get_rows()[0].get_slot_button(Loadout.Slot.WEAPON).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("camp_army_moving")
	army.close()
	await frames(SETTLE_FRAMES)
	node(^"CampaignService").call(&"submit_command", FeastCommand.new(0))
	(scene().call(&"get_leave_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)


# A Key combat's Results, staged at Rewards with its heirloom offered, the offer opened; then the
# heirloom given up and the node left.
func _key_heirloom() -> void:
	if not _stage_node(CampaignGraph.NodeType.KEY):
		return
	var run: CampaignRunState = campaign().run
	var seat_run: SeatRun = run.seat_run(0)
	run.flow.stage = RunFlow.Stage.RESULTS
	var grades: CombatGrades = CombatGrades.new()
	seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
		"grades": grades.capture(), "xp": [], "level_ups": [],
	}
	var offer: KeyHeirloom = KeyHeirloom.roll(
			RngStream.new(RUN_SEED), seat_run, EffectCatalog.index(), false
	)
	if offer == null:
		note("no heirloom is left to offer, so key_heirloom isn't shot")
		return
	offer.store(seat_run)
	note("key heirloom shots: a won Key combat's Results staged with no item pick")
	node(^"SceneRouter").call(&"goto_screen", SCREEN_COMBAT_RESULTS)
	await frames(SETTLE_FRAMES)
	var overlay: Node = _victory_overlay()
	if overlay == null:
		fail("the staged Key combat's Results showed no victory sequence")
		return
	overlay.call(&"skip")
	while (overlay.call(&"get_stage") as int) < STAGE_REWARDS:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await tree.process_frame
	await frames(SETTLE_FRAMES)
	await fade_capture("key_heirloom_rewards")
	var stage: VictoryRewardsStage = overlay.call(&"get_rewards_stage")
	var rows: Array[RewardRow] = stage.get_rows()
	if not rows.is_empty():
		rows[rows.size() - 1].pressed.emit()
		await frames(SETTLE_FRAMES)
		await fade_capture("key_heirloom_offer")
	node(^"CampaignService").call(&"submit_command", KeyHeirloomCommand.new(0, false))
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))


# Puts the run inside the first node of type reached from its map's floor 1, one node per floor,
# as choosing each would (the screens route by the run's stage). Returns false, with a NOTE and
# nothing changed, for a map with none.
func _stage_node(type: CampaignGraph.NodeType) -> bool:
	var run: CampaignRunState = campaign().run
	var routes: Array[PackedInt32Array] = []
	for start: int in run.graph.nodes_on_floor(1):
		routes.append(PackedInt32Array([start]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_front()
		var last: int = route[route.size() - 1]
		if run.graph.type_of(last) == type:
			run.visited = route
			run.floor_number = route.size()
			run.node = last
			run.flow.stage = RunFlow.Stage.NODE
			return true
		for child: int in run.graph.children_of(last):
			var longer: PackedInt32Array = route.duplicate()
			longer.append(child)
			routes.append(longer)
	note("the map has no %s node to stage" % [CampaignGraph.NodeType.find_key(type)])
	return false


# The victory sequence shown: the Results screen's.
func _victory_overlay() -> Node:
	if scene() == null or not scene().has_method(&"get_overlay"):
		return null
	return scene().call(&"get_overlay") as Node
