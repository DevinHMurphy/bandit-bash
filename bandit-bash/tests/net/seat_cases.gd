# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seat_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Seat cases for tests/net/run_all.gd ([SeatDirectory]): peers, seats and Steam ids map both
## ways; invalid and taken entries are refused; a dropped seat keeps its seat and Steam id with no
## peer; it reconnects under a new peer by its Steam id, and only then; only a dropped seat is
## removed, for good; a directory is built from the players and members, the absent dropped; the
## host's mid-run admission lets a dropped seat back and nobody else; the state values are pinned.

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
	_test_remove()
	_test_build()
	_test_admission()
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


func _test_remove() -> void:
	var seats: SeatDirectory = _directory()
	var connected_refused: bool = not seats.remove_seat(1)
	seats.drop_peer(1384211520)
	var removed: bool = seats.remove_seat(1)
	_check("seats: only a dropped seat is removed, and keeps its Steam id", (
			connected_refused
			and removed
			and seats.state_of(1) == SeatDirectory.State.REMOVED
			and seats.has_seat(1)
			and seats.steam_id_of_seat(1) == 76561198000000002
			and seats.seat_of_steam_id(76561198000000002) == 1
			and seats.peer_of_seat(1) == SeatDirectory.NO_PEER
			and seats.dropped_seats().is_empty()
	), str(seats.state_of(1)))
	_check("seats: a removed seat can't reconnect, be removed again or be added anew", (
			seats.reconnect(76561198000000002, NEW_PEER) == SeatDirectory.NO_SEAT
			and not seats.remove_seat(1)
			and not seats.remove_seat(7)
			and not seats.add_seat(3, 76561198000000002, NEW_PEER)
			and seats.state_of(1) == SeatDirectory.State.REMOVED
	))


func _test_build() -> void:
	var steam_ids: Dictionary[int, int] = {}
	var peers: Dictionary[int, int] = {}
	for entry: Array in SEATS:
		steam_ids[entry[0] as int] = entry[1] as int
		if entry[0] != 2:
			peers[entry[1] as int] = entry[2] as int
	peers[STRANGER_STEAM_ID] = NEW_PEER
	var seats: SeatDirectory = SeatDirectory.build(steam_ids, peers)
	_check("seats: build seats every player, connected by its member's peer, else dropped", (
			seats.seats() == PackedInt32Array([0, 1, 2])
			and seats.peer_of_seat(0) == 1
			and seats.peer_of_seat(1) == 1384211520
			and seats.dropped_seats() == PackedInt32Array([2])
			and seats.steam_id_of_seat(2) == 76561198000000003
			and seats.seat_of_peer(NEW_PEER) == SeatDirectory.NO_SEAT
			and seats.reconnect(76561198000000003, NEW_PEER) == 2
	), str(seats.dropped_seats()))
	var repeated: Dictionary[int, int] = {0: 76561198000000001, 1: 76561198000000001}
	_check("seats: build leaves out a repeated Steam id", (
			SeatDirectory.build(repeated, {}).seats() == PackedInt32Array([0])
	))


# The host's admission mid-run: its required ids are the seats not removed, its members the
# connected ones (NetRelay's _admit_campaign() and SteamNetwork's member list).
func _test_admission() -> void:
	var seats: SeatDirectory = _directory()
	seats.drop_peer(1384211520)
	seats.drop_peer(207718203)
	seats.remove_seat(2)
	var required: PackedInt64Array = []
	var members: PackedInt64Array = []
	for seat: int in seats.seats():
		if seats.state_of(seat) != SeatDirectory.State.REMOVED:
			required.append(seats.steam_id_of_seat(seat))
		if seats.state_of(seat) == SeatDirectory.State.CONNECTED:
			members.append(seats.steam_id_of_seat(seat))
	var decided: Dictionary[int, int] = {}
	for steam_id: int in [
		76561198000000001, 76561198000000002, 76561198000000003, STRANGER_STEAM_ID,
	]:
		decided[steam_id] = LobbyAdmission.decide(
				"0.1.0", "0.1.0", 7, 7, steam_id, required, members
		)
	_check("seats: mid-run, a dropped seat's account is admitted (a crashed client's rejoin)", (
			decided[76561198000000002] == LobbyAdmission.ADMIT
	))
	_check("seats: mid-run, a stranger and a removed seat are refused; a connected one too", (
			decided[STRANGER_STEAM_ID] == LobbyAdmission.Refusal.NOT_IN_CAMPAIGN
			and decided[76561198000000003] == LobbyAdmission.Refusal.NOT_IN_CAMPAIGN
			and decided[76561198000000001] == LobbyAdmission.Refusal.ALREADY_JOINED
	), str(decided))


func _test_state_values() -> void:
	_check("seats: the state values are pinned (sent as ints)", (
			SeatDirectory.State.CONNECTED == 0
			and SeatDirectory.State.DROPPED == 1
			and SeatDirectory.State.REMOVED == 2
			and SeatDirectory.State.size() == 3
	))


func _directory() -> SeatDirectory:
	var seats: SeatDirectory = SeatDirectory.new()
	for entry: Array in SEATS:
		seats.add_seat(entry[0] as int, entry[1] as int, entry[2] as int)
	return seats
