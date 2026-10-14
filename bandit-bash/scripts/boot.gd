# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     boot.gd
# Author:
# Created:  October 9, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Node
## Entry point (project.godot main scene). Initializes Steam and settings, then opens the first
## screen.
##
## Steam initializes before any screen loads so every screen reads
## [member SteamManager.is_available] as a settled fact. A failed init is not fatal: the game
## opens the start screen and solo play works without Steam.[br]
## Settings come from the last selected save file, since none is open before Save Select.


func _ready() -> void:
	SteamManager.initialize()
	SaveService.load_startup_settings()
	# Deferred because the tree is still being built during the main scene's _ready().
	SceneRouter.goto_screen.call_deferred(SceneRouter.Screen.START)
