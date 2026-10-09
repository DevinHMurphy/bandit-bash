# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     steam_manager.gd
# Author:
# Created:  October 9, 2026
# Modified: October 9, 2026
# ==============================================================================

extends Node
## Steam API lifecycle: initializes GodotSteam once and exposes whether it succeeded.
##
## Registered as autoload [code]SteamManager[/code], after [code]NetLog[/code]. It does not
## initialize itself in [method Node._ready]; [code]boot.gd[/code] calls [method initialize] once
## before the first screen loads, so every screen reads a settled [member is_available].[br]
## Every other Steam call in the project checks [member is_available] first.[br]
## A failed init (Steam client not running) is a logged warning, never a crash: solo play must
## keep working without Steam.

## Valve's public "Spacewar" test App ID.
##
## Replace with the real Steamworks App ID before a release build. Editor runs and runs not
## launched through Steam also need a gitignored [code]steam_appid.txt[/code] with the same id at
## the project root.
const DEV_APP_ID: int = 480

## True only once [method initialize] succeeded. Read this before any [code]Steam.*[/code] call.
var is_available: bool = false

## Status code from [code]Steam.steamInitEx()[/code]. -1 until [method initialize] runs.
var init_status: int = -1

## Human-readable init result from GodotSteam. Empty until [method initialize] runs.
var init_message: String = ""


## Initializes Steam against [param app_id] and returns true on success.
##
## Passing [code]true[/code] for [code]embed_callbacks[/code] makes GodotSteam pump Steam callbacks
## itself, so nothing in the project polls [code]Steam.run_callbacks()[/code]. Safe to call again
## after a success; it returns true without re-initializing.
func initialize(app_id: int = DEV_APP_ID) -> bool:
	if is_available:
		return true

	NetLog.info(NetLog.Category.STEAM, "Initializing Steam (app id %d)..." % [app_id])
	var result: Dictionary = Steam.steamInitEx(app_id, true)
	init_status = result.get("status", -1)
	init_message = result.get("verbal", "")

	is_available = init_status == Steam.STEAM_API_INIT_RESULT_OK
	if is_available:
		NetLog.info(NetLog.Category.STEAM, "Steam initialized (app id %d)." % [app_id])
	else:
		NetLog.warn(
				NetLog.Category.STEAM,
				"Steam did not initialize (status %d): %s" % [init_status, init_message]
		)
	return is_available
