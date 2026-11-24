# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     scene_router.gd
# Author:
# Created:  October 9, 2026
# Modified: November 24, 2026
# ==============================================================================

extends Node
## Screen switching for the whole game. Autoload [code]SceneRouter[/code]: callers ask for a
## [enum Screen], never a path. [code]change_scene_to_file()[/code] frees the old scene, so the
## screens are kept here, and the RPC lives here too: an autoload has the same NodePath on every
## peer from boot, so a route can't race a scene's loading.[br]
## [b]Moves for everyone[/b] are the host's alone ([method goto_screen_for_everyone]), held while
## the run is paused; one to the screen already showing changes nothing. A client never routes:
## a client screen out of step with its run asks the host for the run and opens again once the
## run reaches it. [b]Invites and lost hosts:[/b] an accepted Steam invite opens a save file if
## none is open and goes to the lobby, which joins it; during a solo run it first asks to Save &
## Quit ([signal invite_confirmation_requested]). A client whose host leaves mid-match returns to
## the Main Menu once it can't get back.

## This machine just entered [param screen].
signal screen_changed(screen: Screen)

## An invite arrived during a solo run. The pause menu asks the player to Save & Quit and join
## ([method accept_pending_invite]) or to ignore it.
signal invite_confirmation_requested()

# Screen flow. Most edges are authored as NavButton exports inside each screen scene, not here.
#   Precondition: boot.tscn opens START once; no other screen is entered before that.
#   START       -> SAVE_SELECT, quit
#   SAVE_SELECT -> MAIN_MENU (only after a save file opens; save_select_screen.gd), START
#   MAIN_MENU   -> LOADING (Continue Run), NEW_RUN, LOBBY (multiplayer), OPTIONS, SAVE_SELECT
#   NEW_RUN     -> LOADING (after the run's first save; new_run_screen.gd), MAIN_MENU. The
#                  faction and commander pickers are skipped: the MVP has one of each.
#   OPTIONS     -> back to whichever screen opened it (only MAIN_MENU links to it)
#   LOBBY       -> LOADING (everyone, host's Start or Resume), MAIN_MENU
#   LOADING     -> the run's screen by its stage (RunScreen.of), on the host's or solo's Continue:
#                  STARTING_HEIRLOOM, CAMPAIGN_MAP, GAMEPLAY, TREASURE, CAMP, ARMORY, GUILDHALL,
#                  EVENT, NODE_PLACEHOLDER or COMBAT_RESULTS; GAMEPLAY with no run
#   STARTING_HEIRLOOM -> CAMPAIGN_MAP (everyone, once every seat's heirloom is taken: the first
#                  node comes after; a seat that has taken one waits on the screen meanwhile)
#   CAMPAIGN_MAP     -> GAMEPLAY (a combat node chosen), TREASURE, CAMP, ARMORY, GUILDHALL; an
#                       Unknown node by what it became (RunScreen.go rolls it first): GAMEPLAY,
#                       TREASURE, ARMORY, GUILDHALL or EVENT, NODE_PLACEHOLDER with no event to draw
#   TREASURE, CAMP   -> CAMPAIGN_MAP (Leave, once the chest or the choice is settled)
#   ARMORY, GUILDHALL -> CAMPAIGN_MAP (Leave, at any time: buying is optional)
#   NODE_PLACEHOLDER -> CAMPAIGN_MAP (Continue leaves the node)
#   EVENT            -> CAMPAIGN_MAP (Leave, once chosen), GAMEPLAY (Fight: a surprise combat)
#   GAMEPLAY    -> COMBAT_RESULTS (a solo battle won, after its victory sequence; a co-op
#                  battle's end, everyone, each machine its own seat's), RESULTS (the run ended,
#                  or no run; everyone); a solo run elsewhere is sent to its stage's screen at once
#   COMBAT_RESULTS -> CAMPAIGN_MAP (Continue leaves the node), RESULTS (End run, after the Boss)
#   RESULTS     -> LOADING (everyone, next round), MAIN_MENU
#   STARTING_HEIRLOOM, CAMPAIGN_MAP, TREASURE, CAMP, ARMORY, GUILDHALL, EVENT, NODE_PLACEHOLDER,
#                  COMBAT_RESULTS, GAMEPLAY -> MAIN_MENU (pause menu)
#   any screen  -> LOBBY on an accepted invite (accept_pending_invite); during a solo run only
#                  after the player chose Save & Quit
#   LOADING and every in-run screen -> MAIN_MENU on a client whose host left and that couldn't
#                  get back (session_ended); LOBBY or the screen it held -> the run's screen on a
#                  client that rejoined a run in progress (CampaignService, on its next sync)
# "Everyone" edges go through goto_screen_for_everyone(): the host's moves everyone, once the run
# isn't paused; a client's moves nobody (it asks the host for the run and waits for its route);
# solo falls back to local.
# Entering START, SAVE_SELECT or MAIN_MENU ends any lobby session, so Leave Match also leaves the
# lobby. Entering SAVE_SELECT also closes the open save file (save_select_screen.gd).
# There is no way to MAIN_MENU without an open save file: every path in passes SAVE_SELECT.
# RESULTS is the run's end (won or lost) and the multiplayer round placeholder; it offers both
# exits. A combat's own results are COMBAT_RESULTS.
## Every screen in the game.
##
## APPEND ONLY with explicit values: an exported [enum Screen] serializes as a plain int in .tscn
## files, so inserting mid-enum silently renumbers every saved value after it.
enum Screen {
	START = 0,
	LOBBY = 1,
	LOADING = 2,
	GAMEPLAY = 3,
	RESULTS = 4,
	MAIN_MENU = 5,
	OPTIONS = 6,
	SAVE_SELECT = 7,
	NEW_RUN = 8,
	CAMPAIGN_MAP = 9,
	COMBAT_RESULTS = 10,
	NODE_PLACEHOLDER = 11,
	STARTING_HEIRLOOM = 12,
	EVENT = 13,
	TREASURE = 14,
	CAMP = 15,
	ARMORY = 16,
	GUILDHALL = 17,
}

## [enum Screen] -> scene path. Every [enum Screen] value needs an entry.
const SCREEN_PATHS: Dictionary[Screen, String] = {
	Screen.START: "res://ui/screens/start_screen.tscn",
	Screen.LOBBY: "res://ui/screens/lobby_screen.tscn",
	Screen.LOADING: "res://ui/screens/loading_gate.tscn",
	Screen.GAMEPLAY: "res://ui/battle/gameplay.tscn",
	Screen.RESULTS: "res://ui/screens/results_screen.tscn",
	Screen.MAIN_MENU: "res://ui/screens/main_menu.tscn",
	Screen.OPTIONS: "res://ui/screens/options_screen.tscn",
	Screen.SAVE_SELECT: "res://ui/screens/save_select_screen.tscn",
	Screen.NEW_RUN: "res://ui/screens/new_run_screen.tscn",
	Screen.CAMPAIGN_MAP: "res://ui/campaign/campaign_map_screen.tscn",
	Screen.COMBAT_RESULTS: "res://ui/campaign/combat_results_screen.tscn",
	Screen.NODE_PLACEHOLDER: "res://ui/campaign/node_placeholder_screen.tscn",
	Screen.STARTING_HEIRLOOM: "res://ui/campaign/starting_heirloom_screen.tscn",
	Screen.EVENT: "res://ui/campaign/events/event_screen.tscn",
	Screen.TREASURE: "res://ui/campaign/treasure_screen.tscn",
	Screen.CAMP: "res://ui/campaign/camp_screen.tscn",
	Screen.ARMORY: "res://ui/campaign/armory_screen.tscn",
	Screen.GUILDHALL: "res://ui/campaign/guildhall_screen.tscn",
}

# The screens a run is played on, where an invite asks to Save & Quit first and a lost host sends
# a client back to the menu.
const _RUN_SCREENS: Array[Screen] = [
	Screen.GAMEPLAY,
	Screen.CAMPAIGN_MAP,
	Screen.COMBAT_RESULTS,
	Screen.NODE_PLACEHOLDER,
	Screen.STARTING_HEIRLOOM,
	Screen.EVENT,
	Screen.TREASURE,
	Screen.CAMP,
	Screen.ARMORY,
	Screen.GUILDHALL,
]

## Screen this machine is showing. [constant Screen.START] until the first [method goto_screen].
var current_screen: Screen = Screen.START
## Screen shown before [member current_screen], used by [method go_back].
var previous_screen: Screen = Screen.START

# Host: a move for everyone asked while the run was paused, sent once it isn't (_process()); the
# latest one asked wins. Dropped with the session or a screen change here.
var _has_held_route: bool = false
var _held_route: Screen = Screen.START

# Client: the screen showing is out of step with the run, which asked the host for state. It
# opens again once the run reaches it (_process()), or the host's route moves it on.
var _is_waiting_for_run: bool = false


func _ready() -> void:
	set_process(false)
	SteamNetwork.invite_received.connect(_on_steam_network_invite_received)
	SteamNetwork.session_ended.connect(_on_steam_network_session_ended)


# Runs only while a route is held or a client screen waits for its run.
func _process(_delta: float) -> void:
	if _has_held_route:
		_send_held_route()
	if _is_waiting_for_run:
		_open_once_reached()
	set_process(_has_held_route or _is_waiting_for_run)


## Switches to [param screen] on this machine only, the screen already showing included (it
## loads again: a rejoined client's rebuilt mirror needs that).
##
## Entering [constant Screen.START], [constant Screen.SAVE_SELECT] or [constant Screen.MAIN_MENU]
## also leaves any lobby.
func goto_screen(screen: Screen) -> void:
	if not SCREEN_PATHS.has(screen):
		push_error(
				"SceneRouter: no scene registered for screen %s." % [Screen.find_key(screen)]
		)
		return

	var path: String = SCREEN_PATHS[screen]
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error(
				"SceneRouter: change_scene_to_file(%s) failed - %s" % [path, error_string(err)]
		)
		return

	previous_screen = current_screen
	current_screen = screen
	_has_held_route = false
	_is_waiting_for_run = false
	NetLog.info(NetLog.Category.SCENE, "Entered screen %s." % [Screen.find_key(screen)])

	# ASSUMPTION: START and MAIN_MENU are outside any match, so entering them ends the lobby.
	# SAVE_SELECT ending it is confirmed by the save system plan.
	if screen == Screen.START or screen == Screen.SAVE_SELECT or screen == Screen.MAIN_MENU:
		SteamNetwork.leave_lobby()

	screen_changed.emit(screen)


## Switches every connected peer, this machine included, to [param screen]; a peer already on it
## stays as it is. Only the host's call moves anyone, and while the run is paused it waits for the
## run to resume. A client's moves nobody: its run says [param screen] while it shows another, so
## it asks the host for the run and waits (see the class doc). With no active session it is a
## plain local switch, so solo play uses the same call.
func goto_screen_for_everyone(screen: Screen) -> void:
	if not SteamNetwork.has_active_session():
		goto_screen(screen)
		return
	if not multiplayer.is_server():
		_wait_for_run(screen)
		return
	if NetRelay.is_paused():
		_hold_route(screen)
		return
	_route_everyone(screen)


## Returns to [member previous_screen]. Used by screens reachable from more than one place.
func go_back() -> void:
	goto_screen(previous_screen)


## Acts on the pending invite: opens a save file if none is open (plan, row 27), then goes to the
## lobby, which joins the invited lobby. Does nothing without a pending invite.
##
## If no save file can be opened, the invite is dropped and logged.
func accept_pending_invite() -> void:
	if SteamNetwork.pending_invite_lobby_id == 0:
		return
	if not SaveService.has_open_save_file():
		var save_number: int = SaveService.get_invite_save_number()
		var err: Error = ERR_UNAVAILABLE
		if save_number != SaveService.NO_SAVE_FILE:
			err = SaveService.open_save_file(save_number)
		if err != OK:
			SteamNetwork.take_pending_invite()
			NetLog.error(
					NetLog.Category.SCENE,
					"Dropping the invite: no save file could be opened (%s)." % [error_string(err)]
			)
			return
	goto_screen(Screen.LOBBY)


func _on_steam_network_invite_received(_lobby_id: int) -> void:
	# ASSUMPTION: an invite arriving while already in a lobby is ignored rather than leaving the
	# current session; the player can leave and accept again.
	if SteamNetwork.has_active_session():
		SteamNetwork.take_pending_invite()
		NetLog.warn(NetLog.Category.SCENE, "Ignoring an invite while already in a lobby.")
		return
	if _RUN_SCREENS.has(current_screen) and SaveService.campaign != null:
		invite_confirmation_requested.emit()
		return
	accept_pending_invite()


# A client whose host left mid-match has nowhere to be but the menu. The lobby screen handles its
# own case, so LOBBY isn't listed.
func _on_steam_network_session_ended() -> void:
	if (
			current_screen == Screen.LOADING or current_screen == Screen.RESULTS
			or _RUN_SCREENS.has(current_screen)
	):
		goto_screen(Screen.MAIN_MENU)


# Host: every peer to screen, the host by the same RPC.
func _route_everyone(screen: Screen) -> void:
	NetLog.info(NetLog.Category.SCENE, "Routing everyone to %s." % [Screen.find_key(screen)])
	_networked_goto_screen.rpc(screen)


# Host: screen waits for the run to resume; a later ask replaces it.
func _hold_route(screen: Screen) -> void:
	NetLog.info(
			NetLog.Category.SCENE,
			"Holding the route to %s until the run resumes." % [Screen.find_key(screen)]
	)
	_has_held_route = true
	_held_route = screen
	set_process(true)


# Host: the held route goes once the run isn't paused; one outlived by its session is dropped.
func _send_held_route() -> void:
	if not SteamNetwork.has_active_session() or not multiplayer.is_server():
		_has_held_route = false
		return
	if NetRelay.is_paused():
		return
	_has_held_route = false
	_route_everyone(_held_route)


# Client: the run says screen, not the one showing. Routing from here would loop whenever this
# mirror and the host's run disagree, so it moves nobody: it asks for the run (CampaignService)
# and waits for the host's route, or for the run to reach the screen showing.
func _wait_for_run(screen: Screen) -> void:
	var asked: bool = CampaignService.request_sync()
	NetLog.info(NetLog.Category.SCENE, "Waiting for the host's route: the run says %s; %s." % [
		Screen.find_key(screen),
		"asked the host for the run" if asked else "no run to ask for yet",
	])
	_is_waiting_for_run = true
	set_process(true)


# Client: once the run reaches the screen showing, that screen opens again, built for the run;
# it bailed out when it opened out of step. Any other stage waits for the host's route.
func _open_once_reached() -> void:
	var session: CampaignSession = CampaignService.session
	if session == null or session.run == null or RunScreen.of(session) != current_screen:
		return
	NetLog.info(
			NetLog.Category.SCENE,
			"The run reached %s; opening it again." % [Screen.find_key(current_screen)]
	)
	goto_screen(current_screen)


# Every peer, the host by call_local, so it takes the same dispatch path as the clients instead of
# jumping a full round trip ahead of them. A route to the screen already showing changes nothing,
# so a choice under way there is never lost to a reload.
@rpc("authority", "reliable", "call_local")
func _networked_goto_screen(screen: Screen) -> void:
	if screen == current_screen:
		NetLog.info(
				NetLog.Category.SCENE,
				"Already on %s; the route changes nothing." % [Screen.find_key(screen)]
		)
		return
	goto_screen(screen)
