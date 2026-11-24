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
## Routing rule cases for the campaign screens suite (BUG-052, P18 question 1): every seat waits on
## the starting offer and the team goes to the map together. For every mix of open and taken
## offers in a 2-seat run, and for each seat as the local one, [method RunScreen.of] names the same
## screen: the offer while any seat's is open, the map once every one is taken. So the host's one
## route lands every seat where it belongs, and no screen it opens moves it again: the loop can't
## start. Solo opens its offer, then the map, as before. The two-process run of the same flow is
## the net suite's ENet offer pairs.

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

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case. Call only with a test user folder.
func run() -> void:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	_test_coop_landings()
	_test_solo()
	SaveService.close_save_file()
	CampaignService.set_local_seat(CampaignData.HOST_SEAT)
	SaveFile.delete_folder("user://saves/")


# Each mix of open and taken offers, each seat as the local one: the screen the run belongs on,
# against the offer while any is open and the map once none is.
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
		var is_any_open: bool = false
		for seat: int in 2:
			var is_open: bool = mix[seat]
			is_any_open = is_any_open or is_open
			if is_open:
				offers[seat].store(session.run.seat_run(seat))
			else:
				session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
		var expected: SceneRouter.Screen = OFFER if is_any_open else MAP
		CampaignService.set_local_seat(CampaignData.HOST_SEAT)
		host_routes.append(_name(RunScreen.of(session)))
		for seat: int in 2:
			CampaignService.set_local_seat(seat)
			var landed: SceneRouter.Screen = RunScreen.of(session)
			if landed != expected:
				wrong.append("offers %s: seat %d belongs on %s, expected %s" % [
					mix, seat, _name(landed), _name(expected),
				])
	_check.call(
			"route: for every mix of offers, every seat belongs on the offer until all are taken",
			wrong.is_empty(), "; ".join(wrong) + " (host routes %s)" % [host_routes]
	)
	CampaignService.set_local_seat(CampaignData.HOST_SEAT)


# Solo: Loading's Continue opens the offer; once taken, the map.
func _test_solo() -> void:
	var err: Error = SaveService.start_new_solo_run(SOLO_SEED)
	var session: CampaignSession = CampaignService.session
	if err != OK or session == null:
		_check.call("route: a new solo run starts", false, error_string(err))
		return
	var is_open: bool = StartingOffer.is_open(session.run.seat_run(0))
	var first: SceneRouter.Screen = RunScreen.of(session)
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	var after: SceneRouter.Screen = RunScreen.of(session)
	_check.call("route: solo opens on its offer from Loading, then the map, as before", (
			is_open and first == OFFER and after == MAP
	), "offer open %s, first %s, then %s" % [is_open, _name(first), _name(after)])


static func _name(screen: SceneRouter.Screen) -> String:
	return SceneRouter.Screen.find_key(screen)
