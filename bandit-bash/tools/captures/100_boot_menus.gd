# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     100_boot_menus.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Boot, start, save select, main menu, new run, options and the lobby, through the real router.
## Opens save file [constant SAVE_NUMBER] on the way, for the run the next group starts.

const BOOT_SCENE: String = "res://ui/screens/boot.tscn"


func run() -> bool:
	tree.change_scene_to_file(BOOT_SCENE)
	await tree.process_frame
	await capture("boot")
	await frames(SETTLE_FRAMES)
	await capture("start")
	await goto(SCREEN_SAVE_SELECT, "save_select")
	open_save()
	await goto(SCREEN_MAIN_MENU, "main_menu")
	await goto(SCREEN_NEW_RUN, "new_run")
	await goto(SCREEN_OPTIONS, "options")
	await goto(SCREEN_LOBBY, "lobby")
	return true
