# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     routing_cases.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## One routing authority, for tests/net/run_all.gd, on the real [code]SceneRouter[/code] and
## [code]SteamNetwork[/code]'s ENet dev transport in this process: a lone host's route reaches its
## screen once, and a route to the screen showing changes nothing; while the run is paused the
## host's route is held, then sent once it resumes. A client joined to a bare ENet server routes
## nobody and sends no notice: a campaign screen opened out of step with its run asks the host for
## the run, and opens again once the run reaches it; one routed to Loading before a new run's
## first sync stays there, never read as a rejoin (BUG-058). [code]RunScreen.of()[/code] reads
## no seat: any seat's open starting offer keeps everyone on it. Solo is as before: a plain local
## switch, the screen showing loading again. The cases read the router's log lines, poke its frame
## step and its state as a frame would, and put both back.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const SteamNetworkScript = preload("res://scripts/autoload/steam_network.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")

const MAP_SCENE_PATH: String = "res://ui/campaign/campaign_map_screen.tscn"
const LOCALHOST: String = "127.0.0.1"
const HOST_ARG: String = "--enet-host="
const JOIN_ARG: String = "--enet-join="
# Limit on the in-process join, which takes milliseconds alone.
const CONNECT_LIMIT_MSEC: int = 10000
const POLL_PAUSE_MSEC: int = 10
# A seat the pause case marks dropped on the host's relay.
const PAUSED_SEAT: int = 1
const RUN_SEED: int = 0x5EED

var _lines: LineCatcher = LineCatcher.new()


func run() -> void:
	if SteamNetwork.current_lobby_id != 0:
		_skip("routing: every case", "SteamNetwork is already in a lobby")
		return
	var kept_link: SteamNetworkScript._DevLink = SteamNetwork._dev_link
	var kept_screen: SceneRouter.Screen = SceneRouter.current_screen
	var kept_previous: SceneRouter.Screen = SceneRouter.previous_screen
	OS.add_logger(_lines)
	_test_host()
	_test_client()
	_test_new_run()
	_test_seats()
	_test_solo()
	OS.remove_logger(_lines)
	SteamNetwork._dev_link = kept_link
	# Back where the suite was, so no later case or the exit follows a route made here.
	SceneRouter.goto_screen(SceneRouter.Screen.LOADING)
	SceneRouter.current_screen = kept_screen
	SceneRouter.previous_screen = kept_previous


# A lone host on ENet: its route enters once, a second to the same screen changes nothing; paused,
# the route is held, still held on the next frame, and sent on the first frame after the resume.
func _test_host() -> void:
	SteamNetwork._dev_link = SteamNetworkScript._dev_link_of(
			PackedStringArray(["%s0" % [HOST_ARG]]), true
	)
	SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.LOBBY)
	if not SteamNetwork.has_active_session() or not SteamNetwork.is_authoritative():
		_skip("routing: the host's cases", "no ENet host could start here")
		SteamNetwork.leave_lobby()
		return
	_lines.take()
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.LOADING)
	var entered: Array = [SceneRouter.current_screen, SceneRouter.previous_screen]
	var entered_screen: int = SceneRouter.current_screen
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.LOADING)
	var lines: PackedStringArray = _lines.take()
	_check("routing: the host routes everyone; a route to the screen showing changes nothing", (
			entered_screen == SceneRouter.Screen.LOADING
			and [SceneRouter.current_screen, SceneRouter.previous_screen] == entered
			and _count(lines, "Routing everyone to LOADING.") == 2
			and _count(lines, "Entered screen LOADING.") == 1
			and _count(lines, "Already on LOADING; the route changes nothing.") == 1
	), "screens %s, %s; %s" % [
		entered, [SceneRouter.current_screen, SceneRouter.previous_screen], lines,
	])

	NetRelay._waits[PAUSED_SEAT] = 0.0
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.RESULTS)
	SceneRouter._process(0.0)
	var held: bool = (
			SceneRouter.current_screen == SceneRouter.Screen.LOADING
			and SceneRouter._has_held_route
	)
	NetRelay._waits.erase(PAUSED_SEAT)
	SceneRouter._process(0.0)
	lines = _lines.take()
	_check("routing: a paused host holds its route and sends it once the run resumes", (
			held
			and SceneRouter.current_screen == SceneRouter.Screen.RESULTS
			and not SceneRouter._has_held_route
			and _count(lines, "Holding the route to RESULTS until the run resumes.") == 1
			and _count(lines, "Routing everyone to RESULTS.") == 1
			and _count(lines, "Entered screen RESULTS.") == 1
	), "held %s, now %s; %s" % [held, SceneRouter.current_screen, lines])
	SteamNetwork.leave_lobby()


# A client of a bare ENet server, its mirror asking for state: a campaign map opened out of step
# routes nobody and sends no notice, but asks for the run; a stage that isn't the screen's keeps it
# waiting, and the run reaching it opens it again.
func _test_client() -> void:
	const CASE_NAME: String = "routing: a client screen out of step asks for the run, routes nobody"
	const REOPEN_CASE: String = "routing: a waiting client screen opens again once its run is there"
	var server: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	server.set_bind_ip(LOCALHOST)
	if server.create_server(0, 1) != OK:
		_skip(CASE_NAME, "no port can be opened on %s" % [LOCALHOST])
		_skip(REOPEN_CASE, "no port can be opened on %s" % [LOCALHOST])
		return
	SteamNetwork._dev_link = SteamNetworkScript._dev_link_of(PackedStringArray([
		"%s%s:%d" % [JOIN_ARG, LOCALHOST, server.host.get_local_port()],
	]), true)
	SteamNetwork._on_scene_router_screen_changed(SceneRouter.Screen.LOBBY)
	var connected: bool = _wait(func() -> bool:
		server.poll()
		SteamNetwork.multiplayer.poll()
		var peer: MultiplayerPeer = SteamNetwork.multiplayer.multiplayer_peer
		return (
				peer != null
				and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		)
	)
	if not connected or not SteamNetwork.has_active_session() or SteamNetwork.is_authoritative():
		_skip(CASE_NAME, "the in-process join didn't connect")
		_skip(REOPEN_CASE, "the in-process join didn't connect")
		SteamNetwork.leave_lobby()
		server.close()
		return
	var replica: CampaignData = CampaignData.new()
	replica.run_seed = RUN_SEED
	SaveService.multiplayer_replica = replica
	CampaignService._process(0.0)
	var mirrored: CampaignSession = Fixture.session(RUN_SEED, 2)
	mirrored.is_mirror = true
	_open_offer(mirrored.run.seat_run(0))
	CampaignService.session = mirrored
	var before: Array = [SceneRouter.current_screen, SceneRouter.previous_screen]
	var before_screen: SceneRouter.Screen = SceneRouter.current_screen
	var before_previous: SceneRouter.Screen = SceneRouter.previous_screen
	_lines.take()
	var screen: Node = (load(MAP_SCENE_PATH) as PackedScene).instantiate()
	_root.add_child(screen)
	var lines: PackedStringArray = _lines.take()
	_check(CASE_NAME, (
			[SceneRouter.current_screen, SceneRouter.previous_screen] == before
			and SceneRouter._is_waiting_for_run
			and _count(lines, "Waiting for the host's route: the run says STARTING_HEIRLOOM;"
					+ " asked the host for the run.") == 1
			and _count(lines, "NetRelay: sent request_sync, ") == 1
			and _count(lines, "NetRelay: sent notice") == 0
			and _count(lines, "Entered screen") == 0
	), "%s; screens %s, were %s" % [
		lines, [SceneRouter.current_screen, SceneRouter.previous_screen], before,
	])

	SceneRouter.current_screen = SceneRouter.Screen.TREASURE
	SceneRouter._process(0.0)
	var still_waiting: bool = (
			SceneRouter._is_waiting_for_run
			and SceneRouter.previous_screen == before_previous
	)
	mirrored.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	SceneRouter.current_screen = SceneRouter.Screen.CAMPAIGN_MAP
	SceneRouter._process(0.0)
	lines = _lines.take()
	_check(REOPEN_CASE, (
			still_waiting
			and not SceneRouter._is_waiting_for_run
			and SceneRouter.current_screen == SceneRouter.Screen.CAMPAIGN_MAP
			and SceneRouter.previous_screen == SceneRouter.Screen.CAMPAIGN_MAP
			and _count(lines, "The run reached CAMPAIGN_MAP; opening it again.") == 1
			and _count(lines, "NetRelay: sent notice") == 0
	), "still waiting %s; %s" % [still_waiting, lines])

	_root.remove_child(screen)
	screen.free()
	CampaignService.session = null
	SaveService.multiplayer_replica = null
	CampaignService._process(0.0)
	SceneRouter.current_screen = before_screen
	SceneRouter.previous_screen = before_previous
	SteamNetwork.leave_lobby()
	server.close()


# BUG-058: a client whose mirror started in the lobby, then routed to Loading before the first
# sync landed, is on a new run: the sync leaves it on Loading instead of moving it as a rejoin.
func _test_new_run() -> void:
	var kept_session: CampaignSession = CampaignService.session
	var kept_screen: SceneRouter.Screen = SceneRouter.current_screen
	var kept_previous: SceneRouter.Screen = SceneRouter.previous_screen
	var mirrored: CampaignSession = Fixture.session(RUN_SEED, 2)
	mirrored.is_mirror = true
	_open_offer(mirrored.run.seat_run(0))
	CampaignService.session = mirrored
	CampaignService._moves_on_sync = true
	CampaignService._is_from_lobby = true
	SceneRouter.current_screen = SceneRouter.Screen.LOADING
	_lines.take()
	CampaignService._on_net_relay_sync_received({}, {}, [], -1)
	var lines: PackedStringArray = _lines.take()
	_check("routing: a new run's sync after the route to Loading isn't a rejoin (BUG-058)", (
			SceneRouter.current_screen == SceneRouter.Screen.LOADING
			and not CampaignService._moves_on_sync
			and not CampaignService._is_from_lobby
			and _count(lines, "A new run: the host's route to LOADING came before its state;") == 1
			and _count(lines, "Rejoined the run") == 0
			and _count(lines, "Entered screen") == 0
	), "now %s; %s" % [SceneRouter.Screen.find_key(SceneRouter.current_screen), lines])
	CampaignService.session = kept_session
	SceneRouter.current_screen = kept_screen
	SceneRouter.previous_screen = kept_previous


# RunScreen.of() reads no seat: while any seat's starting offer is open every seat belongs on it,
# whichever seat this machine plays; once none is, on the map.
func _test_seats() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	_open_offer(made.run.seat_run(0))
	var kept: CampaignSession = CampaignService.session
	CampaignService.session = made
	var by_seat: Array[int] = []
	for seat: int in made.seats:
		CampaignService.set_local_seat(seat)
		by_seat.append(RunScreen.of(made))
	made.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	var after: int = RunScreen.of(made)
	CampaignService.session = kept
	_check("routing: any seat's open starting offer keeps every seat on it, then the map", (
			by_seat == [SceneRouter.Screen.STARTING_HEIRLOOM, SceneRouter.Screen.STARTING_HEIRLOOM]
			and after == SceneRouter.Screen.CAMPAIGN_MAP
	), "%s, then %d" % [by_seat, after])


# Solo, with no session: a move for everyone is a plain local switch, the screen showing loading
# again, and a solo run's screen follows its own offer.
func _test_solo() -> void:
	_lines.take()
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.LOADING)
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.LOADING)
	var lines: PackedStringArray = _lines.take()
	var solo: CampaignSession = Fixture.session(RUN_SEED)
	_open_offer(solo.run.seat_run(0))
	var offered: int = RunScreen.of(solo)
	solo.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	_check("routing: solo is unchanged: a local switch that reloads, its own offer first", (
			SceneRouter.current_screen == SceneRouter.Screen.LOADING
			and SceneRouter.previous_screen == SceneRouter.Screen.LOADING
			and _count(lines, "Entered screen LOADING.") == 2
			and _count(lines, "Routing everyone") == 0
			and _count(lines, "Already on") == 0
			and offered == SceneRouter.Screen.STARTING_HEIRLOOM
			and RunScreen.of(solo) == SceneRouter.Screen.CAMPAIGN_MAP
	), "%s; offer screen %d" % [lines, offered])


# An open starting offer of one option in seat_run's pending offers.
func _open_offer(seat_run: SeatRun) -> void:
	var offer: StartingOffer = StartingOffer.new()
	offer.options.append(StartingOffer.Option.new(StartingOffer.pool(EffectCatalog.index())[0]))
	offer.store(seat_run)


# Polls done every POLL_PAUSE_MSEC until it answers true, at most CONNECT_LIMIT_MSEC.
func _wait(done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + CONNECT_LIMIT_MSEC
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		OS.delay_msec(POLL_PAUSE_MSEC)
	return done.call()


# How many of lines hold part.
static func _count(lines: PackedStringArray, part: String) -> int:
	var found: int = 0
	for line: String in lines:
		if line.contains(part):
			found += 1
	return found


# Keeps every printed line while added with OS.add_logger, the router's and the relay's log lines
# among them. The engine may call a logger from any thread, so the list is locked.
class LineCatcher:
	extends Logger

	var _kept: PackedStringArray = []
	var _lock: Mutex = Mutex.new()

	func _log_message(message: String, _is_error: bool) -> void:
		_lock.lock()
		_kept.append(message)
		_lock.unlock()

	## The lines kept since the last call, then none.
	func take() -> PackedStringArray:
		_lock.lock()
		var taken: PackedStringArray = _kept.duplicate()
		_kept.clear()
		_lock.unlock()
		return taken
