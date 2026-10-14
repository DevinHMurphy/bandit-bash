# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     lobby_admission.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name LobbyAdmission
extends RefCounted
## The host's rules for letting a joining machine into a lobby.
##
## [code]SteamNetwork[/code] asks [method decide] when a client's admission request arrives. The
## rules live here, without Steam or networking, so the headless tests can check them.[br]
## The joining Steam id must come from the Steam connection itself
## ([code]SteamNetwork.get_peer_steam_id()[/code]), never from the client's message: a client can
## lie about who it is, but not about which Steam account its connection belongs to.
##
## @tutorial(Save system design): docs/design/save-system.md

## Why the host refused a joining machine. Sent over the network as an int: [b]append only[/b],
## with explicit values, or old and new builds would read each other's reasons wrong.
enum Refusal {
	## The joiner runs a different game version than the host.
	VERSION_MISMATCH = 0,
	## The host is resuming a campaign this Steam account isn't part of.
	NOT_IN_CAMPAIGN = 1,
	## This Steam account is already in the lobby.
	ALREADY_JOINED = 2,
}

## Returned by [method decide] when the joiner may enter.
const ADMIT: int = -1

## Longest version string accepted from a client, so a hostile message can't carry a huge string
## into logs or comparisons. Real versions are like "0.1.0".
const MAX_VERSION_LENGTH: int = 32


## Decides whether a joining machine may enter. Checks run in the order of [enum Refusal].
##
## [param host_version]: the host's game version. [param joiner_version]: the version the joiner
## reported. [param joiner_steam_id]: from the Steam connection, not the joiner's message.
## [param required_steam_ids]: the campaign's players when resuming; empty admits anyone.
## [param member_steam_ids]: Steam ids already in the lobby.
## Returns [constant ADMIT] or a [enum Refusal] value.
static func decide(
		host_version: String,
		joiner_version: String,
		joiner_steam_id: int,
		required_steam_ids: PackedInt64Array,
		member_steam_ids: PackedInt64Array
) -> int:
	if joiner_version.length() > MAX_VERSION_LENGTH or joiner_version != host_version:
		return Refusal.VERSION_MISMATCH
	if not required_steam_ids.is_empty() and not required_steam_ids.has(joiner_steam_id):
		return Refusal.NOT_IN_CAMPAIGN
	if member_steam_ids.has(joiner_steam_id):
		return Refusal.ALREADY_JOINED
	return ADMIT


## Player-facing text for a refusal received from the host. Unknown values (a newer host) get a
## generic message.
static func describe(refusal: int) -> String:
	match refusal:
		Refusal.VERSION_MISMATCH:
			return "The host runs a different version of the game."
		Refusal.NOT_IN_CAMPAIGN:
			return "This campaign belongs to other players."
		Refusal.ALREADY_JOINED:
			return "You're already in this lobby."
	return "The host refused the join."
