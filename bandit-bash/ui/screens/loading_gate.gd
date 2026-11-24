# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loading_gate.gd
# Author:
# Created:  November 14, 2026
# Modified: November 24, 2026
# ==============================================================================

extends Control
## Loading: the gate every run passes on its way in. A placeholder until loading waits for every
## player.
##
## Continue sends everyone to the screen the run belongs on ([method RunScreen.go]): on the map,
## in the node or at the results, as saved; with no run held, the battle screen. In co-op only
## the host's press moves anyone, every machine at once; a client's press moves nobody: it asks
## the host for the run and waits for the host's route. Continue has focus from the start, so a
## pad can press it.

# ============================================================
# INPUT MAP SETUP: none read here. "ui_accept" (Enter, Space; pad A [Cross]) presses the focused
# Continue through the GUI; a click presses it too.
# ============================================================

@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	_continue_button.pressed.connect(_on_continue_button_pressed)
	_continue_button.grab_focus.call_deferred()


func _on_continue_button_pressed() -> void:
	RunScreen.go()
