# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loading_gate.gd
# Author:
# Created:  November 14, 2026
# Modified: November 22, 2026
# ==============================================================================

extends Control
## Loading: the gate every run passes on its way in. A placeholder until loading waits for every
## player.
##
## Continue sends everyone to the screen the run belongs on ([method RunScreen.go]): a solo run
## and a co-op host's alike continue, by the local seat, on the map, in the node or at the results,
## as saved; with no run held, the battle screen. In co-op only the host's press moves everyone.
## Continue has focus from the start, so a pad can press it.

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
