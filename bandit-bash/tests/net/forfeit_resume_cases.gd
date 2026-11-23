# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forfeit_resume_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## A co-op battle a seat leaves, saved and resumed, with every client in the harness acting
## through its [ClientMirror], for tests/net/run_all.gd: a client's own forfeit at 3 and 4 seats,
## and the host's removal of a dropped client after the wait at 3. Each mirror equals the host
## (run, encounter and every map's hash) once the battle opens, after the leave as its batches
## arrive, and after the resume, which seats only the players left and rebuilds every mirror's
## battle with the left map still forfeited; then the maps left are won, every batch's hash
## matching as it applies, and the battle ends without the seat on every running mirror. Needs a
## test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

const HOST_SEAT: int = CampaignData.HOST_SEAT

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000701

const SAVE_NUMBER: int = 1

# The seat that forfeits in every case: a client's, never the last, so seats keep a gap.
const LEAVING: int = 2


func run() -> void:
	if not _has_test_user_dir():
		_skip("forfeit resume: every case", "needs a test user folder (see run_all.gd's class doc)")
		return
	print("    (errors from refused snapshots and RunSaveSections below are expected)")
	for seat_count: int in [3, 4]:
		_test_forfeit_and_resume(seat_count, false)
	_test_forfeit_and_resume(3, true)


# With is_removed, the leaving client drops and the host removes it after the wait, as
# SeatWaitOverlay's Remove does; otherwise it forfeits through its mirror.
func _test_forfeit_and_resume(seat_count: int, is_removed: bool) -> void:
	var tag: String = "forfeit resume %d seats%s:" % [seat_count, ", removal" if is_removed else ""]
	var session: CampaignSession = _start_run(seat_count)
	if session == null:
		_check("%s the run reaches a combat node" % [tag], false)
		_end_run()
		return
	var every_seat: PackedInt32Array = session.run.seat_numbers()
	var rig: Rig = _make_rig(session, every_seat)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		_end_run()
		return
	var begun: Error = CampaignService.begin_battle(_begin_request(session))
	rig.harness.step_until_idle()
	_push(rig)
	var battle: CombatEncounter = session.encounter
	_check("%s the battle opens on every mirror and every seat's Start settles" % [tag], (
			begun == OK and battle != null and _start_every_map(rig, battle)
			and rig.difference().is_empty()
	), rig.difference())
	if battle == null:
		_stop(rig)
		_end_run()
		return

	var has_left: bool = _leave(rig, is_removed)
	_check("%s after the leave every mirror still equals the host, its battle kept" % [tag], (
			has_left
			and battle.forfeited_seats() == PackedInt32Array([LEAVING])
			and rig.every_mirror_forfeited(LEAVING)
			and rig.combat_failures.is_empty()
			and rig.difference().is_empty()
	), "%s; %s" % [rig.combat_failures, rig.difference()])
	var saved: Dictionary[int, int] = _map_hashes(battle)
	var saved_encounter: int = battle.state_hash()
	_stop(rig)

	var resumed: CampaignSession = _resume()
	var left: PackedInt32Array = _seats_but(every_seat, LEAVING)
	var resumed_battle: CombatEncounter = null if resumed == null else resumed.encounter
	_check("%s the host resumes the battle as saved, for the seats left" % [tag], (
			resumed_battle != null
			and _seats_of(SaveService.campaign.players) == left
			and resumed_battle.forfeited_seats() == PackedInt32Array([LEAVING])
			and _map_hashes(resumed_battle) == saved
			and resumed_battle.state_hash() == saved_encounter
	))
	if resumed_battle == null:
		_end_run()
		return
	rig = _make_rig(resumed, left)
	if rig == null:
		_check("%s the rig starts again without the seat that left" % [tag], false)
		_end_run()
		return
	_check("%s every mirror left rebuilds the resumed battle, the left map forfeited" % [tag], (
			rig.every_mirror_built()
			and rig.difference().is_empty()
			and rig.every_mirror_forfeited(LEAVING)
	), rig.difference())

	for seat: int in left:
		_win(resumed_battle.session_of_seat(seat))
	rig.harness.step_until_idle()
	_check("%s play goes on: every map left is won, every batch's hash matching" % [tag], (
			resumed_battle.is_finished()
			and rig.combat_checks > 0 and rig.combat_failures.is_empty()
			and rig.difference().is_empty()
	), "%d checked; %s; %s" % [rig.combat_checks, rig.combat_failures, rig.difference()])
	var result: CampaignSession.BattleResult = CampaignService.end_battle()
	rig.harness.step_until_idle()
	_check("%s the battle ends without the seat that left; every mirror equals the host" % [tag], (
			result != null and result.forfeited == PackedInt32Array([LEAVING])
			and resumed.encounter == null
			and resumed.seats == left
			and _seats_of(SaveService.campaign.players) == left
			and SaveService.campaign.departed.is_empty()
			and rig.every_mirror_seated(left) and rig.difference().is_empty()
	), rig.difference())
	_stop(rig)
	_end_run()


# The client of seat LEAVING leaves the battle: its own forfeit through its mirror, settled and
# let go; or, with is_removed, a drop, the wait, then the host's removal. Every client left keeps
# comparing as the leave's batches arrive. Whether the leave went through.
func _leave(rig: Rig, is_removed: bool) -> bool:
	var index: int = rig.seat_of_branch.find(LEAVING)
	rig.without(LEAVING)
	if not is_removed:
		var token: int = rig.mirror(index).submit_campaign(ForfeitCommand.new(LEAVING))
		rig.harness.step_until_idle()
		return rig.settles[index].has([token, ""])
	var host: NetRelayScript = rig.relay(NetHarness.HOST)
	rig.harness.drop(index)
	rig.harness.step_until_idle()
	host._process(NetRelayScript.REMOVE_WAIT)
	var batch: CampaignBatch = CampaignService.forfeit_seat(LEAVING, true)
	var removed: bool = host.remove_seat(LEAVING)
	rig.harness.step_until_idle()
	return batch != null and not batch.is_rejected() and removed and not host.is_paused()


# A multiplayer run of seat_count seats through SaveService, no starting offers, inside its first
# floor-1 Standard combat node by every seat's vote; null when it didn't get there.
func _start_run(seat_count: int) -> CampaignSession:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	var steam_ids: PackedInt64Array = []
	for seat: int in seat_count:
		steam_ids.append(FIRST_STEAM_ID + seat)
	var started: Error = SaveService.start_new_multiplayer_run(steam_ids)
	var session: CampaignSession = CampaignService.session
	if started != OK or session == null or session.run == null:
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	for node: int in session.run.next_nodes():
		if session.run.graph.type_of(node) != CampaignGraph.NodeType.STANDARD:
			continue
		for seat: int in session.run.seat_numbers():
			CampaignService.submit_command(RouteVoteCommand.for_session(session, seat, node))
		break
	return session if session.run.flow.stage == RunFlow.Stage.NODE else null


# The saved campaign loaded, resumed and its battle resumed on the host; its session, or null.
func _resume() -> CampaignSession:
	if SaveService.load_multiplayer_campaign() != OK or SaveService.resume_multiplayer_run() != OK:
		return null
	var session: CampaignSession = CampaignService.session
	if session == null or session.run == null:
		return null
	if CampaignService.resume_battle(_begin_request(session)) != OK:
		return null
	if SaveService.resume_point != CombatData.ResumePoint.BATTLE:
		return null
	return session


# A harness linking the host and one client branch per seat of seats but the host's, in order, a
# relay on each seated by seats alone and a started mirror per client, settled; null on failure.
func _make_rig(session: CampaignSession, seats: PackedInt32Array) -> Rig:
	var rig: Rig = Rig.new()
	rig.session = session
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(seats.size() - 1):
		rig.harness.stop()
		return null
	var directory: SeatDirectory = SeatDirectory.new()
	for index: int in seats.size():
		directory.add_seat(seats[index], FIRST_STEAM_ID + seats[index], rig.harness.peer_id(index))
		rig.seat_of_branch.append(seats[index])
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		relay.seats = directory
		rig.relays.append(relay)
		rig.mirrors.append(null)
	for index: int in rig.clients():
		rig.add_mirror(index)
		rig.mirror(index).start()
	rig.harness.step_until_idle()
	return rig


func _stop(rig: Rig) -> void:
	for mirror: ClientMirror in rig.mirrors:
		if mirror != null:
			mirror.close()
	rig.harness.stop()


func _end_run() -> void:
	SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# The host relay's frame after a battle opened: its snapshot goes out.
func _push(rig: Rig) -> void:
	rig.relay(NetHarness.HOST)._process(0.0)
	rig.harness.step_until_idle()


# Every seat's Start on its own map; whether each client's settled with no refusal.
func _start_every_map(rig: Rig, battle: CombatEncounter) -> bool:
	CampaignService.submit_combat(
			StartCommand.new(HOST_SEAT), battle.session_of_seat(HOST_SEAT).session_id
	)
	var tokens: Dictionary[int, int] = {}
	for index: int in rig.clients():
		var seat: int = rig.seat_of_branch[index]
		tokens[index] = rig.mirror(index).submit_combat(
				StartCommand.new(seat), battle.session_of_seat(seat).session_id
		)
	rig.harness.step_until_idle()
	for index: int in rig.clients():
		if rig.settles[index] != [[tokens[index], ""]]:
			return false
	return true


# The run's battle request for its node; every seat's opening swap is on, its setting's default,
# so each seat's Start closes the window.
func _begin_request(session: CampaignSession) -> CampaignSession.BattleRequest:
	return session.run.battle_request(CombatMapPools.load_default(), EffectCatalog.index())


# Ends map as won outside any command, sent as its own batch.
func _win(map: CombatSession) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	map.engine.record(ended)
	map.flush("test win")


func _map_hashes(battle: CombatEncounter) -> Dictionary[int, int]:
	var hashes: Dictionary[int, int] = {}
	for map: CombatSession in battle.get_sessions():
		hashes[map.session_id] = map.state_hash()
	return hashes


func _seats_but(seats: PackedInt32Array, skipped: int) -> PackedInt32Array:
	var kept: PackedInt32Array = seats.duplicate()
	kept.erase(skipped)
	return kept


func _seats_of(entries: Array[CampaignData.PlayerRun]) -> PackedInt32Array:
	var seats: PackedInt32Array = []
	for entry: CampaignData.PlayerRun in entries:
		seats.append(entry.seat)
	return seats


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# One case's peers: the host's session, the harness, each branch's relay and mirror, the seat each
# branch plays, what each client's relay settled and the battle batches' hash checks.
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var mirrors: Array[ClientMirror] = []
	var seat_of_branch: PackedInt32Array = []
	var settles: Dictionary[int, Array] = {}
	var combat_checks: int = 0
	var combat_failures: PackedStringArray = []
	# Client branches no longer compared: their seat left the run.
	var _left: Dictionary[int, bool] = {}

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func mirror(index: int) -> ClientMirror:
		return mirrors[index]

	func clients() -> PackedInt32Array:
		var found: PackedInt32Array = []
		for index: int in range(1, harness.size()):
			if not _left.has(index):
				found.append(index)
		return found

	# Stops comparing the client branch that plays seat.
	func without(seat: int) -> void:
		var index: int = seat_of_branch.find(seat)
		if index > 0:
			_left[index] = true

	# A mirror for client branch index, not started; its settles and battle batches are heard.
	func add_mirror(index: int) -> void:
		var client: NetRelayScript = relay(index)
		mirrors[index] = ClientMirror.new(client, session.rng.run_seed)
		settles[index] = []
		client.command_settled.connect(_on_settled.bind(index))
		client.combat_batch_received.connect(_check_map.bind(index))

	func every_mirror_built() -> bool:
		for index: int in clients():
			var copy: CampaignSession = mirror(index).session
			if copy == null or not copy.is_mirror:
				return false
			if mirror(index).local_seat() != seat_of_branch[index]:
				return false
		return true

	func every_mirror_seated(seats: PackedInt32Array) -> bool:
		for index: int in clients():
			var copy: CampaignSession = mirror(index).session
			if copy == null or copy.seats != seats:
				return false
		return true

	func every_mirror_forfeited(seat: int) -> bool:
		for index: int in clients():
			var battle: CombatEncounter = mirror(index).session.encounter
			if battle == null or battle.forfeited_seats() != PackedInt32Array([seat]):
				return false
		return true

	# The first way a compared client's mirror differs from the host: its run, its battle, a map
	# or the encounter; empty when every one is equal.
	func difference() -> String:
		for index: int in clients():
			var copy: CampaignSession = mirror(index).session
			if copy == null or copy.run == null:
				return "client %d has no run" % [index]
			if RunStateCases.run_text(copy.run) != RunStateCases.run_text(session.run):
				return "client %d's run differs" % [index]
			if (copy.encounter == null) != (session.encounter == null):
				return "client %d's battle is %s" % [
					index, "missing" if copy.encounter == null else "extra",
				]
			if session.encounter == null:
				continue
			if copy.encounter.state_hash() != session.encounter.state_hash():
				return "client %d's encounter differs" % [index]
			for map: CombatSession in session.encounter.get_sessions():
				if copy.encounter.get_session(map.session_id).state_hash() != map.state_hash():
					return "client %d's map %d differs" % [index, map.session_id]
		return ""

	func _on_settled(token: int, reason: String, index: int) -> void:
		settles[index].append([token, reason])

	func _check_map(wire: Array, index: int) -> void:
		if _left.has(index):
			return
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var copy: CampaignSession = mirror(index).session
		var battle: CombatEncounter = null if copy == null else copy.encounter
		if (
				batch == null or battle == null or batch.is_rejected()
				or batch.state_hash == CombatSession.NO_HASH
		):
			return
		var map: CombatSession = battle.get_session(batch.session_id)
		if map == null or map.last_seq() != batch.last_seq():
			return
		combat_checks += 1
		if map.state_hash() != batch.state_hash:
			combat_failures.append("client %d s%d#%d" % [index, batch.session_id, map.last_seq()])
