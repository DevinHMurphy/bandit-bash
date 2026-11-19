# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seat_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Seat cases for tests/net/run_all.gd ([SeatDirectory]): peers, seats and Steam ids map both
## ways; invalid and taken entries are refused; a dropped seat keeps its seat and Steam id with no
## peer; it reconnects under a new peer by its Steam id, and only then; the state values are
## pinned.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

# Three seats: [seat, Steam id, peer]. The host is peer 1; client peer ids are large and random.
const SEATS: Array = [
	[0, 76561198000000001, 1],
	[1, 76561198000000002, 1384211520],
	[2, 76561198000000003, 207718203],
]
const NEW_PEER: int = 990128764
const STRANGER_STEAM_ID: int = 76561198000000099


func run() -> void:
	_test_both_ways()
	_test_refusals()
	_test_drop()
	_test_reconnect()
	_test_state_values()


func _test_both_ways() -> void:
	var seats: SeatDirectory = _directory()
	var is_mapped: bool = true
	for entry: Array in SEATS:
		var seat: int = entry[0]
		var steam_id: int = entry[1]
		var peer: int = entry[2]
		is_mapped = (
				is_mapped
				and seats.seat_of_peer(peer) == seat
				and seats.peer_of_seat(seat) == peer
				and seats.seat_of_steam_id(steam_id) == seat
				and seats.steam_id_of_seat(seat) == steam_id
				and seats.state_of(seat) == SeatDirectory.State.CONNECTED
		)
	_check("seats: peer, seat and Steam id map both ways", (
			is_mapped
			and seats.seats() == PackedInt32Array([0, 1, 2])
			and seats.dropped_seats().is_empty()
	), str(seats.seats()))
	_check("seats: unknown peers, seats and Steam ids have none", (
			seats.seat_of_peer(NEW_PEER) == SeatDirectory.NO_SEAT
			and seats.peer_of_seat(7) == SeatDirectory.NO_PEER
			and seats.seat_of_steam_id(STRANGER_STEAM_ID) == SeatDirectory.NO_SEAT
			and seats.steam_id_of_seat(7) == SeatDirectory.NO_STEAM_ID
			and seats.state_of(7) == SeatDirectory.NO_STATE
			and not seats.has_seat(7)
	))


func _test_refusals() -> void:
	var seats: SeatDirectory = _directory()
	_check("seats: a taken seat, Steam id or peer is refused", (
			not seats.add_seat(1, STRANGER_STEAM_ID, NEW_PEER)
			and not seats.add_seat(3, 76561198000000002, NEW_PEER)
			and not seats.add_seat(3, STRANGER_STEAM_ID, 1)
			and not seats.has_seat(3)
	))
	_check("seats: a negative seat, Steam id 0 or peer 0 is refused", (
			not seats.add_seat(-1, STRANGER_STEAM_ID, NEW_PEER)
			and not seats.add_seat(3, SeatDirectory.NO_STEAM_ID, NEW_PEER)
			and not seats.add_seat(3, STRANGER_STEAM_ID, SeatDirectory.NO_PEER)
			and seats.seats().size() == SEATS.size()
	))


func _test_drop() -> void:
	var seats: SeatDirectory = _directory()
	var dropped: int = seats.drop_peer(1384211520)
	_check("seats: a dropped seat keeps its seat and Steam id with no peer", (
			dropped == 1
			and seats.has_seat(1)
			and seats.state_of(1) == SeatDirectory.State.DROPPED
			and seats.peer_of_seat(1) == SeatDirectory.NO_PEER
			and seats.seat_of_peer(1384211520) == SeatDirectory.NO_SEAT
			and seats.seat_of_steam_id(76561198000000002) == 1
			and seats.steam_id_of_seat(1) == 76561198000000002
			and seats.seats() == PackedInt32Array([0, 1, 2])
			and seats.dropped_seats() == PackedInt32Array([1])
	), str(seats.dropped_seats()))
	_check("seats: a drop leaves the other seats connected", (
			seats.state_of(0) == SeatDirectory.State.CONNECTED
			and seats.state_of(2) == SeatDirectory.State.CONNECTED
			and seats.seat_of_peer(207718203) == 2
	))
	_check("seats: dropping a peer with no seat, or twice, does nothing", (
			seats.drop_peer(NEW_PEER) == SeatDirectory.NO_SEAT
			and seats.drop_peer(1384211520) == SeatDirectory.NO_SEAT
			and seats.dropped_seats() == PackedInt32Array([1])
	))
	_check("seats: a dropped seat's Steam id can't join as a new seat", (
			not seats.add_seat(3, 76561198000000002, NEW_PEER)
			and not seats.has_seat(3)
	))


func _test_reconnect() -> void:
	var seats: SeatDirectory = _directory()
	seats.drop_peer(1384211520)
	_check("seats: a connected seat or an unknown Steam id can't reconnect", (
			seats.reconnect(76561198000000003, NEW_PEER) == SeatDirectory.NO_SEAT
			and seats.reconnect(STRANGER_STEAM_ID, NEW_PEER) == SeatDirectory.NO_SEAT
	))
	_check("seats: a peer that holds a seat can't take a dropped one", (
			seats.reconnect(76561198000000002, 207718203) == SeatDirectory.NO_SEAT
			and seats.state_of(1) == SeatDirectory.State.DROPPED
	))
	var seat: int = seats.reconnect(76561198000000002, NEW_PEER)
	_check("seats: a dropped seat reconnects by its Steam id under a new peer", (
			seat == 1
			and seats.state_of(1) == SeatDirectory.State.CONNECTED
			and seats.peer_of_seat(1) == NEW_PEER
			and seats.seat_of_peer(NEW_PEER) == 1
			and seats.seat_of_peer(1384211520) == SeatDirectory.NO_SEAT
			and seats.dropped_seats().is_empty()
	))
	_check("seats: a reconnected seat can't reconnect again", (
			seats.reconnect(76561198000000002, 1384211520) == SeatDirectory.NO_SEAT
	))


func _test_state_values() -> void:
	_check("seats: the state values are pinned (sent as ints)", (
			SeatDirectory.State.CONNECTED == 0
			and SeatDirectory.State.DROPPED == 1
			and SeatDirectory.State.size() == 2
	))


func _directory() -> SeatDirectory:
	var seats: SeatDirectory = SeatDirectory.new()
	for entry: Array in SEATS:
		seats.add_seat(entry[0] as int, entry[1] as int, entry[2] as int)
	return seats
