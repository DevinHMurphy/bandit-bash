# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     new_run_screen.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Control
## New Run: starts a solo run. A placeholder for the campaign system's run setup.
##
## Start writes the run's first save ([code]SaveService.start_new_solo_run()[/code]) and only then
## moves on to loading, so a run that couldn't be saved never begins. Back returns to the Main
## Menu without creating anything.

@onready var _status_label: Label = %Status
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_button_pressed)
	_start_button.grab_focus.call_deferred()


func _on_start_button_pressed() -> void:
	var err: Error = SaveService.start_new_solo_run()
	if err != OK:
		_status_label.text = "Couldn't start the run (%s)." % [error_string(err)]
		return
	SceneRouter.goto_screen(SceneRouter.Screen.LOADING)
