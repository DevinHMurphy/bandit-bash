# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     494_coop_pause_menu.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The co-op pause menu over the map, opened as each role ([method PauseMenu.open_as]), as no Steam
## session runs here: the host's menu, its Save & Quit question and its Options; the client's menu
## and its Forfeit question. Nothing pauses, so the map's hint bar shows the menu's co-op set. Each
## question is shot, then declined, and the menu closes after, so 500 starts on the map as before.
## [br]
## Needs: the map, as the rune bar shots leave it (493_battle_rune_bar_keywords).


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the co-op pause menu shots need the map (screen %d)" % [router_screen()])
		return true
	var menu: PauseMenu = scene().get_node_or_null(^"PauseMenu") as PauseMenu
	if menu == null:
		fail("the map has no pause menu")
		return true
	note("co-op pause menu shots: opened as the host, then as a client, on the map")
	menu.open_as(PauseMenu.Role.HOST)
	await frames(SETTLE_FRAMES)
	await capture("coop_pause_host")
	(menu.get_node(^"%SaveQuitButton") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_pause_host_save_quit")
	menu.get_save_quit_confirm().cancel()
	menu.open_options()
	await frames(SETTLE_FRAMES)
	await capture("coop_pause_options")
	menu.close_options()
	menu.close()
	menu.open_as(PauseMenu.Role.CLIENT)
	await frames(SETTLE_FRAMES)
	await capture("coop_pause_client")
	(menu.get_node(^"%ForfeitButton") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_pause_client_forfeit")
	menu.get_forfeit_confirm().cancel()
	menu.close()
	await frames(SETTLE_FRAMES)
	return true
