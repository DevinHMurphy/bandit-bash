# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     400_victory.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Ends the battle as won, one unit a point short of a level, and shoots the victory sequence over
## the board: Grade, Recap filling, the level-up, Recap, Rewards, the item picker, placement and
## the leave dialog. Then the sequence resumed over its backdrop, as Save & Quit then Continue Run
## reopen it: on Grade, and once the pick is skipped, on Rewards. Then Leave, to the map.[br]
## Needs: the battle screen open, its battle not ended (250_campaign_map).

# VictoryOverlay.Stage values: the script can't name the overlay, whose script names autoloads.
const STAGE_RECAP_LEVEL_UPS: int = 2
const STAGE_REWARDS: int = 4


func run() -> bool:
	_win_battle()
	await frames(SETTLE_FRAMES)
	await _results()
	return true


# The battle recorded as won and played through, with no end banner wait.
func _win_battle() -> void:
	var view: BattleView = battle_view()
	var session: CombatSession = view.get_session()
	scene().set(&"end_banner_time", 0.0)
	# One unit a point short of a level, so the recap shows a level-up card.
	var leveler: UnitInstance = campaign().run.seat_run(0).army[0]
	leveler.xp = CombatRewardRules.load_default().xp_per_level - 1
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	session.engine.record(ended)
	settle(view)
	view.settled.emit()


func _results() -> void:
	var overlay: Node = _victory_overlay()
	if router_screen() != SCREEN_GAMEPLAY or overlay == null:
		fail("the won battle showed no victory sequence (screen %d)" % [router_screen()])
		return
	await frames(SETTLE_FRAMES)
	await fade_capture("victory_grade")
	(overlay.call(&"get_primary_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await fade_capture("victory_recap_filling")
	overlay.call(&"skip")
	await frames(SETTLE_FRAMES)
	if (overlay.call(&"get_stage") as int) == STAGE_RECAP_LEVEL_UPS:
		await fade_capture("victory_level_up")
	while (overlay.call(&"get_stage") as int) == STAGE_RECAP_LEVEL_UPS:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await tree.process_frame
	await frames(SETTLE_FRAMES)
	await fade_capture("victory_recap")
	(overlay.call(&"get_primary_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await fade_capture("victory_rewards")
	var rows: Array[RewardRow] = _reward_rows(overlay)
	if not rows.is_empty():
		await _picker_and_leave(overlay, rows[0])
	await _resume_results("victory_resumed_grade")
	overlay = _victory_overlay()
	if overlay == null:
		return
	(overlay.call(&"get_primary_button") as Button).pressed.emit()
	overlay.call(&"skip")
	while (overlay.call(&"get_stage") as int) < STAGE_REWARDS:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await tree.process_frame
	var open_rows: Array[RewardRow] = _reward_rows(overlay)
	if not open_rows.is_empty():
		open_rows[0].pressed.emit()
		await frames(SETTLE_FRAMES)
		var resumed_picker: Control = overlay.call(&"get_picker") as Control
		_pick_panel(resumed_picker).get_skip_button().pressed.emit()
		await frames(SETTLE_FRAMES)
	await _resume_results("victory_resumed_rewards")
	overlay = _victory_overlay()
	if overlay != null:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await frames(SETTLE_FRAMES)


# The item picker from a reward row, placement of its first offer, backed out of both; then the
# leave dialog, answered Stay.
func _picker_and_leave(overlay: Node, row: RewardRow) -> void:
	row.pressed.emit()
	await frames(SETTLE_FRAMES)
	await fade_capture("victory_item_picker")
	var picker: Control = overlay.call(&"get_picker") as Control
	var cards: Array[ItemOfferCard] = _pick_panel(picker).get_offer_cards()
	if not cards.is_empty():
		cards[0].pressed.emit()
		await frames(SETTLE_FRAMES)
		await fade_capture("victory_placement")
		(picker.call(&"get_placement_panel") as PlacementPanel).step_back()
		await frames(SETTLE_FRAMES)
	(picker.call(&"get_back_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	(overlay.call(&"get_primary_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await fade_capture("victory_leave_confirm")
	var dialog: LeaveConfirmDialog = overlay.call(&"get_confirm_dialog")
	dialog.get_stay_button().pressed.emit()
	await frames(SETTLE_FRAMES)


# Continues the run from its save through Loading and captures the sequence the Results screen
# reopens.
func _resume_results(shot_name: String) -> void:
	var err: Error = reopen_run()
	if err != OK:
		fail("the run did not continue: %s" % [error_string(err)])
		return
	await goto(SCREEN_LOADING, "loading_resumed")
	(scene().get_node(^"%ContinueButton") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	if router_screen() != SCREEN_COMBAT_RESULTS:
		fail("the continued run did not reopen Results (screen %d)" % [router_screen()])
		return
	await fade_capture(shot_name)


func _reward_rows(overlay: Node) -> Array[RewardRow]:
	var stage: VictoryRewardsStage = overlay.call(&"get_rewards_stage")
	return stage.get_rows()


func _pick_panel(picker: Control) -> ItemPickPanel:
	var panel: ItemPickPanel = picker.call(&"get_pick_panel")
	return panel


# The victory sequence shown: the Results screen's, or the battle screen's over its board.
func _victory_overlay() -> Node:
	if scene() == null:
		return null
	if scene().has_method(&"get_overlay"):
		return scene().call(&"get_overlay") as Node
	for child: Node in scene().get_children():
		if child.has_method(&"get_rewards_stage"):
			return child
	return null
