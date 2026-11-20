# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     scene_router.gd
# Author:
# Created:  October 9, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Node
## Screen switching for the whole game.
##
## Registered as autoload [code]SceneRouter[/code]. Callers ask for a [enum Screen], never a raw
## path, so a scene can move without touching its callers.[br]
## [b]Why an autoload:[/b] [code]change_scene_to_file()[/code] frees the whole old scene, so the
## current and previous screen have to live outside it.[br]
## [b]Why an autoload hosts the RPC:[/b] autoloads sit at the same NodePath on every peer from
## boot, so an RPC routed through one can't race scene-load timing the way a node inside a
## freshly loaded scene can.[br]
## [b]Invites and lost hosts:[/b] an accepted Steam invite opens a save file if none is open
## ([code]SaveService.get_invite_save_number()[/code]) and goes to the lobby, which joins it.
## During a solo run it first asks, through [signal invite_confirmation_requested], whether to
## Save & Quit. A client whose host leaves mid-match returns to the Main Menu.

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
#   LOADING     -> the solo run's screen by its stage (RunScreen.of): STARTING_HEIRLOOM,
#                  CAMPAIGN_MAP, GAMEPLAY, NODE_PLACEHOLDER, EVENT or COMBAT_RESULTS; GAMEPLAY
#                  (everyone) outside a solo run
#   STARTING_HEIRLOOM -> CAMPAIGN_MAP (once the heirloom is taken: the first node comes after)
#   CAMPAIGN_MAP     -> GAMEPLAY (a combat node chosen), NODE_PLACEHOLDER (any other node)
#   NODE_PLACEHOLDER -> CAMPAIGN_MAP (Continue leaves the node)
#   EVENT            -> CAMPAIGN_MAP (Leave, once chosen), GAMEPLAY (Fight: a surprise combat)
#   GAMEPLAY    -> COMBAT_RESULTS (a solo battle won), RESULTS (lost, or outside a solo run;
#                  everyone); a solo run elsewhere is sent to its stage's screen at once
#   COMBAT_RESULTS -> CAMPAIGN_MAP (Continue leaves the node), RESULTS (End run, after the Boss)
#   RESULTS     -> LOADING (everyone, next round), MAIN_MENU
#   STARTING_HEIRLOOM, CAMPAIGN_MAP, NODE_PLACEHOLDER, EVENT, COMBAT_RESULTS, GAMEPLAY
#                  -> MAIN_MENU (pause menu)
#   any screen  -> LOBBY on an accepted invite (accept_pending_invite); during a solo run only
#                  after the player chose Save & Quit
#   LOADING and every in-run screen -> MAIN_MENU on a client whose host left (session_ended)
# "Everyone" edges go through goto_screen_for_everyone(): host only, solo falls back to local.
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
]

## Screen this machine is showing. [constant Screen.START] until the first [method goto_screen].
var current_screen: Screen = Screen.START
## Screen shown before [member current_screen], used by [method go_back].
var previous_screen: Screen = Screen.START


func _ready() -> void:
	SteamNetwork.invite_received.connect(_on_steam_network_invite_received)
	SteamNetwork.session_ended.connect(_on_steam_network_session_ended)


## Switches to [param screen] on this machine only.
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
	NetLog.info(NetLog.Category.SCENE, "Entered screen %s." % [Screen.find_key(screen)])

	# ASSUMPTION: START and MAIN_MENU are outside any match, so entering them ends the lobby.
	# SAVE_SELECT ending it is confirmed by the save system plan.
	if screen == Screen.START or screen == Screen.SAVE_SELECT or screen == Screen.MAIN_MENU:
		SteamNetwork.leave_lobby()

	screen_changed.emit(screen)


## Switches every connected peer, this machine included, to [param screen].
##
## Host only in effect: a client's call is refused with a warning. With no active session it is a
## plain local switch, so solo play uses the same call.
func goto_screen_for_everyone(screen: Screen) -> void:
	if not SteamNetwork.has_active_session():
		goto_screen(screen)
		return
	if not multiplayer.is_server():
		push_warning(
				"SceneRouter: only the host can move everyone to %s." % [Screen.find_key(screen)]
		)
		return

	_networked_goto_screen.rpc(screen)


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


# call_local so the host takes the same dispatch path as the clients instead of jumping a full
# round trip ahead of them.
@rpc("authority", "reliable", "call_local")
func _networked_goto_screen(screen: Screen) -> void:
	goto_screen(screen)
