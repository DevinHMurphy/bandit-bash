# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     320_battle_heirloom_bar.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The HUD's heirloom bar in the states it shows, then its tooltip: War Ledger mid-count (7,
## copied in), Breaker's Maul ready (4 of 5, set here), Burglar's Roll's use spent (here), and the
## first-only Iron Rations and Shaken Footing spent by the battle's first Phase Start.[br]
## Needs: the battle started (300_battle_start) in a run given those heirlooms (200_run_start).


func run() -> bool:
	_stage_heirloom_states(battle_view().get_session())
	await frames(SETTLE_FRAMES)
	await capture("battle_heirloom_bar")
	var controller: BattleController = battle_controller()
	if controller.request_heirloom_bar():
		await frames(SETTLE_FRAMES)
		await capture("battle_heirloom_tooltip")
		controller.step_back()
		await frames(SETTLE_FRAMES)
	return true


func _stage_heirloom_states(session: CombatSession) -> void:
	var hud: BattleHud = scene().call(&"get_hud")
	for icon: HeirloomIcon in hud.get_heirloom_bar().get_icons():
		var view: HeirloomViewModel = icon.get_view()
		if view.heirloom_id == "breakers_maul":
			session.engine.get_instance(view.counter_instance_id).set_counter(
					EffectTerms.Lane.COMBAT, 4
			)
		elif view.heirloom_id == "burglars_roll":
			session.engine.get_instance(view.instance_ids[0]).spend_charge()
	hud.refresh()
	note("heirloom bar shot: Breaker's Maul set to 4 / 5 (ready),"
			+ " Burglar's Roll's use spent")
