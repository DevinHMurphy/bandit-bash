# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     main_menu.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Control
## Main Menu for the open save file: continue, start or abandon the solo run.
##
## Only reachable from Save Select, so a save file is always open; if one somehow isn't, the screen
## sends the player back to Save Select. Continue Run and Abandon Run show only while the save file
## has a solo run; New Run shows only while it doesn't. Abandon asks for confirmation.[br]
## Multiplayer, Options and Back stay NavButtons in the scene.

@onready var _header_label: Label = %Header
@onready var _status_label: Label = %Status
@onready var _continue_button: Button = %ContinueButton
@onready var _new_run_button: Button = %NewRunButton
@onready var _abandon_button: Button = %AbandonButton
@onready var _abandon_dialog: ConfirmationDialog = %AbandonDialog


func _ready() -> void:
	if not SaveService.has_open_save_file():
		SceneRouter.goto_screen.call_deferred(SceneRouter.Screen.SAVE_SELECT)
		return

	_continue_button.pressed.connect(_on_continue_button_pressed)
	_new_run_button.pressed.connect(_on_new_run_button_pressed)
	_abandon_button.pressed.connect(_on_abandon_button_pressed)
	_abandon_dialog.confirmed.connect(_on_abandon_dialog_confirmed)
	_refresh()


func _refresh() -> void:
	var player_name: String = SaveService.profile.last_steam_name
	if player_name.is_empty():
		player_name = "Unknown player"
	_header_label.text = "Save %d  ·  %s" % [SaveService.current_save_number, player_name]

	var has_run: bool = SaveService.has_solo_campaign()
	_continue_button.visible = has_run
	_abandon_button.visible = has_run
	_new_run_button.visible = not has_run
	var first_button: Button = _continue_button if has_run else _new_run_button
	first_button.grab_focus.call_deferred()


func _on_continue_button_pressed() -> void:
	var err: Error = SaveService.continue_solo_run()
	if err != OK:
		_status_label.text = "Couldn't load the run (%s). You can abandon it." % [error_string(err)]
		return
	SceneRouter.goto_screen(SceneRouter.Screen.LOADING)


func _on_new_run_button_pressed() -> void:
	SceneRouter.goto_screen(SceneRouter.Screen.NEW_RUN)


func _on_abandon_button_pressed() -> void:
	_abandon_dialog.popup_centered()


func _on_abandon_dialog_confirmed() -> void:
	var err: Error = SaveService.abandon_solo_run()
	_status_label.text = "" if err == OK else "Couldn't abandon the run (%s)." % [error_string(err)]
	_refresh()
