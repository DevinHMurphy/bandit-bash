# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_end_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## A co-op battle's end through the real [code]SaveService[/code] and [code]CampaignService[/code],
## for tests/sessions/run_all.gd, on real 2- and 3-seat runs and maps: a co-op run lost
## ([method CombatEncounter.is_run_lost], a map frozen with no help left, before every map has
## ended) ends and is archived as lost with every seat; a battle with a failed map is saved and
## reaches its results, the failed seat's showing the loss; a Boss no map beat ends the run as lost.
## Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# Any Steam ids: the first is the host's, one per seat.
const STEAM_BASE: int = 76561198000000001


func run() -> void:
	_run(_test_lost_run_archived.bind(2))
	_run(_test_lost_run_archived.bind(3))
	_run(_test_failed_map_reaches_results)
	_run(_test_boss_no_map_beat)


# Map 0 fails; every later map but the last fails too, and the last is frozen with no player unit
# left: the run is lost, and ending the battle archives it as lost for every seat.
func _test_lost_run_archived(seat_count: int) -> bool:
	var label: String = "co-op end %d seats" % [seat_count]
	if _skipped(label):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var ended: Array[bool] = []
	var on_run_ended: Callable = func(_mode: CampaignData.Mode, won: bool) -> void:
		ended.append(won)
	saves.connect(&"run_ended", on_run_ended)
	var run: CampaignSession = _start(saves, service, seat_count)
	var battle: CombatEncounter = null if run == null else run.encounter
	var is_lost: bool = false
	if battle != null:
		for seat: int in range(0, seat_count - 1):
			_end_map(battle.session_of_seat(seat), ENEMY)
		_freeze(battle.session_of_seat(seat_count - 1))
		is_lost = battle.is_run_lost() and not battle.is_finished()
	var result: CampaignSession.BattleResult = (
			service.call(&"end_battle") if battle != null else null
	)
	var record: ArchiveRecord = saves.call(&"take_ended_run")
	var has_slot: bool = saves.call(&"has_multiplayer_campaign")
	_check("%s: a lost co-op run ends as lost, before every map has ended" % [label], (
			is_lost
			and result != null
			and ended == [false]
			and service.get(&"session") == null
			and run != null and run.is_closed
			and not has_slot
	), "lost %s, ended %s" % [is_lost, ended])
	_check("%s: it is archived as lost with every seat" % [label], (
			record != null and not record.won and record.players.size() == seat_count
	))
	saves.disconnect(&"run_ended", on_run_ended)
	_finish(saves)
	return true


# Seat 0 wins and seat 1's map fails: the battle's end is saved, the run is at its results and
# goes on, and seat 1's results show the loss.
func _test_failed_map_reaches_results() -> bool:
	if _skipped("co-op end failed map"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var ended: Array[bool] = []
	var on_run_ended: Callable = func(_mode: CampaignData.Mode, won: bool) -> void:
		ended.append(won)
	saves.connect(&"run_ended", on_run_ended)
	var run: CampaignSession = _start(saves, service, 2)
	var battle: CombatEncounter = null if run == null else run.encounter
	if battle != null:
		_end_map(battle.session_of_seat(0), PLAYER)
		_end_map(battle.session_of_seat(1), ENEMY)
	var result: CampaignSession.BattleResult = (
			service.call(&"end_battle") if battle != null else null
	)
	var lost: CombatResultsModel = (
			null if run == null or run.run == null else CombatResultsModel.build(run, 1)
	)
	var won: CombatResultsModel = (
			null if run == null or run.run == null else CombatResultsModel.build(run, 0)
	)
	var kept: CampaignSession = service.get(&"session")
	var combat: CombatData = saves.get(&"combat")
	var campaign: CampaignData = saves.get(&"campaign")
	_check("co-op end failed map: the battle's end is saved and the run reaches its results", (
			result != null
			and ended.is_empty()
			and kept == run
			and run.encounter == null
			and run.run.flow.stage == RunFlow.Stage.RESULTS
			and combat == null
			and campaign != null
	), "ended %s" % [ended])
	_check("co-op end failed map: the failed seat's results show the loss, the winner's don't", (
			lost != null and lost.is_lost and won != null and not won.is_lost
	))
	saves.disconnect(&"run_ended", on_run_ended)
	_finish(saves)
	return true


# A co-op Boss whose every map failed: no floor follows, so the run ends as lost.
func _test_boss_no_map_beat() -> bool:
	if _skipped("co-op end boss"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var ended: Array[bool] = []
	var on_run_ended: Callable = func(_mode: CampaignData.Mode, won: bool) -> void:
		ended.append(won)
	saves.connect(&"run_ended", on_run_ended)
	var run: CampaignSession = _start(saves, service, 2)
	var battle: CombatEncounter = null if run == null else run.encounter
	if battle != null:
		# The node plays as a Boss from here: no Boss map pool ships yet to begin one on.
		run.run.graph.set_node_type(run.run.node, CampaignGraph.NodeType.BOSS)
		for session: CombatSession in battle.get_sessions():
			_end_map(session, ENEMY)
	var result: CampaignSession.BattleResult = (
			service.call(&"end_battle") if battle != null else null
	)
	var record: ArchiveRecord = saves.call(&"take_ended_run")
	_check("co-op end boss: a Boss no map beat ends the run as lost", (
			result != null
			and result.is_finished
			and ended == [false]
			and service.get(&"session") == null
			and record != null and not record.won
	), "ended %s" % [ended])
	saves.disconnect(&"run_ended", on_run_ended)
	_finish(saves)
	return true


# A new multiplayer run of seat_count seats in save file 1, past the starting offers, inside its
# first floor-1 Standard combat node (every seat's vote), its battle begun with no opening swap;
# null when any step failed.
func _start(saves: Node, service: Node, seat_count: int) -> CampaignSession:
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	var steam_ids: PackedInt64Array = []
	for seat: int in seat_count:
		steam_ids.append(STEAM_BASE + seat)
	saves.call(&"start_new_multiplayer_run", steam_ids)
	var run: CampaignSession = service.get(&"session")
	if run == null or run.run == null:
		return null
	for seat: int in run.seats:
		run.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	for node: int in run.run.next_nodes():
		if run.run.graph.type_of(node) != CampaignGraph.NodeType.STANDARD:
			continue
		for seat: int in run.seats:
			service.call(&"submit_command", RouteVoteCommand.for_session(run, seat, node))
		break
	if run.run.flow.stage != RunFlow.Stage.NODE:
		return null
	var request: CampaignSession.BattleRequest = run.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return null
	for seat: int in run.seats:
		request.opening_swap[seat] = false
	var begun: int = service.call(&"begin_battle", request)
	return run if begun == OK else null


# Freezes map as a co-op map with no player unit left freezes: every player unit defeated, held
# after its enemy phase (CombatEncounter.is_frozen).
func _freeze(map: CombatSession) -> void:
	for unit_id: String in map.state.units_of(PLAYER):
		map.state.defeat(map.engine, unit_id, "")
	map.state.phase_side = ENEMY
	map.state.is_phase_ended = true


# Ends map's combat with winner as the objectives check would.
func _end_map(map: CombatSession, winner: CombatFact.CombatSide) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	map.engine.record(ended)


# Closes the save file and deletes the test saves; a run still active is abandoned first.
func _finish(saves: Node) -> void:
	if saves.call(&"has_multiplayer_campaign"):
		saves.call(&"abandon_run", CampaignData.Mode.MULTIPLAYER)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _skipped(case_name: String) -> bool:
	if _has_test_user_dir():
		return false
	_skips += 1
	print("SKIP  %s: needs a test user folder (see run_all.gd's class doc)" % [case_name])
	return true
