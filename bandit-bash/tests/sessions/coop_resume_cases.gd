# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_resume_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Resuming a co-op battle a seat left, through the real [code]SaveService[/code] and
## [code]CampaignService[/code], for tests/sessions/run_all.gd: a mid-battle forfeit at 2, 3 and 4
## seats, and a removal, keep the seat's entry in the campaign file but out of its players; a
## resume admits and needs only the seats left, rebuilds the battle with every map as saved, the
## left map still forfeited, and plays on; the battle's end drops the entry from the file. Also: a
## forfeit on the map drops it at once; a save whose entry is already gone restarts from Begin, as
## does one whose battle can't be rebuilt, without the seat; each forfeit's record lists the seats
## still in the run; the Save Select count and an abandon's record skip the seat; solo unchanged.
## Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# Any Steam ids: the first is the host's, one per seat.
const STEAM_BASE: int = 76561198000000501
# A unit's HP before the save, below any unit's maximum: the progress a resume keeps.
const HURT_HP: int = 3
# Any game version and build fingerprint, the same for host and joiner.
const VERSION: String = "1.0.0"
const CONTRACT: int = 7
# A floor no battle is on, written into a combat file so its rebuild refuses it.
const WRONG_FLOOR: int = 99
const SAVE_NUMBER: int = 1


func run() -> void:
	_run(_test_resume_after_forfeit.bind(2, 1, false))
	_run(_test_resume_after_forfeit.bind(3, 2, false))
	_run(_test_resume_after_forfeit.bind(4, 1, false))
	_run(_test_resume_after_forfeit.bind(3, 1, true))
	_run(_test_forfeit_on_the_map)
	_run(_test_old_shape_save_retries)
	_run(_test_unbuildable_battle_restarts_without_seat)
	_run(_test_records_list_seats_left)
	_run(_test_abandon_record)
	_run(_test_solo_unchanged)


# seat_count seats in battle; seat 0's unit is hurt, then leaving forfeits (or, is_removed, is
# removed). The file keeps its entry; the resume admits the others only, rebuilds every map as it
# stood, the left one still forfeited; the battle plays to its end, which drops the entry.
func _test_resume_after_forfeit(seat_count: int, leaving: int, is_removed: bool) -> bool:
	var tag: String = "resume after a %s at %d seats:" % [
		"removal" if is_removed else "forfeit", seat_count,
	]
	if _skipped(tag):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _start(saves, service, seat_count)
	var battle: CombatEncounter = null if run == null else run.encounter
	if battle == null:
		_check("%s the battle begins" % [tag], false)
		_finish(saves)
		return true
	var first: CombatSession = battle.session_of_seat(0)
	var hurt: String = _own_unit_on(first, 0)
	first.state.set_hp(hurt, HURT_HP)
	var batch: CampaignBatch = service.call(&"forfeit_seat", leaving, is_removed)
	var campaign: CampaignData = saves.get(&"campaign")
	var others: PackedInt32Array = _seats_but(seat_count, leaving)
	var on_disk: CampaignData = _campaign_on_disk()
	var summary: SaveFileSummary = saves.call(&"get_summary", SAVE_NUMBER)
	_check("%s the seat leaves the players; the file keeps its entry" % [tag], (
			batch != null and not batch.is_rejected()
			and campaign != null
			and _seats_of(campaign.players) == others
			and _seats_of(campaign.departed) == PackedInt32Array([leaving])
			and on_disk != null and on_disk.players.size() == seat_count
			and summary.multi_player_count == seat_count - 1
	), "disk %s" % [[] if on_disk == null else _seats_of(on_disk.players)])
	var saved: Dictionary[int, int] = _map_hashes(battle)
	var saved_encounter: int = battle.state_hash()

	var loaded: Error = saves.call(&"load_multiplayer_campaign")
	campaign = saves.get(&"campaign")
	var point: int = saves.get(&"resume_point")
	var required: PackedInt64Array = (
			PackedInt64Array() if campaign == null else campaign.get_required_steam_ids()
	)
	_check("%s the loaded campaign needs only the seats left" % [tag], (
			loaded == OK and point == CombatData.ResumePoint.BATTLE
			and _seats_of(campaign.players) == others
			and _seats_of(campaign.departed) == PackedInt32Array([leaving])
			and required == _steam_ids_of(others)
	), "required %s" % [required])
	_check("%s admission refuses the seat that left and admits the rest" % [tag], (
			_admission(required, leaving) == LobbyAdmission.Refusal.NOT_IN_CAMPAIGN
			and _admits_all_but(required, seat_count, leaving)
	))
	var resumed: Error = saves.call(&"resume_multiplayer_run")
	var again: CampaignSession = service.get(&"session")
	var err: Error = FAILED
	if resumed == OK and again != null and again.run != null:
		err = service.call(&"resume_battle", _begin_request(again))
	var rebuilt: CombatEncounter = null if again == null else again.encounter
	point = saves.get(&"resume_point")
	_check("%s the battle resumes as it stood, the left map still forfeited" % [tag], (
			err == OK and point == CombatData.ResumePoint.BATTLE
			and rebuilt != null
			and again.seats.size() == seat_count
			and rebuilt.forfeited_seats() == PackedInt32Array([leaving])
			and rebuilt.is_map_forfeited(rebuilt.session_of_seat(leaving).session_id)
			and _map_hashes(rebuilt) == saved
			and rebuilt.state_hash() == saved_encounter
			and rebuilt.session_of_seat(0).state.unit(hurt).hp == HURT_HP
	), "resume %s" % [error_string(err)])
	if rebuilt == null:
		_finish(saves)
		return true

	for seat: int in others:
		_end_map(rebuilt.session_of_seat(seat), PLAYER)
	var finished: bool = rebuilt.is_finished()
	var result: CampaignSession.BattleResult = service.call(&"end_battle")
	campaign = saves.get(&"campaign")
	on_disk = _campaign_on_disk()
	_check("%s the battle plays to its end, which drops the entry from the file" % [tag], (
			finished
			and result != null and result.forfeited == PackedInt32Array([leaving])
			and again.seats == others
			and again.run.seat_numbers() == others
			and campaign != null and campaign.departed.is_empty()
			and _seats_of(campaign.players) == others
			and on_disk != null and _seats_of(on_disk.players) == others
			and saves.get(&"combat") == null
	), "disk %s" % [[] if on_disk == null else _seats_of(on_disk.players)])
	_finish(saves)
	return true


# A forfeit on the map takes the entry out of the file at once, setting nothing aside.
func _test_forfeit_on_the_map() -> bool:
	if _skipped("forfeit on the map"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _new_run(saves, service, 3)
	var batch: CampaignBatch = null if run == null else service.call(&"forfeit_seat", 1)
	var campaign: CampaignData = saves.get(&"campaign")
	var on_disk: CampaignData = _campaign_on_disk()
	_check("forfeit on the map: the entry leaves the file at once", (
			batch != null and not batch.is_rejected()
			and campaign != null and campaign.departed.is_empty()
			and _seats_of(campaign.players) == PackedInt32Array([0, 2])
			and on_disk != null and _seats_of(on_disk.players) == PackedInt32Array([0, 2])
	))
	_finish(saves)
	return true


# A save from before entries were kept (the left seat's entry gone from the campaign file) still
# restarts its battle from Begin without the seat.
func _test_old_shape_save_retries() -> bool:
	if _skipped("an old-shape save"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _start(saves, service, 3)
	if run == null:
		_check("an old-shape save: the battle begins", false)
		_finish(saves)
		return true
	service.call(&"forfeit_seat", 2)
	var dropped: bool = _edit_campaign_file(func(envelope: Dictionary) -> void:
		var core: Dictionary = envelope[SaveFile.KEY_CORE]
		var kept: Array = []
		for entry: Variant in core["players"]:
			if (entry as Dictionary)["seat"] != 2:
				kept.append(entry)
		core["players"] = kept
	)
	var resumed: CampaignSession = _load_and_resume_session(saves, service)
	var err: Error = _resume_battle(service, resumed)
	var point: int = saves.get(&"resume_point")
	var campaign: CampaignData = saves.get(&"campaign")
	_check("an old-shape save: the battle restarts from Begin without the seat", (
			dropped and err == OK
			and point == CombatData.ResumePoint.BATTLE_RETRY
			and resumed.encounter != null
			and resumed.encounter.get_sessions().size() == 2
			and resumed.encounter.forfeited_seats().is_empty()
			and campaign != null and campaign.departed.is_empty()
	), "resume %s, point %d" % [error_string(err), point])
	_finish(saves)
	return true


# A saved battle the seat left that can't be rebuilt (its combat file names another floor) restarts
# from Begin without that seat, which leaves the run and the file.
func _test_unbuildable_battle_restarts_without_seat() -> bool:
	if _skipped("an unbuildable battle"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _start(saves, service, 3)
	if run == null:
		_check("an unbuildable battle: the battle begins", false)
		_finish(saves)
		return true
	service.call(&"forfeit_seat", 2)
	var path: String = _combat_path()
	var read: SaveFile.ReadResult = SaveFile.read(path)
	var edited: bool = read.error == OK
	if edited:
		var sections: Dictionary = read.envelope[SaveFile.KEY_SECTIONS]
		var data: Dictionary = (sections["combat_state"] as Dictionary)["data"]
		(data["encounter"] as Dictionary)["floor"] = WRONG_FLOOR
		edited = SaveFile.write(path, read.envelope) == OK
	var resumed: CampaignSession = _load_and_resume_session(saves, service)
	var campaign: CampaignData = saves.get(&"campaign")
	var was_set_aside: bool = campaign != null and campaign.departed.size() == 1
	var err: Error = _resume_battle(service, resumed)
	var point: int = saves.get(&"resume_point")
	var on_disk: CampaignData = _campaign_on_disk()
	var left: PackedInt32Array = PackedInt32Array([0, 1])
	_check("an unbuildable battle: it restarts from Begin without the seat that left", (
			edited and was_set_aside and err == OK
			and point == CombatData.ResumePoint.BATTLE_RETRY
			and resumed.seats == left
			and resumed.run.seat_numbers() == left
			and resumed.encounter != null
			and resumed.encounter.get_sessions().size() == 2
			and campaign.departed.is_empty() and _seats_of(campaign.players) == left
			and on_disk != null and _seats_of(on_disk.players) == left
	), "resume %s" % [error_string(err)])
	_finish(saves)
	return true


# Four seats; seats 1 and then 2 forfeit in one battle. Each record lists the run as it stood:
# every seat for the first, the three left for the second.
func _test_records_list_seats_left() -> bool:
	if _skipped("two forfeits' records"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _start(saves, service, 4)
	if run == null:
		_check("two forfeits' records: the battle begins", false)
		_finish(saves)
		return true
	service.call(&"forfeit_seat", 1)
	var first: ArchiveRecord = saves.call(&"take_forfeit_record", 1)
	service.call(&"forfeit_seat", 2)
	var second: ArchiveRecord = saves.call(&"take_forfeit_record", 2)
	_check("two forfeits' records: each lists the seats in the run as it stood", (
			first != null and first.forfeited
			and _record_seats(first) == PackedInt32Array([0, 1, 2, 3])
			and second != null and second.forfeited
			and _record_seats(second) == PackedInt32Array([0, 2, 3])
	), "%s, %s" % [_record_seats(first), _record_seats(second)])
	_finish(saves)
	return true


# A run abandoned from its file (no campaign active) after a mid-battle forfeit is archived without
# the seat that left.
func _test_abandon_record() -> bool:
	if _skipped("abandon after a forfeit"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var run: CampaignSession = _start(saves, service, 3)
	if run == null:
		_check("abandon after a forfeit: the battle begins", false)
		_finish(saves)
		return true
	service.call(&"forfeit_seat", 1)
	saves.call(&"close_save_file")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"abandon_run", CampaignData.Mode.MULTIPLAYER)
	var records: PackedStringArray = []
	for file_name: String in DirAccess.get_files_at(_archive_dir()):
		if file_name.get_extension() == "json":
			records.append(file_name)
	var record: ArchiveRecord = ArchiveRecord.new()
	var read: SaveFile.ReadResult = (
			SaveFile.read(_archive_dir() + records[0]) if records.size() == 1 else null
	)
	var is_read: bool = read != null and read.error == OK and record.load_envelope(read.envelope) == OK
	_check("abandon after a forfeit: the record lists the seats left", (
			err == OK and is_read and not record.won
			and _record_seats(record) == PackedInt32Array([0, 2])
	), "%s" % [records])
	_finish(saves)
	return true


# A solo battle saved and continued resumes as before: nothing is set aside, and the file holds
# the one seat.
func _test_solo_unchanged() -> bool:
	if _skipped("solo"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	saves.call(&"start_new_solo_run")
	var run: CampaignSession = service.get(&"session")
	var begun: Error = FAILED
	if run != null and run.run != null:
		run.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
		for node: int in run.run.next_nodes():
			if run.run.graph.type_of(node) == CampaignGraph.NodeType.STANDARD:
				service.call(&"submit_command", ChooseNodeCommand.new(0, node))
				break
		if run.run.flow.stage == RunFlow.Stage.NODE:
			begun = service.call(&"begin_battle", _begin_request(run))
	var saved_hash: int = -1 if run == null or run.encounter == null else (
			run.encounter.session_of_seat(0).state_hash()
	)
	saves.call(&"save_checkpoint")
	var continued: Error = saves.call(&"continue_solo_run")
	var campaign: CampaignData = saves.get(&"campaign")
	var again: CampaignSession = service.get(&"session")
	var err: Error = FAILED
	if continued == OK and again != null and again.run != null:
		err = service.call(&"resume_battle", _begin_request(again))
	var solo_path: String = (
			saves.call(&"get_save_file_dir", SAVE_NUMBER)
			+ CampaignData.get_file_name(CampaignData.Mode.SOLO)
	)
	var read: SaveFile.ReadResult = SaveFile.read(solo_path)
	var on_disk: CampaignData = CampaignData.new()
	var is_read: bool = read.error == OK and on_disk.load_envelope(read.envelope) == OK
	var point: int = saves.get(&"resume_point")
	_check("solo: a saved battle resumes as before; the file holds the one seat", (
			begun == OK and err == OK
			and point == CombatData.ResumePoint.BATTLE
			and campaign != null and campaign.departed.is_empty()
			and again.encounter != null
			and again.encounter.session_of_seat(0).state_hash() == saved_hash
			and is_read and _seats_of(on_disk.players) == PackedInt32Array([0])
	), "begin %s, resume %s" % [error_string(begun), error_string(err)])
	if saves.call(&"has_solo_campaign"):
		saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	_finish(saves)
	return true


# A new multiplayer run of seat_count seats in save file 1, on the map with no starting offers;
# null when it couldn't start.
func _new_run(saves: Node, service: Node, seat_count: int) -> CampaignSession:
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	saves.call(&"start_new_multiplayer_run", _steam_ids_of(_seats_but(seat_count, -1)))
	var run: CampaignSession = service.get(&"session")
	if run == null or run.run == null:
		return null
	for seat: int in run.seats:
		run.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	return run


# _new_run() inside its first floor-1 Standard combat node, every seat's vote cast, its battle
# begun with no opening swap; null when any step failed.
func _start(saves: Node, service: Node, seat_count: int) -> CampaignSession:
	var run: CampaignSession = _new_run(saves, service, seat_count)
	if run == null:
		return null
	for node: int in run.run.next_nodes():
		if run.run.graph.type_of(node) != CampaignGraph.NodeType.STANDARD:
			continue
		for seat: int in run.seats:
			service.call(&"submit_command", RouteVoteCommand.for_session(run, seat, node))
		break
	if run.run.flow.stage != RunFlow.Stage.NODE:
		return null
	var begun: int = service.call(&"begin_battle", _begin_request(run))
	return run if begun == OK else null


# The saved multiplayer campaign loaded and resumed; its new session, or null.
func _load_and_resume_session(saves: Node, service: Node) -> CampaignSession:
	if saves.call(&"load_multiplayer_campaign") != OK:
		return null
	if saves.call(&"resume_multiplayer_run") != OK:
		return null
	var session: CampaignSession = service.get(&"session")
	return session if session != null and session.run != null else null


# resumed's saved battle resumed from its run's request; FAILED with no session.
func _resume_battle(service: Node, resumed: CampaignSession) -> Error:
	if resumed == null:
		return FAILED
	return service.call(&"resume_battle", _begin_request(resumed))


# The run's battle request for its node, every seat's opening swap off; null outside a node.
func _begin_request(run: CampaignSession) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = run.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return null
	for seat: int in run.seats:
		request.opening_swap[seat] = false
	return request


# What LobbyAdmission decides for seat's account joining a lobby that holds only the host.
func _admission(required: PackedInt64Array, seat: int) -> int:
	return LobbyAdmission.decide(
			VERSION, VERSION, CONTRACT, CONTRACT, STEAM_BASE + seat, required,
			PackedInt64Array([STEAM_BASE])
	)


func _admits_all_but(required: PackedInt64Array, seat_count: int, leaving: int) -> bool:
	for seat: int in _seats_but(seat_count, leaving):
		if seat != CampaignData.HOST_SEAT and _admission(required, seat) != LobbyAdmission.ADMIT:
			return false
	return true


# Seats 0 to seat_count - 1 but skipped (-1: none).
func _seats_but(seat_count: int, skipped: int) -> PackedInt32Array:
	var seats: PackedInt32Array = []
	for seat: int in seat_count:
		if seat != skipped:
			seats.append(seat)
	return seats


func _steam_ids_of(seats: PackedInt32Array) -> PackedInt64Array:
	var steam_ids: PackedInt64Array = []
	for seat: int in seats:
		steam_ids.append(STEAM_BASE + seat)
	return steam_ids


func _seats_of(entries: Array[CampaignData.PlayerRun]) -> PackedInt32Array:
	var seats: PackedInt32Array = []
	for entry: CampaignData.PlayerRun in entries:
		seats.append(entry.seat)
	return seats


func _record_seats(record: ArchiveRecord) -> PackedInt32Array:
	var seats: PackedInt32Array = []
	if record == null:
		return seats
	for player: ArchiveRecord.ArchivedPlayer in record.players:
		seats.append(player.seat)
	return seats


# Each map's state hash, by session id.
func _map_hashes(battle: CombatEncounter) -> Dictionary[int, int]:
	var hashes: Dictionary[int, int] = {}
	for map: CombatSession in battle.get_sessions():
		hashes[map.session_id] = map.state_hash()
	return hashes


# The multiplayer campaign file as written last; null when it can't be read.
func _campaign_on_disk() -> CampaignData:
	var read: SaveFile.ReadResult = SaveFile.read(_campaign_path())
	var loaded: CampaignData = CampaignData.new()
	if read.error != OK or loaded.load_envelope(read.envelope) != OK:
		return null
	return loaded


# Applies edit to the multiplayer campaign file's envelope and writes it back; false on failure.
func _edit_campaign_file(edit: Callable) -> bool:
	var read: SaveFile.ReadResult = SaveFile.read(_campaign_path())
	if read.error != OK:
		return false
	edit.call(read.envelope)
	return SaveFile.write(_campaign_path(), read.envelope) == OK


func _campaign_path() -> String:
	return _save_dir() + CampaignData.get_file_name(CampaignData.Mode.MULTIPLAYER)


func _combat_path() -> String:
	return _save_dir() + CombatData.get_file_name(CampaignData.Mode.MULTIPLAYER)


func _archive_dir() -> String:
	return _save_dir() + ArchiveRecord.FOLDER_NAME + "/"


func _save_dir() -> String:
	return root.get_node(^"SaveService").call(&"get_save_file_dir", SAVE_NUMBER)


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
