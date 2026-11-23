# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     mirror_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Client mirror cases for tests/net/run_all.gd ([ClientMirror], [code]NetRelay[/code]'s sync), on
## a real multiplayer run through SaveService and CampaignService with one relay and one mirror
## per client branch: a 2- and a 4-seat run from the map through a battle, its results and the
## map again, every mirror equal to the host after every step and every batch's hash checked as it
## applies; a client's commands settle after their batches and the mirror announces them; a battle
## opened before a mirror exists arrives by snapshot; a lost batch is repaired by catch-up and,
## past a checkpoint, by a fresh snapshot; a debug hash mismatch dumps and resyncs; an unanswered
## request gives up after 15; a mirror resolves nothing; solo is unchanged. Skipped without a
## test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")
const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")

const GAMEPLAY_SCENE: String = "res://ui/battle/gameplay.tscn"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 1

const HOST: int = NetHarness.HOST

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000101

const RUN_SEED: int = 9191

# Where CombatSession.debug_dump() writes.
const DUMP_DIR: String = "user://logs"


func run() -> void:
	if not _has_test_user_dir():
		_skip("mirror: every case", "needs a test user folder (see run_all.gd's class doc)")
		return
	for client_count: int in [1, 3]:
		_test_run(client_count)
	_test_late_open()
	_test_gap_repair()
	_test_mismatch()
	_test_give_up()
	_test_mirror_refuses()
	_test_host_screen()
	_test_client_screen()
	_test_solo()


# Map, battle, results and the map again, with every seat acting.
func _test_run(client_count: int) -> void:
	var tag: String = "mirror %d peers:" % [client_count + 1]
	var rig: Rig = _start(client_count, true)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	_start_mirrors(rig)
	var session: CampaignSession = rig.session
	var built: bool = true
	for index: int in range(1, rig.harness.size()):
		var mirror: ClientMirror = rig.mirror(index)
		built = (
				built
				and mirror.session != null
				and mirror.session.is_mirror
				and not mirror.is_syncing()
				and mirror.local_seat() == index
		)
	_check("%s every client builds its mirror of the host's run" % [tag], (
			built and _difference(rig).is_empty()
	), _difference(rig))

	# The map: every seat votes for the first floor's Standard combat; the last vote enters it.
	var route: PackedInt32Array = Fixture.route_to(
			session.run.graph, CampaignGraph.NodeType.STANDARD
	)
	if route.size() != 1:
		_check("%s the seed has a Standard combat on floor 1" % [tag], false, str(route))
		_stop(rig)
		return
	var node: int = route[0]
	CampaignService.submit_command(RouteVoteCommand.for_session(session, 0, node))
	rig.harness.step_until_idle()
	var settled_in_order: bool = true
	for index: int in range(1, rig.harness.size()):
		rig.clear()
		var token: int = rig.mirror(index).submit_campaign(RouteVoteCommand.new(index, node))
		rig.harness.step_until_idle()
		var events: PackedStringArray = rig.record(index).events
		settled_in_order = (
				settled_in_order
				and events == PackedStringArray(["batch %d" % [index], "settled %d " % [token]])
		)
	_check("%s each client's vote settles after its mirror announces its batch" % [tag], (
			settled_in_order
	), str(rig.record(1).events))
	_check("%s the last vote enters the node on every mirror" % [tag], (
			session.run.flow.stage == RunFlow.Stage.NODE
			and session.run.node == node
			and _difference(rig).is_empty()
	), _difference(rig))

	# The battle: begun on the host, its snapshot pushed the frame after, then every seat plays.
	rig.clear()
	var request: CampaignSession.BattleRequest = session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	var begun: Error = CampaignService.begin_battle(request)
	rig.harness.step_until_idle()
	var waiting: bool = begun == OK
	for index: int in range(1, rig.harness.size()):
		waiting = waiting and rig.mirror(index).session.encounter == null
	_push(rig)
	var mirrored: bool = waiting
	for index: int in range(1, rig.harness.size()):
		mirrored = (
				mirrored
				and rig.mirror(index).session.encounter != null
				and not rig.mirror(index).is_syncing()
				and rig.record(index).snapshots == 1
		)
	_check("%s the battle's pushed snapshot builds every mirror's battle" % [tag], (
			mirrored and _difference(rig).is_empty()
	), "waiting %s; %s" % [waiting, _difference(rig)])
	var battle: CombatEncounter = session.encounter
	if not mirrored or battle == null:
		_stop(rig)
		return

	rig.clear()
	CampaignService.submit_combat(StartCommand.new(0), battle.session_of_seat(0).session_id)
	var starts: Array[int] = []
	for index: int in range(1, rig.harness.size()):
		starts.append(rig.mirror(index).submit_combat(
				StartCommand.new(index), battle.session_of_seat(index).session_id
		))
	rig.harness.step_until_idle()
	var started: bool = true
	for index: int in range(1, rig.harness.size()):
		started = (
				started
				and rig.record(index).settles == [[starts[index - 1], ""]]
				and not battle.session_of_seat(index).state.map.opening_swap_open
		)
	_check("%s clients' Starts resolve on the host and settle; mirrors follow" % [tag], (
			started and _difference(rig).is_empty()
	), "%s; %s" % [rig.record(1).settles, _difference(rig)])

	CampaignService.submit_combat(EndTurnCommand.new(0), battle.session_of_seat(0).session_id)
	for index: int in range(1, rig.harness.size()):
		rig.mirror(index).submit_combat(
				EndTurnCommand.new(index), battle.session_of_seat(index).session_id
		)
	rig.harness.step_until_idle()
	_check("%s every map's enemy phase plays on every mirror" % [tag], (
			_difference(rig).is_empty()
	), _difference(rig))

	for map: CombatSession in battle.get_sessions():
		_win(map)
	rig.harness.step_until_idle()
	var won: bool = true
	for index: int in range(1, rig.harness.size()):
		var held: CombatEncounter = rig.mirror(index).session.encounter
		won = won and held != null
		if held != null:
			for map: CombatSession in held.get_sessions():
				won = won and map.is_finished and map.is_won
	_check("%s every map's end reaches every mirror" % [tag], (
			won and _difference(rig).is_empty()
	), _difference(rig))
	_check("%s every batch's hash matched the host's as it applied" % [tag], (
			rig.hash_checks > 0 and rig.hash_failures.is_empty()
	), "%d checked; %s" % [rig.hash_checks, rig.hash_failures])

	# Results: the battle's end sends the run; each seat settles its pick; a client leaves.
	var result: CampaignSession.BattleResult = CampaignService.end_battle()
	rig.harness.step_until_idle()
	var at_results: bool = result != null and session.run.flow.stage == RunFlow.Stage.RESULTS
	for index: int in range(1, rig.harness.size()):
		at_results = at_results and rig.mirror(index).session.encounter == null
	_check("%s the battle's end closes every mirror's battle at the results" % [tag], (
			at_results and _difference(rig).is_empty()
	), _difference(rig))
	CampaignService.submit_command(ItemPickCommand.new(0, ItemPickCommand.SKIP))
	rig.mirror(1).submit_campaign(ItemPickCommand.new(1, 0))
	for index: int in range(2, rig.harness.size()):
		rig.mirror(index).submit_campaign(ItemPickCommand.new(index, ItemPickCommand.SKIP))
	rig.harness.step_until_idle()
	rig.clear()
	var leave: int = rig.mirror(1).submit_campaign(LeaveNodeCommand.new(1))
	rig.harness.step_until_idle()
	_check("%s each seat's pick and a client's leave bring every mirror back to the map" % [tag], (
			session.run.is_on_map()
			and rig.record(1).settles == [[leave, ""]]
			and _difference(rig).is_empty()
	), "%s; %s" % [rig.record(1).settles, _difference(rig)])
	_stop(rig)


# A battle on before the client's mirror exists: the mirror's first request brings the run and
# the battle as they stand.
func _test_late_open() -> void:
	var rig: Rig = _start(1, false)
	var battle: CombatEncounter = null if rig == null else _open_battle(rig)
	if battle == null:
		_check("mirror late open: the battle opens", false)
		if rig != null:
			_stop(rig)
		return
	CampaignService.submit_combat(StartCommand.new(0), 0)
	CampaignService.submit_combat(EndTurnCommand.new(0), 0)
	rig.harness.step_until_idle()
	rig.add_mirror(1)
	rig.mirror(1).start()
	rig.harness.step_until_idle()
	_check("mirror late open: a mirror started mid-battle gets it by snapshot", (
			rig.mirror(1).session != null
			and rig.mirror(1).session.encounter != null
			and rig.record(1).snapshots == 1
			and _difference(rig).is_empty()
	), "%s; %s" % [rig.record(1).describe(), _difference(rig)])
	var token: int = rig.mirror(1).submit_combat(StartCommand.new(1), 1)
	rig.harness.step_until_idle()
	_check("mirror late open: it follows the battle from there", (
			rig.record(1).settles == [[token, ""]] and _difference(rig).is_empty()
	), _difference(rig))
	_stop(rig)


# A batch lost on the way to one client: the next shows the gap, and the host answers with the
# facts missed; past the map's checkpoint, with a fresh snapshot.
func _test_gap_repair() -> void:
	var rig: Rig = _start(2, true)
	var battle: CombatEncounter = null if rig == null else _open_battle(rig)
	if battle == null:
		_check("mirror gaps: the battle opens", false)
		if rig != null:
			_stop(rig)
		return
	_start_mirrors(rig)
	rig.clear()
	rig.harness.lose_next(HOST, 2, 1)
	CampaignService.submit_combat(StartCommand.new(0), 0)
	var commander: String = battle.get_session(0).state.commander_of(0)
	var wait: UnitTurnCommand = UnitTurnCommand.new(0, commander, UnitTurnCommand.Action.WAIT)
	CampaignService.submit_combat(wait, 0)
	rig.harness.step_until_idle()
	_check("mirror gaps: a lost batch is caught up from the host's facts", (
			rig.record(2).catch_ups == 1
			and rig.record(2).snapshots == 0
			and rig.record(1).catch_ups == 0
			and not rig.mirror(2).is_syncing()
			and _difference(rig).is_empty()
	), "%s; %s" % [rig.record(2).describe(), _difference(rig)])

	rig.clear()
	rig.harness.lose_next(HOST, 2, 1)
	CampaignService.submit_combat(EndTurnCommand.new(0), 0)
	rig.harness.step_until_idle()
	battle.get_session(0).mark_checkpoint()
	_win(battle.get_session(0))
	rig.harness.step_until_idle()
	_check("mirror gaps: past the map's checkpoint, the host sends a fresh snapshot", (
			rig.record(2).snapshots == 1
			and rig.record(2).catch_ups == 0
			and rig.record(1).snapshots == 0
			and not rig.mirror(2).is_syncing()
			and _difference(rig).is_empty()
	), "%s; %s" % [rig.record(2).describe(), _difference(rig)])
	_stop(rig)


# A mirror whose map differs from the host's: the next batch's hash shows it, the map is dumped
# and a fresh snapshot puts it right.
func _test_mismatch() -> void:
	if not OS.is_debug_build():
		_skip("mirror mismatch", "batches carry hashes in debug builds only")
		return
	var rig: Rig = _start(1, true)
	var battle: CombatEncounter = null if rig == null else _open_battle(rig)
	if battle == null:
		_check("mirror mismatch: the battle opens", false)
		if rig != null:
			_stop(rig)
		return
	_start_mirrors(rig)
	rig.clear()
	var mirrored: CombatSession = rig.mirror(1).session.encounter.get_session(0)
	var commander: String = mirrored.state.commander_of(0)
	mirrored.state.unit(commander).hp -= 1
	var dumps_before: int = _dump_count()
	CampaignService.submit_combat(StartCommand.new(0), 0)
	rig.harness.step_until_idle()
	_check("mirror mismatch: a differing map is dumped and resynced from a fresh snapshot", (
			rig.record(1).snapshots == 1
			and _dump_count() == dumps_before + 1
			and not rig.mirror(1).is_syncing()
			and _difference(rig).is_empty()
	), "%s; dumps %d -> %d; %s" % [
		rig.record(1).describe(), dumps_before, _dump_count(), _difference(rig),
	])
	_stop(rig)


# A host that never answers (the client holds no seat): the mirror asks 15 times, 1.0 s apart,
# then gives up.
func _test_give_up() -> void:
	var rig: Rig = _start(1, true, 0)
	if rig == null:
		_check("mirror retry: the rig starts", false)
		return
	var mirror: ClientMirror = rig.mirror(1)
	var gave_up: Array[int] = []
	mirror.sync_gave_up.connect(func(attempts: int) -> void: gave_up.append(attempts))
	mirror.start()
	rig.harness.step_until_idle()
	for _second: int in ClientMirror.SYNC_ATTEMPTS - 1:
		mirror.advance(ClientMirror.SYNC_INTERVAL / 2.0)
		mirror.advance(ClientMirror.SYNC_INTERVAL / 2.0)
		rig.harness.step_until_idle()
	var asking: bool = mirror.is_syncing() and gave_up.is_empty()
	mirror.advance(ClientMirror.SYNC_INTERVAL)
	_check("mirror retry: an unanswered request is sent 15 times, then given up", (
			asking
			and gave_up == [ClientMirror.SYNC_ATTEMPTS]
			and not mirror.is_syncing()
			and mirror.session == null
	), "%s, %s" % [asking, gave_up])
	_stop(rig)


func _test_mirror_refuses() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	made.is_mirror = true
	var batch: CampaignBatch = made.submit(LeaveNodeCommand.new(1))
	Fixture.enter(made.run, CampaignGraph.NodeType.STANDARD)
	var request: CampaignSession.BattleRequest = made.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	_check("mirror refuses: a mirror resolves no command and begins no battle", (
			batch != null
			and batch.rejected_reason == "a mirror doesn't resolve commands"
			and request != null
			and made.begin_battle(request) == null
			and made.encounter == null
	))


# A co-op host's battle screen: it begins the battle and shows the host's own map, another map's
# player phase end saves the battle, and the host's map ending first doesn't end the battle.
func _test_host_screen() -> void:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	var steam_ids: PackedInt64Array = [FIRST_STEAM_ID, FIRST_STEAM_ID + 1]
	var run: CampaignSession = null
	if SaveService.start_new_multiplayer_run(steam_ids) == OK:
		run = CampaignService.session
	if run == null or not Fixture.enter(run.run, CampaignGraph.NodeType.STANDARD):
		_check("mirror host screen: a co-op run reaches a Standard combat", false)
		_end_run()
		return
	for seat: int in run.run.seat_numbers():
		run.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var screen: BattleScreen = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	# No hold, so a battle that ended with the host's map would end inside this case.
	screen.end_banner_time = 0.0
	_root.add_child(screen)
	var view: BattleView = screen.get_view()
	var battle: CombatEncounter = run.encounter
	var placeholder: Control = screen.get_node(^"%CoopPlaceholder")
	_check("mirror host screen: a co-op host's battle begins on its own map, no placeholder", (
			battle != null
			and battle.get_sessions().size() == 2
			and view.get_session() == battle.session_of_seat(CampaignData.HOST_SEAT)
			and not placeholder.visible
	))
	if battle == null:
		screen.free()
		_end_run()
		return
	var before: int = _combat_checkpoint()
	CampaignService.submit_combat(StartCommand.new(1), 1)
	CampaignService.submit_combat(EndTurnCommand.new(1), 1)
	var after: int = _combat_checkpoint()
	_check("mirror host screen: the teammate's player phase end saves the battle", (
			before >= 0 and after > before
	), "checkpoint %d -> %d" % [before, after])
	_win(battle.session_of_seat(CampaignData.HOST_SEAT))
	BattleViewCases.settle(view)
	_check("mirror host screen: the host's map ending first leaves the battle on", (
			run.encounter == battle
			and not battle.is_closed
			and run.run.flow.stage == RunFlow.Stage.NODE
	))
	screen.free()
	_end_run()


# A client's battle screen on its mirror: it shows the mirror's battle on its own map, never
# begins one, waits for the host's settle before taking input again, and its map ending doesn't
# end the battle. Off the network the mirror stands in as the run's session; its battle resolves
# nothing (CampaignService.submit_combat refuses a mirror's), so the settles are emitted here.
func _test_client_screen() -> void:
	var rig: Rig = _start(1, true)
	var battle: CombatEncounter = null if rig == null else _open_battle(rig)
	if battle == null:
		_check("mirror client screen: the battle opens", false)
		if rig != null:
			_stop(rig)
		return
	_start_mirrors(rig)
	var copy: CampaignSession = rig.mirror(1).session
	var host: CampaignSession = CampaignService.session
	CampaignService.session = copy
	CampaignService.set_local_seat(1)
	var screen: BattleScreen = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	screen.end_banner_time = 0.0
	_root.add_child(screen)
	var view: BattleView = screen.get_view()
	var controller: BattleController = screen.get_controller()
	var own: CombatSession = copy.encounter.session_of_seat(1)
	_check("mirror client screen: it shows the mirror's battle on the client's own map", (
			view.get_session() == own
			and copy.encounter != null
			and host.encounter == battle
			and controller.is_accepting_input()
	))
	controller.request_start()
	BattleViewCases.settle(view)
	var waited: bool = not controller.is_accepting_input()
	CampaignService.combat_settled.emit(own.session_id, "")
	BattleViewCases.settle(view)
	_check("mirror client screen: a sent command waits for the host's settle, then rebuilds", (
			waited and controller.is_accepting_input()
	), "waited %s" % [waited])

	CampaignService.session = host
	_win(battle.session_of_seat(1))
	rig.harness.step_until_idle()
	CampaignService.session = copy
	BattleViewCases.settle(view)
	_check("mirror client screen: the client's map ending leaves the battle to the host", (
			own.is_finished
			and copy.encounter != null
			and host.encounter == battle
			and not battle.is_closed
	))
	screen.free()
	CampaignService.set_local_seat(CampaignData.HOST_SEAT)
	CampaignService.session = host
	_stop(rig)


func _test_solo() -> void:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(1)
	SaveService.start_new_solo_run(RUN_SEED)
	var session: CampaignSession = CampaignService.session
	if session == null or session.run == null:
		_check("mirror solo: a solo run starts", false)
		SaveService.close_save_file()
		return
	var begun: Error = FAILED
	if Fixture.enter(session.run, CampaignGraph.NodeType.STANDARD):
		begun = CampaignService.begin_battle(session.run.battle_request(
				CombatMapPools.load_default(), EffectCatalog.index()
		))
	var batches: Array[CombatSession.FactBatch] = []
	if begun == OK:
		batches = CampaignService.submit_combat(StartCommand.new(0), 0)
	_check("mirror solo: no mirror, the host seat, and a command resolves at once", (
			not session.is_mirror
			and CampaignService.local_seat() == CampaignData.HOST_SEAT
			and begun == OK
			and batches.size() == 1
			and not batches[0].is_rejected()
	))
	SaveService.abandon_run(CampaignData.Mode.SOLO)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# A multiplayer run of client_count + 1 seats through SaveService, no starting offers left, and a
# harness with a relay under each branch and, when with_mirrors, a mirror per client, not yet
# started. Every peer reads one directory, seating the host and the first seated_clients clients
# (-1: all). Null, with everything undone, when any of it fails.
func _start(client_count: int, with_mirrors: bool, seated_clients: int = -1) -> Rig:
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
	var directory: SeatDirectory = SeatDirectory.new()
	directory.add_seat(CampaignData.HOST_SEAT, FIRST_STEAM_ID, rig.harness.peer_id(HOST))
	var seated: int = client_count if seated_clients < 0 else seated_clients
	for seat: int in range(1, seated + 1):
		directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		relay.seats = directory
		rig.relays.append(relay)
		rig.records.append(Record.new())
		rig.mirrors.append(null)
	if with_mirrors:
		for index: int in range(1, rig.harness.size()):
			rig.add_mirror(index)
	return rig


# Starts every client's mirror and lets the host answer.
func _start_mirrors(rig: Rig) -> void:
	for index: int in range(1, rig.harness.size()):
		rig.mirror(index).start()
	rig.harness.step_until_idle()


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


# Puts the rig's run inside its first Standard combat and begins the battle there with its save;
# null when it can't.
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
	return rig.session.encounter


# The host relay's frame after a battle opened: its snapshot goes out.
func _push(rig: Rig) -> void:
	rig.relay(HOST)._process(0.0)
	rig.harness.step_until_idle()


# Ends map as won outside any command, sent as its own batch.
func _win(map: CombatSession) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	map.engine.record(ended)
	map.flush("test win")


# The first way a client's mirror differs from the host: its run, its battle, a map or the
# encounter; empty when every mirror is equal.
func _difference(rig: Rig) -> String:
	var host: CampaignSession = rig.session
	for index: int in range(1, rig.harness.size()):
		var mirror: ClientMirror = rig.mirror(index)
		if mirror == null:
			continue
		var copy: CampaignSession = mirror.session
		if copy == null or copy.run == null:
			return "client %d has no run" % [index]
		if RunStateCases.run_text(copy.run) != RunStateCases.run_text(host.run):
			return "client %d's run differs" % [index]
		if (copy.encounter == null) != (host.encounter == null):
			var state: String = "missing" if copy.encounter == null else "extra"
			return "client %d's battle is %s" % [index, state]
		if host.encounter == null:
			continue
		if copy.encounter.state_hash() != host.encounter.state_hash():
			return "client %d's encounter differs" % [index]
		for map: CombatSession in host.encounter.get_sessions():
			if copy.encounter.get_session(map.session_id).state_hash() != map.state_hash():
				return "client %d's map %d differs" % [index, map.session_id]
	return ""


# The multiplayer combat file's checkpoint number; -1 when it can't be read.
func _combat_checkpoint() -> int:
	var folder: String = SaveService.get_save_file_dir(SAVE_NUMBER)
	var result: SaveFile.ReadResult = SaveFile.read(
			folder + CombatData.get_file_name(CampaignData.Mode.MULTIPLAYER)
	)
	var loaded: CombatData = CombatData.new()
	if result.error != OK or loaded.load_envelope(result.envelope) != OK:
		return -1
	return loaded.checkpoint_seq


func _dump_count() -> int:
	var count: int = 0
	for file: String in DirAccess.get_files_at(DUMP_DIR):
		if file.begins_with("combat_dump_"):
			count += 1
	return count


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# One case's peers: the run's session, the harness, and each branch's relay, mirror and record.
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var mirrors: Array[ClientMirror] = []
	var records: Array[Record] = []
	# Every batch a mirror applied whose host hash could be compared, and each that differed.
	var hash_checks: int = 0
	var hash_failures: PackedStringArray = []

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func mirror(index: int) -> ClientMirror:
		return mirrors[index]

	func record(index: int) -> Record:
		return records[index]

	func clear() -> void:
		for each: Record in records:
			each.clear()

	# A mirror for client branch index, not started; its record and the hash checks hear the
	# relay after it, so they see what it applied.
	func add_mirror(index: int) -> void:
		var client: NetRelayScript = relay(index)
		var made: ClientMirror = ClientMirror.new(client, session.rng.run_seed)
		mirrors[index] = made
		var heard: Record = records[index]
		client.command_settled.connect(heard.on_settled)
		client.sync_received.connect(heard.on_sync)
		client.combat_batch_received.connect(_check_map.bind(index))
		client.encounter_batch_received.connect(_check_encounter.bind(index))
		made.session_built.connect(heard.on_session_built)

	# After the mirror applied a map batch: its map's hash against the host's, when comparable.
	func _check_map(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = _battle_of(index)
		if (
				batch == null or battle == null or batch.is_rejected()
				or batch.state_hash == CombatSession.NO_HASH
		):
			return
		var map: CombatSession = battle.get_session(batch.session_id)
		if map == null or map.last_seq() != batch.last_seq():
			return
		hash_checks += 1
		if map.state_hash() != batch.state_hash:
			hash_failures.append("client %d s%d#%d" % [index, batch.session_id, map.last_seq()])

	func _check_encounter(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = _battle_of(index)
		if batch == null or battle == null or batch.state_hash == CombatSession.NO_HASH:
			return
		hash_checks += 1
		if battle.state_hash() != batch.state_hash:
			hash_failures.append("client %d encounter #%d" % [index, batch.last_seq()])

	func _battle_of(index: int) -> CombatEncounter:
		var copy: CampaignSession = mirror(index).session
		return null if copy == null else copy.encounter


# What one client heard: its mirror's campaign batches and its settles as events in order, every
# settle, and the syncs it got that held a snapshot or catch-up facts.
class Record:
	extends RefCounted

	var events: PackedStringArray = []
	var settles: Array = []
	var catch_ups: int = 0
	var snapshots: int = 0

	func clear() -> void:
		events.clear()
		settles.clear()
		catch_ups = 0
		snapshots = 0

	func describe() -> String:
		return "catch-ups %d, snapshots %d" % [catch_ups, snapshots]

	func on_session_built(built: CampaignSession) -> void:
		built.campaign_batch_resolved.connect(on_batch)

	func on_settled(token: int, reason: String) -> void:
		events.append("settled %d %s" % [token, reason])
		settles.append([token, reason])

	func on_batch(batch: CampaignBatch) -> void:
		events.append("batch %d" % [batch.seat])

	func on_sync(_run: Dictionary, battle: Dictionary, facts: Array, _screen: int) -> void:
		if not battle.is_empty():
			snapshots += 1
		if not facts.is_empty():
			catch_ups += 1
