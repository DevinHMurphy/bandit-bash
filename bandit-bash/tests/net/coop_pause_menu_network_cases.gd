# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_pause_menu_network_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/forfeit_network_cases.gd"
## What the co-op pause menu's buttons do on the network, in the forfeit cases' harness for
## tests/net/run_all.gd, at 2, 3 and 4 seats: the host's Save & Quit saves and every client hears
## the match end, on the map and mid-battle (a client can't end it); Leave Match is a drop that
## pauses everyone until the seat rejoins; a forfeiter, once let go, hears no more run traffic and
## the host cuts it off after the let-go pause, or needs none when it left first; SaveService
## sends campaign data only to members that play a seat, so not to a let-go forfeiter; a forfeit
## while another seat is dropped is refused "paused" on the forfeiter's mirror and nobody leaves.
## The move to the main menu that follows each is a lobby client's (SteamNetwork), checked live.
## Needs a test user folder.

const SteamNetworkScript = preload("res://scripts/autoload/steam_network.gd")


func run() -> void:
	if not _has_test_user_dir():
		_skip("co-op pause menu network: every case", "needs a test user folder (see run_all.gd)")
		return
	for seat_count: int in [2, 3, 4]:
		_test_save_and_quit(seat_count, false)
		_test_leave_and_rejoin(seat_count)
		_test_let_go(seat_count)
	_test_save_and_quit(3, true)
	_test_left_first()
	_test_forfeit_while_paused()


# The host saves, then ends the match: every client hears it once, the host doesn't, and the save
# keeps the run to resume; a client's own call is refused.
func _test_save_and_quit(seat_count: int, in_battle: bool) -> void:
	var tag: String = "pause menu network %d seats, Save & Quit%s:" % [
		seat_count, " in battle" if in_battle else "",
	]
	var rig: Rig = _start(seat_count, in_battle)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	var heard: Dictionary[int, int] = {}
	for index: int in rig.harness.size():
		heard[index] = 0
		rig.relay(index).match_ended.connect(func() -> void: heard[index] += 1)
	var saved: Error = SaveService.save_checkpoint()
	var client_sent: bool = rig.relay(1).end_match()
	var host_sent: bool = rig.relay(HOST).end_match()
	rig.harness.step_until_idle()
	var every_client: bool = true
	for index: int in rig.clients():
		every_client = every_client and heard[index] == 1
	_check("%s the host saves and ends the match; each client hears it once" % [tag], (
			saved == OK and host_sent and not client_sent
			and every_client and heard[HOST] == 0
			and SaveService.has_multiplayer_campaign()
	), "saved %s; host %s, client %s; heard %s" % [
		error_string(saved), host_sent, client_sent, heard,
	])
	_stop(rig)


# A client's Leave Match drops its connection: the run pauses for everyone, waiting on that seat,
# until it rejoins under a new peer; then nobody waits.
func _test_leave_and_rejoin(seat_count: int) -> void:
	var tag: String = "pause menu network %d seats, Leave Match:" % [seat_count]
	var rig: Rig = _start(seat_count, false)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	var leaver: int = seat_count - 1
	rig.harness.drop(leaver)
	rig.harness.step_until_idle()
	var waiting: PackedInt32Array = PackedInt32Array([leaver])
	var everyone_waits: bool = rig.relay(HOST).waiting_seats() == waiting
	for index: int in rig.clients():
		if index != leaver:
			everyone_waits = everyone_waits and rig.relay(index).waiting_seats() == waiting
	_check("%s leaving is a drop: everyone waits for the seat" % [tag], (
			everyone_waits
			and rig.relay(HOST).seats.state_of(leaver) == SeatDirectory.State.DROPPED
	), "host waits for %s" % [rig.relay(HOST).waiting_seats()])
	var is_back: bool = rig.harness.reconnect(leaver)
	rig.relay(HOST).seat_members(_players(seat_count), _peers(rig, seat_count))
	rig.harness.step_until_idle()
	var nobody_waits: bool = not rig.relay(HOST).is_paused()
	for index: int in rig.clients():
		nobody_waits = nobody_waits and not rig.relay(index).is_paused()
	_check("%s the seat rejoins and nobody waits any more" % [tag], (
			is_back and nobody_waits
			and rig.relay(HOST).seats.state_of(leaver) == SeatDirectory.State.CONNECTED
	), "back %s; host waits for %s" % [is_back, rig.relay(HOST).waiting_seats()])
	_stop(rig)


# The last client forfeits on the map and ignores its record: the run's next batch doesn't reach
# it, SaveService no longer counts it, and the host cuts it off after the let-go pause.
func _test_let_go(seat_count: int) -> void:
	var tag: String = "pause menu network %d seats, let go:" % [seat_count]
	var rig: Rig = _start(seat_count, false)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	var leaver: int = seat_count - 1
	var leaver_peer: int = rig.harness.peer_id(leaver)
	var before: Array[int] = _save_peers(rig, seat_count)
	rig.mirror(leaver).submit_campaign(ForfeitCommand.new(leaver))
	rig.harness.step_until_idle()
	var host_api: SceneMultiplayer = rig.harness.api(HOST)
	var kept_at_first: bool = host_api.get_peers().has(leaver_peer)
	rig.clear_events()
	var node: int = _standard_node(rig.session)
	var left: PackedInt32Array = _seats_but(seat_count, leaver)
	if left.size() == 1:
		_campaign(rig, HOST_SEAT, ChooseNodeCommand.new(HOST_SEAT, node))
	else:
		_campaign(rig, HOST_SEAT, RouteVoteCommand.for_session(rig.session, HOST_SEAT, node))
	var after: Array[int] = _save_peers(rig, seat_count)
	var others_heard: bool = true
	for index: int in rig.clients():
		if index != leaver:
			others_heard = others_heard and rig.events[index].has(BATCH)
	_check("%s the leaver hears no batch after it, and SaveService skips it" % [tag], (
			kept_at_first
			and rig.events[leaver].is_empty() and others_heard
			and before.has(leaver_peer) and not after.has(leaver_peer)
			and after.size() == seat_count - 2
	), "kept %s; leaver heard %s; save peers %s then %s" % [
		kept_at_first, rig.events[leaver], before, after,
	])
	rig.relay(HOST)._process(NetRelayScript.LET_GO_WAIT)
	# A kick isn't traffic, so the idle network needs one step to take it.
	rig.harness.step()
	rig.harness.step_until_idle()
	_check("%s the host cuts the leaver off after the pause; the run doesn't pause" % [tag], (
			not host_api.get_peers().has(leaver_peer)
			and rig.harness.has_event(leaver, &"server_disconnected")
			and not rig.relay(HOST).is_paused()
	), "host peers %s; leaver events %s" % [host_api.get_peers(), rig.harness.events(leaver)])
	_stop(rig)


# A forfeiter that leaves before the cut (its main menu leaves the lobby) needs none: nothing is
# pending and nobody waits for it.
func _test_left_first() -> void:
	var tag: String = "pause menu network, left before the cut:"
	var rig: Rig = _start(3, false)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	rig.mirror(2).submit_campaign(ForfeitCommand.new(2))
	rig.harness.step_until_idle()
	var pending_at_first: bool = not (rig.relay(HOST).get(&"_letting_go") as Dictionary).is_empty()
	rig.harness.drop(2)
	rig.harness.step_until_idle()
	var pending: Dictionary = rig.relay(HOST).get(&"_letting_go")
	rig.relay(HOST)._process(NetRelayScript.LET_GO_WAIT)
	_check("%s the cut is dropped and the run doesn't pause" % [tag], (
			pending_at_first and pending.is_empty() and not rig.relay(HOST).is_paused()
	), "pending %s then %s" % [pending_at_first, pending])
	_stop(rig)


# Seat 1 drops, then seat 2 forfeits: its mirror hears the refusal "paused" for its own seat, as
# the menu shows, and the seat stays in the run.
func _test_forfeit_while_paused() -> void:
	var tag: String = "pause menu network, forfeit while paused:"
	var rig: Rig = _start(3, false)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	rig.harness.drop(1)
	rig.harness.step_until_idle()
	rig.without(1)
	var refusals: Array[String] = []
	rig.mirror(2).session.command_rejected.connect(
			func(seat: int, _arrival: int, reason: String) -> void:
				refusals.append("%d %s" % [seat, reason])
	)
	rig.mirror(2).submit_campaign(ForfeitCommand.new(2))
	rig.harness.step_until_idle()
	_check("%s the forfeiter's mirror hears it refused \"paused\"; nobody leaves" % [tag], (
			refusals == ["2 paused"]
			and not rig.events[2].has(LEFT)
			and rig.relay(HOST).seats.state_of(2) == SeatDirectory.State.CONNECTED
			and _seats_of(SaveService.campaign.players) == PackedInt32Array([0, 1, 2])
	), "%s; %s" % [refusals, rig.events[2]])
	_stop(rig)


# The peers SaveService would send campaign data to, given every branch as an admitted member.
func _save_peers(rig: Rig, seat_count: int) -> Array[int]:
	var members: Array[SteamNetworkScript.LobbyMember] = []
	for seat: int in seat_count:
		var member: SteamNetworkScript.LobbyMember = SteamNetworkScript.LobbyMember.new()
		member.peer_id = rig.harness.peer_id(seat)
		member.steam_id = FIRST_STEAM_ID + seat
		members.append(member)
	return SaveService.client_peers_of(members, SaveService.campaign, rig.harness.peer_id(HOST))


# Each seat's Steam id, as the campaign's players give them.
func _players(seat_count: int) -> Dictionary[int, int]:
	var steam_ids: Dictionary[int, int] = {}
	for seat: int in seat_count:
		steam_ids[seat] = FIRST_STEAM_ID + seat
	return steam_ids


# Each linked branch's peer by its Steam id, as the admitted members are.
func _peers(rig: Rig, seat_count: int) -> Dictionary[int, int]:
	var by_steam_id: Dictionary[int, int] = {}
	for seat: int in seat_count:
		if rig.harness.is_linked(seat):
			by_steam_id[FIRST_STEAM_ID + seat] = rig.harness.peer_id(seat)
	return by_steam_id
