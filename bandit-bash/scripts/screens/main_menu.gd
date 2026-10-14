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
## Main Menu for the open save file: the solo run and the hosted multiplayer campaign.
##
## Only reachable from Save Select, so a save file is always open; if one somehow isn't, the screen
## sends the player back to Save Select.[br]
## [b]Solo:[/b] Continue Run and Abandon Run show while the save file has a solo run; New Run shows
## while it doesn't.[br]
## [b]Multiplayer:[/b] Multiplayer opens the lobby to host a new campaign or join a friend's.
## Resume Campaign and Abandon Multiplayer Campaign show while the save file hosts a campaign;
## Resume loads it so the lobby gathers its players.[br]
## Both abandons ask for confirmation, then archive the run as lost. Options and Back stay
## NavButtons in the scene.

# Which slot the open abandon confirmation is for.
var _pending_abandon: CampaignData.Mode = CampaignData.Mode.SOLO

@onready var _header_label: Label = %Header
@onready var _status_label: Label = %Status
@onready var _continue_button: Button = %ContinueButton
@onready var _new_run_button: Button = %NewRunButton
@onready var _abandon_button: Button = %AbandonButton
@onready var _multiplayer_button: Button = %MultiplayerButton
@onready var _resume_multi_button: Button = %ResumeMultiButton
@onready var _abandon_multi_button: Button = %AbandonMultiButton
@onready var _abandon_dialog: ConfirmationDialog = %AbandonDialog


func _ready() -> void:
	if not SaveService.has_open_save_file():
		SceneRouter.goto_screen.call_deferred(SceneRouter.Screen.SAVE_SELECT)
		return

	_continue_button.pressed.connect(_on_continue_button_pressed)
	_new_run_button.pressed.connect(_on_new_run_button_pressed)
	_abandon_button.pressed.connect(_on_abandon_button_pressed)
	_multiplayer_button.pressed.connect(_on_multiplayer_button_pressed)
	_resume_multi_button.pressed.connect(_on_resume_multi_button_pressed)
	_abandon_multi_button.pressed.connect(_on_abandon_multi_button_pressed)
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

	var hosts_campaign: bool = SaveService.has_multiplayer_campaign()
	_resume_multi_button.visible = hosts_campaign
	_abandon_multi_button.visible = hosts_campaign

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
	_pending_abandon = CampaignData.Mode.SOLO
	_abandon_dialog.dialog_text = "Abandon this run? It counts as a loss and can't be undone."
	_abandon_dialog.popup_centered()


# The lobby treats a loaded multiplayer campaign as "resume", so clear any left from before.
func _on_multiplayer_button_pressed() -> void:
	SaveService.clear_campaign()
	SceneRouter.goto_screen(SceneRouter.Screen.LOBBY)


func _on_resume_multi_button_pressed() -> void:
	var err: Error = SaveService.load_multiplayer_campaign()
	if err != OK:
		_status_label.text = (
				"Couldn't load the campaign (%s). You can abandon it." % [error_string(err)]
		)
		return
	SceneRouter.goto_screen(SceneRouter.Screen.LOBBY)


func _on_abandon_multi_button_pressed() -> void:
	_pending_abandon = CampaignData.Mode.MULTIPLAYER
	_abandon_dialog.dialog_text = (
			"Abandon this multiplayer campaign? It counts as a loss for you, and nobody can resume"
			+ " it. This can't be undone."
	)
	_abandon_dialog.popup_centered()


func _on_abandon_dialog_confirmed() -> void:
	var err: Error = SaveService.abandon_run(_pending_abandon)
	var what: String = "Run" if _pending_abandon == CampaignData.Mode.SOLO else "Campaign"
	if err != OK:
		_status_label.text = "Couldn't abandon it (%s)." % [error_string(err)]
	elif SaveService.last_archive_error != OK:
		_status_label.text = "%s abandoned. It couldn't be saved to the archive." % [what]
	else:
		_status_label.text = "%s abandoned and saved to the archive." % [what]
	_refresh()
