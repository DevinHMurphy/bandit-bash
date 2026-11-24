# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_screen_route_cases.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

extends RefCounted
## Routing rule cases for the campaign screens suite (BUG-052): which moves are a seat's own
## (out of its starting offer, or from the map into it) and which are everyone's; a move for
## everyone never names the starting offer; each machine lands on its own seat's screen for one.
## For every mix of open and taken offers in a 2-seat run, and for each seat, a route for everyone
## by the host's run lands the seat on the screen it belongs on, so no screen it opens moves it
## again: the loop can't start. Solo lands on its offer, then the map, as before. The two-process
## run of the same flow is the net suite's ENet offer pairs.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"

## The cases start runs, which save.
const NEEDS_TEST_USER_FOLDER: bool = true

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 3
# Two made-up Steam ids: the host's, then the teammate's.
const STEAM_IDS: Array[int] = [0x1111, 0x2222]
const SOLO_SEED: int = 52

const MAP: SceneRouter.Screen = SceneRouter.Screen.CAMPAIGN_MAP
const OFFER: SceneRouter.Screen = SceneRouter.Screen.STARTING_HEIRLOOM
const LOADING: SceneRouter.Screen = SceneRouter.Screen.LOADING
const BATTLE: SceneRouter.Screen = SceneRouter.Screen.GAMEPLAY
const RESULTS: SceneRouter.Screen = SceneRouter.Screen.COMBAT_RESULTS
const TREASURE: SceneRouter.Screen = SceneRouter.Screen.TREASURE

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case. Call only with a test user folder.
func run() -> void:
	_test_seat_moves()
	_test_for_everyone()
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	_test_coop_landings()
	_test_solo()
	SaveService.close_save_file()
	CampaignService.set_local_seat(CampaignData.HOST_SEAT)
	SaveFile.delete_folder("user://saves/")


func _test_seat_moves() -> void:
	var seat_moves: Array[Array] = [[OFFER, MAP], [MAP, OFFER], [OFFER, BATTLE]]
	var team_moves: Array[Array] = [
		[LOADING, OFFER], [LOADING, MAP], [MAP, BATTLE], [MAP, TREASURE], [TREASURE, MAP],
		[RESULTS, MAP], [MAP, MAP],
	]
	var wrong: PackedStringArray = []
	for move: Array in seat_moves + team_moves:
		var from: SceneRouter.Screen = move[0]
		var to: SceneRouter.Screen = move[1]
		var expected: bool = seat_moves.has(move)
		if RunScreen._is_seat_move(from, to) != expected:
			wrong.append("%s -> %s is%s a seat move" % [
				_name(from), _name(to), "n't" if expected else "",
			])
	_check.call(
			"route: leaving the offer, or the map into it, is the seat's own; the rest everyone's",
			wrong.is_empty(), ", ".join(wrong)
	)


func _test_for_everyone() -> void:
	var kept: Array[SceneRouter.Screen] = [MAP, BATTLE, RESULTS, TREASURE, LOADING]
	var is_kept: bool = true
	for screen: SceneRouter.Screen in kept:
		is_kept = is_kept and RunScreen._for_everyone(screen) == screen
	_check.call("route: a move for everyone names the map in place of the offer, the rest as is", (
			RunScreen._for_everyone(OFFER) == MAP and is_kept
	), _name(RunScreen._for_everyone(OFFER)))


# Each mix of open and taken offers, each seat as the local one: where a host's route for
# everyone, by its own run, lands that seat, against the screen the seat belongs on.
func _test_coop_landings() -> void:
	var ids: PackedInt64Array = []
	for steam_id: int in STEAM_IDS:
		ids.append(steam_id)
	var err: Error = SaveService.start_new_multiplayer_run(ids)
	var session: CampaignSession = CampaignService.session
	_check.call("route: a new 2-seat run starts, both offers open", (
			err == OK and session != null and session.seats.size() == 2
			and StartingOffer.is_open(session.run.seat_run(0))
			and StartingOffer.is_open(session.run.seat_run(1))
	), error_string(err))
	if session == null or session.seats.size() != 2:
		return
	var offers: Array[StartingOffer] = [
		StartingOffer.pending(session.run.seat_run(0)),
		StartingOffer.pending(session.run.seat_run(1)),
	]
	# [seat 0 open, seat 1 open] for each mix.
	var mixes: Array[Array] = [[true, true], [false, true], [true, false], [false, false]]
	var wrong: PackedStringArray = []
	var host_routes: PackedStringArray = []
	for mix: Array in mixes:
		for seat: int in 2:
			if mix[seat]:
				offers[seat].store(session.run.seat_run(seat))
			else:
				session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
		CampaignService.set_local_seat(CampaignData.HOST_SEAT)
		var routed: SceneRouter.Screen = RunScreen._for_everyone(RunScreen.of(session))
		host_routes.append(_name(routed))
		if routed == OFFER:
			wrong.append("the host routed everyone to the offer")
		for seat: int in 2:
			CampaignService.set_local_seat(seat)
			var landed: SceneRouter.Screen = RunScreen.for_local_seat(session, routed)
			var own: SceneRouter.Screen = OFFER if mix[seat] else MAP
			if landed != own or RunScreen.of(session) != own:
				wrong.append("offers %s: seat %d landed on %s, belongs on %s" % [
					mix, seat, _name(landed), _name(RunScreen.of(session)),
				])
			for other: SceneRouter.Screen in [BATTLE, RESULTS, TREASURE, LOADING]:
				if RunScreen.for_local_seat(session, other) != other:
					wrong.append("offers %s: seat %d's %s was changed" % [mix, seat, _name(other)])
	_check.call(
			"route: for every mix of offers, each seat lands where it belongs, never moved again",
			wrong.is_empty(), "; ".join(wrong) + " (host routes %s)" % [host_routes]
	)
	_check.call("route: with no run, a move for everyone lands as it was sent", (
			RunScreen.for_local_seat(null, MAP) == MAP
	))
	CampaignService.set_local_seat(CampaignData.HOST_SEAT)


# Solo: Loading's Continue lands on the offer at once, never the map first; once taken, the map.
func _test_solo() -> void:
	var err: Error = SaveService.start_new_solo_run(SOLO_SEED)
	var session: CampaignSession = CampaignService.session
	if err != OK or session == null:
		_check.call("route: a new solo run starts", false, error_string(err))
		return
	var is_open: bool = StartingOffer.is_open(session.run.seat_run(0))
	var from_loading: SceneRouter.Screen = RunScreen._for_everyone(RunScreen.of(session))
	var first: SceneRouter.Screen = RunScreen.for_local_seat(session, from_loading)
	var is_seat_move: bool = RunScreen._is_seat_move(LOADING, RunScreen.of(session))
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	var after: SceneRouter.Screen = RunScreen.of(session)
	_check.call("route: solo opens on its offer from Loading, then the map, as before", (
			is_open and first == OFFER and not is_seat_move and after == MAP
			and RunScreen._is_seat_move(OFFER, after)
	), "offer open %s, first %s, then %s" % [is_open, _name(first), _name(after)])


static func _name(screen: SceneRouter.Screen) -> String:
	return SceneRouter.Screen.find_key(screen)
