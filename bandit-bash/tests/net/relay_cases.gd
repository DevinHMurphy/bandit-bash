# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     relay_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Relay cases for tests/net/run_all.gd ([code]NetRelay[/code]), on a real multiplayer run through
## SaveService and CampaignService, with one relay under each harness branch, 2 and 4 peers: a
## client's campaign and combat commands resolve on the host and settle to their sender; every
## campaign, map and encounter batch reaches every client in the host's order, campaign batches
## with the run's capture, and a battle's end sends the run; a forged seat acts only for the
## sender; an unseated peer, a pause, malformed data, a map outside the battle, no battle, and an
## authority RPC from a client are settled or dropped and change nothing; a rejection reaches only
## its sender; notices round-trip; [HostFill] covers every campaign wire type and fills what
## arrives; the fingerprint holds the relay's RPCs and kinds and a build without them is refused;
## solo play is unchanged. Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

const HOST: int = NetHarness.HOST

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000001

const RUN_SEED: int = 9191

# Every RPC NetRelay declares, as its RPC config names them.
const RELAY_RPCS: PackedStringArray = [
	"_submit_combat",
	"_submit_campaign",
	"_command_settled",
	"_combat_batch",
	"_encounter_batch",
	"_campaign_batch",
	"_request_sync",
	"_sync",
	"_notice",
]

# A token no relay hands out in these cases, for calls made around send_*().
const FORGED_TOKEN: int = 9000


func run() -> void:
	if not _has_test_user_dir():
		_skip("relay: every case", "needs a test user folder (see run_all.gd's class doc)")
		return
	for client_count: int in [1, 3]:
		_test_campaign(client_count)
		_test_combat(client_count)
	_test_refusals()
	_test_notices()
	_test_host_fill()
	_test_fingerprint()
	_test_solo()


func _test_campaign(client_count: int) -> void:
	var tag: String = "relay %d peers:" % [client_count + 1]
	var rig: Rig = _start(client_count, client_count)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	var session: CampaignSession = rig.session
	var node: int = session.run.next_nodes()[0]
	# Sent as seat 0: the host takes seat 1 from the connection.
	var token: int = rig.relay(1).send_campaign(RouteVoteCommand.new(0, node))
	rig.harness.step_until_idle()
	var host_stream: Array = rig.host_record.stream
	var resolved: bool = (
			token != NetRelayScript.NO_TOKEN
			and host_stream.size() == 1
			and session.run.route_votes.get(1, CampaignGraph.NO_NODE) == node
			and not session.run.route_votes.has(0)
	)
	_check("%s a client's campaign command resolves on the host for its own seat" % [tag], (
			resolved
	), "%s, votes %s" % [host_stream, session.run.route_votes])
	_check("%s it settles to its sender only, after its batch" % [tag], (
			rig.record(1).settled == [[token, ""]]
			and _nobody_else_settled(rig, 1)
	), str(rig.record(1).settled))
	var reached: bool = true
	for index: int in range(1, rig.harness.size()):
		var record: Record = rig.record(index)
		reached = (
				reached
				and record.stream == host_stream
				and record.runs.size() == 1
				and _is_run_capture(record.runs[0], session)
		)
	_check("%s the batch and the run's capture reach every client" % [tag], reached)

	rig.clear()
	var leave: int = rig.relay(1).send_campaign(LeaveNodeCommand.new(1))
	rig.harness.step_until_idle()
	var settled: Array = rig.record(1).settled
	var reason: String = "" if settled.size() != 1 else str((settled[0] as Array)[1])
	var others_heard: bool = false
	for index: int in range(2, rig.harness.size()):
		others_heard = others_heard or not rig.record(index).stream.is_empty()
	# Typed, since a comparison of an Array's Variant values is a Variant.
	var is_sender_only: bool = (
			not reason.is_empty()
			and rig.record(1).stream.size() == 1
			and not others_heard
			and (settled[0] as Array)[0] == leave
	)
	_check("%s a rejected campaign command's batch reaches only its sender" % [tag], (
			is_sender_only
	), "%s; %s" % [settled, rig.record(1).stream])
	_stop(rig)


func _test_combat(client_count: int) -> void:
	var tag: String = "relay %d peers:" % [client_count + 1]
	var rig: Rig = _start(client_count, client_count)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	var early: int = rig.relay(1).send_combat(StartCommand.new(1), 1)
	rig.harness.step_until_idle()
	_check("%s a combat command with no battle settles \"no battle\"" % [tag], (
			rig.record(1).settled == [[early, "no battle"]]
	), str(rig.record(1).settled))

	var battle: CombatEncounter = _open_battle(rig)
	if battle == null:
		_check("%s the battle opens" % [tag], false)
		_stop(rig)
		return
	rig.harness.step_until_idle()
	var opening: bool = not rig.host_record.stream.is_empty()
	for index: int in range(1, rig.harness.size()):
		opening = opening and rig.record(index).stream == rig.host_record.stream
	_check("%s the battle's opening batches reach every client" % [tag], opening)

	rig.clear()
	var own: Array[CombatSession.FactBatch] = CampaignService.submit_combat(StartCommand.new(0), 0)
	var start: int = rig.relay(1).send_combat(StartCommand.new(1), 1)
	rig.harness.step_until_idle()
	var aid: int = rig.relay(1).send_combat(CallForAidCommand.new(1, true), 1)
	rig.harness.step_until_idle()
	var kinds: PackedStringArray = []
	for entry: Variant in rig.host_record.stream:
		kinds.append(str((entry as Array)[0]))
	_check("%s the host's own command resolves through the same call" % [tag], (
			own.size() == 1 and not own[0].is_rejected()
	))
	_check("%s a client's combat commands resolve on the host and settle" % [tag], (
			rig.record(1).settled == [[start, ""], [aid, ""]]
			and battle.is_aid_called(1)
			and _nobody_else_settled(rig, 1)
	), str(rig.record(1).settled))
	var in_order: bool = kinds.has("map") and kinds.has("encounter")
	for index: int in range(1, rig.harness.size()):
		in_order = in_order and rig.record(index).stream == rig.host_record.stream
	_check("%s map and encounter batches reach every client in the host's order" % [tag], (
			in_order
	), str(kinds))

	rig.clear()
	var hashes: PackedInt64Array = _hashes(battle)
	var commander: String = battle.get_session(0).state.commander_of(0)
	var forged: UnitTurnCommand = UnitTurnCommand.new(0, commander, UnitTurnCommand.Action.WAIT)
	var forged_token: int = rig.relay(1).send_combat(forged, 0)
	var outside: int = rig.relay(1).send_combat(StartCommand.new(1), battle.seats.size())
	rig.harness.step_until_idle()
	var settled: Array = rig.record(1).settled
	var forged_reason: String = (
			"" if settled.size() != 2 else str((settled[0] as Array)[1])
	)
	var others_heard: bool = false
	for index: int in range(2, rig.harness.size()):
		others_heard = others_heard or not rig.record(index).stream.is_empty()
	# Typed, since a comparison of an Array's Variant values is a Variant.
	var is_refused: bool = (
			not forged_reason.is_empty()
			and (settled[0] as Array)[0] == forged_token
			and _hashes(battle) == hashes
	)
	var is_outside: bool = settled.size() == 2 and settled[1] == [outside, "no such map"]
	_check("%s a command for another seat's unit is rejected and changes nothing" % [tag], (
			is_refused
	), str(settled))
	_check("%s its rejected batch reaches only its sender" % [tag], (
			rig.record(1).stream.size() == 1 and not others_heard
	), str(rig.record(1).stream.size()))
	_check("%s a map outside the battle settles \"no such map\"" % [tag], is_outside, str(settled))

	rig.clear()
	CampaignService.session.abandon_battle()
	rig.harness.step_until_idle()
	var ended: bool = true
	for index: int in range(1, rig.harness.size()):
		var record: Record = rig.record(index)
		ended = (
				ended and record.stream == [["campaign", []]]
				and _is_run_capture(record.runs[0], rig.session)
		)
	_check("%s a battle's end sends the run with no facts to every client" % [tag], ended)
	_stop(rig)


func _test_refusals() -> void:
	var rig: Rig = _start(NetHarness.MAX_CLIENTS, 2)
	if rig == null:
		_check("relay refusals: the rig starts", false)
		return
	var run_before: String = RunStateCases.run_text(rig.session.run)
	var node: int = rig.session.run.next_nodes()[0]
	var unseated: int = rig.relay(3).send_campaign(RouteVoteCommand.new(3, node))
	rig.harness.step_until_idle()
	_check("relay refusals: a peer holding no seat settles \"not seated\"", (
			rig.record(3).settled == [[unseated, "not seated"]]
	), str(rig.record(3).settled))

	var host_relay: NetRelayScript = rig.relay(HOST)
	host_relay.seats.drop_peer(rig.harness.peer_id(2))
	var paused: int = rig.relay(1).send_campaign(RouteVoteCommand.new(1, node))
	rig.harness.step_until_idle()
	host_relay.seats.reconnect(FIRST_STEAM_ID + 2, rig.harness.peer_id(2))
	_check("relay refusals: a command while a seat is dropped settles \"paused\"", (
			rig.record(1).settled == [[paused, "paused"]]
	), str(rig.record(1).settled))

	rig.clear()
	var client: NetRelayScript = rig.relay(1)
	client.rpc_id(1, &"_submit_campaign", ["no_such_command", 1, 0], FORGED_TOKEN)
	client.rpc_id(1, &"_submit_campaign", ["route_vote", 1, 0, "node"], FORGED_TOKEN + 1)
	client.rpc_id(1, &"_submit_combat", ["start", 1], 1, FORGED_TOKEN + 2)
	var untokened: Array = LeaveNodeCommand.new(1).to_wire()
	client.rpc_id(1, &"_submit_campaign", untokened, NetRelayScript.NO_TOKEN)
	rig.harness.step_until_idle()
	_check("relay refusals: malformed commands settle \"malformed\"; no token, no settle", (
			rig.record(1).settled == [
				[FORGED_TOKEN, "malformed"],
				[FORGED_TOKEN + 1, "malformed"],
				[FORGED_TOKEN + 2, "malformed"],
			]
	), str(rig.record(1).settled))

	# Godot refuses an authority RPC from a client before any handler runs, on the host and on a
	# client the host's relay forwarded it to; the engine's errors in the output are expected.
	client.rpc_id(1, &"_campaign_batch", [], {})
	client.rpc_id(rig.harness.peer_id(2), &"_command_settled", FORGED_TOKEN, "forged")
	client.rpc_id(rig.harness.peer_id(2), &"_combat_batch", [])
	rig.harness.step_until_idle()
	var heard: bool = false
	for index: int in range(1, rig.harness.size()):
		var record: Record = rig.record(index)
		heard = (
				heard
				or not record.stream.is_empty()
				or (index != 1 and not record.settled.is_empty())
		)
	_check("relay refusals: an authority RPC from a client changes nothing anywhere", (
			not heard
			and rig.host_record.stream.is_empty()
			and RunStateCases.run_text(rig.session.run) == run_before
	))
	_stop(rig)


func _test_notices() -> void:
	var rig: Rig = _start(NetHarness.MAX_CLIENTS, NetHarness.MAX_CLIENTS)
	if rig == null:
		_check("relay notices: the rig starts", false)
		return
	var selection: int = NetRelayScript.NoticeKind.SELECTION
	var data: Array = [1, "unit_7"]
	rig.relay(1).send_notice(selection, data)
	rig.harness.step_until_idle()
	var up: bool = (
			rig.host_record.notices == [[1, selection, data]]
			and rig.record(1).notices.is_empty()
	)
	for index: int in range(2, rig.harness.size()):
		up = up and rig.record(index).notices == [[1, selection, data]]
	_check("relay notices: a client's notice reaches the host and every other client", up)

	rig.clear()
	rig.relay(HOST).send_notice(selection, [0, ""])
	rig.harness.step_until_idle()
	var down: bool = rig.host_record.notices.is_empty()
	for index: int in range(1, rig.harness.size()):
		down = down and rig.record(index).notices == [[0, selection, [0, ""]]]
	_check("relay notices: the host's notice reaches every client, as seat 0", down)

	rig.clear()
	var client: NetRelayScript = rig.relay(1)
	client.rpc_id(1, &"_notice", 0, selection, [-1, "unit_7"])
	client.rpc_id(1, &"_notice", 0, selection + 99, [0, ""])
	client.rpc_id(rig.harness.peer_id(2), &"_notice", 0, selection, [0, ""])
	rig.harness.step_until_idle()
	var quiet: bool = rig.host_record.notices.is_empty()
	for index: int in range(1, rig.harness.size()):
		quiet = quiet and rig.record(index).notices.is_empty()
	_check("relay notices: bad data, unknown kinds and client-to-client notices are dropped", quiet)
	_stop(rig)


func _test_host_fill() -> void:
	var campaign_types: PackedStringArray = _campaign_wire_types()
	var listed: bool = not campaign_types.is_empty()
	for wire_type: String in campaign_types:
		var count: int = (
				(1 if HostFill.FILLED.has(wire_type) else 0)
				+ (1 if HostFill.NOTHING_TO_FILL.has(wire_type) else 0)
		)
		listed = listed and count == 1
	_check("relay fill: every campaign wire type is in exactly one HostFill list", (
			listed
			and HostFill.FILLED.size() + HostFill.NOTHING_TO_FILL.size() == campaign_types.size()
	), str(campaign_types))

	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var node: int = made.run.next_nodes()[0]
	var vote: CampaignCommand = CampaignCommand.from_wire(RouteVoteCommand.new(1, node).to_wire())
	var filled_vote: RouteVoteCommand = HostFill.complete(vote, made) as RouteVoteCommand
	var choose: CampaignCommand = CampaignCommand.from_wire(
			EventOptionCommand.new(1, 0).to_wire()
	)
	var filled_choice: EventOptionCommand = HostFill.complete(choose, made) as EventOptionCommand
	var leave: CampaignCommand = CampaignCommand.from_wire(LeaveNodeCommand.new(1).to_wire())
	_check("relay fill: arrived commands get their host objects and keep their input", (
			filled_vote != null
			and filled_vote.draw_stream != null
			and filled_vote.node_id == node
			and filled_vote.seat == 1
			and filled_choice != null
			and filled_choice.pool != null
			and filled_choice.ids == made.ids
			and filled_choice.streams.has(1)
			and HostFill.complete(leave, made) == leave
	))


func _test_fingerprint() -> void:
	var parts: Dictionary = NetContract.format_parts()
	var configs: Dictionary = parts["rpc"]
	var relay_config: Dictionary = configs.get("NetRelay", {})
	var has_rpcs: bool = relay_config.size() == RELAY_RPCS.size()
	for method: String in RELAY_RPCS:
		has_rpcs = has_rpcs and relay_config.has(method)
	var versions: Dictionary = parts.get("RunSaveSections.versions", {})
	# Typed, since a comparison of a Dictionary's Variant values is a Variant.
	var is_held: bool = (
			has_rpcs
			and parts.get("NetRelay.NoticeKind", {}) == NetRelayScript.NoticeKind
			and versions.get("campaign_map", 0) == RunSaveSections.MAP_VERSION
			and versions.size() == 6
	)
	_check("relay fingerprint: it holds NetRelay's RPCs, notice kinds and run section versions", (
			is_held
	), str(relay_config.keys()))

	var without: Dictionary = parts.duplicate(true)
	(without["rpc"] as Dictionary).erase("NetRelay")
	without.erase("NetRelay.NoticeKind")
	var version: String = SaveFile.get_running_version()
	var with_relay: int = NetContract.combine(version, parts, "")
	var older: int = NetContract.combine(version, without, "")
	var nobody: PackedInt64Array = []
	_check("relay fingerprint: a build without the relay differs and is refused", (
			with_relay != older
			and LobbyAdmission.decide(
					version, version, with_relay, older, FIRST_STEAM_ID + 1, nobody, nobody
			) == LobbyAdmission.Refusal.BUILD_MISMATCH
	))


func _test_solo() -> void:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(1)
	SaveService.start_new_solo_run(RUN_SEED)
	var session: CampaignSession = CampaignService.session
	if session == null or session.run == null:
		_check("relay solo: a solo run starts", false)
		SaveService.close_save_file()
		return
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	var relay: Node = _root.get_node_or_null(^"NetRelay")
	var batch: CampaignBatch = CampaignService.submit_command(
			ChooseNodeCommand.new(0, session.run.next_nodes()[0])
	)
	_check("relay solo: the autoload is there and a solo command resolves at once", (
			relay != null
			and batch != null
			and not batch.is_rejected()
			and not session.run.is_on_map()
	), "" if batch == null else batch.rejected_reason)
	SaveService.abandon_run(CampaignData.Mode.SOLO)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# A multiplayer run of client_count + 1 seats through SaveService, no starting offers left, and a
# harness with a relay under each branch; the host's directory seats the host and the first
# seated_clients clients. Null, with everything undone, when any of it fails.
func _start(client_count: int, seated_clients: int) -> Rig:
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
	var rig: Rig = Rig.new()
	rig.session = session
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(client_count):
		rig.harness.stop()
		_end_run()
		return null
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		var record: Record = Record.new()
		relay.command_settled.connect(record.on_settled)
		relay.combat_batch_received.connect(record.on_combat)
		relay.encounter_batch_received.connect(record.on_encounter)
		relay.campaign_batch_received.connect(record.on_campaign)
		relay.notice_received.connect(record.on_notice)
		rig.relays.append(relay)
		rig.records.append(record)
	var directory: SeatDirectory = SeatDirectory.new()
	directory.add_seat(CampaignData.HOST_SEAT, FIRST_STEAM_ID, rig.harness.peer_id(HOST))
	for seat: int in range(1, seated_clients + 1):
		directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
	rig.relay(HOST).seats = directory
	rig.host_record = rig.record(HOST)
	session.campaign_batch_resolved.connect(rig.host_record.on_host_campaign)
	session.combat_encounter_closed.connect(rig.host_record.on_host_closed)
	return rig


func _stop(rig: Rig) -> void:
	rig.harness.stop()
	_end_run()


func _end_run() -> void:
	SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# Puts the rig's run inside its first Standard combat and begins the battle there, recording the
# host's map and encounter batches from now. Null when it can't.
func _open_battle(rig: Rig) -> CombatEncounter:
	var run_state: CampaignRunState = rig.session.run
	if not Fixture.enter(run_state, CampaignGraph.NodeType.STANDARD):
		return null
	var request: CampaignSession.BattleRequest = run_state.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return null
	rig.session.combat_encounter_opened.connect(rig.host_record.on_host_battle)
	return rig.session.begin_battle(request)


# Whether no client but index was told a command settled.
func _nobody_else_settled(rig: Rig, index: int) -> bool:
	for other: int in range(1, rig.harness.size()):
		if other != index and not rig.record(other).settled.is_empty():
			return false
	return true


# Whether run is a capture of session's run: both shared sections and each seat's four.
func _is_run_capture(run: Dictionary, session: CampaignSession) -> bool:
	if not run.has("campaign_map") or not run.has("run_flow") or not run.has("seats"):
		return false
	var seats: Dictionary = run["seats"]
	for seat: int in session.seats:
		var parts: Dictionary = seats.get(seat, {})
		if parts.size() != 4 or not parts.has("roster") or not parts.has("economy"):
			return false
	return (run["campaign_map"] as Dictionary) == session.run.capture_map()


# Each map's state hash, by session id.
func _hashes(battle: CombatEncounter) -> PackedInt64Array:
	var hashes: PackedInt64Array = []
	for map: CombatSession in battle.get_sessions():
		hashes.append(map.state_hash())
	hashes.append(battle.state_hash())
	return hashes


# The WIRE_TYPE of every global class under res://scripts/ descending from CampaignCommand.
func _campaign_wire_types() -> PackedStringArray:
	var bases: Dictionary[String, String] = {}
	var paths: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		bases[entry["class"] as String] = entry["base"] as String
		paths[entry["class"] as String] = entry["path"] as String
	var found: PackedStringArray = []
	for class_id: String in bases:
		if not paths[class_id].begins_with(NetContract.SCRIPTS_ROOT):
			continue
		var current: String = bases[class_id]
		while not current.is_empty() and current != "CampaignCommand":
			current = bases.get(current, "")
		if current.is_empty():
			continue
		var constants: Dictionary = (load(paths[class_id]) as Script).get_script_constant_map()
		if constants.has("WIRE_TYPE"):
			found.append(str(constants["WIRE_TYPE"]))
	found.sort()
	return found


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# One case's peers: the run's session, the harness, each branch's relay and what it heard.
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var records: Array[Record] = []
	var host_record: Record = null

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func record(index: int) -> Record:
		return records[index]

	func clear() -> void:
		for each: Record in records:
			each.clear()


# What one branch heard: settles, every batch in arrival order as [kind, wire], the run captures
# and notices. On the host it records what the host sent instead, rejections left out.
class Record:
	extends RefCounted

	var settled: Array = []
	var stream: Array = []
	var runs: Array[Dictionary] = []
	var notices: Array = []

	func clear() -> void:
		settled.clear()
		stream.clear()
		runs.clear()
		notices.clear()

	func on_settled(token: int, reason: String) -> void:
		settled.append([token, reason])

	func on_combat(wire: Array) -> void:
		stream.append(["map", wire])

	func on_encounter(wire: Array) -> void:
		stream.append(["encounter", wire])

	func on_campaign(facts: Array, run: Dictionary) -> void:
		stream.append(["campaign", facts])
		runs.append(run)

	func on_notice(seat: int, kind: int, data: Array) -> void:
		notices.append([seat, kind, data])

	func on_host_campaign(batch: CampaignBatch) -> void:
		if not batch.is_rejected():
			stream.append(["campaign", batch.to_wire()])

	func on_host_closed(_encounter: CombatEncounter) -> void:
		stream.append(["campaign", []])

	func on_host_battle(encounter: CombatEncounter) -> void:
		encounter.session_opened.connect(on_host_map_opened)
		encounter.batch_resolved.connect(on_host_encounter)

	func on_host_map_opened(map: CombatSession) -> void:
		map.batch_resolved.connect(on_host_map)

	func on_host_map(batch: CombatSession.FactBatch) -> void:
		if not batch.is_rejected():
			stream.append(["map", batch.to_wire()])

	func on_host_encounter(batch: CombatSession.FactBatch) -> void:
		stream.append(["encounter", batch.to_wire()])
