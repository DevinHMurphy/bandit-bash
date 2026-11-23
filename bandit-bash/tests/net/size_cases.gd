# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     size_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Message size cases for tests/net/run_all.gd ([code]NetRelay[/code]'s packing, send guard and
## log lines): the largest relay messages measured as they travel (a 4-seat Powder Keep battle's
## [code]_sync[/code] with the run, as a rejoin gets it; a 4-seat campaign batch with its capture;
## the engaged 9-enemy key board's combat batches) are under Steam's message limit, each size
## printed; a packed message round-trips and a corrupt one is refused, also over the loopback; a
## message over the limit is never sent; every message sent and received is one NetLog line with
## its kind, size and peer; the fingerprint covers RPC arguments and the pack format.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const BenchBoards = preload("res://tests/bench/bench_boards.gd")

const HOST: int = NetHarness.HOST
const RELAY_NAME: StringName = &"NetRelay"

# The 4-seat battle: the Powder Keep at its floor, each seat the bench's six units
# (bench_boards.gd).
const KEEP_PATH: String = "res://maps/boss/powder_keep.tres"
const BOSS_FLOOR: int = 18
const BOSS_NODE: int = 3
const SEATS: int = 4
const RUN_SEED: int = 8080
const RECRUITS: Array[String] = ["fighter", "mage"]

# The engaged board the largest combat batch is measured on, and the player phases played there:
# each phase's enemy phase is the large batch. Enemy phases on 9-enemy boards cost about a second
# each in a debug build, so the case plays few; NT7's report has a whole battle's figures.
const BATCH_BOARD: String = "key_engaged"
const BOARD_PHASES: int = 2


func run() -> void:
	_test_largest_messages()
	_test_pack_round_trip()
	_test_corrupt_refused()
	_test_corrupt_over_the_wire()
	_test_send_guard()
	_test_log_lines()
	_test_fingerprint()


# Every message measured as it goes on the wire (_size_of() of its RPC arguments, packed where
# they travel packed), under the guard's budget; each printed for the step report.
func _test_largest_messages() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var sizes: Dictionary[String, int] = {}
	var raw_sizes: Dictionary[String, int] = {}

	var made: CampaignSession = Fixture.session(RUN_SEED, SEATS)
	var capture: Dictionary = _capture(made)
	var route: PackedInt32Array = Fixture.route_to(made.run.graph, CampaignGraph.NodeType.STANDARD)
	var chosen: CampaignBatch = null if route.is_empty() else Fixture.choose(made, route[0])
	if chosen != null:
		var batch_args: Array = [chosen.to_wire(), _capture(made)]
		raw_sizes["campaign_batch"] = NetRelayScript._size_of(batch_args)
		sizes["campaign_batch"] = NetRelayScript._size_of([NetRelayScript._pack(batch_args)])

	var battle: CombatEncounter = _begin_boss(made, catalog)
	if battle != null:
		var sync_args: Array = [capture, battle.snapshot(), [], SceneRouter.Screen.GAMEPLAY]
		raw_sizes["sync"] = NetRelayScript._size_of(sync_args)
		sizes["sync"] = NetRelayScript._size_of([NetRelayScript._pack(sync_args)])
	made.close()

	sizes["combat_batch"] = _largest_board_batch(BATCH_BOARD, catalog)

	var lines: PackedStringArray = []
	var is_under: bool = sizes.size() == 3 and raw_sizes.size() == 2
	for kind: String in sizes:
		var raw: String = (
				"" if not raw_sizes.has(kind) else ", %d B before packing" % [raw_sizes[kind]]
		)
		print("      size: %s %d B%s" % [kind, sizes[kind], raw])
		lines.append("%s %d" % [kind, sizes[kind]])
		is_under = is_under and sizes[kind] > 0 and sizes[kind] <= NetRelayScript._SEND_BUDGET
	_check("size: the largest messages, as they travel, are under Steam's message limit", (
			is_under
	), ", ".join(lines))


func _test_pack_round_trip() -> void:
	var args: Array = _sample_sync()
	var packed: PackedByteArray = NetRelayScript._pack(args)
	var unpacked: Array = NetRelayScript._unpack(packed)
	_check("size: a packed sync unpacks to its arguments, smaller", (
			unpacked == args
			and NetRelayScript._is_sync_shape(unpacked)
			and packed.size() < var_to_bytes(args).size()
	), "%d B packed from %d B" % [packed.size(), var_to_bytes(args).size()])


func _test_corrupt_refused() -> void:
	var packed: PackedByteArray = NetRelayScript._pack(_sample_sync())
	var flipped: PackedByteArray = packed.duplicate()
	var middle: int = (NetRelayScript._PACK_HEADER + packed.size()) >> 1
	flipped[middle] = flipped[middle] ^ 0xFF
	var truncated: PackedByteArray = packed.slice(0, packed.size() - 1)
	var other_format: PackedByteArray = packed.duplicate()
	other_format.encode_u8(0, NetRelayScript._PACK_FORMAT + 1)
	var wrong_size: PackedByteArray = packed.duplicate()
	wrong_size.encode_u32(
			NetRelayScript._PACK_SIZE_AT, packed.decode_u32(NetRelayScript._PACK_SIZE_AT) + 1
	)
	var huge_size: PackedByteArray = packed.duplicate()
	huge_size.encode_u32(NetRelayScript._PACK_SIZE_AT, NetRelayScript._UNPACK_LIMIT + 1)
	var wrong_digest: PackedByteArray = packed.duplicate()
	wrong_digest[NetRelayScript._PACK_DIGEST_AT] = wrong_digest[NetRelayScript._PACK_DIGEST_AT] ^ 1
	var not_array: PackedByteArray = _pack_value({"run": {}})
	var header_only: PackedByteArray = packed.slice(0, NetRelayScript._PACK_HEADER)
	var refusals: Array[bool] = []
	for corrupt: PackedByteArray in [
		flipped, truncated, other_format, wrong_size, huge_size, wrong_digest, not_array,
		header_only, PackedByteArray(),
	]:
		refusals.append(NetRelayScript._unpack(corrupt).is_empty())
	_check("size: a corrupt, cut, foreign or oversized packed message is refused", (
			not refusals.has(false)
			and not NetRelayScript._is_sync_shape([{}, {}, [], "screen"])
			and not NetRelayScript._is_campaign_batch_shape([{}, []])
	), str(refusals))


# A corrupt sync and campaign batch from the host reach no client signal; good ones after them do.
func _test_corrupt_over_the_wire() -> void:
	var rig: Rig = _start()
	if rig == null:
		_check("size: the rig starts", false)
		return
	var client: NetRelayScript = rig.relay(1)
	var syncs: Array = []
	var batches: Array = []
	client.sync_received.connect(
			func(run: Dictionary, battle: Dictionary, facts: Array, screen: int) -> void:
				syncs.append([run, battle, facts, screen])
	)
	client.campaign_batch_received.connect(func(facts: Array, run: Dictionary) -> void:
		batches.append([facts, run])
	)
	var peer: Array[int] = [rig.harness.peer_id(1)]
	var good_sync: Array = _sample_sync()
	var good_batch: Array = [[], {"campaign_map": {}}]
	var bad: PackedByteArray = NetRelayScript._pack(good_sync)
	bad[bad.size() - 1] = bad[bad.size() - 1] ^ 0xFF
	var host: NetRelayScript = rig.relay(HOST)
	var catcher: ErrorCatcher = ErrorCatcher.new()
	OS.add_logger(catcher)
	host._send(peer, &"_sync", [bad])
	host._send(peer, &"_campaign_batch", [bad])
	rig.harness.step_until_idle()
	var dropped_quietly: bool = syncs.is_empty() and batches.is_empty()
	host._send(peer, &"_sync", [NetRelayScript._pack(good_sync)])
	host._send(peer, &"_campaign_batch", [NetRelayScript._pack(good_batch)])
	rig.harness.step_until_idle()
	OS.remove_logger(catcher)
	_stop(rig)
	_check("size: a corrupt sync and campaign batch are dropped; good ones arrive whole", (
			dropped_quietly and syncs == [good_sync] and batches == [good_batch]
	), "%d syncs, %d batches; %s" % [syncs.size(), batches.size(), catcher.get_errors()])


# A message one 4-byte step over the budget goes to nobody, with an error; one at it arrives.
func _test_send_guard() -> void:
	var rig: Rig = _start()
	if rig == null:
		_check("size: the rig starts", false)
		return
	var received: Array[int] = []
	rig.relay(1).combat_batch_received.connect(func(wire: Array) -> void:
		received.append(NetRelayScript._size_of([wire]))
	)
	var overhead: int = NetRelayScript._size_of([[PackedByteArray()]])
	# Byte arrays encode padded to 4 bytes, so a multiple of 4 lands on the budget exactly.
	var fits: int = NetRelayScript._SEND_BUDGET - overhead
	fits -= fits % 4
	var at_budget: Array = [[_bytes(fits)]]
	var over_budget: Array = [[_bytes(fits + 4)]]
	var peer: Array[int] = [rig.harness.peer_id(1)]
	var catcher: ErrorCatcher = ErrorCatcher.new()
	OS.add_logger(catcher)
	var over_sent: bool = rig.relay(HOST)._send(peer, &"_combat_batch", over_budget)
	rig.harness.step_until_idle()
	var nothing_arrived: bool = received.is_empty()
	var at_sent: bool = rig.relay(HOST)._send(peer, &"_combat_batch", at_budget)
	rig.harness.step_until_idle()
	OS.remove_logger(catcher)
	_stop(rig)
	var errors: String = "\n".join(catcher.get_errors())
	_check("size: a message over the limit is never sent, and says so; one at the limit is", (
			not over_sent
			and nothing_arrived
			and errors.contains("not sent")
			and at_sent
			and received == [NetRelayScript._size_of(at_budget)]
			and NetRelayScript._size_of(at_budget) <= NetRelayScript._SEND_BUDGET
			and NetRelayScript._size_of(over_budget) > NetRelayScript._SEND_BUDGET
	), "over sent %s, at sent %s, received %s, budget %d" % [
		over_sent, at_sent, received, NetRelayScript._SEND_BUDGET,
	])


# A client's request for state and the host's answer: four lines, each with its kind, the same
# size at both ends, and the other end's peer.
func _test_log_lines() -> void:
	var rig: Rig = _start()
	if rig == null:
		_check("size: the rig starts", false)
		return
	var client_id: int = rig.harness.peer_id(1)
	var lines: LineCatcher = LineCatcher.new()
	OS.add_logger(lines)
	var asked: bool = rig.relay(1).request_sync({"battle": [], "seqs": [], "fresh": false})
	rig.harness.step_until_idle()
	OS.remove_logger(lines)
	_stop(rig)
	var request_size: int = NetRelayScript._size_of([{"battle": [], "seqs": [], "fresh": false}])
	var relay_lines: PackedStringArray = lines.containing("NetRelay: ")
	var wanted: PackedStringArray = [
		"NetRelay: sent request_sync, %d B, to peer 1." % [request_size],
		"NetRelay: received request_sync, %d B, from peer %d." % [request_size, client_id],
	]
	var has_all: bool = asked
	for line: String in wanted:
		has_all = has_all and _has_line(relay_lines, line)
	var sync_sent: String = _first_with(relay_lines, "NetRelay: sent sync, ")
	var sync_got: String = _first_with(relay_lines, "NetRelay: received sync, ")
	var sync_size: String = sync_sent.get_slice(", ", 1)
	_check("size: each relay message sent and received is one NetLog line (kind, size, peer)", (
			has_all
			and relay_lines.size() == 4
			and sync_sent.ends_with("to peer %d." % [client_id])
			and sync_got.ends_with("from peer 1.")
			and sync_size.ends_with(" B")
			and sync_got.get_slice(", ", 1) == sync_size
	), "\n".join(relay_lines))


func _test_fingerprint() -> void:
	var parts: Dictionary = NetContract.format_parts()
	var relay_rpcs: Dictionary = (parts["rpc"] as Dictionary).get("NetRelay", {})
	var packed_only: Array = [["packed", TYPE_PACKED_BYTE_ARRAY, ""]]
	var sync_entry: Dictionary = relay_rpcs.get("_sync", {})
	var batch_entry: Dictionary = relay_rpcs.get("_campaign_batch", {})
	var submit_entry: Dictionary = relay_rpcs.get("_submit_combat", {})
	var submit_names: Array = []
	for argument: Array in submit_entry.get("args", []):
		submit_names.append(argument[0])
	var version: String = SaveFile.get_running_version()
	var base: int = NetContract.combine(version, parts, "content")
	var four_args: Dictionary = parts.duplicate(true)
	var four_rpcs: Dictionary = four_args["rpc"]
	var four_relay: Dictionary = four_rpcs["NetRelay"]
	var four_sync: Dictionary = four_relay["_sync"]
	four_sync["args"] = [
		["run", TYPE_DICTIONARY, ""], ["battle", TYPE_DICTIONARY, ""],
		["facts", TYPE_ARRAY, ""], ["screen", TYPE_INT, ""],
	]
	var other_pack: Dictionary = parts.duplicate(true)
	other_pack["NetRelay.pack_format"] = NetRelayScript._PACK_FORMAT + 1
	# Typed, since a comparison of a Dictionary's Variant values is a Variant.
	var is_covered: bool = (
			sync_entry.get("args", []) == packed_only
			and batch_entry.get("args", []) == packed_only
			and submit_names == ["wire", "session_id", "token"]
			and parts.get("NetRelay.pack_format", -1) == NetRelayScript._PACK_FORMAT
			and NetContract.combine(version, four_args, "content") != base
			and NetContract.combine(version, other_pack, "content") != base
	)
	_check("size: the fingerprint covers every RPC's arguments and the pack format", (
			is_covered
	), "%s; %s" % [sync_entry, submit_names])


# The run's capture as the host's relay sends it, from a relay that follows made only meanwhile.
func _capture(made: CampaignSession) -> Dictionary:
	var relay: NetRelayScript = NetRelayScript.new()
	relay._follow(made)
	var captured: Dictionary = relay._capture_run()
	relay._follow(null)
	relay.free()
	return captured


# The Powder Keep for made's four seats, each the bench's six units, turn 1 at once.
func _begin_boss(made: CampaignSession, catalog: EffectCatalog.Index) -> CombatEncounter:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BOSS_FLOOR
	request.node = BOSS_NODE
	request.pool = [load(KEEP_PATH) as CombatMapDefinition]
	request.catalog = catalog
	for seat: int in SEATS:
		var mercenary: StartingArmy = StartingArmy.build(catalog, "mercenary", made.ids)
		var army: CampaignSession.Army = CampaignSession.Army.new()
		army.unit_instances = mercenary.units
		army.item_instances = mercenary.items
		army.heirloom_ids = mercenary.heirloom_ids.duplicate()
		for type_id: String in RECRUITS:
			var unit: UnitInstance = UnitInstance.new(made.ids.next_unit_id(type_id), type_id)
			var definition: UnitTypeDefinition = unit.definition(catalog)
			if definition != null and not definition.starting_weapon_id.is_empty():
				unit.weapon_id = made.ids.next_item_id(definition.starting_weapon_id)
				army.item_instances[unit.weapon_id] = ItemInstance.new(
						unit.weapon_id, definition.starting_weapon_id
				)
			army.unit_instances.append(unit)
		request.opening_swap[seat] = false
		request.armies[seat] = army
	return made.begin_battle(request)


# board (bench_boards.gd), engaged, played BOARD_PHASES player phases by the M1 driver; its largest
# batch as it travels.
func _largest_board_batch(board: String, catalog: EffectCatalog.Index) -> int:
	var boards: BenchBoards = BenchBoards.new(catalog)
	boards.is_verbose = false
	var session: CombatSession = boards.build(board)
	var largest: int = 0
	if session == null:
		boards.close()
		return largest
	var driver: M1BattleCases = M1BattleCases.new(_ignore)
	for _phase: int in BOARD_PHASES:
		if session.is_finished:
			break
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			if session.is_finished:
				break
			largest = maxi(largest, _resolve_alone(session, driver._turn_for(session, unit_id)))
		if not session.is_finished:
			largest = maxi(largest, _resolve_alone(session, EndTurnCommand.new(0)))
	boards.close()
	return largest


func _resolve_alone(session: CombatSession, command: Command) -> int:
	session.submit(command)
	var batch: CombatSession.FactBatch = session.resolve_next()
	return 0 if batch == null else NetRelayScript._size_of([batch.to_wire()])


# _sync's arguments with something in each slot, for the pack cases.
static func _sample_sync() -> Array:
	return [
		{"campaign_map": {"floor": 3, "nodes": [1, 2, 3]}, "seats": {0: {"seat_army": {}}}},
		{"format": 3, "sessions": [{"combat_state": {"units": ["u1", "u2"]}}]},
		[[1, 0, "", 4, 0]],
		SceneRouter.Screen.GAMEPLAY,
	]


# value packed as _pack() packs an Array, so only its type is wrong.
static func _pack_value(value: Variant) -> PackedByteArray:
	var raw: PackedByteArray = var_to_bytes(value)
	var packed: PackedByteArray = PackedByteArray()
	packed.resize(NetRelayScript._PACK_DIGEST_AT)
	packed.encode_u8(0, NetRelayScript._PACK_FORMAT)
	packed.encode_u32(NetRelayScript._PACK_SIZE_AT, raw.size())
	packed.append_array(NetRelayScript._md5(raw))
	packed.append_array(raw.compress(NetRelayScript._PACK_MODE))
	return packed


static func _bytes(count: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count)
	return bytes


static func _has_line(lines: PackedStringArray, wanted: String) -> bool:
	for line: String in lines:
		if line.ends_with(wanted):
			return true
	return false


static func _first_with(lines: PackedStringArray, part: String) -> String:
	for line: String in lines:
		if line.contains(part):
			return line
	return ""


static func _ignore(_case_name: String, _passed: bool, _detail: String = "") -> void:
	pass


# A host and one seated client, each with a relay; no run.
func _start() -> Rig:
	var rig: Rig = Rig.new()
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(1):
		rig.harness.stop()
		return null
	var directory: SeatDirectory = SeatDirectory.new()
	directory.add_seat(CampaignData.HOST_SEAT, 1, rig.harness.peer_id(HOST))
	directory.add_seat(1, 2, rig.harness.peer_id(1))
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		relay.seats = directory
		rig.relays.append(relay)
	return rig


func _stop(rig: Rig) -> void:
	rig.harness.stop()


class Rig:
	extends RefCounted

	var harness: NetHarness = null
	var relays: Array[Node] = []

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript


# Keeps every printed line while it is added with OS.add_logger. The engine may call a logger
# from any thread, so the list is locked.
class LineCatcher:
	extends Logger

	var _lines: PackedStringArray = []
	var _lock: Mutex = Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_lock.lock()
		_lines.append(message.strip_edges())
		_lock.unlock()

	## The lines that contain [param part], in order.
	func containing(part: String) -> PackedStringArray:
		_lock.lock()
		var found: PackedStringArray = []
		for line: String in _lines:
			if line.contains(part):
				found.append(line)
		_lock.unlock()
		return found
