# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     boot.gd
# Author:
# Created:  October 9, 2026
# Modified: November 18, 2026
# ==============================================================================

extends Node
## Entry point (project.godot main scene). Initializes Steam and settings, then opens the first
## screen.
##
## Steam initializes before any screen loads so every screen reads
## [member SteamManager.is_available] as a settled fact. A failed init is not fatal: the game
## opens the start screen and solo play works without Steam.[br]
## Settings come from the last selected save file, since none is open before Save Select.[br]
## An invite accepted while the game was closed arrives as a launch argument; it is checked after
## the start screen opens, so accepting it routes from there like any other invite.[br]
## It also sets the window's clear colour to the style guide's [code]bg[/code] token, which every
## screen without a background of its own shows through.


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiTokens.color(UiTokens.BG))
	SteamManager.initialize()
	SaveService.load_startup_settings()
	# Deferred because the tree is still being built during the main scene's _ready(). The invite
	# check is queued after it so the start screen is current when the invite is handled.
	SceneRouter.goto_screen.call_deferred(SceneRouter.Screen.START)
	SteamNetwork.check_launch_invite.call_deferred()
