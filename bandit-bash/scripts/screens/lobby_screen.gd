# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     lobby_screen.gd
# Author:
# Created:  October 9, 2026
# Modified: October 9, 2026
# ==============================================================================

extends Control
## Steam lobby screen: host, join by code, live member list, host-only Start, Leave.
##
## [b]Lobby code:[/b] the host's code is [member SteamNetwork.current_lobby_id], shown in a
## read-only field with a Copy button as soon as Steam confirms the lobby. A joiner types it into
## the join field.[br]
## [b]Visibility:[/b] [method _refresh] derives every widget's state from live session state, so
## the screen cannot drift into a half-updated combination.[br]
## [b]Start:[/b] host only. It moves every peer to loading through
## [method SceneRouter.goto_screen_for_everyone]; a client never sees the button.[br]
## Without Steam the screen stays usable: the buttons are disabled and the status says why.

# Text for a request that is in flight, or "" when idle. Non-empty disables Host and Join.
var _pending_text: String = ""
# Why the last request failed, or "" when there is nothing to report. Cleared on the next request.
var _error_text: String = ""

@onready var _title_label: Label = %Title
@onready var _status_label: Label = %Status
@onready var _code_row: HBoxContainer = %CodeRow
@onready var _code_field: LineEdit = %CodeField
@onready var _copy_button: Button = %CopyButton
@onready var _host_button: Button = %HostButton
@onready var _join_row: HBoxContainer = %JoinRow
@onready var _join_input: LineEdit = %JoinInput
@onready var _join_button: Button = %JoinButton
@onready var _members_list: VBoxContainer = %MembersList
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_host_button.pressed.connect(_on_host_button_pressed)
	_join_button.pressed.connect(_on_join_button_pressed)
	_join_input.text_submitted.connect(_on_join_input_text_submitted)
	_copy_button.pressed.connect(_on_copy_button_pressed)
	_start_button.pressed.connect(_on_start_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)

	SteamNetwork.lobby_created.connect(_on_steam_network_lobby_created)
	SteamNetwork.lobby_joined.connect(_on_steam_network_lobby_joined)
	SteamNetwork.lobby_members_changed.connect(_refresh)
	SteamNetwork.session_ended.connect(_on_steam_network_session_ended)

	_refresh()


func _on_host_button_pressed() -> void:
	_error_text = ""
	_pending_text = "Creating lobby..."
	SteamNetwork.host_lobby()
	_refresh()


func _on_join_button_pressed() -> void:
	# Enter in the join field reaches this too, so honor the button's disabled state.
	if _join_button.disabled:
		return

	var code: String = _join_input.text.strip_edges()
	if not code.is_valid_int() or code.to_int() <= 0:
		_error_text = "Enter a valid lobby code first."
		_refresh()
		return

	_error_text = ""
	_pending_text = "Joining lobby..."
	SteamNetwork.join_lobby(code.to_int())
	_refresh()


func _on_join_input_text_submitted(_text: String) -> void:
	_on_join_button_pressed()


func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(_code_field.text)


func _on_start_button_pressed() -> void:
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.LOADING)


func _on_leave_button_pressed() -> void:
	SteamNetwork.leave_lobby()
	_refresh()


func _on_steam_network_lobby_created(success: bool) -> void:
	_pending_text = ""
	if not success:
		_error_text = "Could not create the lobby. See the log for details."
	_refresh()


func _on_steam_network_lobby_joined(success: bool) -> void:
	_pending_text = ""
	if not success:
		_error_text = "Could not join that lobby. Check the code and try again."
	_refresh()


func _on_steam_network_session_ended() -> void:
	_error_text = "The host closed the lobby."
	_refresh()


func _refresh() -> void:
	var in_lobby: bool = SteamNetwork.current_lobby_id != 0
	var is_host: bool = in_lobby and SteamNetwork.is_authoritative()
	var can_request: bool = SteamManager.is_available and _pending_text.is_empty()

	_host_button.visible = not in_lobby
	_host_button.disabled = not can_request
	_join_row.visible = not in_lobby
	_join_button.disabled = not can_request
	_code_row.visible = in_lobby
	_start_button.visible = is_host
	_leave_button.visible = in_lobby
	_back_button.visible = not in_lobby

	_status_label.text = _get_status_text(in_lobby, is_host)

	if in_lobby:
		var owner_name: String = SteamNetwork.get_member_name(SteamNetwork.get_lobby_owner())
		_title_label.text = "%s's Lobby" % [owner_name]
		_code_field.text = str(SteamNetwork.current_lobby_id)
	else:
		_title_label.text = "Lobby"
		_code_field.text = ""

	_rebuild_member_list()


func _get_status_text(in_lobby: bool, is_host: bool) -> String:
	if not SteamManager.is_available:
		return "Steam is not available. Open Steam, then restart the game."
	if not _error_text.is_empty():
		return _error_text
	if not _pending_text.is_empty():
		return _pending_text
	if not in_lobby:
		return "Host a lobby, or join one with a lobby code."
	if is_host:
		return "Hosting. Share the lobby code with your friends."
	return "Joined. Waiting for the host to start."


func _rebuild_member_list() -> void:
	for child: Node in _members_list.get_children():
		child.queue_free()

	var owner_id: int = SteamNetwork.get_lobby_owner()
	for steam_id: int in SteamNetwork.get_lobby_members():
		var label: Label = Label.new()
		label.text = SteamNetwork.get_member_name(steam_id)
		if steam_id == owner_id:
			label.text += " (host)"
		_members_list.add_child(label)
