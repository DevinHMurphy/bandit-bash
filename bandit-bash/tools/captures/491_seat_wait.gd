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
## The wait overlay over the map: the host waiting for two dropped seats, then a client that lost
## the host, reconnecting. The NetRelay autoload is told the seats dropped as the host's word would
## tell it (its seat change, called here), and, for the second shot, that its host is gone, with a
## stand-in seat directory; both are undone afterwards, so 500 starts on the map with no wait.[br]
## Needs: the map, as the co-op battle shots leave it (489_coop_battle).

# SeatDirectory.State.DROPPED and CONNECTED, sent as ints.
const DROPPED: int = 1
const CONNECTED: int = 0

# Seconds each seat has waited when the first shot is taken.
const SECOND_SEAT_WAIT: float = 42.0
const THIRD_SEAT_WAIT: float = 7.0

# Any Steam id for the stand-in host seat; Steam is off, so its name is "Player 1".
const STAND_IN_STEAM_ID: int = 76561198000000901


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the wait overlay shots need the map (screen %d)" % [router_screen()])
		return true
	var relay: Node = node(^"NetRelay")
	note("wait overlay shots: seats 1 and 2 dropped, then the host lost, on the NetRelay autoload")
	relay.call(&"_seat_changed", 1, DROPPED, SECOND_SEAT_WAIT)
	relay.call(&"_seat_changed", 2, DROPPED, THIRD_SEAT_WAIT)
	await frames(SETTLE_FRAMES)
	await capture("seat_wait_host")
	relay.call(&"_seat_changed", 1, CONNECTED, SECOND_SEAT_WAIT)
	relay.call(&"_seat_changed", 2, CONNECTED, THIRD_SEAT_WAIT)
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
