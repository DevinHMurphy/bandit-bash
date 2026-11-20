# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     300_battle_start.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The battle's swap window, then the battle started and the HUD with the cursor on the first
## player unit, showing the unit panel and rune bar.[br]
## Needs: the battle screen open, before its start (250_campaign_map). The battle groups after
## this one each start and end with the battle idle in the player phase.


func run() -> bool:
	var view: BattleView = battle_view()
	var controller: BattleController = battle_controller()
	settle(view)
	await frames(SETTLE_FRAMES)
	await capture("battle_swap_window")
	controller.request_start()
	settle(view)
	await frames(SETTLE_FRAMES)
	var session: CombatSession = view.get_session()
	controller.move_cursor(session.state.tile_of(first_player(session)))
	await frames(SETTLE_FRAMES)
	await capture("battle_hud")
	return true
