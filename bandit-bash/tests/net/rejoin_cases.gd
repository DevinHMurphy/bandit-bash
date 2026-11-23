# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rejoin_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Drop, pause and rejoin cases for tests/net/run_all.gd ([code]NetRelay[/code]'s seats,
## [ClientMirror]), on a real multiplayer run with a relay and a mirror per client branch, each
## relay seated by [code]seat_members()[/code] as a lobby's would be: a drop on the map and in a
## battle keeps the seat and pauses every peer (overlay shown, commands settled "paused", batches
## already sent still applied); the client reconnects and rejoins from a fresh snapshot, every
## hash equal; a crashed client's fresh relay and mirror are admitted by Steam id and rebuilt; the
## host removes a seat only after the wait, and it never comes back; an unseated connection hears
## nothing; a client's route notice reaches the host alone, not while paused; the host leaving
## makes every client wait, and SteamNetwork's verdicts end it; the host's own commands settle
## "paused"; a rejoined client's screen. Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const SteamNetworkScript = preload("res://scripts/autoload/steam_network.gd")
const CampaignServiceScript = preload("res://scripts/autoload/campaign_service.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

const HOST: int = NetHarness.HOST

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000201

const PAUSED: String = "paused"
const NOT_SEATED: String = "not seated"

# The seated client a case drops, and another that stays.
const DROPPED: int = 1
const STAYING: int = 2


func run() -> void:
	if not _has_test_user_dir():
		_skip("rejoin: every case", "needs a test user folder (see run_all.gd's class doc)")
		return
	_test_drop_on_map()
	_test_drop_in_battle()
	_test_crashed_rejoin()
	_test_remove()
	_test_unseated()
	_test_route()
	_test_host_leaves()
	_test_host_paused()
	_test_rejoin_screen()


# A client drops on the map: its seat is kept, every peer pauses and shows the wait; a command
# meanwhile settles "paused"; it reconnects and rejoins from a fresh snapshot, and play goes on.
func _test_drop_on_map() -> void:
	var rig: Rig = _start(3, 3)
	if rig == null:
		_check("rejoin map: the rig starts", false)
		return
	var host: NetRelayScript = rig.relay(HOST)
	rig.clear()
	rig.harness.drop(DROPPED)
	rig.harness.step_until_idle()
	_check("rejoin map: a drop keeps the seat, dropped, and pauses every connected peer", (
			host.seats.state_of(DROPPED) == SeatDirectory.State.DROPPED
			and host.seats.steam_id_of_seat(DROPPED) == FIRST_STEAM_ID + DROPPED
			and host.waiting_seats() == PackedInt32Array([DROPPED])
			and rig.relay(STAYING).waiting_seats() == PackedInt32Array([DROPPED])
			and rig.record(HOST).seat_events == PackedStringArray(["dropped 1"])
			and rig.record(STAYING).seat_events == PackedStringArray(["dropped 1"])
	), "%s; %s" % [rig.record(HOST).seat_events, rig.record(STAYING).seat_events])
	_check("rejoin map: every peer shows the wait overlay, naming the dropped seat", (
			_overlay_line(host) == "Waiting for Player 2 · 0:00"
			and _overlay_line(rig.relay(STAYING)) == "Waiting for Player 2 · 0:00"
	), _overlay_line(host))
	_check("rejoin map: the dropped client waits for the host it lost", (
			rig.relay(DROPPED).is_host_lost()
			and rig.relay(DROPPED).waiting_seats() == PackedInt32Array([CampaignData.HOST_SEAT])
			and _overlay_line(rig.relay(DROPPED)) == "Reconnecting to Player 1 · 0:00"
	), _overlay_line(rig.relay(DROPPED)))

	var node: int = rig.session.run.next_nodes()[0]
	var run_before: String = RunStateCases.run_text(rig.session.run)
	var token: int = rig.mirror(STAYING).submit_campaign(RouteVoteCommand.new(STAYING, node))
	rig.harness.step_until_idle()
	_check("rejoin map: a client's command while paused settles \"paused\"; nothing changes", (
			rig.record(STAYING).settles == [[token, PAUSED]]
			and RunStateCases.run_text(rig.session.run) == run_before
	), str(rig.record(STAYING).settles))

	host._process(30.0)
	rig.relay(STAYING)._process(30.0)
	_check("rejoin map: each peer counts the wait", (
			is_equal_approx(host.waited(DROPPED), 30.0)
			and is_equal_approx(rig.relay(STAYING).waited(DROPPED), 30.0)
			and _overlay_line(host) == "Waiting for Player 2 · 0:30"
	), _overlay_line(host))

	rig.clear()
	if not _rejoin(rig, DROPPED):
		_stop(rig)
		return
	_check("rejoin map: the client is back; every peer hears it and the pause lifts", (
			host.seats.peer_of_seat(DROPPED) == rig.harness.peer_id(DROPPED)
			and not host.is_paused()
			and not rig.relay(STAYING).is_paused()
			and not rig.relay(DROPPED).is_paused()
			and not rig.relay(DROPPED).is_host_lost()
			and rig.record(HOST).seat_events == PackedStringArray(["rejoined 1"])
			and rig.record(STAYING).seat_events == PackedStringArray(["rejoined 1"])
			and not _overlay_shows(host)
			and not _overlay_shows(rig.relay(STAYING))
			and not _overlay_shows(rig.relay(DROPPED))
	), "%s" % [rig.record(HOST).seat_events])
	_check("rejoin map: the rejoin brings a fresh snapshot; every mirror equals the host", (
			rig.record(DROPPED).syncs == 1
			and rig.mirror(DROPPED).local_seat() == DROPPED
			and _difference(rig).is_empty()
	), "%d syncs; %s" % [rig.record(DROPPED).syncs, _difference(rig)])
	rig.clear()
	token = rig.mirror(DROPPED).submit_campaign(RouteVoteCommand.new(DROPPED, node))
	rig.harness.step_until_idle()
	_check("rejoin map: the rejoined client's command resolves again", (
			rig.record(DROPPED).settles == [[token, ""]] and _difference(rig).is_empty()
	), str(rig.record(DROPPED).settles))
	_stop(rig)


# A client drops mid-battle: a batch already sent still plays; a command settles "paused"; the
# rejoin rebuilds its battle from a fresh snapshot with every hash equal.
func _test_drop_in_battle() -> void:
	var rig: Rig = _start(3, 3)
	var battle: CombatEncounter = null if rig == null else _open_battle(rig)
	if battle == null:
		_check("rejoin battle: the battle opens on every mirror", false)
		if rig != null:
			_stop(rig)
		return
	rig.clear()
	CampaignService.submit_combat(StartCommand.new(0), battle.session_of_seat(0).session_id)
	rig.harness.drop(STAYING)
	rig.harness.step_until_idle()
	_check("rejoin battle: a batch resolved as the seat dropped still plays on the others", (
			rig.record(DROPPED).combat_batches > 0
			and _difference_of(rig, DROPPED).is_empty()
			and rig.relay(DROPPED).waiting_seats() == PackedInt32Array([STAYING])
	), _difference_of(rig, DROPPED))

	var own: CombatSession = battle.session_of_seat(DROPPED)
	var hash_before: int = own.state_hash()
	rig.clear()
	var token: int = rig.mirror(DROPPED).submit_combat(StartCommand.new(DROPPED), own.session_id)
	rig.harness.step_until_idle()
	_check("rejoin battle: a combat command while paused settles \"paused\"; its map is as it was", (
			rig.record(DROPPED).settles == [[token, PAUSED]] and own.state_hash() == hash_before
	), str(rig.record(DROPPED).settles))

	rig.clear()
	if not _rejoin(rig, STAYING):
		_stop(rig)
		return
	var held: CombatEncounter = rig.mirror(STAYING).session.encounter
	var equal: bool = held != null and held.state_hash() == battle.state_hash()
	for map: CombatSession in battle.get_sessions():
		equal = (
				equal
				and held.get_session(map.session_id) != null
				and held.get_session(map.session_id).state_hash() == map.state_hash()
		)
	_check("rejoin battle: the rejoin rebuilds the battle from a fresh snapshot, hashes equal", (
			rig.record(STAYING).snapshots == 1
			and equal
			and _difference(rig).is_empty()
	), "%d snapshots; %s" % [rig.record(STAYING).snapshots, _difference(rig)])
	rig.clear()
	token = rig.mirror(DROPPED).submit_combat(StartCommand.new(DROPPED), own.session_id)
	rig.harness.step_until_idle()
	_check("rejoin battle: play goes on, every mirror equal", (
			rig.record(DROPPED).settles == [[token, ""]] and _difference(rig).is_empty()
	), "%s; %s" % [rig.record(DROPPED).settles, _difference(rig)])
	_stop(rig)


# A client crashes mid-battle: a new process has a new relay and mirror and holds nothing; its
# Steam id is admitted back to its seat and the host's push builds the run and the battle.
func _test_crashed_rejoin() -> void:
	var rig: Rig = _start(2, 2)
	var battle: CombatEncounter = null if rig == null else _open_battle(rig)
	if battle == null:
		_check("rejoin crash: the battle opens", false)
		if rig != null:
			_stop(rig)
		return
	rig.harness.drop(DROPPED)
	rig.harness.step_until_idle()
	rig.mirror(DROPPED).close()
	rig.relay(DROPPED).free()
	var relay: NetRelayScript = rig.add_relay(DROPPED)
	if not rig.harness.reconnect(DROPPED):
		_check("rejoin crash: the branch reconnects", false)
		_stop(rig)
		return
	var fresh: ClientMirror = ClientMirror.new(relay, rig.session.rng.run_seed)
	rig.mirrors[DROPPED] = fresh
	relay.seat_members(rig.players(), rig.peers())
	rig.relay(HOST).seat_members(rig.players(), rig.peers())
	rig.harness.step_until_idle()
	_check("rejoin crash: a crashed client's account is seated again under its new peer", (
			rig.relay(HOST).seats.seat_of_peer(rig.harness.peer_id(DROPPED)) == DROPPED
			and not rig.relay(HOST).is_paused()
			and fresh.local_seat() == DROPPED
	))
	_check("rejoin crash: its fresh mirror holds the run and the battle, hashes equal", (
			fresh.session != null
			and fresh.session.encounter != null
			and fresh.session.encounter.state_hash() == battle.state_hash()
			and _difference(rig).is_empty()
	), _difference(rig))
	_stop(rig)


# The host may remove a dropped seat only after REMOVE_WAIT; every peer hears it, the pause lifts,
# and the seat's account is never seated again.
func _test_remove() -> void:
	var rig: Rig = _start(3, 3)
	if rig == null:
		_check("rejoin remove: the rig starts", false)
		return
	var host: NetRelayScript = rig.relay(HOST)
	rig.harness.drop(DROPPED)
	rig.harness.step_until_idle()
	host._process(NetRelayScript.REMOVE_WAIT - 1.0)
	var early: bool = host.remove_seat(DROPPED)
	var by_client: bool = rig.relay(STAYING).remove_seat(DROPPED)
	_check("rejoin remove: not before the wait, and never by a client", (
			not early
			and not by_client
			and host.seats.state_of(DROPPED) == SeatDirectory.State.DROPPED
	))
	rig.clear()
	host._process(1.0)
	var removed: bool = host.remove_seat(DROPPED)
	rig.harness.step_until_idle()
	_check("rejoin remove: after the wait the host removes it; every peer hears; play resumes", (
			removed
			and host.seats.state_of(DROPPED) == SeatDirectory.State.REMOVED
			and rig.relay(STAYING).seats.state_of(DROPPED) == SeatDirectory.State.REMOVED
			and rig.record(HOST).seat_events == PackedStringArray(["removed 1"])
			and rig.record(STAYING).seat_events == PackedStringArray(["removed 1"])
			and not host.is_paused()
			and not rig.relay(STAYING).is_paused()
	), "%s" % [rig.record(STAYING).seat_events])
	rig.harness.reconnect(DROPPED)
	rig.clear()
	host.seat_members(rig.players(), rig.peers())
	rig.harness.step_until_idle()
	var node: int = rig.session.run.next_nodes()[0]
	var token: int = rig.relay(DROPPED).send_campaign(RouteVoteCommand.new(DROPPED, node))
	rig.harness.step_until_idle()
	_check("rejoin remove: a removed seat's account is never seated again and hears nothing", (
			host.seats.state_of(DROPPED) == SeatDirectory.State.REMOVED
			and host.seats.seat_of_peer(rig.harness.peer_id(DROPPED)) == SeatDirectory.NO_SEAT
			and rig.record(DROPPED).syncs == 0
			and rig.record(DROPPED).seat_events.is_empty()
			and rig.record(DROPPED).settles == [[token, NOT_SEATED]]
	), "%s" % [rig.record(DROPPED).settles])
	_stop(rig)


# A connection the host never seated (a stranger awaiting refusal) hears none of the run: no
# batch, snapshot, notice or seat change.
func _test_unseated() -> void:
	var rig: Rig = _start(2, 3)
	if rig == null:
		_check("rejoin unseated: the rig starts", false)
		return
	var stranger: int = 2
	rig.clear()
	var node: int = rig.session.run.next_nodes()[0]
	CampaignService.submit_command(RouteVoteCommand.for_session(rig.session, 0, node))
	rig.relay(HOST).send_notice(NetRelayScript.NoticeKind.SELECTION, [0, ""])
	rig.harness.step_until_idle()
	var battle: CombatEncounter = _open_battle(rig)
	if battle != null:
		CampaignService.submit_combat(StartCommand.new(0), battle.session_of_seat(0).session_id)
	rig.harness.drop(DROPPED)
	rig.harness.step_until_idle()
	var heard: Record = rig.record(stranger)
	_check("rejoin unseated: the seated client hears the run", (
			battle != null
			and rig.record(DROPPED).campaign_batches > 0
			and rig.record(DROPPED).snapshots == 1
			and rig.record(DROPPED).combat_batches > 0
			and rig.record(DROPPED).notices == 1
	), rig.record(DROPPED).describe())
	_check("rejoin unseated: an unseated connection receives nothing at all", (
			heard.campaign_batches == 0
			and heard.combat_batches == 0
			and heard.encounter_batches == 0
			and heard.syncs == 0
			and heard.notices == 0
			and heard.seat_events.is_empty()
			and not rig.relay(stranger).is_paused()
	), heard.describe())
	_stop(rig)


# A client's route notice reaches the host alone, which routes everyone; while paused it's
# dropped; the host never sends one.
func _test_route() -> void:
	var rig: Rig = _start(3, 3)
	if rig == null:
		_check("rejoin route: the rig starts", false)
		return
	var route: int = NetRelayScript.NoticeKind.ROUTE
	rig.clear()
	rig.relay(DROPPED).send_notice(route, [])
	rig.harness.step_until_idle()
	_check("rejoin route: a client's route reaches the host alone, as its seat's", (
			rig.record(HOST).notice_list == [[DROPPED, route, []]]
			and rig.record(STAYING).notices == 0
			and rig.record(DROPPED).notices == 0
	), str(rig.record(HOST).notice_list))
	rig.clear()
	rig.relay(DROPPED).rpc_id(1, &"_notice", 0, route, [0])
	rig.relay(HOST).send_notice(route, [])
	rig.harness.step_until_idle()
	_check("rejoin route: a route with data, or from the host, goes nowhere", (
			rig.record(HOST).notices == 0
			and rig.record(STAYING).notices == 0
			and rig.record(DROPPED).notices == 0
	))
	rig.harness.drop(STAYING)
	rig.harness.step_until_idle()
	rig.clear()
	rig.relay(DROPPED).send_notice(route, [])
	rig.harness.step_until_idle()
	_check("rejoin route: while the run is paused the host ignores a route", (
			rig.record(HOST).notices == 0
	), str(rig.record(HOST).notice_list))
	_stop(rig)


# The host leaves: every client waits for it, reconnecting; SteamNetwork ends the session when
# the lobby is gone or has another host, as it does for a client outside a run at once.
func _test_host_leaves() -> void:
	var rig: Rig = _start(3, 3)
	if rig == null:
		_check("rejoin host leaves: the rig starts", false)
		return
	rig.harness.drop(HOST)
	rig.harness.step_until_idle()
	var waiting: bool = true
	for index: int in range(1, rig.harness.size()):
		waiting = (
				waiting
				and rig.relay(index).is_host_lost()
				and _overlay_line(rig.relay(index)) == "Reconnecting to Player 1 · 0:00"
		)
	_check("rejoin host leaves: every client waits for the host, reconnecting", waiting)
	_stop(rig)

	var success: int = Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS
	var host_id: int = FIRST_STEAM_ID
	var own_id: int = FIRST_STEAM_ID + 1
	var verdicts: Array[int] = [
		SteamNetworkScript._rejoin_verdict(success, host_id, host_id, own_id),
		SteamNetworkScript._rejoin_verdict(success, FIRST_STEAM_ID + 2, host_id, own_id),
		SteamNetworkScript._rejoin_verdict(success, own_id, host_id, own_id),
		SteamNetworkScript._rejoin_verdict(
				Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST, 0, host_id, own_id
		),
		SteamNetworkScript._rejoin_verdict(
				Steam.CHAT_ROOM_ENTER_RESPONSE_ERROR, 0, host_id, own_id
		),
	]
	var expected: Array[int] = [
		SteamNetworkScript._Rejoin.ENTER,
		SteamNetworkScript._Rejoin.END,
		SteamNetworkScript._Rejoin.END,
		SteamNetworkScript._Rejoin.END,
		SteamNetworkScript._Rejoin.RETRY,
	]
	_check("rejoin host leaves: a rejoin enters only the same host's lobby; else it ends", (
			verdicts == expected
	), str(verdicts))

	var ended: Array[int] = [0]
	var count_end: Callable = func() -> void: ended[0] += 1
	SteamNetwork.session_ended.connect(count_end)
	SteamNetwork._on_multiplayer_server_disconnected()
	_check("rejoin host leaves: outside a run a lost host ends the session at once, as built", (
			ended[0] == 1 and not SteamNetwork.is_reconnecting()
	))
	SteamNetwork.session_ended.disconnect(count_end)


# The host's own commands while a seat is dropped settle "paused", campaign and combat, and
# resolve again once it's back. On the autoload relay, which CampaignService asks.
func _test_host_paused() -> void:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(1)
	var started: Error = SaveService.start_new_multiplayer_run(
			PackedInt64Array([FIRST_STEAM_ID, FIRST_STEAM_ID + 1])
	)
	var session: CampaignSession = CampaignService.session
	var relay: NetRelayScript = _root.get_node_or_null(^"NetRelay") as NetRelayScript
	if started != OK or session == null or session.run == null or relay == null:
		_check("rejoin host paused: a co-op run starts", false)
		_end_run()
		return
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var told: Array = []
	var tell: Callable = func(seat: int, _arrival: int, reason: String) -> void:
		told.append([seat, reason])
	session.command_rejected.connect(tell)
	relay._seat_changed(1, SeatDirectory.State.DROPPED, 0.0)
	var node: int = session.run.next_nodes()[0]
	var before: String = RunStateCases.run_text(session.run)
	var batch: CampaignBatch = CampaignService.submit_command(
			RouteVoteCommand.for_session(session, 0, node)
	)
	_check("rejoin host paused: the host's campaign command settles \"paused\"; nothing changes", (
			relay.is_paused()
			and batch != null
			and batch.rejected_reason == PAUSED
			and told == [[0, PAUSED]]
			and RunStateCases.run_text(session.run) == before
	), str(told))
	_check("rejoin host paused: the host's overlay offers Save & Quit", (
			_overlay_shows(relay) and _overlay_button(relay) == "Save & Quit"
	))
	var battle: CombatEncounter = null
	if Fixture.enter(session.run, CampaignGraph.NodeType.STANDARD):
		var request: CampaignSession.BattleRequest = session.run.battle_request(
				CombatMapPools.load_default(), EffectCatalog.index()
		)
		if request != null and CampaignService.begin_battle(request) == OK:
			battle = session.encounter
	if battle == null:
		_check("rejoin host paused: the battle begins", false)
	else:
		var map: CombatSession = battle.session_of_seat(0)
		var hash_before: int = map.state_hash()
		var paused: Array[CombatSession.FactBatch] = CampaignService.submit_combat(
				StartCommand.new(0), map.session_id
		)
		_check("rejoin host paused: the host's combat command is rejected \"paused\"", (
				paused.size() == 1
				and paused[0].rejected_reason == PAUSED
				and map.state_hash() == hash_before
		))
		relay._seat_changed(1, SeatDirectory.State.CONNECTED, 0.0)
		var resolved: Array[CombatSession.FactBatch] = CampaignService.submit_combat(
				StartCommand.new(0), map.session_id
		)
		_check("rejoin host paused: once the seat is back the host's command resolves", (
				not relay.is_paused()
				and not _overlay_shows(relay)
				and resolved.size() == 1
				and not resolved[0].is_rejected()
		))
	relay._seat_changed(1, SeatDirectory.State.CONNECTED, 0.0)
	session.command_rejected.disconnect(tell)
	_end_run()


func _test_rejoin_screen() -> void:
	var made: CampaignSession = Fixture.session(0x5EA7, 2)
	for seat: int in made.run.seat_numbers():
		made.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	_check("rejoin screen: a rejoined client opens the battle, else its run's own screen", (
			CampaignServiceScript._rejoin_screen(made, SceneRouter.Screen.GAMEPLAY)
					== SceneRouter.Screen.GAMEPLAY
			and CampaignServiceScript._rejoin_screen(made, -1) == SceneRouter.Screen.CAMPAIGN_MAP
	))
	made.close()


# A multiplayer run of seat_count seats through SaveService, no starting offers left, and a
# harness of branch_count peers (the branches past the seats are connections never seated), a
# relay under each, each seated relay seated as a lobby's, and a started mirror per seated client.
# Null, with everything undone, when any of it fails.
func _start(seat_count: int, branch_count: int) -> Rig:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(1)
	var steam_ids: PackedInt64Array = []
	for seat: int in seat_count:
		steam_ids.append(FIRST_STEAM_ID + seat)
	var started: Error = SaveService.start_new_multiplayer_run(steam_ids)
	var session: CampaignSession = CampaignService.session
	if started != OK or session == null or session.run == null:
		SaveService.close_save_file()
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var rig: Rig = Rig.new()
	rig.session = session
	rig.seat_count = seat_count
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(branch_count - 1):
		rig.harness.stop()
		_end_run()
		return null
	for index: int in branch_count:
		rig.relays.append(null)
		rig.records.append(null)
		rig.mirrors.append(null)
		rig.add_relay(index)
	for index: int in seat_count:
		rig.relay(index).seat_members(rig.players(), rig.peers())
	for index: int in range(1, seat_count):
		rig.mirrors[index] = ClientMirror.new(rig.relay(index), session.rng.run_seed)
		rig.mirror(index).start()
	rig.harness.step_until_idle()
	return rig


# Reconnects client index under a new peer, as Steam does, and seats it again: the client's
# member list first, as the host's broadcast arrives before its news, then the host's admission.
func _rejoin(rig: Rig, index: int) -> bool:
	if not rig.harness.reconnect(index):
		_check("rejoin: client %d reconnects" % [index], false)
		return false
	for client: int in range(1, rig.seat_count):
		if rig.harness.is_linked(client):
			rig.relay(client).seat_members(rig.players(), rig.peers())
	rig.relay(HOST).seat_members(rig.players(), rig.peers())
	rig.harness.step_until_idle()
	return true


func _stop(rig: Rig) -> void:
	for mirror: ClientMirror in rig.mirrors:
		if mirror != null:
			mirror.close()
	rig.harness.stop()
	_end_run()


func _end_run() -> void:
	SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# Puts the rig's run inside its first Standard combat, begins the battle there with its save and
# pushes its snapshot to every mirror; null when it can't.
func _open_battle(rig: Rig) -> CombatEncounter:
	var run_state: CampaignRunState = rig.session.run
	if not Fixture.enter(run_state, CampaignGraph.NodeType.STANDARD):
		return null
	var request: CampaignSession.BattleRequest = run_state.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null or CampaignService.begin_battle(request) != OK:
		return null
	rig.harness.step_until_idle()
	rig.relay(HOST)._process(0.0)
	rig.harness.step_until_idle()
	for index: int in range(1, rig.seat_count):
		var mirror: ClientMirror = rig.mirror(index)
		if mirror.session == null or mirror.session.encounter == null:
			return null
	return rig.session.encounter


func _overlay_of(relay: NetRelayScript) -> SeatWaitOverlay:
	for child: Node in relay.get_children():
		if child is SeatWaitOverlay:
			return child as SeatWaitOverlay
	return null


func _overlay_shows(relay: NetRelayScript) -> bool:
	var overlay: SeatWaitOverlay = _overlay_of(relay)
	if overlay == null:
		return false
	overlay.refresh()
	return overlay.visible


# The overlay's lines, or "" when it isn't shown.
func _overlay_line(relay: NetRelayScript) -> String:
	if not _overlay_shows(relay):
		return ""
	return (_overlay_of(relay).get_node(^"%Lines") as Label).text


func _overlay_button(relay: NetRelayScript) -> String:
	return (_overlay_of(relay).get_node(^"%LeaveButton") as Button).text


# The first way a seated client's mirror differs from the host; empty when every one is equal.
func _difference(rig: Rig) -> String:
	for index: int in range(1, rig.seat_count):
		var found: String = _difference_of(rig, index)
		if not found.is_empty():
			return found
	return ""


func _difference_of(rig: Rig, index: int) -> String:
	var host: CampaignSession = rig.session
	var mirror: ClientMirror = rig.mirror(index)
	var copy: CampaignSession = null if mirror == null else mirror.session
	if copy == null or copy.run == null:
		return "client %d has no run" % [index]
	if RunStateCases.run_text(copy.run) != RunStateCases.run_text(host.run):
		return "client %d's run differs" % [index]
	if (copy.encounter == null) != (host.encounter == null):
		var state: String = "missing" if copy.encounter == null else "extra"
		return "client %d's battle is %s" % [index, state]
	if host.encounter == null:
		return ""
	if copy.encounter.state_hash() != host.encounter.state_hash():
		return "client %d's encounter differs" % [index]
	for map: CombatSession in host.encounter.get_sessions():
		var mirrored: CombatSession = copy.encounter.get_session(map.session_id)
		if mirrored == null or mirrored.state_hash() != map.state_hash():
			return "client %d's map %d differs" % [index, map.session_id]
	return ""


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# One case's peers: the run's session, the harness, and each branch's relay, mirror and record.
# Branch index plays seat index; branches from seat_count on are never seated.
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var seat_count: int = 0
	var relays: Array[Node] = []
	var mirrors: Array[ClientMirror] = []
	var records: Array[Record] = []

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func mirror(index: int) -> ClientMirror:
		return mirrors[index]

	func record(index: int) -> Record:
		return records[index]

	func clear() -> void:
		for each: Record in records:
			each.clear()

	# Each seat's Steam id, as the campaign holds them.
	func players() -> Dictionary[int, int]:
		var steam_ids: Dictionary[int, int] = {}
		for seat: int in seat_count:
			steam_ids[seat] = FIRST_STEAM_ID + seat
		return steam_ids

	# Each linked seated branch's peer by its Steam id, as the admitted members are.
	func peers() -> Dictionary[int, int]:
		var by_steam_id: Dictionary[int, int] = {}
		for seat: int in seat_count:
			if harness.is_linked(seat):
				by_steam_id[FIRST_STEAM_ID + seat] = harness.peer_id(seat)
		return by_steam_id

	# A new relay under branch index, heard by a new record.
	func add_relay(index: int) -> NetRelayScript:
		var made: NetRelayScript = NetRelayScript.new()
		made.name = RELAY_NAME
		harness.branch(index).add_child(made)
		var heard: Record = Record.new()
		made.command_settled.connect(heard.on_settled)
		made.sync_received.connect(heard.on_sync)
		made.combat_batch_received.connect(heard.on_combat)
		made.encounter_batch_received.connect(heard.on_encounter)
		made.campaign_batch_received.connect(heard.on_campaign)
		made.notice_received.connect(heard.on_notice)
		made.seat_dropped.connect(heard.on_seat.bind("dropped"))
		made.seat_rejoined.connect(heard.on_seat.bind("rejoined"))
		made.seat_removed.connect(heard.on_seat.bind("removed"))
		relays[index] = made
		records[index] = heard
		return made


# What one relay heard.
class Record:
	extends RefCounted

	var settles: Array = []
	var seat_events: PackedStringArray = []
	var notice_list: Array = []
	var notices: int = 0
	var syncs: int = 0
	var snapshots: int = 0
	var combat_batches: int = 0
	var encounter_batches: int = 0
	var campaign_batches: int = 0

	func clear() -> void:
		settles.clear()
		seat_events.clear()
		notice_list.clear()
		notices = 0
		syncs = 0
		snapshots = 0
		combat_batches = 0
		encounter_batches = 0
		campaign_batches = 0

	func describe() -> String:
		return "campaign %d, combat %d, encounter %d, syncs %d, notices %d, seats %s" % [
			campaign_batches, combat_batches, encounter_batches, syncs, notices, seat_events,
		]

	func on_settled(token: int, reason: String) -> void:
		settles.append([token, reason])

	func on_sync(_run: Dictionary, battle: Dictionary, _facts: Array, _screen: int) -> void:
		syncs += 1
		if not battle.is_empty():
			snapshots += 1

	func on_combat(_wire: Array) -> void:
		combat_batches += 1

	func on_encounter(_wire: Array) -> void:
		encounter_batches += 1

	func on_campaign(_facts: Array, _run: Dictionary) -> void:
		campaign_batches += 1

	func on_notice(seat: int, kind: int, data: Array) -> void:
		notices += 1
		notice_list.append([seat, kind, data])

	func on_seat(seat: int, what: String) -> void:
		seat_events.append("%s %d" % [what, seat])
