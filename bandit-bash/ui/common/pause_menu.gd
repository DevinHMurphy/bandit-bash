# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pause_menu.gd
# Author:
# Created:  October 14, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name PauseMenu
extends CanvasLayer
## The in-game menu, under the run's seed, by [enum Role]. [b]Solo[/b] pauses the tree: Resume,
## Save & Quit (or Quit to Menu with no run). [b]Co-op[/b] never pauses: the game goes on beneath,
## the screen beneath reads nothing meanwhile, and the hint bar shows the menu's own set
## ([method get_hint_context]). The host: Resume, Options, Save & Quit, which asks first, saves,
## and ends the match for everyone ([code]NetRelay.end_match()[/code]). A client: Resume, Options,
## Leave Match (a drop: everyone waits, and it can rejoin from the lobby) and Forfeit, which asks
## first and sends a [ForfeitCommand] for the local seat: the archive and the move to the main
## menu follow from the host's word, a refusal shows its reason. In battle Board Key shows the
## [BoardKey]; Options and the questions show in the buttons' place too. A Steam invite during a
## solo run asks "Save & Quit and join?" ([signal SceneRouter.invite_confirmation_requested]).[br]
## [b]Focus:[/b] while open something of its own always has focus, so a pad can always move; on
## close the control focused before it opened has focus again.

# ============================================================
# INPUT MAP SETUP (built-in action, overridden in project.godot's [input] to add its pad buttons):
#   "ui_cancel"  -> Escape; pad B [Circle],   (opens the menu; while open steps back one part:
#                   Menu [Options]             a question, the options or the board key go back to
#                                              the buttons, else the menu closes)
#   "ui_up" / "ui_down" / "ui_left" /         (not read here: the GUI moves focus between the
#   "ui_right" / "ui_accept"                   buttons and presses the focused one, by key, d-pad,
#                                              stick or A [Cross])
# Solo reads ui_cancel in _unhandled_input, the tree paused beneath. Co-op reads it in _input while
# open, before the screen's own handlers (this node is last in each screen), and takes every other
# press and mouse motion in _unhandled_input, so the screen beneath acts on none; releases pass,
# so a key held before opening (fast_forward) lets go.
# On the battle screen, Esc is shared with turn input by stage (deliberate reuse of one key):
# BattleController reads ui_cancel in _input, before this _unhandled_input, and takes it while
# there is a stage to step back from (a unit selected, a menu, picker or dialog open, a swap
# pick): there Esc steps back one stage and this menu doesn't open. It opens from idle (nothing
# selected) or the opening swap window, and while turn input is off (playback running, no turn).
# Right-click steps back the same way but never opens this menu.
# ============================================================

## Who the menu is for, which decides its buttons and whether it pauses.
enum Role {
	## No session: pauses the tree.
	SOLO = 0,
	## The host of a co-op session: the game goes on.
	HOST = 1,
	## A co-op client, in a session or reconnecting to its host: the game goes on.
	CLIENT = 2,
}

## The group every pause menu joins, so a [ControlHintBar] finds one open in co-op and shows its
## hints ([method get_hint_context]); the bar names the group itself, so keep the two equal.
const GROUP: StringName = &"pause_menu"

## The hint contexts while open in co-op ([method get_hint_context]), each a key of
## [constant LIVE_ACTIONS]; [ControlHintBar] names what each action does in them.
const HINT_MENU: StringName = &"COOP_MENU"
const HINT_BOARD_KEY: StringName = &"COOP_BOARD_KEY"
const HINT_OPTIONS: StringName = &"COOP_OPTIONS"
const HINT_CONFIRM: StringName = &"COOP_CONFIRM"

## The actions live in each co-op hint context, in the order the hint bar shows them.
const LIVE_ACTIONS: Dictionary[StringName, Array] = {
	HINT_MENU: [&"ui_up", &"ui_down", &"ui_accept", &"ui_cancel"],
	HINT_BOARD_KEY: [&"ui_accept", &"ui_cancel"],
	HINT_OPTIONS: [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel"],
	HINT_CONFIRM: [&"ui_left", &"ui_right", &"ui_accept", &"ui_cancel"],
}

# The title by role: solo pauses; in co-op the game goes on, so it isn't "Paused".
# ASSUMPTION: the co-op title's wording, and the confirms' (pause_menu.tscn); no design doc words
# them.
const _SOLO_TITLE: String = "Paused"
const _COOP_TITLE: String = "Menu"

# ASSUMPTION: the forfeit's status wordings; no design doc words them.
const _FORFEITING_TEXT: String = "Forfeiting..."
const _FORFEIT_REFUSED_TEXT: String = "Couldn't forfeit: %s."

## The board key Board Key opens ([BoardKey]); the battle screen sets it.[br]
## [b]Unset:[/b] the menu has no Board Key button (every screen but the battle's).
@export var board_key_scene: PackedScene = null

# The role the menu last opened as; it holds until the next open.
var _role: Role = Role.SOLO

# The control that had focus when the menu opened, given it back on close; null for none.
var _focus_before: Control = null

# The key built from board_key_scene, in the panel beside the column; null with none.
var _board_key: BoardKey = null

# A forfeit sent and not yet refused; its refusal comes on this session's command_rejected.
var _is_forfeiting: bool = false
var _followed_session: CampaignSession = null

@onready var _root: Control = %Root
@onready var _panel: Control = %Panel
@onready var _column: Control = %Column
@onready var _title_label: Label = %Title
@onready var _board_key_button: Button = %BoardKeyButton
@onready var _status_label: Label = %Status
@onready var _seed_label: Label = %Seed
@onready var _resume_button: Button = %ResumeButton
@onready var _options_button: Button = %OptionsButton
@onready var _save_quit_button: Button = %SaveQuitButton
@onready var _leave_button: Button = %LeaveButton
@onready var _forfeit_button: Button = %ForfeitButton
@onready var _options: OptionsPanel = %Options
@onready var _save_quit_confirm: MenuConfirm = %SaveQuitConfirm
@onready var _forfeit_confirm: MenuConfirm = %ForfeitConfirm
@onready var _invite_dialog: ConfirmationDialog = %InviteDialog


func _ready() -> void:
	add_to_group(GROUP)
	_root.visible = false
	_resume_button.pressed.connect(close)
	_options_button.pressed.connect(open_options)
	_save_quit_button.pressed.connect(_on_save_quit_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_forfeit_button.pressed.connect(_on_forfeit_button_pressed)
	_options.back_pressed.connect(close_options)
	_save_quit_confirm.confirmed.connect(_on_save_quit_confirm_confirmed)
	_save_quit_confirm.cancelled.connect(_on_confirm_cancelled.bind(_save_quit_button))
	_forfeit_confirm.confirmed.connect(_on_forfeit_confirm_confirmed)
	_forfeit_confirm.cancelled.connect(_on_confirm_cancelled.bind(_forfeit_button))
	_build_board_key()
	_invite_dialog.confirmed.connect(_on_invite_dialog_confirmed)
	_invite_dialog.canceled.connect(_on_invite_dialog_canceled)
	SceneRouter.invite_confirmation_requested.connect(
			_on_scene_router_invite_confirmation_requested
	)


func _exit_tree() -> void:
	# A scene change while open must not leave the next screen paused.
	if _root.visible:
		get_tree().paused = false
	_follow_rejections(null)


func _process(_delta: float) -> void:
	keep_focus()


func _input(event: InputEvent) -> void:
	if not _is_coop_open() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	step_back()


func _unhandled_input(event: InputEvent) -> void:
	if _is_coop_open():
		if event.is_pressed() or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if is_board_key_open():
		close_board_key()
	elif _root.visible:
		close()
	else:
		open()


## Shows the menu for this machine's [method role_now].
func open() -> void:
	open_as(role_now())


## Shows the menu as [param role]: its buttons, and in solo the tree paused. Tests and captures
## open a co-op role without a session. The control focused before it gets focus back when it
## closes ([method close]), so a pad user can carry on where they were.
func open_as(role: Role) -> void:
	if not _root.visible:
		var focused: Control = _root.get_viewport().gui_get_focus_owner()
		_focus_before = null if focused != null and _root.is_ancestor_of(focused) else focused
	_role = role
	var is_coop: bool = role != Role.SOLO
	var is_client: bool = role == Role.CLIENT
	_status_label.text = _FORFEITING_TEXT if _is_forfeiting else ""
	_title_label.text = _COOP_TITLE if is_coop else _SOLO_TITLE
	var has_run: bool = SaveService.campaign != null
	_options_button.visible = is_coop
	_save_quit_button.visible = has_run and not is_client
	_leave_button.visible = not _save_quit_button.visible
	_leave_button.text = "Leave Match" if is_client else "Quit to Menu"
	_forfeit_button.visible = is_client
	_forfeit_button.disabled = _is_forfeiting
	var run: CampaignData = SaveService.multiplayer_replica if is_client else SaveService.campaign
	_seed_label.visible = run != null
	if run != null:
		_seed_label.text = "Seed %s" % [RunSeed.format(run.run_seed)]

	_show_part(_column)
	_root.visible = true
	if not is_coop:
		get_tree().paused = true
	_link_focus()
	_focus_first_button.call_deferred()


## Hides the menu and unpauses, giving focus back to the control that had it when it opened.
## Every part closes with it (an unapplied option is dropped), so it opens on its buttons next.
func close() -> void:
	if _options.visible:
		_options.discard()
	_show_part(_column)
	_root.visible = false
	get_tree().paused = false
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null


## Goes back one part, as ui_cancel does in co-op: a question is declined, the options or the
## board key give way to the buttons, else the menu closes.
func step_back() -> void:
	if _save_quit_confirm.visible:
		_save_quit_confirm.cancel()
	elif _forfeit_confirm.visible:
		_forfeit_confirm.cancel()
	elif _options.visible:
		close_options()
	elif is_board_key_open():
		close_board_key()
	elif _root.visible:
		close()


## Whether the menu shows.
func is_open() -> bool:
	return _root.visible


## The role the menu last opened as.
func get_role() -> Role:
	return _role


## While the menu is open and its invite question isn't, gives the part shown focus when nothing
## of the menu's has it: the first button, the board key's Back, the options' first slider or a
## question's cancel. [method Node._process] calls it each frame; tests call it to stand for one.
## Returns whether it moved focus.
func keep_focus() -> bool:
	if not _root.visible or _invite_dialog.visible:
		return false
	var focused: Control = _root.get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		return false
	if _save_quit_confirm.visible:
		_save_quit_confirm.focus_first()
	elif _forfeit_confirm.visible:
		_forfeit_confirm.focus_first()
	elif _options.visible:
		_options.focus_first()
	elif is_board_key_open():
		_board_key.focus_first()
	else:
		_first_button().grab_focus()
	return true


## Shows the board key in the buttons' place, focus on its Back; nothing without a key or while
## the menu is closed.
func open_board_key() -> void:
	if _board_key == null or not _root.visible:
		return
	_show_part(_board_key)
	_board_key.focus_first()


## Shows the buttons again in the board key's place, focus on Board Key.
func close_board_key() -> void:
	if not is_board_key_open():
		return
	_show_part(_column)
	_board_key_button.grab_focus()


## Whether the board key shows.
func is_board_key_open() -> bool:
	return _board_key != null and _board_key.visible and _root.visible


## The board key built from [member board_key_scene]; null with none.
func get_board_key() -> BoardKey:
	return _board_key


## Shows the options in the buttons' place, editing the settings in effect, focus on the first
## slider; nothing while the menu is closed.
func open_options() -> void:
	if not _root.visible:
		return
	_options.reload()
	_show_part(_options)
	_options.focus_first()


## Shows the buttons again in the options' place, an unapplied change dropped, focus on Options.
func close_options() -> void:
	if not _options.visible:
		return
	_options.discard()
	_show_part(_column)
	_options_button.grab_focus()


## Whether the options show.
func is_options_open() -> bool:
	return _options.visible and _root.visible


## The options panel, for tests and captures.
func get_options_panel() -> OptionsPanel:
	return _options


## The host's Save & Quit question, for tests and captures.
func get_save_quit_confirm() -> MenuConfirm:
	return _save_quit_confirm


## The client's Forfeit question, for tests and captures.
func get_forfeit_confirm() -> MenuConfirm:
	return _forfeit_confirm


## The status line's text: a failed save, a forfeit on its way or refused; empty for none.
func get_status_text() -> String:
	return _status_label.text


## The seed line's text, for tests; empty while it is hidden.
func get_seed_text() -> String:
	return _seed_label.text if _seed_label.visible else ""


## The hint context while open in co-op, a key of [constant LIVE_ACTIONS], by the part shown;
## empty while closed or in solo, where the screen's own hints show (PAUSED with the tree paused).
func get_hint_context() -> StringName:
	if not _root.visible or _role == Role.SOLO:
		return &""
	if _save_quit_confirm.visible or _forfeit_confirm.visible:
		return HINT_CONFIRM
	if _options.visible:
		return HINT_OPTIONS
	if is_board_key_open():
		return HINT_BOARD_KEY
	return HINT_MENU


## The actions live in [method get_hint_context], in the order the hint bar shows them; empty for
## none.
func get_live_actions() -> Array[StringName]:
	var live: Array[StringName] = []
	for action: StringName in LIVE_ACTIONS.get(get_hint_context(), []):
		live.append(action)
	return live


# Whether the menu is open over a co-op game, which goes on beneath it.
func _is_coop_open() -> bool:
	return _root.visible and _role != Role.SOLO


# Focuses the first button, deferred from open_as() so the button is laid out first; by then the
# menu may be closed again or its screen gone (change_scene_to_file takes the old scene out of the
# tree at once), and then it does nothing.
func _focus_first_button() -> void:
	if not is_inside_tree() or not _root.visible or not _column.visible:
		return
	_first_button().grab_focus()


# The button focused when the menu opens: in solo Save & Quit when shown, else Resume; in co-op
# Resume, since the game goes on and getting back matters most.
# ASSUMPTION: co-op opens on Resume; no design doc says which button.
func _first_button() -> Button:
	if _role == Role.SOLO and _save_quit_button.visible:
		return _save_quit_button
	return _resume_button


# Links the visible buttons as one column, so up and down stop at its ends and never reach a
# widget under the menu; left and right stay put.
func _link_focus() -> void:
	var column: Array[Button] = []
	for button: Button in [
		_resume_button, _board_key_button, _options_button, _save_quit_button, _leave_button,
		_forfeit_button,
	]:
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


# Builds the key from board_key_scene into the panel, hidden, and shows Board Key for it.
func _build_board_key() -> void:
	if board_key_scene == null:
		return
	_board_key = board_key_scene.instantiate() as BoardKey
	if _board_key == null:
		push_error("PauseMenu: board_key_scene is no BoardKey - %s" % [
			board_key_scene.resource_path,
		])
		return
	_board_key.visible = false
	_panel.add_child(_board_key)
	_board_key.back_pressed.connect(close_board_key)
	_board_key_button.visible = true
	_board_key_button.pressed.connect(open_board_key)


# Shows shown alone in the panel: the buttons' column, the board key, the options or a question.
func _show_part(shown: Control) -> void:
	for part: Control in [_column, _board_key, _options, _save_quit_confirm, _forfeit_confirm]:
		if part != null:
			part.visible = part == shown


# Follows session's rejections for a forfeit's refusal, letting go of the one followed before.
func _follow_rejections(session: CampaignSession) -> void:
	if _followed_session == session:
		return
	if is_instance_valid(_followed_session):
		_followed_session.command_rejected.disconnect(_on_session_command_rejected)
	_followed_session = session
	if session != null:
		session.command_rejected.connect(_on_session_command_rejected)


# Solo saves and leaves at once; the co-op host asks first, as it ends the match for everyone.
func _on_save_quit_button_pressed() -> void:
	if _role == Role.HOST:
		_status_label.text = ""
		_show_part(_save_quit_confirm)
		_save_quit_confirm.focus_first()
		return
	var err: Error = SaveService.save_checkpoint()
	if err != OK:
		_status_label.text = "Couldn't save (%s). The game was not closed." % [error_string(err)]
		return
	close()
	SceneRouter.goto_screen(SceneRouter.Screen.MAIN_MENU)


# The host saves, tells every client the match is over, then leaves; a failed save keeps the
# match going.
func _on_save_quit_confirm_confirmed() -> void:
	_show_part(_column)
	var err: Error = SaveService.save_checkpoint()
	if err != OK:
		_status_label.text = "Couldn't save (%s). The match goes on." % [error_string(err)]
		_save_quit_button.grab_focus()
		return
	NetRelay.end_match()
	close()
	SceneRouter.goto_screen(SceneRouter.Screen.MAIN_MENU)


# Leaving is a drop for a client (the host and teammates wait, and it can rejoin), and the main
# menu leaves the lobby.
func _on_leave_button_pressed() -> void:
	close()
	SceneRouter.goto_screen(SceneRouter.Screen.MAIN_MENU)


func _on_forfeit_button_pressed() -> void:
	_status_label.text = ""
	_show_part(_forfeit_confirm)
	_forfeit_confirm.focus_first()


# Sends the local seat's forfeit; the host's word does the rest (NetRelay.left_run), and a
# refusal comes back on the session's command_rejected.
func _on_forfeit_confirm_confirmed() -> void:
	_show_part(_column)
	var session: CampaignSession = CampaignService.session
	if session == null:
		_status_label.text = _FORFEIT_REFUSED_TEXT % ["no run"]
		_forfeit_button.grab_focus()
		return
	_follow_rejections(session)
	_is_forfeiting = true
	_forfeit_button.disabled = true
	_status_label.text = _FORFEITING_TEXT
	_resume_button.grab_focus()
	CampaignService.submit_command(ForfeitCommand.new(CampaignService.local_seat()))


func _on_confirm_cancelled(opener: Button) -> void:
	_show_part(_column)
	opener.grab_focus()


func _on_session_command_rejected(seat: int, _arrival: int, reason: String) -> void:
	if not _is_forfeiting or seat != CampaignService.local_seat():
		return
	_is_forfeiting = false
	_forfeit_button.disabled = false
	_status_label.text = _FORFEIT_REFUSED_TEXT % [reason]


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


## This machine's role now: a client in a session, or reconnecting to its host, is
## [constant Role.CLIENT]; the host of a session [constant Role.HOST]; else
## [constant Role.SOLO].
static func role_now() -> Role:
	# ASSUMPTION: a client reconnecting to its host (no session meanwhile) is still a client, so
	# the menu never pauses its tree, which would stop SteamNetwork's reconnect clock.
	if SteamNetwork.is_reconnecting():
		return Role.CLIENT
	if not SteamNetwork.has_active_session():
		return Role.SOLO
	return Role.HOST if SteamNetwork.is_authoritative() else Role.CLIENT
