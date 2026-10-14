# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     scene_router.gd
# Author:
# Created:  October 9, 2026
# Modified: October 14, 2026
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
## freshly loaded scene can.

## This machine just entered [param screen].
signal screen_changed(screen: Screen)

# Screen flow. Most edges are authored as NavButton exports inside each screen scene, not here.
#   Precondition: boot.tscn opens START once; no other screen is entered before that.
#   START       -> SAVE_SELECT, quit
#   SAVE_SELECT -> MAIN_MENU (only after a save file opens; save_select_screen.gd), START
#   MAIN_MENU   -> LOADING (Continue Run), NEW_RUN, LOBBY (multiplayer), OPTIONS, SAVE_SELECT
#   NEW_RUN     -> LOADING (after the run's first save; new_run_screen.gd), MAIN_MENU
#   OPTIONS     -> back to whichever screen opened it (only MAIN_MENU links to it)
#   LOBBY       -> LOADING (everyone), MAIN_MENU
#   LOADING     -> GAMEPLAY (everyone)
#   GAMEPLAY    -> RESULTS (everyone)
#   RESULTS     -> LOADING (everyone, next round), MAIN_MENU
# "Everyone" edges go through goto_screen_for_everyone(): host only, solo falls back to local.
# Entering START, SAVE_SELECT or MAIN_MENU ends any lobby session, so Leave Match also leaves the
# lobby. Entering SAVE_SELECT also closes the open save file (save_select_screen.gd).
# There is no way to MAIN_MENU without an open save file: every path in passes SAVE_SELECT.
# There is no separate match-over screen: RESULTS offers both exits.
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
}

## [enum Screen] -> scene path. Every [enum Screen] value needs an entry.
const SCREEN_PATHS: Dictionary[Screen, String] = {
	Screen.START: "res://scenes/screens/start_screen.tscn",
	Screen.LOBBY: "res://scenes/screens/lobby_screen.tscn",
	Screen.LOADING: "res://scenes/screens/loading_gate.tscn",
	Screen.GAMEPLAY: "res://scenes/gameplay/gameplay.tscn",
	Screen.RESULTS: "res://scenes/screens/results_screen.tscn",
	Screen.MAIN_MENU: "res://scenes/screens/main_menu.tscn",
	Screen.OPTIONS: "res://scenes/screens/options_screen.tscn",
	Screen.SAVE_SELECT: "res://scenes/screens/save_select_screen.tscn",
	Screen.NEW_RUN: "res://scenes/screens/new_run_screen.tscn",
}

## Screen this machine is showing. [constant Screen.START] until the first [method goto_screen].
var current_screen: Screen = Screen.START
## Screen shown before [member current_screen], used by [method go_back].
var previous_screen: Screen = Screen.START


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


# call_local so the host takes the same dispatch path as the clients instead of jumping a full
# round trip ahead of them.
@rpc("authority", "reliable", "call_local")
func _networked_goto_screen(screen: Screen) -> void:
	goto_screen(screen)
