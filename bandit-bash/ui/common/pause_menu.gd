# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pause_menu.gd
# Author:
# Created:  October 14, 2026
# Modified: November 19, 2026
# ==============================================================================

extends CanvasLayer
## In-game pause menu: Resume, Save & Quit, or Leave, under the run's seed.
##
## Save & Quit saves through [code]SaveService.save_checkpoint()[/code] (the mid-battle save too)
## and leaves for the Main Menu only once that succeeds; on failure it says so and stays. With no
## active run it offers Quit to Menu; a multiplayer client gets Leave Match, as clients never save.
## The seed line shows the run's seed by [method RunSeed.format] (on a client, the host's replica)
## for bug reports, and hides with no run. It pauses the tree only in solo play: in a session the
## host keeps simulating for everyone. A Steam invite during a solo run asks "Save & Quit and
## join?" ([signal SceneRouter.invite_confirmation_requested]); declining drops the invite.[br]
## [b]Focus:[/b] while open one of its buttons always has focus, so a pad can always move (up and
## down stay in its column; focus a click took elsewhere returns the next frame). On close the
## control focused before it opened has focus again.

# ============================================================
# INPUT MAP SETUP (built-in action, overridden in project.godot's [input] to add its pad buttons):
#   "ui_cancel"  -> Escape; pad B [Circle],   (opens the menu; closes it again while open)
#                   Menu [Options]
#   "ui_up" / "ui_down" / "ui_accept"         (not read here: the GUI moves focus between the
#                                              buttons and presses the focused one, by key, d-pad,
#                                              stick or A [Cross])
# On the battle screen, Esc is shared with turn input by stage (deliberate reuse of one key):
# BattleController reads ui_cancel in _input, before this _unhandled_input, and takes it while
# there is a stage to step back from (a unit selected, a menu, picker or dialog open, a swap
# pick): there Esc steps back one stage and this menu doesn't open. It opens from idle (nothing
# selected) or the opening swap window, and while turn input is off (playback running, no turn).
# Right-click steps back the same way but never opens this menu.
# Nothing else is read here: the buttons are mouse and focus driven.
# ============================================================

# The control that had focus when the menu opened, given it back on close; null for none.
var _focus_before: Control = null

@onready var _root: Control = %Root
@onready var _status_label: Label = %Status
@onready var _seed_label: Label = %Seed
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


func _process(_delta: float) -> void:
	keep_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _root.visible:
		close()
	else:
		open()


## Shows the menu, pausing the game in solo play. The control focused before it gets focus back
## when it closes ([method close]), so a pad user can carry on where they were.
func open() -> void:
	if not _root.visible:
		var focused: Control = _root.get_viewport().gui_get_focus_owner()
		_focus_before = null if focused != null and _root.is_ancestor_of(focused) else focused
	_status_label.text = ""
	var is_client: bool = SteamNetwork.has_active_session() and not SteamNetwork.is_authoritative()
	var has_run: bool = SaveService.campaign != null
	_save_quit_button.visible = has_run and not is_client
	_leave_button.visible = not _save_quit_button.visible
	_leave_button.text = "Leave Match" if is_client else "Quit to Menu"
	var run: CampaignData = SaveService.multiplayer_replica if is_client else SaveService.campaign
	_seed_label.visible = run != null
	if run != null:
		_seed_label.text = "Seed %s" % [RunSeed.format(run.run_seed)]

	_root.visible = true
	if not SteamNetwork.has_active_session():
		get_tree().paused = true
	_link_focus()
	_focus_first_button.call_deferred()


## Hides the menu and unpauses, giving focus back to the control that had it when it opened.
func close() -> void:
	_root.visible = false
	get_tree().paused = false
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null


## While the menu is open and its invite question isn't, gives its first button focus when none of
## its buttons has it. [method Node._process] calls it each frame; tests call it to stand for one.
## Returns whether it moved focus.
func keep_focus() -> bool:
	if not _root.visible or _invite_dialog.visible:
		return false
	var focused: Control = _root.get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		return false
	_first_button().grab_focus()
	return true


# Focuses the first button, deferred from open() so the button is laid out first; by then the
# menu may be closed again or its screen gone (change_scene_to_file takes the old scene out of the
# tree at once), and then it does nothing.
func _focus_first_button() -> void:
	if not is_inside_tree() or not _root.visible:
		return
	_first_button().grab_focus()


# The button focused when the menu opens: Save & Quit when shown, else Resume.
func _first_button() -> Button:
	return _save_quit_button if _save_quit_button.visible else _resume_button


# Links the visible buttons as one column, so up and down stop at its ends and never reach a
# widget under the menu; left and right stay put.
func _link_focus() -> void:
	var column: Array[Button] = []
	for button: Button in [_resume_button, _save_quit_button, _leave_button]:
		if button.visible:
			column.append(button)
	for i: int in column.size():
		var button: Button = column[i]
		var above: Button = column[maxi(i - 1, 0)]
		var below: Button = column[mini(i + 1, column.size() - 1)]
		button.focus_neighbor_top = button.get_path_to(above)
		button.focus_neighbor_bottom = button.get_path_to(below)
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom


## The seed line's text, for tests; empty while it is hidden.
func get_seed_text() -> String:
	return _seed_label.text if _seed_label.visible else ""


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
