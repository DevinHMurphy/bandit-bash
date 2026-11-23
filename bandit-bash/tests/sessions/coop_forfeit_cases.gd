# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_forfeit_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Co-op forfeits through the real [code]SaveService[/code] and [code]CampaignService[/code]
## ([method CampaignService.forfeit_seat]), for tests/sessions/run_all.gd, on real 1- to 3-seat
## runs and maps: on the map the seat leaves the campaign's players and its archive record is
## forfeited, and a resume needs and builds only the seats left; mid-battle its map leaves play,
## a teammate's unit there goes home as it stood, its units on their way leave with it, and the
## battle ends without it; its units on a teammate's map leave the battle with it; a 1-seat
## multiplayer run that loses ends as a solo loss does (BUG-040). Skipped without a test user
## folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# Any Steam ids: the first is the host's, one per seat.
const STEAM_BASE: int = 76561198000000101
# A sent unit's HP when the battle ends, below any unit's maximum.
const HURT_HP: int = 3


func run() -> void:
	_run(_test_on_the_map)
	_run(_test_mid_battle)
	_run(_test_unit_on_teammate_map_leaves)
	_run(_test_one_seat_loss_ends_run)


# Seat 1 of 3 forfeits on the map: it leaves the players, its record is forfeited, and a resume
# needs and builds only seats 0 and 2.
func _test_on_the_map() -> bool:
	if _skipped("forfeit on the map"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _new_run(saves, service, 3)
	var batch: CampaignBatch = null if run == null else service.call(&"forfeit_seat", 1)
	var record: ArchiveRecord = saves.call(&"take_forfeit_record", 1)
	var campaign: CampaignData = saves.get(&"campaign")
	var required: PackedInt64Array = (
			PackedInt64Array() if campaign == null else campaign.get_required_steam_ids()
	)
	_check("forfeit on the map: the seat leaves the run and the players", (
			batch != null and not batch.is_rejected()
			and run.seats == PackedInt32Array([0, 2])
			and required == PackedInt64Array([STEAM_BASE, STEAM_BASE + 2])
	), "required %s" % [required])
	var version: int = (
			0 if record == null else record.to_envelope().get(SaveFile.KEY_SCHEMA_VERSION)
	)
	_check("forfeit on the map: its record is a forfeited loss, the run as it stood", (
			record != null and record.forfeited and not record.won
			and record.players.size() == 3
			and version == 2
	))
	var loaded: Error = saves.call(&"load_multiplayer_campaign")
	var resumed: Error = saves.call(&"resume_multiplayer_run")
	var again: CampaignSession = service.get(&"session")
	_check("forfeit on the map: a resume needs and builds only the seats left", (
			loaded == OK and resumed == OK
			and again != null and again != run
			and again.seats == PackedInt32Array([0, 2])
			and again.run != null
			and again.run.seat_numbers() == PackedInt32Array([0, 2])
	), "loaded %s" % [error_string(loaded)])
	_finish(saves)
	return true


# Three seats in battle: seat 0 wins and sends a unit to seat 2's map, where it is hurt; seat 2
# forfeits. Its map leaves play and the players; the battle ends once seat 1's map ends, without
# seat 2, and the sent unit goes home with the HP it had.
func _test_mid_battle() -> bool:
	if _skipped("forfeit mid-battle"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _start(saves, service, 3)
	var battle: CombatEncounter = null if run == null else run.encounter
	if battle == null:
		_check("forfeit mid-battle: the battle begins", false)
		_finish(saves)
		return true
	var won: CombatSession = battle.session_of_seat(0)
	var forfeited: CombatSession = battle.session_of_seat(2)
	_end_map(won, PLAYER)
	var sent: String = _own_unit_on(won, 0)
	var send_problem: String = battle.send_unit(
			sent, won.session_id, forfeited.session_id, CombatFact.NO_TILE
	)
	battle.deliver_arrivals(forfeited.session_id)
	forfeited.state.set_hp(sent, HURT_HP)
	var batch: CampaignBatch = service.call(&"forfeit_seat", 2)
	var record: ArchiveRecord = saves.call(&"take_forfeit_record", 2)
	var campaign: CampaignData = saves.get(&"campaign")
	var refused: int = battle.submit(EndTurnCommand.new(2), forfeited.session_id)
	var unfinished: bool = battle.is_finished()
	_check("forfeit mid-battle: the map leaves play, the seat the players", (
			send_problem.is_empty()
			and batch != null and not batch.is_rejected()
			and _kinds(batch) == [CampaignFact.Kind.SEAT_FORFEITED]
			and battle.forfeited_seats() == PackedInt32Array([2])
			and refused == CombatSession.NO_ARRIVAL
			and not unfinished
			and campaign != null and campaign.players.size() == 2
			and record != null and record.forfeited
			and run.run.seat_numbers() == PackedInt32Array([0, 1, 2])
	), "send %s, batch %s" % [send_problem, "" if batch == null else batch.rejected_reason])
	_end_map(battle.session_of_seat(1), PLAYER)
	var finished: bool = battle.is_finished()
	var result: CampaignSession.BattleResult = service.call(&"end_battle")
	var home: UnitInstance = null if run.run == null else run.run.seat_run(0).unit(sent)
	var combat: CombatData = saves.get(&"combat")
	_check("forfeit mid-battle: the battle ends without it; a sent unit goes home as it stood", (
			finished
			and result != null
			and result.forfeited == PackedInt32Array([2])
			and not result.seats.has(2)
			and run.encounter == null
			and run.seats == PackedInt32Array([0, 1])
			and run.run.seat_numbers() == PackedInt32Array([0, 1])
			and run.run.flow.stage == RunFlow.Stage.RESULTS
			and home != null and home.hp == HURT_HP
			and combat == null
	), "hp %d" % [-1 if home == null else home.hp])
	_finish(saves)
	return true


# Three seats in battle; seat 1 wins and sends a unit to seat 0's map. Landed there or still on
# its way, the forfeit goes ahead and the unit leaves the battle with it.
func _test_unit_on_teammate_map_leaves() -> bool:
	for has_landed: bool in [true, false]:
		var label: String = "forfeit with a unit %s" % [
			"on a teammate's map" if has_landed else "on its way",
		]
		if _skipped(label):
			return true
		var saves: Node = root.get_node(^"SaveService")
		var service: Node = root.get_node(^"CampaignService")
		var run: CampaignSession = _start(saves, service, 3)
		var battle: CombatEncounter = null if run == null else run.encounter
		if battle == null:
			_check("%s: the battle begins" % [label], false)
			_finish(saves)
			return true
		var leaving: CombatSession = battle.session_of_seat(1)
		var target: CombatSession = battle.session_of_seat(0)
		_end_map(leaving, PLAYER)
		var unit_id: String = _own_unit_on(leaving, 1)
		battle.send_unit(unit_id, leaving.session_id, target.session_id, CombatFact.NO_TILE)
		if has_landed:
			battle.deliver_arrivals(target.session_id)
		var was_on_way: bool = battle.units_in_transit().has(unit_id)
		var batch: CampaignBatch = service.call(&"forfeit_seat", 1)
		var campaign: CampaignData = saves.get(&"campaign")
		var record: ArchiveRecord = saves.call(&"take_forfeit_record", 1)
		_check("%s: the forfeit goes ahead and the unit leaves with it" % [label], (
				was_on_way != has_landed
				and batch != null and not batch.is_rejected()
				and battle.forfeited_seats() == PackedInt32Array([1])
				and not battle.units_in_transit().has(unit_id)
				and target.state.unit(unit_id) == null
				and battle.session_of_unit(unit_id) != target
				and campaign != null and campaign.players.size() == 2
				and record != null
		), "" if batch == null else batch.rejected_reason)
		_finish(saves)
	return true


# BUG-040: a multiplayer run of one seat that loses its battle ends and is archived as lost, as a
# solo loss does.
func _test_one_seat_loss_ends_run() -> bool:
	if _skipped("one-seat multiplayer loss"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var ended: Array[bool] = []
	var on_run_ended: Callable = func(_mode: CampaignData.Mode, won: bool) -> void:
		ended.append(won)
	saves.connect(&"run_ended", on_run_ended)
	var run: CampaignSession = _start(saves, service, 1)
	var battle: CombatEncounter = null if run == null else run.encounter
	if battle != null:
		_end_map(battle.session_of_seat(0), ENEMY)
	var result: CampaignSession.BattleResult = (
			service.call(&"end_battle") if battle != null else null
	)
	var record: ArchiveRecord = saves.call(&"take_ended_run")
	var has_slot: bool = saves.call(&"has_multiplayer_campaign")
	var kept: CampaignSession = service.get(&"session")
	_check("BUG-040: a 1-seat multiplayer run that loses ends as a solo loss does", (
			result != null
			and ended == [false]
			and kept == null
			and not has_slot
			and record != null and not record.won and not record.forfeited
	), "ended %s" % [ended])
	saves.disconnect(&"run_ended", on_run_ended)
	_finish(saves)
	return true


# A new multiplayer run of seat_count seats in save file 1, on the map with no starting offers;
# null when it couldn't start.
func _new_run(saves: Node, service: Node, seat_count: int) -> CampaignSession:
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
	return run


# _new_run() inside its first floor-1 Standard combat node (every seat's vote, or the one seat's
# choice), its battle begun with no opening swap; null when any step failed.
func _start(saves: Node, service: Node, seat_count: int) -> CampaignSession:
	var run: CampaignSession = _new_run(saves, service, seat_count)
	if run == null:
		return null
	for node: int in run.run.next_nodes():
		if run.run.graph.type_of(node) != CampaignGraph.NodeType.STANDARD:
			continue
		if seat_count == 1:
			service.call(&"submit_command", ChooseNodeCommand.new(0, node))
		for seat: int in run.seats:
			if seat_count > 1:
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


# The kinds of batch's facts, in order.
func _kinds(batch: CampaignBatch) -> Array[CampaignFact.Kind]:
	var found: Array[CampaignFact.Kind] = []
	for fact: CampaignFact in batch.facts:
		found.append(fact.kind)
	return found


# A player unit of seat on map that isn't its commander; empty when there is none.
func _own_unit_on(map: CombatSession, seat: int) -> String:
	for unit_id: String in map.state.units_of(PLAYER):
		if map.state.seat_of(unit_id) == seat and map.commander_ids.get(seat, "") != unit_id:
			return unit_id
	return ""


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
