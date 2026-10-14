# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pause_menu.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends CanvasLayer
## In-game pause menu: Resume, Save & Quit, or Leave.
##
## Save & Quit saves through [code]SaveService.save_checkpoint()[/code], which is also the battle
## save mid-battle, and only leaves for the Main Menu once the save succeeded; on failure it says
## so and stays. With nothing to save (no active run) it offers Quit to Menu instead. A
## multiplayer client gets Leave Match: clients never save a campaign.[br]
## Pauses the scene tree only in solo play. In a multiplayer session the host keeps simulating for
## everyone, so the menu opens without pausing.[br]
## Also asks "Save & Quit and join?" when a Steam invite arrives during a solo run
## ([signal SceneRouter.invite_confirmation_requested]); declining drops the invite.

# ============================================================
# INPUT MAP SETUP (no [input] section in project.godot; built-in action):
#   "ui_cancel"  -> Escape key, gamepad B   (opens the menu; closes it again while open)
# Nothing else is read here: the buttons are mouse/focus driven.
# ============================================================

@onready var _root: Control = %Root
@onready var _status_label: Label = %Status
@onready var _resume_button: Button = %ResumeButton
@onready var _save_quit_button: Button = %SaveQuitButton
@onready var _leave_button: Button = %LeaveButton
@onready var _invite_dialog: ConfirmationDialog = %InviteDialog


func _ready() -> void:
	_root.visible = false
	_resume_button.pressed.connect(close)
	_save_quit_button.pressed.connect(_on_save_quit_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_invite_dialog.confirmed.connect(_on_invite_dialog_confirmed)
	_invite_dialog.canceled.connect(_on_invite_dialog_canceled)
	SceneRouter.invite_confirmation_requested.connect(
			_on_scene_router_invite_confirmation_requested
	)


func _exit_tree() -> void:
	# A scene change while open must not leave the next screen paused.
	if _root.visible:
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _root.visible:
		close()
	else:
		open()


## Shows the menu, pausing the game in solo play.
func open() -> void:
	_status_label.text = ""
	var is_client: bool = SteamNetwork.has_active_session() and not SteamNetwork.is_authoritative()
	var has_run: bool = SaveService.campaign != null
	_save_quit_button.visible = has_run and not is_client
	_leave_button.visible = not _save_quit_button.visible
	_leave_button.text = "Leave Match" if is_client else "Quit to Menu"

	_root.visible = true
	if not SteamNetwork.has_active_session():
		get_tree().paused = true
	var first_button: Button = _save_quit_button if _save_quit_button.visible else _resume_button
	first_button.grab_focus.call_deferred()


## Hides the menu and unpauses.
func close() -> void:
	_root.visible = false
	get_tree().paused = false


func _on_save_quit_button_pressed() -> void:
	var err: Error = SaveService.save_checkpoint()
	if err != OK:
		_status_label.text = "Couldn't save (%s). The game was not closed." % [error_string(err)]
		return
	close()
	SceneRouter.goto_screen(SceneRouter.Screen.MAIN_MENU)


func _on_leave_button_pressed() -> void:
	close()
	SceneRouter.goto_screen(SceneRouter.Screen.MAIN_MENU)


func _on_scene_router_invite_confirmation_requested() -> void:
	open()
	_invite_dialog.popup_centered()


func _on_invite_dialog_confirmed() -> void:
	var err: Error = SaveService.save_checkpoint()
	if err != OK:
		SteamNetwork.take_pending_invite()
		_status_label.text = "Couldn't save (%s), so the invite was declined." % [error_string(err)]
		return
	close()
	SceneRouter.accept_pending_invite()


func _on_invite_dialog_canceled() -> void:
	SteamNetwork.take_pending_invite()
