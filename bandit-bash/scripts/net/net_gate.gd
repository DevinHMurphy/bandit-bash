# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     net_gate.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name NetGate
extends RefCounted
## The one definition of "is there a session" and "may this machine decide", for any
## [MultiplayerAPI].
##
## [code]SteamNetwork[/code]'s session helpers call these with the scene tree's API. Code that
## runs under its own [SceneMultiplayer] branch, as each peer of a two-peer test does in one
## process, passes its own node's [code]multiplayer[/code] instead, so the rule stays one rule
## (kit P1) while every branch answers for itself.
##
## @tutorial(Net transport plan): docs/plans/2026-11-19-net-transport.md


## True when [param api] has a real peer: neither none nor the default
## [OfflineMultiplayerPeer]. False for a null [param api].
static func has_session(api: MultiplayerAPI) -> bool:
	if api == null:
		return false
	var peer: MultiplayerPeer = api.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


## True on the host of [param api]'s session, and always true without a session (solo play).
## The gate for every decision about shared state.
static func is_authoritative(api: MultiplayerAPI) -> bool:
	return not has_session(api) or api.is_server()
