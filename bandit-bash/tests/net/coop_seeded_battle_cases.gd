# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_seeded_battle_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## BUG-046's seeds, in the harness for tests/net/run_all.gd: a 2-seat run's floor-1 Standard
## battle on each seed, the client seat acting through its [ClientMirror], played to its end by a
## driver that keeps the co-op rules. On both seeds one map is won while the other's last player
## unit falls, so that map freezes and waits for help: the winner sends every unit it has left
## there, and every seat acts on every map it has units on. Both maps then end won, and the
## client's battle equals the host's. The seat's own moves come from [M1BattleCases]'s driver.
## Needs a test user folder.

# What one seat did in a round.
enum Played {
	NOTHING,
	ACTED,
	SENT,
}

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")

const HOST: int = NetHarness.HOST
const HOST_SEAT: int = CampaignData.HOST_SEAT
const CLIENT: int = 1

# The seeds BUG-046 was seen on, with the two-instance ENet case's driver, which never sent.
const SEEDS: Array[String] = ["9456-F0E2-B5D2-6", "B072-5FA4-D5CB-1"]

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000501

const SAVE_NUMBER: int = 1

# Rounds of play (each seat's next command) before the case calls the battle stalled; both seeds
# end in about 40.
const ROUND_LIMIT: int = 400

var _driver: M1BattleCases = M1BattleCases.new(_ignore)


func run() -> void:
	if not _has_test_user_dir():
		_skip("coop seeded battle: every case", "needs a test user folder (see run_all.gd)")
		return
	for seed_text: String in SEEDS:
		_test_seed(seed_text)


# The seed's battle from Begin to its end.
func _test_seed(seed_text: String) -> void:
	var tag: String = "coop seeded battle %s:" % [seed_text]
	var rig: Rig = _start(RunSeed.parse(seed_text))
	var battle: CombatEncounter = null if rig == null else rig.session.encounter
	if battle == null:
		_check("%s the battle opens on the host and the client" % [tag], false)
		if rig != null:
			_stop(rig)
		return
	# A send is made only to a frozen map (_play), so it stands for the freeze, which the landing
	# ends within the same round.
	var sent: bool = false
	var idle: int = 0
	var rounds: int = 0
	while rounds < ROUND_LIMIT and not battle.is_finished() and idle < 2:
		rounds += 1
		var acted: bool = false
		for seat: int in [HOST_SEAT, CLIENT]:
			var played: Played = _play(rig, seat)
			acted = acted or played != Played.NOTHING
			sent = sent or played == Played.SENT
		idle = 0 if acted else idle + 1
	var all_won: bool = true
	for map: CombatSession in battle.get_sessions():
		all_won = all_won and map.is_finished and map.is_won
	var difference: String = rig.difference()
	_check("%s a map freezes, the winner sends, and the battle plays to its end" % [tag], (
			sent and battle.is_finished() and all_won and not battle.is_run_lost()
	), "rounds %d, sent %s, %s" % [rounds, sent, _states(battle)])
	_check("%s the client's battle equals the host's at the end" % [tag], (
			difference.is_empty() and rig.failures.is_empty()
	), "%s; %s" % [difference, rig.failures])
	_check("%s the battle ends on the host" % [tag], CampaignService.end_battle() != null)
	rig.harness.step_until_idle()
	_stop(rig)


# A 2-seat run on run_seed inside its floor-1 Standard combat with no opening swap, its battle
# begun and pushed to a started client mirror. Null when any of it fails.
func _start(run_seed: int) -> Rig:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	var steam_ids: PackedInt64Array = [FIRST_STEAM_ID, FIRST_STEAM_ID + CLIENT]
	if SaveService.start_new_multiplayer_run(steam_ids) != OK:
		SaveService.close_save_file()
		return null
	# The run is rebuilt on the seed as the debug command line's --run-seed= would have made it.
	SaveService.campaign.run_seed = run_seed
	SaveService.campaign_activated.emit(CampaignData.Mode.MULTIPLAYER, false)
	var session: CampaignSession = CampaignService.session
	if session == null or session.run == null or session.rng.run_seed != run_seed:
		_end_run()
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var route: PackedInt32Array = Fixture.route_to(
			session.run.graph, CampaignGraph.NodeType.STANDARD
	)
	if route.size() != 1:
		_end_run()
		return null
	for seat: int in session.run.seat_numbers():
		CampaignService.submit_command(RouteVoteCommand.for_session(session, seat, route[0]))
	var rig: Rig = Rig.new()
	rig.session = session
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(CLIENT):
		rig.harness.stop()
		_end_run()
		return null
	var directory: SeatDirectory = SeatDirectory.new()
	for seat: int in CLIENT + 1:
		directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		relay.seats = directory
		rig.relays.append(relay)
	rig.mirror = ClientMirror.new(rig.relay(CLIENT), session.rng.run_seed)
	rig.relay(CLIENT).combat_batch_received.connect(rig.check_map)
	rig.relay(CLIENT).encounter_batch_received.connect(rig.check_encounter)
	rig.mirror.start()
	rig.harness.step_until_idle()
	var request: CampaignSession.BattleRequest = session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return rig
	for seat: int in session.run.seat_numbers():
		request.opening_swap[seat] = false
	if CampaignService.begin_battle(request) != OK:
		return rig
	rig.harness.step_until_idle()
	rig.relay(HOST)._process(0.0)
	rig.harness.step_until_idle()
	return rig if rig.view(CLIENT) != null else null


# Seat's next command, read from its own view of the battle (the host's, or the client's mirror):
# its Start, a unit's turn or its End Turn on the first map it has to act on, else, its map won
# while a map is frozen, a send of every unit it has left there.
func _play(rig: Rig, seat: int) -> Played:
	var view: CombatEncounter = rig.view(seat)
	if view == null:
		return Played.NOTHING
	for map: CombatSession in view.get_sessions():
		var command: Command = _command_on(map, seat)
		if command != null:
			rig.submit(seat, command, map.session_id)
			return Played.ACTED
	var own: CombatSession = view.session_of_seat(seat)
	if own == null or not own.is_finished or not own.is_won:
		return Played.NOTHING
	var units: PackedStringArray = []
	for unit_id: String in own.state.units_of(CombatFact.CombatSide.PLAYER):
		if view.session_of_unit(unit_id) == own and not view.units_in_transit().has(unit_id):
			units.append(unit_id)
	for map: CombatSession in view.get_sessions():
		if not units.is_empty() and view.is_frozen(map.session_id):
			rig.submit(seat, SendUnitsCommand.new(seat, units, map.session_id), own.session_id)
			return Played.SENT
	return Played.NOTHING


# Seat's next command on map: Start in its window, then each unit's turn, then End Turn; null
# when it has nothing to do there.
func _command_on(map: CombatSession, seat: int) -> Command:
	var state: CombatState = map.state
	if map.is_finished:
		return null
	if state.seats_to_start.has(seat):
		return StartCommand.new(seat)
	if (
			state.phase_side != CombatFact.CombatSide.PLAYER
			or state.is_phase_ended
			or state.ended_seats.has(seat)
			or not PhaseRunner.seats_with_units(map).has(seat)
	):
		return null
	var acting: PackedStringArray = TurnInputModel.acting_units(map, seat)
	if acting.is_empty():
		return EndTurnCommand.new(seat)
	var turn: UnitTurnCommand = _driver._turn_for(map, acting[0])
	turn.seat = seat
	return turn


# Each map's end, turn and phase, for a failure's detail.
func _states(battle: CombatEncounter) -> String:
	var parts: PackedStringArray = []
	for map: CombatSession in battle.get_sessions():
		parts.append("s%d %s turn %d side %d ended %s" % [
			map.session_id, "won" if map.is_won else ("lost" if map.is_finished else "on"),
			map.state.turn, map.state.phase_side, map.state.ended_seats,
		])
	return "; ".join(parts)


func _stop(rig: Rig) -> void:
	if rig.mirror != null:
		rig.mirror.close()
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


static func _ignore(_case_name: String, _passed: bool, _detail: String = "") -> void:
	pass



# One case's peers: the host's session, the harness, each branch's relay, the client's mirror,
# and every battle batch whose hash the mirror didn't match as it applied.
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var mirror: ClientMirror = null
	var failures: PackedStringArray = []

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	# Seat's view of the battle: the host's encounter, or the client's mirror of it.
	func view(seat: int) -> CombatEncounter:
		if seat == HOST_SEAT:
			return session.encounter
		return null if mirror == null or mirror.session == null else mirror.session.encounter

	# Sends command as seat does, then lets the network settle.
	func submit(seat: int, command: Command, session_id: int) -> void:
		if seat == HOST_SEAT:
			CampaignService.submit_combat(command, session_id)
		else:
			mirror.submit_combat(command, session_id)
		harness.step_until_idle()

	# How the client's battle differs from the host's; empty when every hash is equal.
	func difference() -> String:
		var host: CombatEncounter = session.encounter
		var copy: CombatEncounter = view(CLIENT)
		if host == null or copy == null:
			return "no battle"
		if copy.state_hash() != host.state_hash():
			return "encounter"
		for map: CombatSession in host.get_sessions():
			if copy.get_session(map.session_id).state_hash() != map.state_hash():
				return "map %d" % [map.session_id]
		return ""

	func check_map(wire: Array) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = view(CLIENT)
		if (
				batch == null or battle == null or batch.is_rejected()
				or batch.state_hash == CombatSession.NO_HASH
		):
			return
		var map: CombatSession = battle.get_session(batch.session_id)
		if map == null or map.last_seq() != batch.last_seq():
			return
		if map.state_hash() != batch.state_hash:
			failures.append("s%d#%d" % [batch.session_id, map.last_seq()])

	func check_encounter(wire: Array) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = view(CLIENT)
		if batch == null or battle == null or batch.state_hash == CombatSession.NO_HASH:
			return
		if battle.state_hash() != batch.state_hash:
			failures.append("encounter #%d" % [batch.last_seq()])
