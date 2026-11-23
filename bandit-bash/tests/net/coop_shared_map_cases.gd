# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_shared_map_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Co-op battles on maps two seats share, in the harness for tests/net/run_all.gd, 2 and 4 seats,
## every client acting through its [ClientMirror]: accepted swaps put a visitor on each partner's
## map, every seat's Start in the opening swap windows (the visitor's owner's too) and every End
## Turn on each map, then a client seat forfeits while the teammate whose map its visitor stands
## on has ended its turn, so the visitor leaves and that map's turn runs on. Every client's
## encounter and every map's [method CombatSession.state_hash] equals the host's after each Start,
## each End Turn and the leave (BUG-043, P11 CO23). Needs a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")

const HOST: int = NetHarness.HOST
const HOST_SEAT: int = CampaignData.HOST_SEAT

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000401

const SAVE_NUMBER: int = 1

# The client seat that forfeits; its visitor stands on the host seat's map.
const LEAVER: int = 1

# Any fixed run seed: the cases compare peers with each other, never with golden numbers.
const RUN_SEED: String = "3F9A-12C0-77E1-A"


func run() -> void:
	if not _has_test_user_dir():
		_skip("coop shared map: every case", "needs a test user folder (see run_all.gd)")
		return
	for client_count: int in [1, 3]:
		_test_shared_maps(client_count)


# Swaps between seats 0 and 1 (and 2 and 3), a Standard battle with every opening swap window on,
# each seat's Start and End Turn on every map it has units on, then seat 1's forfeit.
func _test_shared_maps(client_count: int) -> void:
	var tag: String = "coop shared map %d seats:" % [client_count + 1]
	var rig: Rig = _start(client_count)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	var battle: CombatEncounter = _begin(rig)
	if battle == null:
		_check("%s the battle opens on every mirror with its visitors" % [tag], false)
		_stop(rig)
		return
	var shared: CombatSession = battle.session_of_seat(HOST_SEAT)
	_check("%s the battle opens on every mirror with its visitors" % [tag], (
			PhaseRunner.seats_with_units(shared) == PackedInt32Array([HOST_SEAT, LEAVER])
			and _difference(rig, battle).is_empty()
	), _difference(rig, battle))
	var failed: PackedStringArray = []
	var steps: int = 0
	for map: CombatSession in battle.get_sessions():
		for seat: int in map.state.seats_to_start.duplicate():
			steps += 1
			_act(rig, seat, StartCommand.new(seat), map.session_id)
			_note(failed, _difference(rig, battle), "s%d Start %d" % [map.session_id, seat])
	for map: CombatSession in battle.get_sessions():
		var turn: int = map.state.turn
		for seat: int in PhaseRunner.seats_with_units(map):
			steps += 1
			_act(rig, seat, EndTurnCommand.new(seat), map.session_id)
			_note(failed, _difference(rig, battle), "s%d End Turn %d" % [map.session_id, seat])
		_note(failed, "" if map.state.turn == turn + 1 else "turn", "s%d turn" % [map.session_id])
	_check("%s every mirror equals the host after each Start and End Turn" % [tag], (
			steps > battle.get_sessions().size() and failed.is_empty() and rig.failures.is_empty()
	), "%s; %s" % [failed, rig.failures])

	var turn: int = shared.state.turn
	_act(rig, HOST_SEAT, EndTurnCommand.new(HOST_SEAT), shared.session_id)
	var waited: bool = shared.state.turn == turn
	rig.after_batch.clear()
	var forfeit: CampaignBatch = CampaignService.forfeit_seat(LEAVER)
	rig.harness.step_until_idle()
	# Each client is compared as the forfeit's last battle batch reaches it: the SEAT_FORFEITED
	# campaign batch after them closes a mirror's battle, as any campaign batch in a battle does.
	var followed: bool = rig.after_batch.size() == rig.harness.size() - 1
	for index: int in rig.after_batch:
		followed = followed and rig.after_batch[index].is_empty()
	_check("%s the leave runs the teammate's turn on, every mirror following" % [tag], (
			waited
			and forfeit != null and not forfeit.is_rejected()
			and shared.state.turn == turn + 1
			and PhaseRunner.seats_with_units(shared) == PackedInt32Array([HOST_SEAT])
			and followed
			and rig.failures.is_empty()
	), "waited %s, refused %s, turn %d of %d, seats %s; %s; %s" % [
		waited, "-" if forfeit == null else forfeit.rejected_reason, shared.state.turn, turn + 1,
		PhaseRunner.seats_with_units(shared), rig.after_batch, rig.failures,
	])
	_stop(rig)


# A multiplayer run of client_count + 1 seats, no starting offers, with accepted swaps between
# seats 0 and 1 (and 2 and 3), inside a floor-1 Standard combat node, and a harness with a relay
# and a started mirror per client. Null when any of it fails.
func _start(client_count: int) -> Rig:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	var steam_ids: PackedInt64Array = []
	for seat: int in client_count + 1:
		steam_ids.append(FIRST_STEAM_ID + seat)
	if SaveService.start_new_multiplayer_run(steam_ids) != OK:
		SaveService.close_save_file()
		return null
	# The run is rebuilt on RUN_SEED, as the debug command line's --run-seed= would make it, so
	# the battle (who falls before the leave) is the same every run.
	SaveService.campaign.run_seed = RunSeed.parse(RUN_SEED)
	SaveService.campaign_activated.emit(CampaignData.Mode.MULTIPLAYER, false)
	var session: CampaignSession = CampaignService.session
	if session == null or session.run == null:
		_end_run()
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var pairs: int = 0
	for first: int in range(0, client_count + 1, 2):
		_swap(session, first, first + 1)
		pairs += 1
	if (
			session.run.flow.swaps.size() != pairs
			or not Fixture.enter(session.run, CampaignGraph.NodeType.STANDARD)
	):
		_end_run()
		return null
	var rig: Rig = Rig.new()
	rig.session = session
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(client_count):
		rig.harness.stop()
		_end_run()
		return null
	var directory: SeatDirectory = SeatDirectory.new()
	for seat: int in client_count + 1:
		directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		relay.seats = directory
		rig.relays.append(relay)
		rig.mirrors.append(null)
	for index: int in range(1, rig.harness.size()):
		rig.add_mirror(index)
		rig.mirror(index).start()
	rig.harness.step_until_idle()
	return rig


# Seat first proposes, and seat second accepts, a swap of their last army units.
func _swap(session: CampaignSession, first: int, second: int) -> void:
	var mine: String = _soldier(session, first)
	var theirs: String = _soldier(session, second)
	CampaignService.submit_command(
			HostFill.complete(ProposeSwapCommand.new(first, mine, second, theirs), session)
	)
	CampaignService.submit_command(
			HostFill.complete(AnswerSwapCommand.new(second, first, true, mine, theirs), session)
	)


# Begins the node's battle with every seat's opening swap on and pushes it to every mirror.
# Returns the host's battle; null when it didn't open everywhere.
func _begin(rig: Rig) -> CombatEncounter:
	var request: CampaignSession.BattleRequest = rig.session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return null
	for seat: int in rig.session.run.seat_numbers():
		request.opening_swap[seat] = true
	if CampaignService.begin_battle(request) != OK:
		return null
	rig.harness.step_until_idle()
	rig.relay(HOST)._process(0.0)
	rig.harness.step_until_idle()
	var battle: CombatEncounter = rig.session.encounter
	for index: int in range(1, rig.harness.size()):
		if battle == null or rig.mirror(index).session.encounter == null:
			return null
	return battle


# Sends command for seat on the map session_id as that seat does: the host seat's on the host, a
# client's through its mirror. Then lets the network settle.
func _act(rig: Rig, seat: int, command: Command, session_id: int) -> void:
	if seat == HOST_SEAT:
		CampaignService.submit_combat(command, session_id)
	else:
		rig.mirror(seat).submit_combat(command, session_id)
	rig.harness.step_until_idle()


# Adds step to failed when difference isn't empty.
func _note(failed: PackedStringArray, difference: String, step: String) -> void:
	if not difference.is_empty():
		failed.append("%s: %s" % [step, difference])


# The first way a client's battle differs from the host's: its encounter or a map; empty when
# every mirror is equal.
func _difference(rig: Rig, battle: CombatEncounter) -> String:
	for index: int in range(1, rig.harness.size()):
		var copy: CampaignSession = rig.mirror(index).session
		var mirrored: CombatEncounter = null if copy == null else copy.encounter
		if mirrored == null:
			return "client %d has no battle" % [index]
		if mirrored.state_hash() != battle.state_hash():
			return "client %d's encounter differs" % [index]
		for map: CombatSession in battle.get_sessions():
			if mirrored.get_session(map.session_id).state_hash() != map.state_hash():
				return "client %d's map %d differs" % [index, map.session_id]
	return ""


# The last unit of seat's army: never its commander.
func _soldier(session: CampaignSession, seat: int) -> String:
	var army: Array[UnitInstance] = session.run.seat_run(seat).army
	return army[army.size() - 1].instance_id


func _stop(rig: Rig) -> void:
	for mirror: ClientMirror in rig.mirrors:
		if mirror != null:
			mirror.close()
	rig.harness.stop()
	_end_run()


func _end_run() -> void:
	if SaveService.has_multiplayer_campaign():
		SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# One case's peers: the host's session, the harness, each branch's relay and mirror, every battle
# batch whose hash a client's mirror didn't match as it applied, and by client, how its battle
# differed from the host's right after the last battle batch it applied (empty: equal).
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var mirrors: Array[ClientMirror] = []
	var failures: PackedStringArray = []
	var after_batch: Dictionary[int, String] = {}

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func mirror(index: int) -> ClientMirror:
		return mirrors[index]

	# A mirror for client branch index, not started; the hash checks hear its relay after it.
	func add_mirror(index: int) -> void:
		var client: NetRelayScript = relay(index)
		mirrors[index] = ClientMirror.new(client, session.rng.run_seed)
		client.combat_batch_received.connect(_check_map.bind(index))
		client.encounter_batch_received.connect(_check_encounter.bind(index))

	func _check_map(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = _battle_of(index)
		if (
				batch == null or battle == null or batch.is_rejected()
				or batch.state_hash == CombatSession.NO_HASH
		):
			return
		var map: CombatSession = battle.get_session(batch.session_id)
		after_batch[index] = _against_host(battle)
		if map == null or map.last_seq() != batch.last_seq():
			return
		if map.state_hash() != batch.state_hash:
			failures.append("client %d s%d#%d" % [index, batch.session_id, map.last_seq()])

	func _check_encounter(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = _battle_of(index)
		if batch == null or battle == null:
			return
		after_batch[index] = _against_host(battle)
		if batch.state_hash != CombatSession.NO_HASH and battle.state_hash() != batch.state_hash:
			failures.append("client %d encounter #%d" % [index, batch.last_seq()])

	# How mirrored differs from the host's battle as it stands: empty when every hash is equal.
	func _against_host(mirrored: CombatEncounter) -> String:
		var host: CombatEncounter = session.encounter
		if host == null or mirrored.state_hash() != host.state_hash():
			return "encounter"
		for map: CombatSession in host.get_sessions():
			if mirrored.get_session(map.session_id).state_hash() != map.state_hash():
				return "map %d" % [map.session_id]
		return ""

	func _battle_of(index: int) -> CombatEncounter:
		var copy: CampaignSession = mirror(index).session
		return null if copy == null else copy.encounter
