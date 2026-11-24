# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enet_dev_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 24, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## ENet dev transport cases for tests/net/run_all.gd ([code]SteamNetwork[/code]'s debug flags):
## the flags ask for a host or a join in a debug build, and for nothing, with why, in a release
## build or when malformed; entering the lobby with the host flag hosts on ENet on the real
## autoload (stand-in ids, "Player <id>") and leaving ends it; the lobby screen's status names the
## transport and its address under either flag, and is as before without one. [b]Two pairs of
## instances[/b] of this project at once, each its own port and user folders, driven by [PairPeer]
## from [code]harness/enet_pair_peer.gd[/code]: each pair takes its starting heirlooms through the
## real screens, one host first, one client first, and must reach the map with one route per
## screen and no screen entered twice (from both logs); the host-first pair then plays a battle to
## its end, every map's hash matching and every relay message arriving. Logs are kept in
## [code]user://logs/[/code]; only instances this case started are stopped. Skipped without a test
## user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const SteamNetworkScript = preload("res://scripts/autoload/steam_network.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")

const PEER_SCRIPT: String = "res://tests/net/harness/enet_pair_peer.gd"
# Loaded by its case alone: the pair's instances load this file too, and never show a lobby.
const LOBBY_SCENE_PATH: String = "res://ui/screens/lobby_screen.tscn"
const LOCALHOST: String = "127.0.0.1"
const HOST_ARG: String = "--enet-host="
const JOIN_ARG: String = "--enet-join="

# What the instances print: the host's listening line (SteamNetwork's), each instance's end, a
# failure, and one line per map with its state hash.
const HOSTING_LINE: String = "Hosting on ENet "
const DONE_LINE: String = "PAIR DONE"
const FAILED_LINE: String = "PAIR FAILED"
const MAP_LINE: String = "PAIR MAP "
const STEP_LINE: String = "PAIR STEP "
const SEED_LINE: String = "New multiplayer run, seed "
# At the starting heirloom: each seat's pick, first or after its teammate's, and the waiting line
# its screen shows once its own is taken.
const PICKED_FIRST_LINE: String = "PAIR PICKED first"
const PICKED_SECOND_LINE: String = "PAIR PICKED after the teammate"
const WAITING_LINE: String = "PAIR WAITING "

# What an instance is told after "--" besides its ENet flag: which seat takes its starting
# heirloom first (FIRST_HOST or FIRST_CLIENT), and whether the pair ends at the map.
const FIRST_ARG: String = "--pair-first="
const STOP_AT_MAP_ARG: String = "--pair-stop-at-map"
const FIRST_HOST: String = "host"
const FIRST_CLIENT: String = "client"
# The screens the host routes everyone to on the way to the map, in order: each once.
const ROUTED_SCREENS: PackedStringArray = ["LOADING", "STARTING_HEIRLOOM", "CAMPAIGN_MAP"]
# How each machine's screen entries begin, once each: _entries_text()'s form.
const EXPECTED_ENTRIES: String = "LOBBY 1, LOADING 1, STARTING_HEIRLOOM 1, CAMPAIGN_MAP 1"
# Probes for a free port before giving up, so the two pairs never share one.
const PORT_ATTEMPTS: int = 8

# Limits that only stop a hang. Alone, an instance boots in seconds and the battle ends in about
# 10 s; under a full run's load it can take minutes, so each instance fails on its own first
# (PairPeer's limits) and this case's limit is a backstop past them. The hosts boot together, so
# their START waits overlap: about 330 s with PAIR, plus the rest of the net suite (under a
# minute), stays inside a SUITE_TIMEOUT of 450 s.
const START_LIMIT_MSEC: int = 30000
const PAIR_LIMIT_MSEC: int = 300000
# Log lines a failure's detail quotes from the end of each instance's log.
const TAIL_LINES: int = 6
# The pause between polls while waiting, so the wait doesn't spin a core.
const POLL_PAUSE_MSEC: int = 50

const NONE: int = SteamNetworkScript._DevRole.NONE
const HOST_ROLE: int = SteamNetworkScript._DevRole.HOST
const JOIN_ROLE: int = SteamNetworkScript._DevRole.JOIN


func run() -> void:
	_test_flags()
	_test_host_in_process()
	_test_lobby_status()
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


# The lobby screen's status on the real SteamNetwork: without the flags, as it was (Steam's line
# when Steam is off); hosting, the transport and its port above the lobby's line; joining an ENet
# server here, the host's address while connecting, then above the lobby's line once connected.
func _test_lobby_status() -> void:
	const NONE_CASE: String = "enet: without the flags the lobby's status is as before"
	const HOST_CASE: String = "enet: hosting, the lobby's status names the transport and port"
	const JOIN_CASE: String = "enet: joining, the lobby's status names the host's address"
	const STEAM_OFF_TEXT: String = "Steam is not available. Open Steam, then restart the game."
	const PREFIX: String = "ENet dev transport: "
	var case_names: PackedStringArray = [NONE_CASE, HOST_CASE, JOIN_CASE]
	var scene: PackedScene = load(LOBBY_SCENE_PATH) as PackedScene
	if SteamNetwork.current_lobby_id != 0 or scene == null:
		for case_name: String in case_names:
			_skip(case_name, "SteamNetwork is in a lobby, or %s doesn't load" % [LOBBY_SCENE_PATH])
		return
	var kept: SteamNetworkScript._DevLink = SteamNetwork._dev_link
	var screen: Control = scene.instantiate() as Control
	_root.add_child(screen)
	var status: Label = screen.get_node("%Status") as Label

	SteamNetwork._dev_link = SteamNetworkScript._dev_link_of(PackedStringArray(), true)
	SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.LOBBY)
	var plain: String = status.text
	var is_plain: bool = (
			not SteamNetwork.has_active_session()
			and not plain.contains(PREFIX)
			and (SteamManager.is_available or plain == STEAM_OFF_TEXT)
	)

	SteamNetwork._dev_link = SteamNetworkScript._dev_link_of(
			PackedStringArray(["%s0" % [HOST_ARG]]), true
	)
	SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.LOBBY)
	var host_port: int = _dev_port()
	var host_lines: PackedStringArray = status.text.split("\n")
	SteamNetwork.leave_lobby()
	var after_host: String = status.text
	_check(NONE_CASE, is_plain and after_host == plain, "before %s, after leaving %s" % [
		plain.c_escape(), after_host.c_escape(),
	])
	_check(HOST_CASE, (
			host_lines.size() == 2
			and host_lines[0] == "%shosting on %s:%d" % [PREFIX, LOCALHOST, host_port]
			and not host_lines[1].is_empty()
			and host_lines[1] != STEAM_OFF_TEXT
	), "port %d: %s" % [host_port, "\\n".join(host_lines)])

	var server: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	server.set_bind_ip(LOCALHOST)
	if server.create_server(0, 1) != OK:
		_skip(JOIN_CASE, "no port can be opened on %s" % [LOCALHOST])
	else:
		var port: int = server.host.get_local_port()
		var where: String = "%s:%d" % [LOCALHOST, port]
		SteamNetwork._dev_link = SteamNetworkScript._dev_link_of(
				PackedStringArray(["%s%s" % [JOIN_ARG, where]]), true
		)
		SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.LOBBY)
		var joining: String = status.text
		var connected: bool = _wait(START_LIMIT_MSEC, func() -> bool:
			server.poll()
			SteamNetwork.multiplayer.poll()
			return _dev_port() > 0 and (
					SteamNetwork.multiplayer.multiplayer_peer.get_connection_status()
					== MultiplayerPeer.CONNECTION_CONNECTED
			)
		)
		screen.call("_refresh")
		var joined_lines: PackedStringArray = status.text.split("\n")
		SteamNetwork.leave_lobby()
		server.close()
		_check(JOIN_CASE, (
				joining == "%sjoining %s..." % [PREFIX, where]
				and connected
				and joined_lines.size() == 2
				and joined_lines[0] == "%sjoined %s" % [PREFIX, where]
				and not joined_lines[1].is_empty()
				and status.text == plain
		), "connecting %s, connected %s, joined %s, after leaving %s" % [
			joining.c_escape(), connected, "\\n".join(joined_lines), status.text.c_escape(),
		])
	SteamNetwork._dev_link = kept
	_root.remove_child(screen)
	screen.queue_free()


# The local port of SteamNetwork's ENet peer, or 0 without one: a host's listening port, a
# client's own.
static func _dev_port() -> int:
	var peer: ENetMultiplayerPeer = (
			SteamNetwork.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	)
	if peer == null or peer.host == null:
		return 0
	return peer.host.get_local_port()


# Two pairs at once, each its own port and user folders: one takes the starting heirlooms host
# first and plays the battle; the other takes them client first and ends at the map.
func _test_two_instances() -> void:
	const CASE_NAME: String = "enet: two instances on one machine play a battle to its end"
	var pairs: Array[Pair] = [
		Pair.new("host", "client", FIRST_HOST, false),
		Pair.new("host_client_first", "client_client_first", FIRST_CLIENT, true),
	]
	var case_names: PackedStringArray = [CASE_NAME]
	for pair: Pair in pairs:
		case_names.append(pair.heirloom_case())
	if not _has_test_user_dir():
		for case_name: String in case_names:
			_skip(case_name, "needs a test user folder (see run_all.gd's class doc)")
		return
	var user_variable: String = _user_variable()
	if user_variable.is_empty():
		for case_name: String in case_names:
			_skip(case_name, "no known user folder variable on %s" % [OS.get_name()])
		return
	var logs: String = OS.get_user_data_dir().path_join("logs")
	var roots: String = OS.get_user_data_dir().path_join("enet_pair")
	DirAccess.make_dir_recursive_absolute(logs)
	var taken: PackedInt32Array = []
	for pair: Pair in pairs:
		pair.port = _free_port(taken)
		if pair.port <= 0:
			for case_name: String in case_names:
				_skip(case_name, "no port can be opened on %s" % [LOCALHOST])
			return
		taken.append(pair.port)
		pair.host = _launch(pair.host_role, user_variable, roots, logs, pair.host_args())
	for pair: Pair in pairs:
		var hosting: Instance = pair.host
		pair.is_listening = _wait(START_LIMIT_MSEC, func() -> bool:
			return not hosting.is_running() or hosting.log_text().contains(HOSTING_LINE)
		) and hosting.is_running()
		if pair.is_listening:
			pair.client = _launch(
					pair.client_role, user_variable, roots, logs, pair.client_args()
			)
	var instances: Array[Instance] = []
	for pair: Pair in pairs:
		instances.append_array(pair.instances())
	var started_msec: int = Time.get_ticks_msec()
	var ended: bool = _wait(PAIR_LIMIT_MSEC, func() -> bool:
		for instance: Instance in instances:
			if instance.is_running():
				return false
		return true
	)
	var seconds: float = (Time.get_ticks_msec() - started_msec) / 1000.0
	for instance: Instance in instances:
		instance.stop()
	for pair: Pair in pairs:
		_check_heirlooms(pair, ended)
	var battle: Pair = pairs[0]
	var host: Instance = battle.host
	var client: Instance = battle.client
	var listening: bool = battle.is_listening
	var host_text: String = host.log_text()
	var client_text: String = "" if client == null else client.log_text()
	var host_maps: PackedStringArray = _lines_with(host_text, MAP_LINE)
	var client_maps: PackedStringArray = _lines_with(client_text, MAP_LINE)
	var run_seed: String = _after_last(host_text, SEED_LINE).get_slice(",", 0)
	# Every relay message one side sent the other arrived, kind by kind, both ways.
	var to_client: String = _count_text(host_text, "sent")
	var to_host: String = _count_text(client_text, "sent")
	var counts_match: bool = (
			not to_client.is_empty()
			and to_client == _count_text(client_text, "received")
			and to_host == _count_text(host_text, "received")
	)
	print("      enet pair: %.1f s from the client's launch, seed %s; logs: %s, %s" % [
		seconds, run_seed, host.log_path, "(no client)" if client == null else client.log_path,
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
			and counts_match
	), (
			"listening %s, ended %s after %.1f s, seed %s, maps %s / %s; messages to the client"
			+ " %s / %s, to the host %s / %s; steps reached: %s / %s; host's last lines: %s;"
			+ " client's last lines: %s"
	) % [
		listening, ended, seconds, run_seed, host_maps, client_maps,
		to_client, _count_text(client_text, "received"),
		to_host, _count_text(host_text, "received"),
		_after_last(host_text, STEP_LINE), _after_last(client_text, STEP_LINE),
		_tail(host_text), _tail(client_text),
	])


# The starting heirlooms of pair, from both logs: each seat took its own through the real
# StartingHeirloomScreen in the pair's order, the first one shown waiting for the other by name;
# the host routed everyone to Loading, the heirloom screen and the map once each; each machine
# entered those in order and no screen twice; no client sent a notice, and the host dropped no
# route.
func _check_heirlooms(pair: Pair, ended: bool) -> void:
	var host_text: String = pair.host.log_text()
	var client_text: String = "" if pair.client == null else pair.client.log_text()
	var first: String = host_text if pair.first == FIRST_HOST else client_text
	var second: String = client_text if pair.first == FIRST_HOST else host_text
	var waited_for: String = "Player 2" if pair.first == FIRST_HOST else "Player 1"
	var routes: PackedInt32Array = []
	for screen: String in ROUTED_SCREENS:
		routes.append(_lines_with(host_text, "Routing everyone to %s." % [screen]).size())
	var host_entries: String = _entries_text(host_text)
	var client_entries: String = _entries_text(client_text)
	print("      enet pair, %s first: routes %s, entries %s / %s; logs: %s, %s" % [
		pair.first, routes, host_entries, client_entries, pair.host.log_path,
		"(no client)" if pair.client == null else pair.client.log_path,
	])
	_check(pair.heirloom_case(), (
			pair.is_listening
			and ended
			and first.contains(PICKED_FIRST_LINE)
			and second.contains(PICKED_SECOND_LINE)
			and first.contains("%sWaiting for %s." % [WAITING_LINE, waited_for])
			and host_text.contains("%shost MAP" % [STEP_LINE])
			and client_text.contains("%sclient MAP" % [STEP_LINE])
			and routes == PackedInt32Array([1, 1, 1])
			and host_entries.begins_with(EXPECTED_ENTRIES)
			and client_entries.begins_with(EXPECTED_ENTRIES)
			and _most_entries(host_text) == 1
			and _most_entries(client_text) == 1
			and _lines_with(client_text, "NetRelay: sent notice").is_empty()
			and _lines_with(host_text, "a route notice").is_empty()
			and not (host_text + client_text).contains(FAILED_LINE)
			and not (host_text + client_text).contains("SCRIPT ERROR")
	), (
			"listening %s, ended %s; routes %s; entries %s / %s; first picked %s, second picked"
			+ " %s, waiting %s; steps reached: %s / %s; host's last lines: %s; client's last"
			+ " lines: %s"
	) % [
		pair.is_listening, ended, routes, host_entries, client_entries,
		first.contains(PICKED_FIRST_LINE), second.contains(PICKED_SECOND_LINE),
		_after_last(first, WAITING_LINE), _after_last(host_text, STEP_LINE),
		_after_last(client_text, STEP_LINE), _tail(host_text), _tail(client_text),
	])


# An instance of this project on PEER_SCRIPT with flags, its user folder under roots/role (through
# user_variable, which Godot builds user:// from) and its log at logs/enet_pair_<role>.log.
func _launch(
		role: String,
		user_variable: String,
		roots: String,
		logs: String,
		flags: PackedStringArray,
) -> Instance:
	var instance: Instance = Instance.new()
	var user_root: String = roots.path_join(role)
	DirAccess.make_dir_recursive_absolute(user_root)
	instance.log_path = logs.path_join("enet_pair_%s.log" % [role])
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", instance.log_path, "--script", PEER_SCRIPT, "--",
	]
	args.append_array(flags)
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


# A port free on LOCALHOST now and not in taken, from a server bound to any port and closed
# again; 0 when none.
static func _free_port(taken: PackedInt32Array = PackedInt32Array()) -> int:
	for _attempt: int in PORT_ATTEMPTS:
		var probe: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		probe.set_bind_ip(LOCALHOST)
		if probe.create_server(0, 1) != OK:
			return 0
		var port: int = probe.host.get_local_port()
		probe.close()
		if not taken.has(port):
			return port
	return 0


static func _lines_with(text: String, part: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for line: String in text.split("\n"):
		if line.contains(part):
			found.append(line.strip_edges())
	found.sort()
	return found


# How many relay messages of each kind text's log lines say were sent, or received, as
# "kind n, ..." in kind order; "" with none. One line per message ("NetRelay: sent sync, 84 B,
# to peer 1."), as net_relay.gd logs it.
static func _count_text(text: String, verb: String) -> String:
	var marker: String = "NetRelay: %s " % [verb]
	var counts: Dictionary[String, int] = {}
	for line: String in text.split("\n"):
		var at: int = line.find(marker)
		if at < 0:
			continue
		var kind: String = line.substr(at + marker.length()).get_slice(",", 0)
		counts[kind] = counts.get(kind, 0) + 1
	var kinds: Array[String] = []
	kinds.assign(counts.keys())
	kinds.sort()
	var parts: PackedStringArray = []
	for kind: String in kinds:
		parts.append("%s %d" % [kind, counts[kind]])
	return ", ".join(parts)


# Each screen text's log entered, in the order first entered, with how often: "LOBBY 1, LOADING
# 1, ..." from SceneRouter's "Entered screen X." lines.
static func _entries_text(text: String) -> String:
	var counts: Dictionary[String, int] = _entry_counts(text)
	var parts: PackedStringArray = []
	for screen: String in counts:
		parts.append("%s %d" % [screen, counts[screen]])
	return ", ".join(parts)


# The most times text's log entered any one screen; 0 with none.
static func _most_entries(text: String) -> int:
	var most: int = 0
	for times: int in _entry_counts(text).values():
		most = maxi(most, times)
	return most


# How often text's log entered each screen, by name, in the order first entered (a Dictionary
# keeps its insertion order).
static func _entry_counts(text: String) -> Dictionary[String, int]:
	const MARKER: String = "Entered screen "
	var counts: Dictionary[String, int] = {}
	for line: String in text.split("\n"):
		var at: int = line.find(MARKER)
		if at < 0:
			continue
		var screen: String = line.substr(at + MARKER.length()).strip_edges().trim_suffix(".")
		counts[screen] = counts.get(screen, 0) + 1
	return counts


# The rest of text's last line holding part, after it, or "(none)": the step an instance
# reached, or the host's run seed.
static func _after_last(text: String, part: String) -> String:
	var at: int = text.rfind(part)
	if at < 0:
		return "(none)"
	return text.substr(at + part.length()).get_slice("\n", 0).strip_edges()


# The last TAIL_LINES lines of text, for a failure's detail, leaving out the backtrace lines
# under warnings and errors.
static func _tail(text: String) -> String:
	var kept: PackedStringArray = []
	for line: String in text.strip_edges().split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty() or line.begins_with(" ") or line.begins_with("\t"):
			continue
		kept.append(trimmed)
	return " | ".join(kept.slice(maxi(kept.size() - TAIL_LINES, 0)))


# Two instances on their own port: the roles naming their logs and user folders, which seat takes
# its starting heirloom first, and whether they end at the map.
class Pair:
	extends RefCounted

	var host_role: String = ""
	var client_role: String = ""
	var first: String = ""
	var is_stopping_at_map: bool = false
	var port: int = 0
	var is_listening: bool = false
	var host: Instance = null
	var client: Instance = null

	func _init(host_name: String, client_name: String, first_seat: String, stops: bool) -> void:
		host_role = host_name
		client_role = client_name
		first = first_seat
		is_stopping_at_map = stops

	## The case this pair's starting heirlooms report as.
	func heirloom_case() -> String:
		return "enet: two instances take the starting heirlooms %s first through the real" % [
			first,
		] + " screens and reach the map together, routed once"

	func host_args() -> PackedStringArray:
		return _with_pair_flags("%s%d" % [HOST_ARG, port])

	func client_args() -> PackedStringArray:
		return _with_pair_flags("%s%s:%d" % [JOIN_ARG, LOCALHOST, port])

	func instances() -> Array[Instance]:
		var launched: Array[Instance] = [host]
		if client != null:
			launched.append(client)
		return launched

	func _with_pair_flags(enet_flag: String) -> PackedStringArray:
		var flags: PackedStringArray = [enet_flag, "%s%s" % [FIRST_ARG, first]]
		if is_stopping_at_map:
			flags.append(STOP_AT_MAP_ARG)
		return flags


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


## One instance's side of the two-instance run, ticked every frame by
## [code]harness/enet_pair_peer.gd[/code]: the host enters the lobby (which hosts on ENet), waits
## for the client, starts a 2-seat run and routes everyone to Loading, as the lobby's Start does;
## once the client's mirror holds the run it presses Loading's Continue. Each seat takes its
## starting heirloom through the real StartingHeirloomScreen, in the order [constant FIRST_ARG]
## names, printing the waiting line its screen shows; the host's route takes both to the map.
## There, with [constant STOP_AT_MAP_ARG], the client leaves and the host follows; else both vote
## for floor 1's Standard combat, the host begins it, and each plays its seat by command (the
## client through its mirror, one at a time) with the M1 battle driver, on every map it has units
## on, sending its units to a frozen map once its own is won. When every map has ended, or the
## co-op run is lost, each prints its maps' hashes; the host ends the battle and waits for the
## client to leave at the results, or once a lost run's battle is gone. Fails when no step or fact
## moves for [constant STALL_LIMIT] s, or at [constant PEER_LIMIT] s in all.
class PairPeer:
	extends RefCounted

	enum Step {
		BOOT = 0,
		LOBBY = 1,
		SEATED = 2,
		BATTLE = 3,
		PLAY = 4,
		END = 5,
		LOADING = 6,
		HEIRLOOM = 7,
		MAP = 8,
	}

	## What [method tick] returns: still going, or the instance's exit code.
	const RUNNING: int = -1
	const PASSED: int = 0
	const FAILED: int = 1

	# Seconds with no new step and no new fact on any map before an instance fails: a hang. Under
	# load a command can take seconds, so this is far above the slowest gap seen.
	const STALL_LIMIT: float = 60.0
	# Seconds in all before an instance fails, however it moves: a battle that never ends. Under
	# the case's PAIR_LIMIT_MSEC, so the instance reports its own failure first.
	const PEER_LIMIT: float = 270.0
	# Commands refused before the instance gives up: the driver would otherwise send one again.
	const REJECTION_LIMIT: int = 20

	var _is_host: bool = false
	var _step: Step = Step.BOOT
	var _clock: float = 0.0
	# Seconds since the step or a map's last fact last moved, and what they were then (-1 before
	# the first frame).
	var _stall_clock: float = 0.0
	var _seen_step: int = -1
	var _seen_seq: int = -1
	var _node: int = -1
	var _driver: M1BattleCases = null
	var _is_waiting: bool = false
	var _rejections: int = 0
	var _has_printed: bool = false
	# Whether this side saw the co-op run lost (CombatEncounter.is_run_lost): its end ends the run,
	# which takes the host's session, and a client's mirror with it, so neither is a failure then.
	var _is_run_lost: bool = false
	var _tree: SceneTree = null
	# Which seat takes its starting heirloom first (FIRST_HOST or FIRST_CLIENT), and whether the
	# pair ends at the map.
	var _first: String = FIRST_HOST
	var _stops_at_map: bool = false
	# This seat's pick was sent from the heirloom screen held here; its waiting line was printed.
	var _has_picked: bool = false
	var _heirloom_screen: Node = null
	var _has_shown_waiting: bool = false

	func _init(tree: SceneTree) -> void:
		_tree = tree
		for arg: String in OS.get_cmdline_user_args():
			_is_host = _is_host or arg.begins_with(HOST_ARG)
			_stops_at_map = _stops_at_map or arg == STOP_AT_MAP_ARG
			if arg.begins_with(FIRST_ARG):
				_first = arg.trim_prefix(FIRST_ARG)
		_driver = M1BattleCases.new(PairPeer._ignore)
		CampaignService.combat_settled.connect(_on_combat_settled)

	## Advances by [param delta] seconds; [constant RUNNING] until this side is done.
	func tick(delta: float) -> int:
		_clock += delta
		_note_progress(delta)
		if _stall_clock > STALL_LIMIT:
			return _fail("nothing moved for %.0f s" % [STALL_LIMIT])
		if _clock > PEER_LIMIT:
			return _fail("no end after %.0f s" % [PEER_LIMIT])
		if _rejections > REJECTION_LIMIT:
			return _fail("%d commands refused" % [_rejections])
		# Past the lobby the run is there until this side is done, or a lost run ends; a client
		# whose host left has none (SteamNetwork ends the session, the menus clear it).
		if _step > Step.LOBBY and CampaignService.session == null and not _is_run_lost:
			return _fail("the run's session ended")
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
			Step.LOADING:
				return _tick_loading()
			Step.HEIRLOOM:
				return _tick_heirloom()
			Step.MAP:
				return _tick_map()
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

	# Host: once the client is admitted, a 2-seat run, its starting offers kept, and everyone to
	# Loading, as the lobby's Start does.
	func _tick_host_lobby() -> int:
		if not SteamNetwork.has_active_session() or SteamNetwork.get_members().size() < 2:
			return RUNNING
		var steam_ids: PackedInt64Array = []
		for member: SteamNetwork.LobbyMember in SteamNetwork.get_members():
			steam_ids.append(member.steam_id)
		if SaveService.start_new_multiplayer_run(steam_ids) != OK:
			return _fail("the run didn't start")
		SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.LOADING)
		_step = Step.LOADING
		return RUNNING

	# Client: once its mirror holds the run and its seat, it follows the host's routes.
	func _tick_client_lobby() -> int:
		var session: CampaignSession = CampaignService.session
		if session == null or session.run == null or CampaignService.local_seat() <= 0:
			return RUNNING
		session.command_rejected.connect(_on_session_command_rejected)
		session.combat_encounter_closed.connect(_on_session_combat_encounter_closed)
		_step = Step.LOADING
		return RUNNING

	# Host: on Loading, once the client's mirror holds the run (its relay sends its settings only
	# then), Loading's own Continue. Client: nothing to press; it waits for the host's route.
	func _tick_loading() -> int:
		if not _is_host:
			_step = Step.HEIRLOOM
			return RUNNING
		var gate: Node = _live_scene(SceneRouter.Screen.LOADING)
		if gate == null or NetRelay.seat_settings(_teammate()).is_empty():
			return RUNNING
		(gate.get_node(^"%ContinueButton") as Button).pressed.emit()
		_step = Step.HEIRLOOM
		return RUNNING

	# Each seat's pick through the heirloom screen's view, the second once the first's is taken
	# in its own run; then on to the map with the host's route.
	func _tick_heirloom() -> int:
		var session: CampaignSession = CampaignService.session
		if _has_picked:
			_note_waiting()
			if _live_scene(SceneRouter.Screen.CAMPAIGN_MAP) != null:
				_step = Step.MAP
			return RUNNING
		var screen: Node = _live_scene(SceneRouter.Screen.STARTING_HEIRLOOM)
		if screen == null:
			return RUNNING
		var is_first: bool = (_first == FIRST_HOST) == _is_host
		if not is_first and StartingOffer.is_open(session.run.seat_run(_teammate())):
			return RUNNING
		var command: StartingHeirloomCommand = PairPeer._first_pick(
				session.run, CampaignService.local_seat()
		)
		if command == null:
			return _fail("no starting heirloom can be taken")
		_has_picked = true
		_heirloom_screen = screen
		print(PICKED_FIRST_LINE if is_first else PICKED_SECOND_LINE)
		# After the screen's own link, so the screen has shown each batch when it is read.
		session.campaign_batch_resolved.connect(_on_session_heirloom_batch_resolved)
		(screen.call(&"get_view") as StartingOfferView).command_ready.emit(command)
		_note_waiting()
		return RUNNING

	# On the map: with STOP_AT_MAP_ARG the client leaves, then the host once it has; else each
	# seat's vote for floor 1's Standard combat.
	func _tick_map() -> int:
		if _stops_at_map:
			if _is_host and SteamNetwork.get_members().size() > 1:
				return RUNNING
			print("%s %s after %.1f s" % [DONE_LINE, _side(), _clock])
			SteamNetwork.leave_lobby()
			return PASSED
		if not _vote(CampaignService.session):
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

	# Every map ended, or the co-op run lost: its hashes, then the host ends the battle. A client
	# whose battle closed before it looked has printed them as it closed. A lost run on a host
	# showing GAMEPLAY is its battle screen's to end, as in play: it ends one at once
	# (CoopBattle reads the loss every frame) and would end it again after the driver (BUG-050).
	# Only a press of the draw's Continue takes the host there, which the pair never makes.
	func _tick_play() -> int:
		var session: CampaignSession = CampaignService.session
		var battle: CombatEncounter = null if session == null else session.encounter
		if battle == null:
			if _has_printed:
				_step = Step.END
			return RUNNING
		var is_over: bool = true
		for map: CombatSession in battle.get_sessions():
			is_over = is_over and map.is_finished
		# ASSUMPTION: a lost co-op run is an end the case passes on, as a lost map was.
		if not is_over and not battle.is_run_lost():
			_act(battle)
			return RUNNING
		_print_maps(battle)
		var is_screens: bool = (
				_is_run_lost and SceneRouter.current_screen == SceneRouter.Screen.GAMEPLAY
		)
		if _is_host and not is_screens and CampaignService.end_battle() == null:
			return _fail("the battle didn't end")
		_step = Step.END
		return RUNNING

	# Each map's session id, state hash and result (won, lost, or in a lost run frozen or still
	# fought), once; notes whether the run was lost.
	func _print_maps(battle: CombatEncounter) -> void:
		if _has_printed:
			return
		_has_printed = true
		_is_run_lost = battle.is_run_lost()
		for map: CombatSession in battle.get_sessions():
			var result: String = "won" if map.is_won else "lost"
			if not map.is_finished:
				result = "frozen" if battle.is_frozen(map.session_id) else "fought"
			print("%s%d %d %s" % [MAP_LINE, map.session_id, map.state_hash(), result])

	# Host: done once the client left. Client: done at the results with the battle closed, or in a
	# lost run once the battle closed or the mirror went with the run.
	func _tick_end() -> int:
		if _is_host:
			if SteamNetwork.get_members().size() > 1:
				return RUNNING
		else:
			var session: CampaignSession = CampaignService.session
			if _is_run_lost:
				if session != null and session.encounter != null:
					return RUNNING
			elif session.encounter != null or session.run.flow.stage != RunFlow.Stage.RESULTS:
				return RUNNING
		print("%s %s after %.1f s" % [DONE_LINE, "host" if _is_host else "client", _clock])
		SteamNetwork.leave_lobby()
		return PASSED

	# The other seat of the run: the client's on the host, the host's on the client.
	func _teammate() -> int:
		var local: int = CampaignService.local_seat()
		for seat: int in CampaignService.session.seats:
			if seat != local:
				return seat
		return SeatDirectory.NO_SEAT

	# The scene showing screen, once the router entered it and it is ready; else null.
	func _live_scene(screen: SceneRouter.Screen) -> Node:
		var scene: Node = _tree.current_scene
		if SceneRouter.current_screen != screen or scene == null or not scene.is_node_ready():
			return null
		if scene.scene_file_path != SceneRouter.SCREEN_PATHS[screen]:
			return null
		return scene

	# Prints the heirloom screen's waiting line once it shows, its own pick taken.
	func _note_waiting() -> void:
		if (
				_has_shown_waiting or not is_instance_valid(_heirloom_screen)
				or not _heirloom_screen.has_method(&"get_waiting_line")
		):
			return
		var line: Label = _heirloom_screen.call(&"get_waiting_line")
		if line == null or not line.is_visible_in_tree():
			return
		_has_shown_waiting = true
		print("%s%s" % [WAITING_LINE, line.text])

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

	# The seat's next command, one at a time on a client, on the first map it has to act on (its
	# own, or a teammate's its sent units stand on), else, its map won while one is frozen, a send
	# of every unit it has left there, as the co-op rules require (BUG-046).
	func _act(battle: CombatEncounter) -> void:
		var seat: int = CampaignService.local_seat()
		if _is_waiting:
			return
		var command: Command = null
		var session_id: int = -1
		for map: CombatSession in battle.get_sessions():
			command = _command_on(map, seat)
			if command != null:
				session_id = map.session_id
				break
		if command == null:
			command = _send_to_frozen(battle, seat)
			session_id = battle.session_of_seat(seat).session_id
		if command == null:
			return
		_is_waiting = not _is_host
		for batch: CombatSession.FactBatch in CampaignService.submit_combat(command, session_id):
			if batch.is_rejected():
				_rejections += 1
				print("PAIR REFUSED %s: %s" % [batch.label, batch.rejected_reason])

	# Seat's next command on map: Start in its window, then each unit the driver's turn, then the
	# end of its turn; null when it has nothing to do there.
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

	# With seat's map won and a map frozen, a send of every unit it has left to that map; else
	# null.
	func _send_to_frozen(battle: CombatEncounter, seat: int) -> Command:
		var own: CombatSession = battle.session_of_seat(seat)
		if own == null or not own.is_finished or not own.is_won:
			return null
		var units: PackedStringArray = []
		var travelling: PackedStringArray = battle.units_in_transit()
		for unit_id: String in own.state.units_of(CombatFact.CombatSide.PLAYER):
			if battle.session_of_unit(unit_id) == own and not travelling.has(unit_id):
				units.append(unit_id)
		for map: CombatSession in battle.get_sessions():
			if not units.is_empty() and battle.is_frozen(map.session_id):
				return SendUnitsCommand.new(seat, units, map.session_id)
		return null

	# Restarts the stall clock when the step or the battle's facts moved since the last frame, and
	# prints each step entered, so a case whose instance was stopped still knows where it was.
	func _note_progress(delta: float) -> void:
		var seq: int = _seq_total()
		if _step != _seen_step:
			print("%s%s %s at %.1f s" % [STEP_LINE, _side(), Step.find_key(_step), _clock])
		if _step == _seen_step and seq == _seen_seq:
			_stall_clock += delta
			return
		_seen_step = _step
		_seen_seq = seq
		_stall_clock = 0.0

	# The sum of every map's last fact seq in this instance's battle; 0 without one. A rebuilt
	# mirror may move it either way: any change is movement.
	func _seq_total() -> int:
		var session: CampaignSession = CampaignService.session
		if session == null or session.encounter == null:
			return 0
		var total: int = 0
		for map: CombatSession in session.encounter.get_sessions():
			total += map.last_seq()
		return total

	# Each map's last fact seq, for a failure's detail.
	func _seqs_text() -> String:
		var session: CampaignSession = CampaignService.session
		if session == null or session.encounter == null:
			return "no battle"
		var parts: PackedStringArray = []
		for map: CombatSession in session.encounter.get_sessions():
			parts.append("s%d#%d%s" % [
				map.session_id, map.last_seq(), " ended" if map.is_finished else "",
			])
		return " ".join(parts)

	func _side() -> String:
		return "host" if _is_host else "client"

	func _fail(why: String) -> int:
		print("%s %s: %s, at step %s after %.1f s, maps %s" % [
			FAILED_LINE, _side(), why, Step.find_key(_step), _clock, _seqs_text(),
		])
		SteamNetwork.leave_lobby()
		return FAILED

	func _on_combat_settled(_session_id: int, reason: String) -> void:
		_is_waiting = false
		if not reason.is_empty():
			_rejections += 1
			print("PAIR REFUSED: %s" % [reason])

	# A client's battle closes with every map ended, or the run lost, its state as it was then.
	func _on_session_combat_encounter_closed(encounter: CombatEncounter) -> void:
		var is_over: bool = true
		for map: CombatSession in encounter.get_sessions():
			is_over = is_over and map.is_finished
		if is_over or encounter.is_run_lost():
			_print_maps(encounter)

	func _on_session_command_rejected(seat: int, _arrival: int, reason: String) -> void:
		if seat == CampaignService.local_seat():
			_rejections += 1
			print("PAIR REFUSED campaign: %s" % [reason])

	# Any batch once this seat picked: the screen has shown it, so its waiting line is read now,
	# before a route can take the screen away.
	func _on_session_heirloom_batch_resolved(_batch: CampaignBatch) -> void:
		_note_waiting()

	static func _ignore(_case_name: String, _passed: bool, _detail: String = "") -> void:
		pass

	# seat's first starting heirloom that run accepts, with the first sub-choice that fits (the
	# first recruit or weapon, the weapon to the convoy, the first unit that may be named); a skip
	# when none can be taken; null when not even that is accepted.
	static func _first_pick(run: CampaignRunState, seat: int) -> StartingHeirloomCommand:
		var offer: StartingOffer = StartingOffer.pending(run.seat_run(seat))
		if offer == null:
			return null
		var units: PackedStringArray = [""]
		for unit: UnitInstance in run.seat_run(seat).army:
			units.append(unit.instance_id)
		var choices: PackedInt32Array = [StartingHeirloomCommand.NO_CHOICE, 0]
		for option: int in offer.options.size():
			for recruit: int in choices:
				for weapon: int in choices:
					for unit_id: String in units:
						var taking: StartingHeirloomCommand = StartingHeirloomCommand.new(
								seat, option
						)
						taking.recruit = recruit
						taking.weapon = weapon
						taking.unit_id = unit_id
						if weapon != StartingHeirloomCommand.NO_CHOICE:
							taking.placement = ItemPlacement.new(
									ItemPlacement.Destination.CONVOY
							)
						if taking.validate(run).is_empty():
							return taking
		var skip: StartingHeirloomCommand = StartingHeirloomCommand.new(seat)
		return skip if skip.validate(run).is_empty() else null
