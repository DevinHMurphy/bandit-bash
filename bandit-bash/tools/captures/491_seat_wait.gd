# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     491_seat_wait.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The wait overlay over the map: the host waiting for two dropped seats, then for one past the
## wait, with Remove, then a client that lost the host, reconnecting. The NetRelay autoload is told
## the seats dropped as the host's word would tell it (its seat change, called here), and, for the
## last shot, that its host is gone, with a stand-in seat directory; all are undone afterwards, so
## 500 starts on the map with no wait.[br]
## Needs: the map, as the co-op map shots leave it (490_coop_map).

const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")

# SeatDirectory.State.DROPPED and CONNECTED, sent as ints.
const DROPPED: int = 1
const CONNECTED: int = 0

# Seconds each seat has waited when the first shot is taken.
const SECOND_SEAT_WAIT: float = 42.0
const THIRD_SEAT_WAIT: float = 7.0

# Seconds the second seat has waited in the Remove shot: just past the wait, so Remove shows.
const REMOVABLE_WAIT: float = NetRelayScript.REMOVE_WAIT + 5.0

# Any Steam id for the stand-in host seat; Steam is off, so its name is "Player 1".
const STAND_IN_STEAM_ID: int = 76561198000000901


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the wait overlay shots need the map (screen %d)" % [router_screen()])
		return true
	var relay: Node = node(^"NetRelay")
	note("wait overlay shots: seats 1 and 2 dropped, then the host lost, on the NetRelay autoload")
	_change_seats(relay, DROPPED, SECOND_SEAT_WAIT)
	await frames(SETTLE_FRAMES)
	await capture("seat_wait_host")
	_change_seats(relay, DROPPED, REMOVABLE_WAIT)
	await frames(SETTLE_FRAMES)
	await capture("seat_wait_remove")
	_change_seats(relay, CONNECTED, REMOVABLE_WAIT)
	var stand_in: SeatDirectory = SeatDirectory.new()
	stand_in.add_seat(0, STAND_IN_STEAM_ID, 1)
	relay.set(&"seats", stand_in)
	relay.call(&"_on_multiplayer_server_disconnected")
	await frames(SETTLE_FRAMES)
	await capture("seat_wait_reconnecting")
	relay.call(&"_end_run")
	relay.set(&"seats", null)
	await frames(SETTLE_FRAMES)
	return true


# Seats 1 (waited second_wait s) and 2 to state, as the host's seat change tells it. The relay asks
# its API whether it is the host, which logs an error with no peer at all, as after SteamNetwork
# leaves a lobby: the calls hold Godot's solo peer meanwhile (no session, so nothing is sent), then
# put back the last.
func _change_seats(relay: Node, state: int, second_wait: float) -> void:
	var api: MultiplayerAPI = relay.multiplayer
	var kept: MultiplayerPeer = api.multiplayer_peer
	if kept == null:
		api.multiplayer_peer = OfflineMultiplayerPeer.new()
	relay.call(&"_seat_changed", 1, state, second_wait)
	relay.call(&"_seat_changed", 2, state, THIRD_SEAT_WAIT)
	if kept == null:
		api.multiplayer_peer = null
