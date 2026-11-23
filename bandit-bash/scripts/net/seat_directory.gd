# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seat_directory.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SeatDirectory
extends RefCounted
## Which connection is which seat: the campaign's seats by Steam id, each seat's Godot peer and
## [enum State], looked up both ways.
##
## Pure: no nodes, no Steam, no networking. It is built from the admitted members ([method build]);
## the Steam id comes from the connection, never from a message, so the seat a command acts for is
## taken from its sender's peer here, never from the command.[br]
## [b]A dropped seat keeps its entry[/b] with no peer, so the same Steam id reconnects to the same
## seat under its new peer id ([method reconnect]) instead of joining as a new player. A removed
## seat keeps its entry too, so its Steam id stays known, but can never reconnect.
##
## @tutorial(Net transport plan): docs/plans/2026-11-19-net-transport.md

## A seat's connection. Sent over the network as an int: [b]append only[/b], with explicit values.
enum State {
	## The seat's machine is connected under [method peer_of_seat].
	CONNECTED = 0,
	## The seat's machine lost its connection; the seat waits for its Steam id to reconnect.
	DROPPED = 1,
	## The host removed the seat after its wait ([method remove_seat]); it never reconnects.
	REMOVED = 2,
}

## Returned for a peer or Steam id with no seat.
const NO_SEAT: int = -1

## [method peer_of_seat] of a dropped, removed or unknown seat. Godot never gives a connection id 0.
const NO_PEER: int = 0

## [method steam_id_of_seat] of an unknown seat. Steam never gives an account id 0.
const NO_STEAM_ID: int = 0

## [method state_of] an unknown seat.
const NO_STATE: int = -1

var _steam_ids: Dictionary[int, int] = {}
var _peers: Dictionary[int, int] = {}
var _seats_by_steam_id: Dictionary[int, int] = {}
var _seats_by_peer: Dictionary[int, int] = {}
var _removed: Dictionary[int, bool] = {}


## Adds [param seat], held by Steam account [param steam_id] connected as Godot peer
## [param peer_id], in [constant State.CONNECTED]. Returns false, with an error, when any of the
## three is invalid or already in the directory.
func add_seat(seat: int, steam_id: int, peer_id: int) -> bool:
	if seat < 0 or steam_id == NO_STEAM_ID or peer_id <= NO_PEER:
		push_error("SeatDirectory: invalid seat - %d, Steam %d, peer %d" % [
			seat, steam_id, peer_id,
		])
		return false
	if _seats_by_peer.has(peer_id) or not _add_dropped(seat, steam_id):
		push_error("SeatDirectory: seat, Steam id or peer already taken - %d, %d, %d" % [
			seat, steam_id, peer_id,
		])
		return false
	_peers[seat] = peer_id
	_seats_by_peer[peer_id] = seat
	return true


## Marks the seat of [param peer_id] [constant State.DROPPED] and forgets the peer; the seat and
## its Steam id stay. Returns that seat, or [constant NO_SEAT] when the peer holds none.
func drop_peer(peer_id: int) -> int:
	var seat: int = seat_of_peer(peer_id)
	if seat == NO_SEAT:
		return NO_SEAT
	_seats_by_peer.erase(peer_id)
	_peers[seat] = NO_PEER
	return seat


## Gives the dropped seat of [param steam_id] the new connection [param peer_id], making it
## [constant State.CONNECTED]. Returns that seat, or [constant NO_SEAT] when the Steam id has no
## seat, its seat isn't dropped (connected or removed), or the peer already holds a seat.
func reconnect(steam_id: int, peer_id: int) -> int:
	var seat: int = seat_of_steam_id(steam_id)
	if seat == NO_SEAT or state_of(seat) != State.DROPPED:
		return NO_SEAT
	if peer_id <= NO_PEER or _seats_by_peer.has(peer_id):
		return NO_SEAT
	_peers[seat] = peer_id
	_seats_by_peer[peer_id] = seat
	return seat


## Marks the dropped [param seat] [constant State.REMOVED], for good. Returns false, changing
## nothing, when it isn't dropped: connected, removed already or unknown.
func remove_seat(seat: int) -> bool:
	if state_of(seat) != State.DROPPED:
		return false
	_removed[seat] = true
	return true


## Whether [param seat] is in the directory, in any [enum State].
func has_seat(seat: int) -> bool:
	return _steam_ids.has(seat)


## The seat Godot peer [param peer_id] holds, or [constant NO_SEAT].
func seat_of_peer(peer_id: int) -> int:
	return _seats_by_peer.get(peer_id, NO_SEAT)


## The Godot peer [param seat] is connected as; [constant NO_PEER] when it is dropped, removed or
## unknown.
func peer_of_seat(seat: int) -> int:
	return _peers.get(seat, NO_PEER)


## The seat Steam account [param steam_id] holds, in any [enum State], or [constant NO_SEAT].
func seat_of_steam_id(steam_id: int) -> int:
	return _seats_by_steam_id.get(steam_id, NO_SEAT)


## The Steam account holding [param seat], or [constant NO_STEAM_ID].
func steam_id_of_seat(seat: int) -> int:
	return _steam_ids.get(seat, NO_STEAM_ID)


## The [enum State] of [param seat], or [constant NO_STATE] when it isn't in the directory.
func state_of(seat: int) -> int:
	if not has_seat(seat):
		return NO_STATE
	if _removed.has(seat):
		return State.REMOVED
	return State.CONNECTED if peer_of_seat(seat) != NO_PEER else State.DROPPED


## Every seat, in any [enum State], in ascending order.
func seats() -> PackedInt32Array:
	var all: PackedInt32Array = PackedInt32Array(_steam_ids.keys())
	all.sort()
	return all


## The dropped seats, in ascending order; empty when none waits to reconnect. Removed seats aren't
## dropped.
func dropped_seats() -> PackedInt32Array:
	var dropped: PackedInt32Array = []
	for seat: int in seats():
		if state_of(seat) == State.DROPPED:
			dropped.append(seat)
	return dropped


# Adds seat for steam_id with no peer; false when either is invalid or taken.
func _add_dropped(seat: int, steam_id: int) -> bool:
	if (
			seat < 0 or steam_id == NO_STEAM_ID
			or _steam_ids.has(seat) or _seats_by_steam_id.has(steam_id)
	):
		return false
	_steam_ids[seat] = steam_id
	_seats_by_steam_id[steam_id] = seat
	_peers[seat] = NO_PEER
	return true


## A directory of every seat in [param steam_ids_by_seat] (the campaign's players), each connected
## under the peer [param peers_by_steam_id] gives its Steam id (the admitted members), else
## [constant State.DROPPED]. An invalid or repeated entry is left out, with an error.
static func build(
		steam_ids_by_seat: Dictionary[int, int], peers_by_steam_id: Dictionary[int, int]
) -> SeatDirectory:
	var made: SeatDirectory = SeatDirectory.new()
	var ordered: PackedInt32Array = PackedInt32Array(steam_ids_by_seat.keys())
	ordered.sort()
	for seat: int in ordered:
		var steam_id: int = steam_ids_by_seat[seat]
		var peer: int = peers_by_steam_id.get(steam_id, NO_PEER)
		var added: bool = (
				made.add_seat(seat, steam_id, peer) if peer > NO_PEER
				else made._add_dropped(seat, steam_id)
		)
		if not added:
			push_error("SeatDirectory: left out seat %d (Steam %d, peer %d)" % [
				seat, steam_id, peer,
			])
	return made
