# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enet_dev_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## ENet dev transport cases for tests/net/run_all.gd ([code]SteamNetwork[/code]'s debug flags):
## the flags ask for a host or a join in a debug build, and for nothing, with why, in a release
## build or when malformed; entering the lobby with the host flag hosts on ENet on the real
## autoload (stand-in ids, "Player <id>") and leaving ends it. [b]Two instances:[/b] two headless
## instances of this project, launched with the flags and each its own user folder, play a
## battle to its end over ENet through the real autoloads, each driven by [PairPeer] from
## [code]harness/enet_pair_peer.gd[/code]; every map's hash must match on both, and both logs
## are kept in [code]user://logs/[/code]. Only the instances this case started are ever stopped.
## Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const SteamNetworkScript = preload("res://scripts/autoload/steam_network.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")

const PEER_SCRIPT: String = "res://tests/net/harness/enet_pair_peer.gd"
const LOCALHOST: String = "127.0.0.1"
const HOST_ARG: String = "--enet-host="
const JOIN_ARG: String = "--enet-join="

# What the instances print: the host's listening line (SteamNetwork's), each instance's end, a
# failure, and one line per map with its state hash.
const HOSTING_LINE: String = "Hosting on ENet "
const DONE_LINE: String = "PAIR DONE"
const FAILED_LINE: String = "PAIR FAILED"
const MAP_LINE: String = "PAIR MAP "

# Limits that only stop a hang: an instance boots in seconds and a localhost battle of two seats
# ends in under a minute, both well inside the runner's suite limit.
const START_LIMIT_MSEC: int = 30000
const PAIR_LIMIT_MSEC: int = 180000
# The pause between polls while waiting, so the wait doesn't spin a core.
const POLL_PAUSE_MSEC: int = 50

const NONE: int = SteamNetworkScript._DevRole.NONE
const HOST_ROLE: int = SteamNetworkScript._DevRole.HOST
const JOIN_ROLE: int = SteamNetworkScript._DevRole.JOIN


func run() -> void:
	_test_flags()
	_test_host_in_process()
	_test_two_instances()


func _test_flags() -> void:
	# Each: the user arguments, then role, address and port asked for in a debug build.
	var asked: Array = [
		[["--enet-host=7777"], HOST_ROLE, "", 7777],
		[["--enet-host=0"], HOST_ROLE, "", 0],
		[["--enet-join=127.0.0.1:7777"], JOIN_ROLE, "127.0.0.1", 7777],
		[["--run-seed=3F9A-12C0-77E1-A", "--enet-join=localhost:1"], JOIN_ROLE, "localhost", 1],
	]
	var parsed: bool = true
	var released: bool = true
	for each: Array in asked:
		var args: PackedStringArray = each[0]
		var link: SteamNetworkScript._DevLink = SteamNetworkScript._dev_link_of(args, true)
		parsed = (
				parsed
				and link.role == each[1]
				and link.address == each[2]
				and link.port == each[3]
				and link.problem.is_empty()
		)
		var release: SteamNetworkScript._DevLink = SteamNetworkScript._dev_link_of(args, false)
		released = released and release.role == NONE and not release.problem.is_empty()
	_check("enet: the flags ask for a host or a join in a debug build", parsed)
	_check("enet: the flags are ignored in a release build, with a warning", released)

	var malformed: Array = [
		["--enet-host=abc"], ["--enet-host=70000"], ["--enet-host=-1"], ["--enet-host="],
		["--enet-join=7777"], ["--enet-join=:7777"], ["--enet-join=127.0.0.1:0"],
		["--enet-join=127.0.0.1:x"],
		["--enet-host=7777", "--enet-join=127.0.0.1:7777"], ["--enet-host=1", "--enet-host=2"],
	]
	var refused: PackedStringArray = []
	for args: Array in malformed:
		var link: SteamNetworkScript._DevLink = SteamNetworkScript._dev_link_of(
				PackedStringArray(args), true
		)
		if link.role != NONE or link.problem.is_empty():
			refused.append(str(args))
	var quiet: SteamNetworkScript._DevLink = SteamNetworkScript._dev_link_of(
			PackedStringArray(["--run-seed=3F9A-12C0-77E1-A"]), true
	)
	_check("enet: malformed or doubled flags ask for nothing, saying why; others are no flag", (
			refused.is_empty() and quiet.role == NONE and quiet.problem.is_empty()
	), "accepted: %s" % [refused])


# The host flag on the real SteamNetwork: nothing until the lobby, then a session on ENet with
# stand-in ids; leaving ends it; a release build's flag starts nothing.
func _test_host_in_process() -> void:
	const CASE_NAME: String = "enet: entering the lobby with the host flag hosts on ENet"
	if SteamNetwork.current_lobby_id != 0:
		_skip(CASE_NAME, "SteamNetwork is already in a lobby")
		return
	var kept: SteamNetworkScript._DevLink = SteamNetwork._dev_link
	SteamNetwork._dev_link = SteamNetworkScript._dev_link_of(
			PackedStringArray(["%s0" % [HOST_ARG]]), true
	)
	SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.MAIN_MENU)
	var waits_for_lobby: bool = not SteamNetwork.has_active_session()
	SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.LOBBY)
	var members: Array[SteamNetwork.LobbyMember] = SteamNetwork.get_members()
	var hosted: bool = (
			SteamNetwork.has_active_session()
			and SteamNetwork.is_authoritative()
			and SteamNetwork.multiplayer.multiplayer_peer is ENetMultiplayerPeer
			and members.size() == 1
			and members[0].steam_id == MultiplayerPeer.TARGET_PEER_SERVER
			and SteamNetwork.get_lobby_owner() == MultiplayerPeer.TARGET_PEER_SERVER
			and SteamNetwork.get_lobby_members() == [MultiplayerPeer.TARGET_PEER_SERVER]
			and SteamNetwork.get_member_name(MultiplayerPeer.TARGET_PEER_SERVER) == "Player 1"
			and SteamNetwork.get_peer_steam_id(77) == 77
	)
	SteamNetwork.leave_lobby()
	var left: bool = (
			not SteamNetwork.has_active_session()
			and SteamNetwork.multiplayer.multiplayer_peer == null
			and SteamNetwork.get_members().is_empty()
	)
	SteamNetwork._dev_link = SteamNetworkScript._dev_link_of(
			PackedStringArray(["%s0" % [HOST_ARG]]), false
	)
	SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.LOBBY)
	var release_quiet: bool = not SteamNetwork.has_active_session()
	SteamNetwork.leave_lobby()
	SteamNetwork._dev_link = kept
	_check(CASE_NAME, waits_for_lobby and hosted and left and release_quiet, (
			"waits %s, hosted %s, left %s, release quiet %s"
			% [waits_for_lobby, hosted, left, release_quiet]
	))


func _test_two_instances() -> void:
	const CASE_NAME: String = "enet: two instances on one machine play a battle to its end"
	if not _has_test_user_dir():
		_skip(CASE_NAME, "needs a test user folder (see run_all.gd's class doc)")
		return
	var user_variable: String = _user_variable()
	if user_variable.is_empty():
		_skip(CASE_NAME, "no known user folder variable on %s" % [OS.get_name()])
		return
	var port: int = _free_port()
	if port <= 0:
		_skip(CASE_NAME, "no port can be opened on %s" % [LOCALHOST])
		return
	var logs: String = OS.get_user_data_dir().path_join("logs")
	var roots: String = OS.get_user_data_dir().path_join("enet_pair")
	DirAccess.make_dir_recursive_absolute(logs)
	var host: Instance = _launch("host", user_variable, roots, logs, "%s%d" % [HOST_ARG, port])
	var listening: bool = _wait(START_LIMIT_MSEC, func() -> bool:
		return not host.is_running() or host.log_text().contains(HOSTING_LINE)
	) and host.is_running()
	var client: Instance = null
	if listening:
		client = _launch(
				"client", user_variable, roots, logs, "%s%s:%d" % [JOIN_ARG, LOCALHOST, port]
		)
	var instances: Array[Instance] = [host]
	if client != null:
		instances.append(client)
	var ended: bool = _wait(PAIR_LIMIT_MSEC, func() -> bool:
		for instance: Instance in instances:
			if instance.is_running():
				return false
		return true
	)
	for instance: Instance in instances:
		instance.stop()
	var host_text: String = host.log_text()
	var client_text: String = "" if client == null else client.log_text()
	var host_maps: PackedStringArray = _lines_with(host_text, MAP_LINE)
	var client_maps: PackedStringArray = _lines_with(client_text, MAP_LINE)
	print("      enet pair logs: %s, %s" % [
		host.log_path, "(no client)" if client == null else client.log_path,
	])
	_check(CASE_NAME, (
			listening
			and ended
			and host_text.contains(DONE_LINE)
			and client_text.contains(DONE_LINE)
			and not (host_text + client_text).contains(FAILED_LINE)
			and not (host_text + client_text).contains("SCRIPT ERROR")
			and host_maps.size() == 2
			and host_maps == client_maps
			and host_text.contains("NetRelay: sent sync, ")
			and client_text.contains("NetRelay: received sync, ")
	), "listening %s, ended %s, maps %s / %s; host: %s; client: %s" % [
		listening, ended, host_maps, client_maps, _tail(host_text), _tail(client_text),
	])


# An instance of this project on PEER_SCRIPT with flag, its user folder under roots/role (through
# user_variable, which Godot builds user:// from) and its log at logs/enet_pair_<role>.log.
func _launch(
		role: String, user_variable: String, roots: String, logs: String, flag: String
) -> Instance:
	var instance: Instance = Instance.new()
	var user_root: String = roots.path_join(role)
	DirAccess.make_dir_recursive_absolute(user_root)
	instance.log_path = logs.path_join("enet_pair_%s.log" % [role])
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", instance.log_path, "--script", PEER_SCRIPT, "--", flag,
	]
	var kept: String = OS.get_environment(user_variable)
	OS.set_environment(user_variable, user_root)
	instance.pid = OS.create_process(OS.get_executable_path(), args)
	OS.set_environment(user_variable, kept)
	return instance


# Polls done every POLL_PAUSE_MSEC until it answers true, at most limit_msec.
func _wait(limit_msec: int, done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + limit_msec
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		OS.delay_msec(POLL_PAUSE_MSEC)
	return done.call()


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# The environment variable Godot builds user:// from here, as tools/run_tests.sh sets it; empty
# where the runner knows none.
static func _user_variable() -> String:
	match OS.get_name():
		"Windows":
			return "APPDATA"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return "XDG_DATA_HOME"
		"macOS":
			return "HOME"
	return ""


# A port free on LOCALHOST now, from a server bound to any port and closed again; 0 when none.
static func _free_port() -> int:
	var probe: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	probe.set_bind_ip(LOCALHOST)
	if probe.create_server(0, 1) != OK:
		return 0
	var port: int = probe.host.get_local_port()
	probe.close()
	return port


static func _lines_with(text: String, part: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for line: String in text.split("\n"):
		if line.contains(part):
			found.append(line.strip_edges())
	found.sort()
	return found


# The last lines of text, for a failure's detail.
static func _tail(text: String) -> String:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	return " | ".join(lines.slice(maxi(lines.size() - 4, 0)))


# One launched instance: its process and its log.
class Instance:
	extends RefCounted

	var pid: int = -1
	var log_path: String = ""

	func is_running() -> bool:
		return pid > 0 and OS.is_process_running(pid)

	## Stops this instance if it still runs: only a process this case started.
	func stop() -> void:
		if is_running():
			OS.kill(pid)

	func log_text() -> String:
		if not FileAccess.file_exists(log_path):
			return ""
		return FileAccess.get_file_as_string(log_path)


## One instance's side of the two-instance battle, ticked every frame by
## [code]harness/enet_pair_peer.gd[/code]: the host enters the lobby (which hosts on ENet), waits
## for the client, starts a 2-seat run, votes for floor 1's Standard combat with the client,
## begins it and plays its map; the client enters the lobby (which joins), votes, and plays its
## own map through its mirror, one command at a time. Each map is played by the M1 battle driver
## ([code]m1_battle_cases.gd[/code]). When every map has ended each prints its maps' hashes; the
## host ends the battle and waits for the client to leave; the client leaves at the results.
class PairPeer:
	extends RefCounted

	enum Step {
		BOOT = 0,
		LOBBY = 1,
		SEATED = 2,
		BATTLE = 3,
		PLAY = 4,
		END = 5,
	}

	## What [method tick] returns: still going, or the instance's exit code.
	const RUNNING: int = -1
	const PASSED: int = 0
	const FAILED: int = 1

	# Seconds an instance waits for the battle to end before it fails; only stops a hang.
	const PEER_LIMIT: float = 150.0
	# Commands refused before the instance gives up: the driver would otherwise send one again.
	const REJECTION_LIMIT: int = 20

	var _is_host: bool = false
	var _step: Step = Step.BOOT
	var _clock: float = 0.0
	var _node: int = -1
	var _driver: M1BattleCases = null
	var _is_waiting: bool = false
	var _rejections: int = 0
	var _has_printed: bool = false

	func _init(_tree: SceneTree) -> void:
		for arg: String in OS.get_cmdline_user_args():
			_is_host = _is_host or arg.begins_with(HOST_ARG)
		_driver = M1BattleCases.new(PairPeer._ignore)
		CampaignService.combat_settled.connect(_on_combat_settled)

	## Advances by [param delta] seconds; [constant RUNNING] until this side is done.
	func tick(delta: float) -> int:
		_clock += delta
		if _clock > PEER_LIMIT:
			return _fail("no end after %.0f s, at step %s" % [PEER_LIMIT, Step.find_key(_step)])
		if _rejections > REJECTION_LIMIT:
			return _fail("%d commands refused" % [_rejections])
		match _step:
			Step.BOOT:
				# SteamNetwork follows the router from its deferred call, done by the first frame.
				if _is_host:
					SaveFile.delete_folder("user://saves/")
					if SaveService.open_save_file(1) != OK:
						return _fail("the host's save file didn't open")
				SceneRouter.goto_screen(SceneRouter.Screen.LOBBY)
				_step = Step.LOBBY
			Step.LOBBY:
				return _tick_host_lobby() if _is_host else _tick_client_lobby()
			Step.SEATED:
				return _tick_seated()
			Step.BATTLE:
				var session: CampaignSession = CampaignService.session
				if session != null and session.encounter != null:
					_step = Step.PLAY
			Step.PLAY:
				return _tick_play()
			Step.END:
				return _tick_end()
		return RUNNING

	# Host: once the client is admitted, a 2-seat run, its offers settled, and the host's vote.
	func _tick_host_lobby() -> int:
		if not SteamNetwork.has_active_session() or SteamNetwork.get_members().size() < 2:
			return RUNNING
		var steam_ids: PackedInt64Array = []
		for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
			steam_ids.append(member.steam_id)
		if SaveService.start_new_multiplayer_run(steam_ids) != OK:
			return _fail("the run didn't start")
		var session: CampaignSession = CampaignService.session
		for seat: int in session.run.seat_numbers():
			session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
		if not _vote(session):
			return _fail("floor 1 has no Standard combat")
		_step = Step.SEATED
		return RUNNING

	# Client: once its mirror holds the run and its seat, its vote.
	func _tick_client_lobby() -> int:
		var session: CampaignSession = CampaignService.session
		if session == null or session.run == null or CampaignService.local_seat() <= 0:
			return RUNNING
		session.command_rejected.connect(_on_session_command_rejected)
		session.combat_encounter_closed.connect(_on_session_combat_encounter_closed)
		if not _vote(session):
			return _fail("floor 1 has no Standard combat")
		_step = Step.SEATED
		return RUNNING

	# Host: once both votes entered the node, the battle begins. Client: it waits for it.
	func _tick_seated() -> int:
		var session: CampaignSession = CampaignService.session
		if not _is_host:
			_step = Step.BATTLE
			return RUNNING
		if session.run.flow.stage != RunFlow.Stage.NODE or session.run.node != _node:
			return RUNNING
		var request: CampaignSession.BattleRequest = session.run.battle_request(
				CombatMapPools.load_default(), EffectCatalog.index()
		)
		if request == null or CampaignService.begin_battle(request) != OK:
			return _fail("the battle didn't begin")
		_step = Step.BATTLE
		return RUNNING

	# Every map ended: its hashes, then the host ends the battle. A client whose battle closed
	# before it looked has printed them as it closed.
	func _tick_play() -> int:
		var battle: CombatEncounter = CampaignService.session.encounter
		if battle == null:
			if _has_printed:
				_step = Step.END
			return RUNNING
		var is_over: bool = true
		for map: CombatSession in battle.get_sessions():
			is_over = is_over and map.is_finished
		if not is_over:
			_act(battle.session_of_seat(CampaignService.local_seat()))
			return RUNNING
		_print_maps(battle)
		if _is_host and CampaignService.end_battle() == null:
			return _fail("the battle didn't end")
		_step = Step.END
		return RUNNING

	# Each map's session id, state hash and result, once.
	func _print_maps(battle: CombatEncounter) -> void:
		if _has_printed:
			return
		_has_printed = true
		for map: CombatSession in battle.get_sessions():
			print("%s%d %d %s" % [
				MAP_LINE, map.session_id, map.state_hash(), "won" if map.is_won else "lost",
			])

	# Host: done once the client left. Client: done at the results, with the battle closed.
	func _tick_end() -> int:
		if _is_host:
			if SteamNetwork.get_members().size() > 1:
				return RUNNING
		else:
			var session: CampaignSession = CampaignService.session
			if session.encounter != null or session.run.flow.stage != RunFlow.Stage.RESULTS:
				return RUNNING
		print("%s %s after %.1f s" % [DONE_LINE, "host" if _is_host else "client", _clock])
		SteamNetwork.leave_lobby()
		return PASSED

	# This seat's vote for floor 1's Standard combat; false when there is none.
	func _vote(session: CampaignSession) -> bool:
		var route: PackedInt32Array = Fixture.route_to(
				session.run.graph, CampaignGraph.NodeType.STANDARD
		)
		if route.size() != 1:
			return false
		_node = route[0]
		var seat: int = CampaignService.local_seat()
		var vote: RouteVoteCommand = (
				RouteVoteCommand.for_session(session, seat, _node) if _is_host
				else RouteVoteCommand.new(seat, _node)
		)
		CampaignService.submit_command(vote)
		return true

	# The seat's next command on map, one at a time on a client: Start in the opening window, then
	# each unit the driver's turn, then the end of the turn.
	func _act(map: CombatSession) -> void:
		var seat: int = CampaignService.local_seat()
		if map == null or map.is_finished or _is_waiting:
			return
		var command: Command = null
		if map.state.seats_to_start.has(seat):
			command = StartCommand.new(seat)
		elif (
				map.state.phase_side == CombatFact.CombatSide.PLAYER
				and not map.state.is_phase_ended
				and not map.state.ended_seats.has(seat)
		):
			var acting: PackedStringArray = TurnInputModel.acting_units(map, seat)
			if acting.is_empty():
				command = EndTurnCommand.new(seat)
			else:
				var turn: UnitTurnCommand = _driver._turn_for(map, acting[0])
				turn.seat = seat
				command = turn
		if command == null:
			return
		_is_waiting = not _is_host
		for batch: CombatSession.FactBatch in CampaignService.submit_combat(
				command, map.session_id
		):
			if batch.is_rejected():
				_rejections += 1
				print("PAIR REFUSED %s: %s" % [batch.label, batch.rejected_reason])

	func _fail(why: String) -> int:
		print("%s %s: %s" % [FAILED_LINE, "host" if _is_host else "client", why])
		SteamNetwork.leave_lobby()
		return FAILED

	func _on_combat_settled(_session_id: int, reason: String) -> void:
		_is_waiting = false
		if not reason.is_empty():
			_rejections += 1
			print("PAIR REFUSED: %s" % [reason])

	# A client's battle closes with every map ended, its state as it was then.
	func _on_session_combat_encounter_closed(encounter: CombatEncounter) -> void:
		var is_over: bool = true
		for map: CombatSession in encounter.get_sessions():
			is_over = is_over and map.is_finished
		if is_over:
			_print_maps(encounter)

	func _on_session_command_rejected(seat: int, _arrival: int, reason: String) -> void:
		if seat == CampaignService.local_seat():
			_rejections += 1
			print("PAIR REFUSED campaign: %s" % [reason])

	static func _ignore(_case_name: String, _passed: bool, _detail: String = "") -> void:
		pass
