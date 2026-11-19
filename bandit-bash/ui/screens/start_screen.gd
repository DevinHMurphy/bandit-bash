# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     start_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name StartScreen
extends Control
## The first screen of every launch: the game's title, Play (on to Save Select) and Quit, both
## [NavButton]s in the scene. Play has focus from the start, so a pad can press it at once.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_up" / "ui_down" -> arrows; d-pad, left stick   (move between Play and Quit)
#   "ui_accept"         -> Enter, Space; pad A [Cross] (press the focused button)
#   Mouse: a click on a button.
# Hint context: MENU.
# ============================================================

@onready var _play_button: Button = %PlayButton


func _ready() -> void:
	_play_button.grab_focus.call_deferred()


## The Play button, the screen's main action, for tests.
func get_main_button() -> Button:
	return _play_button
