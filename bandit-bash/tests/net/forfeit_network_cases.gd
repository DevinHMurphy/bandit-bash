# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forfeit_network_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Forfeits and removals over the network, in the harness for tests/net/run_all.gd, at 2, 3 and 4
## seats, every client acting through its [ClientMirror] and its own seat directory: the last
## client forfeits on the map, and mid-battle on its own map; the host removes it, dropped, after
## the wait, mid-battle, through [SeatWaitOverlay]'s Remove. The leaver hears its forfeit's batch
## and settle, then its archive record (forfeited, every seat listed), and nobody else's removal;
## a removed player gets no record. The rest play on to the battle's end and back to the map, every
## mirror's map and encounter hash equal to the host's after each batch, after the forfeit's
## campaign batch and after the battle, each holding the seats left. Needs a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

const HOST: int = NetHarness.HOST
const HOST_SEAT: int = CampaignData.HOST_SEAT

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000801

const SAVE_NUMBER: int = 1

# What a client's log records, in order (Rig.events).
const BATCH: String = "batch"
const SETTLED: String = "settled"
const LEFT: String = "left"
const REMOVED: String = "removed"


func run() -> void:
	if not _has_test_user_dir():
		_skip("forfeit network: every case", "needs a test user folder (see run_all.gd)")
		return
	for seat_count: int in [2, 3, 4]:
		_test_map_forfeit(seat_count)
		_test_battle_forfeit(seat_count)
		_test_removal(seat_count)


# The last client forfeits on the map; the seats left vote a node and enter it.
func _test_map_forfeit(seat_count: int) -> void:
	var tag: String = "forfeit network %d seats, map:" % [seat_count]
	var rig: Rig = _start(seat_count, false)
	if rig == null:
		_check("%s the rig starts on the map" % [tag], false)
		return
	var leaver: int = seat_count - 1
	var archived_before: int = _archive_count()
	var archived: Array[Error] = []
	rig.relay(leaver).left_run.connect(
			func(record: ArchiveRecord) -> void:
				if record != null:
					archived.append(SaveService.archive_forfeit_record(record))
	)
	rig.clear_events()
	rig.mirror(leaver).submit_campaign(ForfeitCommand.new(leaver))
	rig.harness.step_until_idle()
	var left: PackedInt32Array = _seats_but(seat_count, leaver)
	_check_leaver(tag, rig, leaver, left)
	_check("%s the leaver's mirror keeps its run, and its record is archived" % [tag], (
			rig.mirror(leaver).session.seats.has(leaver)
			and archived == [OK]
			and _archive_count() == archived_before + 1
	), "%s, %d archived" % [archived, _archive_count() - archived_before])
	rig.without(leaver)
	_check("%s every other mirror equals the host, without the seat" % [tag], (
			rig.difference().is_empty()
	), rig.difference())

	# One seat left chooses its route alone, as a run of one seat does.
	var node: int = _standard_node(rig.session)
	if left.size() == 1:
		_campaign(rig, HOST_SEAT, ChooseNodeCommand.new(HOST_SEAT, node))
	else:
		for seat: int in left:
			_campaign(rig, seat, RouteVoteCommand.for_session(rig.session, seat, node))
	_check("%s the seats left go on to a node and enter it, every mirror equal" % [tag], (
			rig.session.run.flow.stage == RunFlow.Stage.NODE
			and rig.session.run.node == node
			and rig.difference().is_empty()
	), rig.difference())
	_stop(rig)


# The last client forfeits mid-battle on its own map; the rest win theirs and leave the node.
func _test_battle_forfeit(seat_count: int) -> void:
	var tag: String = "forfeit network %d seats, battle:" % [seat_count]
	var rig: Rig = _start(seat_count, true)
	if rig == null:
		_check("%s the rig starts in a battle" % [tag], false)
		return
	var leaver: int = seat_count - 1
	rig.clear_events()
	rig.mirror(leaver).submit_campaign(ForfeitCommand.new(leaver))
	rig.harness.step_until_idle()
	var battle: CombatEncounter = rig.session.encounter
	_check_leaver(tag, rig, leaver, _seats_but(seat_count, leaver))
	rig.without(leaver)
	_check("%s every mirror keeps its battle, the map forfeited, equal after the campaign batch" % [
		tag,
	], (
			battle.forfeited_seats() == PackedInt32Array([leaver])
			and rig.every_mirror_forfeited(leaver)
			and rig.after_campaign_batch_equal()
			and rig.failures.is_empty()
			and rig.difference().is_empty()
	), "%s; %s; %s" % [rig.after_campaign, rig.failures, rig.difference()])
	_play_on(tag, rig, battle, leaver)
	_stop(rig)


# The last client drops mid-battle; after the wait the host's Remove takes it out.
func _test_removal(seat_count: int) -> void:
	var tag: String = "forfeit network %d seats, removal:" % [seat_count]
	var rig: Rig = _start(seat_count, true)
	if rig == null:
		_check("%s the rig starts in a battle" % [tag], false)
		return
	var leaver: int = seat_count - 1
	var archived_before: int = _archive_count()
	rig.harness.drop(leaver)
	rig.harness.step_until_idle()
	rig.without(leaver)
	var host_relay: NetRelayScript = rig.relay(HOST)
	host_relay._process(NetRelayScript.REMOVE_WAIT)
	var overlay: SeatWaitOverlay = _overlay_of(host_relay)
	var remove: Button = null
	if overlay != null:
		remove = overlay.get_node(^"%RemoveButton") as Button
		overlay.refresh()
	_check("%s the host waits for the dropped seat, then offers Remove" % [tag], (
			host_relay.is_paused()
			and remove != null and remove.visible
			and remove.text == "Remove %s" % [CampaignLink.seat_name(leaver)]
	), "no overlay" if remove == null else remove.text)
	if remove == null:
		_stop(rig)
		return
	rig.clear_events()
	remove.pressed.emit()
	rig.harness.step_until_idle()
	var battle: CombatEncounter = rig.session.encounter
	var heard_removal: bool = true
	for index: int in rig.clients():
		heard_removal = heard_removal and rig.events[index].has("%s %d" % [REMOVED, leaver])
	_check("%s Remove takes the seat out of the battle and the run; everyone hears it" % [tag], (
			battle != null and battle.forfeited_seats() == PackedInt32Array([leaver])
			and host_relay.seats.state_of(leaver) == SeatDirectory.State.REMOVED
			and not host_relay.is_paused()
			and not _seats_of(SaveService.campaign.players).has(leaver)
			and heard_removal
			and rig.every_mirror_forfeited(leaver)
			and rig.failures.is_empty()
			and rig.difference().is_empty()
	), "%s; %s; %s" % [rig.events, rig.failures, rig.difference()])
	_check("%s the removed player gets no archive record" % [tag], (
			not rig.events[leaver].has(LEFT)
			and SaveService.take_forfeit_record(leaver) == null
			and _archive_count() == archived_before
	), "%s" % [rig.events[leaver]])
	_play_on(tag, rig, battle, leaver)
	_stop(rig)


# The leaver heard its forfeit's batch, its settle and then its record, and no removal; every
# other client heard the batch, then the removal; the host lets the seat go, and the campaign
# keeps only the seats left (mid-battle, the seat is set aside until the battle ends).
func _check_leaver(tag: String, rig: Rig, leaver: int, left: PackedInt32Array) -> void:
	var record: ArchiveRecord = rig.records.get(leaver, null)
	var leaver_log: PackedStringArray = rig.events[leaver]
	var others_heard: bool = true
	for index: int in rig.clients():
		if index == leaver:
			continue
		var heard: PackedStringArray = rig.events[index]
		var removed_at: int = heard.find("%s %d" % [REMOVED, leaver])
		others_heard = others_heard and removed_at > heard.find(BATCH) and heard.find(BATCH) >= 0
	_check("%s the leaver gets its batch, its settle, then its record, first" % [tag], (
			leaver_log == PackedStringArray([BATCH, SETTLED, LEFT])
			and rig.settles[leaver] == [""]
			and record != null and record.forfeited and not record.won
			and record.players.size() == left.size() + 1
	), "%s, %s, %s" % [
		leaver_log, rig.settles[leaver], "no record" if record == null else record.forfeited,
	])
	_check("%s the host lets the seat go; the others hear it removed" % [tag], (
			rig.relay(HOST).seats.state_of(leaver) == SeatDirectory.State.REMOVED
			and _seats_of(SaveService.campaign.players) == left
			and SaveService.take_forfeit_record(leaver) == null
			and others_heard
	), "%s" % [rig.events])


# The seats left win their maps and the battle ends without the seat that left; each seat skips
# its item pick and the team leaves the node, every mirror equal to the host throughout.
func _play_on(tag: String, rig: Rig, battle: CombatEncounter, leaver: int) -> void:
	var checks_before: int = rig.checks
	for seat: int in rig.session.run.seat_numbers():
		if seat != leaver:
			_win(battle.session_of_seat(seat))
	rig.harness.step_until_idle()
	# With two seats, nobody is left to mirror the host.
	var is_mirrored: bool = not rig.clients().is_empty()
	_check("%s the maps left are won, every batch's hash matching" % [tag], (
			battle.is_finished()
			and (rig.checks > checks_before or not is_mirrored) and rig.failures.is_empty()
			and rig.difference().is_empty()
	), "%d checked; %s; %s" % [rig.checks - checks_before, rig.failures, rig.difference()])
	var result: CampaignSession.BattleResult = CampaignService.end_battle()
	rig.harness.step_until_idle()
	var left: PackedInt32Array = _seats_but(rig.harness.size(), leaver)
	_check("%s the battle ends without the seat; each mirror takes the host's run" % [tag], (
			result != null and result.forfeited == PackedInt32Array([leaver])
			and rig.session.encounter == null
			and rig.session.seats == left
			and SaveService.campaign.departed.is_empty()
			and rig.difference().is_empty()
	), rig.difference())
	for seat: int in left:
		_campaign(rig, seat, ItemPickCommand.new(seat, ItemPickCommand.SKIP))
	_campaign(rig, HOST_SEAT, LeaveNodeCommand.new(HOST_SEAT))
	_check("%s the team goes back to the map, every mirror equal" % [tag], (
			rig.session.run.is_on_map() and rig.difference().is_empty()
	), rig.difference())


# A multiplayer run of seat_count seats through SaveService, no starting offers, on the map, or
# with in_battle inside a floor-1 Standard node by every seat's vote, its battle open on every
# mirror and every seat's Start settled. A harness with a relay per branch (its own directory) and
# a started mirror per client. Null when any of it fails.
func _start(seat_count: int, in_battle: bool) -> Rig:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	var steam_ids: PackedInt64Array = []
	for seat: int in seat_count:
		steam_ids.append(FIRST_STEAM_ID + seat)
	var session: CampaignSession = null
	if SaveService.start_new_multiplayer_run(steam_ids) == OK:
		session = CampaignService.session
	if session == null or session.run == null:
		_end_run()
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var rig: Rig = Rig.new()
	rig.session = session
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(seat_count - 1):
		_stop(rig)
		return null
	for index: int in rig.harness.size():
		var directory: SeatDirectory = SeatDirectory.new()
		for seat: int in seat_count:
			directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
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
	if in_battle and not _open_battle(rig):
		_stop(rig)
		return null
	if rig.difference() != "" or not rig.every_mirror_built():
		_stop(rig)
		return null
	return rig


# Every seat votes the first Standard node; the battle begins, is pushed, and every seat starts
# its map, each client's Start settling with no refusal.
func _open_battle(rig: Rig) -> bool:
	var node: int = _standard_node(rig.session)
	for seat: int in rig.session.run.seat_numbers():
		CampaignService.submit_command(RouteVoteCommand.for_session(rig.session, seat, node))
	if rig.session.run.flow.stage != RunFlow.Stage.NODE:
		return false
	var request: CampaignSession.BattleRequest = rig.session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null or CampaignService.begin_battle(request) != OK:
		return false
	rig.harness.step_until_idle()
	rig.relay(HOST)._process(0.0)
	rig.harness.step_until_idle()
	var battle: CombatEncounter = rig.session.encounter
	CampaignService.submit_combat(
			StartCommand.new(HOST_SEAT), battle.session_of_seat(HOST_SEAT).session_id
	)
	for index: int in rig.clients():
		rig.mirror(index).submit_combat(
				StartCommand.new(index), battle.session_of_seat(index).session_id
		)
	rig.harness.step_until_idle()
	for index: int in rig.clients():
		if rig.settles[index].size() != 1 or rig.settles[index][0] != "":
			return false
		rig.settles[index].clear()
	return rig.failures.is_empty()


# Sends command for seat as that seat does: the host seat's on the host, a client's through its
# mirror (branch index is the seat here). Then lets the network settle.
func _campaign(rig: Rig, seat: int, command: CampaignCommand) -> void:
	if seat == HOST_SEAT:
		CampaignService.submit_command(command)
	else:
		rig.mirror(seat).submit_campaign(command)
	rig.harness.step_until_idle()


# The first Standard node the run can choose next; NO_NODE when there is none.
func _standard_node(session: CampaignSession) -> int:
	for node: int in session.run.next_nodes():
		if session.run.graph.type_of(node) == CampaignGraph.NodeType.STANDARD:
			return node
	return CampaignGraph.NO_NODE


# Ends map as won outside any command, sent as its own batch.
func _win(map: CombatSession) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	map.engine.record(ended)
	map.flush("test win")


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


# The records in the open save file's archive.
func _archive_count() -> int:
	var folder: String = SaveService.get_save_file_dir(SAVE_NUMBER) + ArchiveRecord.FOLDER_NAME
	if not DirAccess.dir_exists_absolute(folder):
		return 0
	return DirAccess.get_files_at(folder).size()


func _overlay_of(relay: NetRelayScript) -> SeatWaitOverlay:
	for child: Node in relay.get_children():
		if child is SeatWaitOverlay:
			return child as SeatWaitOverlay
	return null


# Seats 0 to seat_count - 1, but skipped.
func _seats_but(seat_count: int, skipped: int) -> PackedInt32Array:
	var kept: PackedInt32Array = []
	for seat: int in seat_count:
		if seat != skipped:
			kept.append(seat)
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


# One case's peers: the host's session, the harness, each branch's relay and mirror (branch index
# is the seat), by client what its relay settled, what it heard in order (events), the record it
# was given, how its battle differed from the host's right after each campaign batch, and every
# map or encounter batch whose hash a mirror didn't match as it applied.
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var mirrors: Array[ClientMirror] = []
	var settles: Dictionary[int, Array] = {}
	var events: Dictionary[int, PackedStringArray] = {}
	var records: Dictionary[int, ArchiveRecord] = {}
	var after_campaign: Dictionary[int, String] = {}
	var checks: int = 0
	var failures: PackedStringArray = []
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

	func without(index: int) -> void:
		_left[index] = true

	func clear_events() -> void:
		for index: int in events:
			events[index] = PackedStringArray()
			settles[index].clear()
		after_campaign.clear()

	# A mirror for client branch index, not started. Heard after the mirror, which connected first,
	# so each check sees the batch applied.
	func add_mirror(index: int) -> void:
		var client: NetRelayScript = relay(index)
		mirrors[index] = ClientMirror.new(client, session.rng.run_seed)
		settles[index] = []
		events[index] = PackedStringArray()
		client.command_settled.connect(_on_settled.bind(index))
		client.campaign_batch_received.connect(_on_campaign_batch.bind(index))
		client.left_run.connect(_on_left_run.bind(index))
		client.seat_removed.connect(_on_seat_removed.bind(index))
		client.combat_batch_received.connect(_check_map.bind(index))
		client.encounter_batch_received.connect(_check_encounter.bind(index))

	func every_mirror_built() -> bool:
		for index: int in clients():
			var copy: CampaignSession = mirror(index).session
			if copy == null or not copy.is_mirror or mirror(index).local_seat() != index:
				return false
		return true

	func every_mirror_forfeited(seat: int) -> bool:
		for index: int in clients():
			var battle: CombatEncounter = mirror(index).session.encounter
			if battle == null or battle.forfeited_seats() != PackedInt32Array([seat]):
				return false
		return true

	func after_campaign_batch_equal() -> bool:
		for index: int in clients():
			if after_campaign.get(index, "unheard") != "":
				return false
		return true

	# The first way a compared client's mirror differs from the host: its seats, its run, its
	# battle, a map or the encounter; empty when every one is equal.
	func difference() -> String:
		for index: int in clients():
			var copy: CampaignSession = mirror(index).session
			if copy == null or copy.run == null:
				return "client %d has no run" % [index]
			if copy.seats != session.seats:
				return "client %d holds seats %s" % [index, copy.seats]
			if RunStateCases.run_text(copy.run) != RunStateCases.run_text(session.run):
				return "client %d's run differs" % [index]
			var battle_gap: String = _battle_difference(copy.encounter)
			if not battle_gap.is_empty():
				return "client %d's %s" % [index, battle_gap]
		return ""

	func _battle_difference(mirrored: CombatEncounter) -> String:
		var host: CombatEncounter = session.encounter
		if (mirrored == null) != (host == null):
			return "battle is %s" % ["missing" if mirrored == null else "extra"]
		if host == null:
			return ""
		if mirrored.state_hash() != host.state_hash():
			return "encounter differs"
		for map: CombatSession in host.get_sessions():
			if mirrored.get_session(map.session_id).state_hash() != map.state_hash():
				return "map %d differs" % [map.session_id]
		return ""

	func _on_settled(_token: int, reason: String, index: int) -> void:
		settles[index].append(reason)
		events[index].append(SETTLED)

	func _on_campaign_batch(_facts: Array, _run: Dictionary, index: int) -> void:
		events[index].append(BATCH)
		var copy: CampaignSession = mirror(index).session
		if copy != null:
			after_campaign[index] = _battle_difference(copy.encounter)

	func _on_left_run(record: ArchiveRecord, index: int) -> void:
		records[index] = record
		events[index].append(LEFT)

	func _on_seat_removed(seat: int, index: int) -> void:
		events[index].append("%s %d" % [REMOVED, seat])

	func _check_map(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var copy: CampaignSession = mirror(index).session
		var battle: CombatEncounter = null if copy == null else copy.encounter
		if (
				_left.has(index) or batch == null or battle == null or batch.is_rejected()
				or batch.state_hash == CombatSession.NO_HASH
		):
			return
		var map: CombatSession = battle.get_session(batch.session_id)
		if map == null or map.last_seq() != batch.last_seq():
			return
		checks += 1
		if map.state_hash() != batch.state_hash:
			failures.append("client %d s%d#%d" % [index, batch.session_id, map.last_seq()])

	func _check_encounter(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var copy: CampaignSession = mirror(index).session
		var battle: CombatEncounter = null if copy == null else copy.encounter
		if _left.has(index) or batch == null or battle == null:
			return
		if batch.state_hash != CombatSession.NO_HASH:
			checks += 1
			if battle.state_hash() != batch.state_hash:
				failures.append("client %d encounter #%d" % [index, batch.last_seq()])
