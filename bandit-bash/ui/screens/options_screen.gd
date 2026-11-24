# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     options_screen.gd
# Author:
# Created:  October 14, 2026
# Modified: November 23, 2026
# ==============================================================================

extends Control
## Options: the open save file's settings, reached from the Main Menu. The settings themselves are
## an [OptionsPanel] (the co-op pause menu shows the same one); this screen titles it, gives its
## first slider focus, and goes back to the screen that opened it on Back.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick   (move between the rows and buttons)
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick   (step the focused volume slider)
#   "ui_accept"            -> Enter, Space; pad A [Cross] (press Apply or Back, flip the toggle)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (Back's shortcut: presses it)
#   Mouse: drag or click a slider, click the toggle and buttons.
# Hint context: MENU.
# ============================================================

@onready var _panel: OptionsPanel = %OptionsPanel


func _ready() -> void:
	_panel.back_pressed.connect(_on_options_panel_back_pressed)
	_panel.focus_first.call_deferred()


## The volume row of [param channel], for tests; null for a channel with none.
func get_volume_row(channel: SettingsData.Channel) -> VolumeRow:
	return _panel.get_volume_row(channel)


func _on_options_panel_back_pressed() -> void:
	SceneRouter.go_back()
