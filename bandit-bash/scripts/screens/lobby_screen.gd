# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     lobby_screen.gd
# Author:
# Created:  October 9, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Control
## Steam lobby screen: host, join, Ready, invite, and start or resume a multiplayer campaign.
##
## [b]Modes:[/b] when the Main Menu loaded the save file's multiplayer campaign
## ([code]SaveService.campaign[/code]) this is a [i]resume[/i] lobby: only that campaign's players
## are admitted, missing ones are listed, and the host's Resume needs every one present and Ready.
## Otherwise it is a [i]new[/i] lobby: anyone may join, and Start locks the admitted members in as
## the campaign's players.[br]
## [b]Joining:[/b] by lobby code, from the friends' games list, or from an accepted invite waiting
## in [code]SteamNetwork.pending_invite_lobby_id[/code]. A lobby advertising another game version
## is left at once; the host's admission check is the real gate, and its refusal reason is shown.
## [br]
## [b]Visibility:[/b] [method _refresh] derives every widget's state from live session state, so
## the screen cannot drift into a half-updated combination. Without Steam the screen stays usable:
## the buttons are disabled and the status says why.

# Text for a request that is in flight, or "" when idle. Non-empty disables Host and Join.
var _pending_text: String = ""
# Why the last request failed, or "" when there is nothing to report. Cleared on the next request.
var _error_text: String = ""

@onready var _title_label: Label = %Title
@onready var _status_label: Label = %Status
@onready var _version_label: Label = %VersionLabel
@onready var _code_row: HBoxContainer = %CodeRow
@onready var _code_field: LineEdit = %CodeField
@onready var _copy_button: Button = %CopyButton
@onready var _host_button: Button = %HostButton
@onready var _join_row: HBoxContainer = %JoinRow
@onready var _join_input: LineEdit = %JoinInput
@onready var _join_button: Button = %JoinButton
@onready var _friends_row: HBoxContainer = %FriendsRow
@onready var _refresh_friends_button: Button = %RefreshFriendsButton
@onready var _friends_list: VBoxContainer = %FriendsList
@onready var _members_list: VBoxContainer = %MembersList
@onready var _ready_toggle: CheckButton = %ReadyToggle
@onready var _invite_button: Button = %InviteButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_host_button.pressed.connect(_on_host_button_pressed)
	_join_button.pressed.connect(_on_join_button_pressed)
	_join_input.text_submitted.connect(_on_join_input_text_submitted)
	_copy_button.pressed.connect(_on_copy_button_pressed)
	_refresh_friends_button.pressed.connect(_rebuild_friends_list)
	_ready_toggle.toggled.connect(_on_ready_toggle_toggled)
	_invite_button.pressed.connect(_on_invite_button_pressed)
	_start_button.pressed.connect(_on_start_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)

	SteamNetwork.lobby_created.connect(_on_steam_network_lobby_created)
	SteamNetwork.lobby_joined.connect(_on_steam_network_lobby_joined)
	SteamNetwork.lobby_members_changed.connect(_refresh)
	SteamNetwork.lobby_state_changed.connect(_refresh)
	SteamNetwork.session_ended.connect(_on_steam_network_session_ended)
	SteamNetwork.join_refused.connect(_on_steam_network_join_refused)
	SteamNetwork.lobby_data_updated.connect(_on_steam_network_lobby_data_updated)

	_version_label.text = "Game version %s" % [SaveFile.get_running_version()]
	_rebuild_friends_list()
	_refresh()

	var invited_lobby: int = SteamNetwork.take_pending_invite()
	if invited_lobby != 0:
		_join(invited_lobby)


func _is_resume_mode() -> bool:
	var campaign: CampaignData = SaveService.campaign
	return campaign != null and campaign.mode == CampaignData.Mode.MULTIPLAYER


# Why this machine can't host right now, or "" when it can.
func _get_host_blocker() -> String:
	if _is_resume_mode():
		var host_id: int = SaveService.campaign.get_host_steam_id()
		# ASSUMPTION: only the Steam account that hosted the campaign may resume it.
		if SteamManager.is_available and Steam.getSteamID() != host_id:
			return "This campaign was hosted from another Steam account."
		return ""
	if SaveService.has_multiplayer_campaign():
		return "This save file already hosts a campaign. Resume or abandon it from the Main Menu."
	return ""


func _join(lobby_id: int) -> void:
	_error_text = ""
	_pending_text = "Joining lobby..."
	SteamNetwork.join_lobby(lobby_id)
	_refresh()


func _on_host_button_pressed() -> void:
	_error_text = ""
	_pending_text = "Creating lobby..."
	var max_players: int = SteamNetwork.DEFAULT_MAX_PLAYERS
	if _is_resume_mode():
		max_players = SaveService.campaign.players.size()
	SteamNetwork.host_lobby(max_players)
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
	_join(code.to_int())


func _on_join_input_text_submitted(_text: String) -> void:
	_on_join_button_pressed()


func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(_code_field.text)


func _on_ready_toggle_toggled(is_ready: bool) -> void:
	SteamNetwork.set_local_ready(is_ready)


func _on_invite_button_pressed() -> void:
	SteamNetwork.invite_friends()


func _on_start_button_pressed() -> void:
	var err: Error = OK
	if _is_resume_mode():
		err = SaveService.resume_multiplayer_run()
	else:
		var steam_ids: PackedInt64Array = []
		for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
			steam_ids.append(member.steam_id)
		err = SaveService.start_new_multiplayer_run(steam_ids)
	if err != OK:
		_error_text = "Couldn't start the campaign (%s)." % [error_string(err)]
		_refresh()
		return
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.LOADING)


func _on_leave_button_pressed() -> void:
	SteamNetwork.leave_lobby()
	_refresh()


func _on_steam_network_lobby_created(success: bool) -> void:
	_pending_text = ""
	if not success:
		_error_text = "Could not create the lobby. See the log for details."
	elif _is_resume_mode():
		SteamNetwork.set_required_steam_ids(SaveService.campaign.get_required_steam_ids())
	_refresh()


func _on_steam_network_lobby_joined(success: bool) -> void:
	_pending_text = ""
	if not success:
		_error_text = "Could not join that lobby. Check the code and try again."
		_refresh()
		return

	# A friendly early check; the host's admission check is the one that counts.
	var lobby_version: String = SteamNetwork.get_lobby_version(SteamNetwork.current_lobby_id)
	if not lobby_version.is_empty() and lobby_version != SaveFile.get_running_version():
		SteamNetwork.leave_lobby()
		_error_text = (
				"That lobby runs game version %s; you have %s."
				% [lobby_version, SaveFile.get_running_version()]
		)
	_refresh()


func _on_steam_network_session_ended() -> void:
	_error_text = "The host closed the lobby."
	_refresh()


func _on_steam_network_join_refused(refusal: int) -> void:
	_pending_text = ""
	_error_text = LobbyAdmission.describe(refusal)
	_refresh()


func _on_steam_network_lobby_data_updated(_lobby_id: int) -> void:
	if SteamNetwork.current_lobby_id == 0:
		_rebuild_friends_list()


func _refresh() -> void:
	var in_lobby: bool = SteamNetwork.current_lobby_id != 0
	var is_host: bool = in_lobby and SteamNetwork.is_authoritative()
	var can_request: bool = SteamManager.is_available and _pending_text.is_empty()
	var host_blocker: String = _get_host_blocker()

	_host_button.visible = not in_lobby
	_host_button.disabled = not can_request or not host_blocker.is_empty()
	_host_button.text = "Host Resume Lobby" if _is_resume_mode() else "Host Lobby"
	_join_row.visible = not in_lobby and not _is_resume_mode()
	_join_button.disabled = not can_request
	_friends_row.visible = not in_lobby and not _is_resume_mode() and SteamManager.is_available
	_friends_list.visible = _friends_row.visible
	_code_row.visible = in_lobby
	_ready_toggle.visible = in_lobby
	_ready_toggle.set_pressed_no_signal(_is_local_member_ready())
	_invite_button.visible = is_host
	_start_button.visible = is_host
	_start_button.text = "Resume Campaign" if _is_resume_mode() else "Start Campaign"
	_start_button.disabled = not _can_start()
	_leave_button.visible = in_lobby
	_back_button.visible = not in_lobby

	_status_label.text = _get_status_text(in_lobby, is_host, host_blocker)

	if in_lobby:
		var owner_name: String = SteamNetwork.get_member_name(SteamNetwork.get_lobby_owner())
		_title_label.text = "%s's Lobby" % [owner_name]
		_code_field.text = str(SteamNetwork.current_lobby_id)
	else:
		_title_label.text = "Resume Campaign" if _is_resume_mode() else "Lobby"
		_code_field.text = ""

	_rebuild_member_list()


func _can_start() -> bool:
	if not SteamNetwork.are_all_members_ready():
		return false
	if not _is_resume_mode():
		return _get_host_blocker().is_empty()
	return _get_missing_steam_ids().is_empty()


func _is_local_member_ready() -> bool:
	for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
		if member.peer_id == SteamNetwork.local_peer_id():
			return member.is_ready
	return false


# Resume mode only: the campaign's players who aren't admitted yet.
func _get_missing_steam_ids() -> PackedInt64Array:
	var missing: PackedInt64Array = []
	if not _is_resume_mode():
		return missing
	var present: PackedInt64Array = []
	for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
		present.append(member.steam_id)
	for steam_id: int in SaveService.campaign.get_required_steam_ids():
		if not present.has(steam_id):
			missing.append(steam_id)
	return missing


func _get_status_text(in_lobby: bool, is_host: bool, host_blocker: String) -> String:
	if not SteamManager.is_available:
		return "Steam is not available. Open Steam, then restart the game."
	if not _error_text.is_empty():
		return _error_text
	if not _pending_text.is_empty():
		return _pending_text
	if not in_lobby:
		if not host_blocker.is_empty():
			return host_blocker
		if _is_resume_mode():
			return "Host a lobby, then invite the campaign's players."
		return "Host a lobby, or join one with a lobby code or from a friend's game."
	if is_host:
		if _is_resume_mode() and not _get_missing_steam_ids().is_empty():
			return "Waiting for every player of the campaign to join."
		if not SteamNetwork.are_all_members_ready():
			return "Waiting for everyone to press Ready."
		return "Everyone is ready."
	return "Joined. Press Ready, then wait for the host."


func _rebuild_member_list() -> void:
	for child: Node in _members_list.get_children():
		child.queue_free()

	var owner_id: int = SteamNetwork.get_lobby_owner()
	for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
		var label: Label = Label.new()
		label.text = SteamNetwork.get_member_name(member.steam_id)
		if member.steam_id == owner_id:
			label.text += " (host)"
		label.text += "  ·  %s" % ["Ready" if member.is_ready else "Not ready"]
		_members_list.add_child(label)

	for steam_id: int in _get_missing_steam_ids():
		var missing_label: Label = Label.new()
		var name_text: String = "Player %d" % [steam_id]
		if SteamManager.is_available:
			name_text = SteamNetwork.get_member_name(steam_id)
		missing_label.text = "%s  ·  missing" % [name_text]
		_members_list.add_child(missing_label)


func _rebuild_friends_list() -> void:
	for child: Node in _friends_list.get_children():
		child.queue_free()

	var lobbies: Array[SteamNetwork.FriendLobby] = SteamNetwork.get_friend_lobbies()
	if lobbies.is_empty():
		var none_label: Label = Label.new()
		none_label.text = "No friends are in a lobby right now."
		_friends_list.add_child(none_label)
		return

	for entry: SteamNetwork.FriendLobby in lobbies:
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		var lobby_version: String = SteamNetwork.get_lobby_version(entry.lobby_id)
		if lobby_version.is_empty():
			SteamNetwork.request_lobby_data(entry.lobby_id)
			label.text = entry.friend_name
		elif lobby_version != SaveFile.get_running_version():
			label.text = "%s  ·  version %s (yours: %s)" % [
				entry.friend_name, lobby_version, SaveFile.get_running_version()
			]
		else:
			label.text = entry.friend_name
		row.add_child(label)

		var join_button: Button = Button.new()
		var version_differs: bool = lobby_version != SaveFile.get_running_version()
		join_button.text = "Join"
		join_button.disabled = not lobby_version.is_empty() and version_differs
		join_button.pressed.connect(_join.bind(entry.lobby_id))
		row.add_child(join_button)
		_friends_list.add_child(row)
