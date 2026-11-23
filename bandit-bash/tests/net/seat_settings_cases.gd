# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seat_settings_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Seat settings cases for tests/net/run_all.gd (NetRelay's [code]_seat_settings[/code],
## [code]CampaignService.begin_battle()[/code]), on a real multiplayer run with a relay under each
## harness branch, 2 and 4 peers: a joining client's settings reach the host for its seat, and an
## Apply sends them again; nothing is sent while they are unchanged; the host keeps none for its
## own seat, a client keeps none, an unseated or malformed message is dropped, and a removal or
## the run's end forgets them. Through the service, seat 1's opening swap on or off opens or skips
## its map's window, and a seat that sent none has it on. Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")

const HOST: int = NetHarness.HOST

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000001

const KEY: String = SettingsData.OPENING_SWAP_KEY


func run() -> void:
	if not _has_test_user_dir():
		_skip("seat settings: every case", "needs a test user folder (see run_all.gd's class doc)")
		return
	for client_count: int in [1, 3]:
		_test_join_and_apply(client_count)
	_test_refusals()
	_test_forgotten()
	for sent: Variant in [true, false, null]:
		_test_battle(sent)


func _test_join_and_apply(client_count: int) -> void:
	var tag: String = "seat settings %d peers:" % [client_count + 1]
	var rig: Rig = _start(client_count, client_count)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	var host: NetRelayScript = rig.relay(HOST)
	_set_opening_swap(true)
	_process_clients(rig)
	var joined: bool = true
	for seat: int in range(1, client_count + 1):
		joined = joined and host.seat_settings(seat) == {KEY: true}
	_check("%s each client's settings reach the host for its own seat when it joins" % [tag], (
			joined
	), str(host.seat_settings(1)))
	_check("%s the host keeps none for its own seat, and a client keeps none" % [tag], (
			host.seat_settings(HOST).is_empty() and rig.relay(1).seat_settings(1).is_empty()
	))

	_set_opening_swap(false)
	_process_clients(rig)
	_check("%s an Apply sends the changed setting again" % [tag], (
			host.seat_settings(1) == {KEY: false}
	), str(host.seat_settings(1)))

	# Changed on the host by a hand-made message: an unchanged client sends nothing to put it back.
	rig.relay(1).rpc_id(1, &"_seat_settings", {KEY: true})
	rig.harness.step_until_idle()
	_process_clients(rig)
	_check("%s nothing is sent while the settings are unchanged" % [tag], (
			host.seat_settings(1) == {KEY: true}
	))
	_set_opening_swap(true)
	_stop(rig)


func _test_refusals() -> void:
	var rig: Rig = _start(2, 1)
	if rig == null:
		_check("seat settings refusals: the rig starts", false)
		return
	var host: NetRelayScript = rig.relay(HOST)
	_set_opening_swap(false)
	_process_clients(rig)
	_check("seat settings refusals: an unseated client's settings are dropped", (
			host.seat_settings(1) == {KEY: false} and host.seat_settings(2).is_empty()
	), str(host.seat_settings(2)))
	var client: NetRelayScript = rig.relay(1)
	var bad: Array[Dictionary] = [
		{},
		{KEY: 1},
		{KEY: "false"},
		{KEY: true, "music": 3},
		{"opening": true},
	]
	for settings: Dictionary in bad:
		client.rpc_id(1, &"_seat_settings", settings)
	rig.harness.step_until_idle()
	_check("seat settings refusals: malformed settings are dropped, the kept ones stay", (
			host.seat_settings(1) == {KEY: false}
	), str(host.seat_settings(1)))
	var copy: Dictionary = host.seat_settings(1)
	copy[KEY] = true
	_check("seat settings refusals: the host's read is a copy", (
			host.seat_settings(1) == {KEY: false}
	))
	_set_opening_swap(true)
	_stop(rig)


func _test_forgotten() -> void:
	var rig: Rig = _start(2, 2)
	if rig == null:
		_check("seat settings forgotten: the rig starts", false)
		return
	var host: NetRelayScript = rig.relay(HOST)
	_process_clients(rig)
	host._seat_changed(1, SeatDirectory.State.REMOVED, NetRelayScript.REMOVE_WAIT)
	_check("seat settings forgotten: a removed seat's settings go, the others' stay", (
			host.seat_settings(1).is_empty() and host.seat_settings(2) == {KEY: true}
	))
	SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	_check("seat settings forgotten: the run's end forgets every seat's", (
			host.seat_settings(2).is_empty()
	))
	rig.harness.stop()
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# A two-seat run whose seat 1 sent sent (on, off, or nothing for null) begins its first Standard
# combat through the service, the host's own entry on as the battle screen sets it.
func _test_battle(sent: Variant) -> void:
	var tag: String = "seat settings battle, seat 1 %s:" % [
		"sent nothing" if sent == null else ("on" if sent else "off"),
	]
	var session: CampaignSession = _start_run(1)
	if session == null:
		_check("%s the run starts" % [tag], false)
		return
	# The service reads the NetRelay autoload, which is on no network here, so seat 1's message is
	# kept as its RPC would keep it.
	if sent != null:
		NetRelay._keep_settings(1, {KEY: sent})
	var request: CampaignSession.BattleRequest = null
	if Fixture.enter(session.run, CampaignGraph.NodeType.STANDARD):
		request = session.run.battle_request(CombatMapPools.load_default(), EffectCatalog.index())
	if request == null:
		_check("%s the battle's request is built" % [tag], false)
		_end_run()
		return
	request.opening_swap[CampaignData.HOST_SEAT] = true
	var err: Error = CampaignService.begin_battle(request)
	var battle: CombatEncounter = session.encounter
	if err != OK or battle == null:
		_check("%s the battle begins" % [tag], false, error_string(err))
		_end_run()
		return
	var expected: bool = true if sent == null else sent
	var host_map: CombatSession = battle.session_of_seat(CampaignData.HOST_SEAT)
	var client_map: CombatSession = battle.session_of_seat(1)
	# Typed, since a comparison of a Dictionary's Variant values is a Variant.
	var is_filled: bool = request.opening_swap.get(1, null) == sent
	_check("%s seat 1's map opens its swap window by seat 1's setting" % [tag], (
			client_map.state.map.opening_swap_open == expected
			and host_map.state.map.opening_swap_open
			and is_filled
	), "client %s, host %s, request %s" % [
		client_map.state.map.opening_swap_open,
		host_map.state.map.opening_swap_open,
		request.opening_swap,
	])
	_end_run()
	_check("%s the run's end forgets the settings" % [tag], NetRelay.seat_settings(1).is_empty())


# A multiplayer run of client_count + 1 seats through SaveService, no starting offers left, and a
# harness with a relay under each branch; the host's directory seats the host and the first
# seated_clients clients. Null, with everything undone, when any of it fails.
func _start(client_count: int, seated_clients: int) -> Rig:
	var session: CampaignSession = _start_run(client_count)
	if session == null:
		return null
	var rig: Rig = Rig.new()
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(client_count):
		rig.harness.stop()
		_end_run()
		return null
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		rig.relays.append(relay)
	var directory: SeatDirectory = SeatDirectory.new()
	directory.add_seat(CampaignData.HOST_SEAT, FIRST_STEAM_ID, rig.harness.peer_id(HOST))
	for seat: int in range(1, seated_clients + 1):
		directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
	rig.relay(HOST).seats = directory
	return rig


# A multiplayer run of client_count + 1 seats with no starting offers left; null, undone, when it
# didn't start.
func _start_run(client_count: int) -> CampaignSession:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(1)
	var steam_ids: PackedInt64Array = []
	for seat: int in client_count + 1:
		steam_ids.append(FIRST_STEAM_ID + seat)
	var started: Error = SaveService.start_new_multiplayer_run(steam_ids)
	var session: CampaignSession = CampaignService.session
	if started != OK or session == null or session.run == null:
		SaveService.close_save_file()
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	return session


func _stop(rig: Rig) -> void:
	rig.harness.stop()
	_end_run()


func _end_run() -> void:
	SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# Every client's relay takes a frame's look at the settings (its _process), then the network
# settles.
func _process_clients(rig: Rig) -> void:
	for index: int in range(1, rig.harness.size()):
		rig.relay(index)._process(0.0)
	rig.harness.step_until_idle()


# Applies the opening-swap setting as Options' Apply does (SaveService.save_settings()).
func _set_opening_swap(is_on: bool) -> void:
	var edited: SettingsData = SaveService.settings.copy()
	edited.is_opening_swap_on = is_on
	var err: Error = SaveService.save_settings(edited)
	if err != OK:
		push_error("seat_settings_cases: the settings weren't applied - %s" % [error_string(err)])


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# One case's peers: the harness and each branch's relay.
class Rig:
	extends RefCounted

	var harness: NetHarness = null
	var relays: Array[Node] = []

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript
