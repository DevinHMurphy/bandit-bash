# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_service_cases.gd
# Author:
# Created:  November 13, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## The run state through the real [code]SaveService[/code] and [code]CampaignService[/code], for
## tests/sessions/run_all.gd: a new solo run is built, saved with its six run sections and
## continued identically; the same seed starts the same run; a resolved command saves and a
## rejected one doesn't; a save holding no run (a crash between a new run's two writes) continues
## as the same new run; a multiplayer run has a part per seat. Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# The campaign suite's run_text(), which turns a run into comparable text.
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

const RUN_KEYS: PackedStringArray = ["campaign_map", "run_flow"]
const SEAT_KEYS: PackedStringArray = ["roster", "heirlooms", "runes", "economy"]


func run() -> void:
	_run(_test_new_run_saves_and_continues)
	_run(_test_commands_save)
	_run(_test_crash_between_first_writes)
	_run(_test_multiplayer_run)


func _test_new_run_saves_and_continues() -> bool:
	if _skipped("run service new run"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var first: CampaignSession = service.get(&"session")
	var built: String = RunStateCases.run_text(first.run) if first.run != null else ""
	var file: CampaignData = _read_campaign(saves)
	_check("run service: a new run is built and saved with every run section at its version", (
			first.run != null
			and first.run.seat_run(0).army.size() == 4
			and _holds_run(file)
	), _section_summary(file))

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var continued: CampaignSession = service.get(&"session")
	_check("run service: a continued run is the run that was saved", (
			continued != null
			and continued != first
			and continued.run != null
			and _as_saved(RunStateCases.run_text(continued.run)) == _as_saved(built)
	))

	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var again: CampaignSession = service.get(&"session")
	_check("run service: the same seed starts the same run", (
			again.run != null and RunStateCases.run_text(again.run) == built
	))
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


func _test_commands_save() -> bool:
	if _skipped("run service commands"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var session: CampaignSession = service.get(&"session")
	var node_id: int = session.run.graph.nodes_on_floor(1)[0]
	var seq_before: int = _read_campaign(saves).checkpoint_seq
	var rejected: CampaignBatch = service.call(&"submit_command", LeaveNodeCommand.new(0))
	var seq_rejected: int = _read_campaign(saves).checkpoint_seq
	# These cases start past the starting heirloom offer, with nothing taken from it.
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	var chosen: CampaignBatch = service.call(
			&"submit_command", ChooseNodeCommand.new(0, node_id)
	)
	var file: CampaignData = _read_campaign(saves)
	var map_entry: Dictionary = file.sections.get("campaign_map", {})
	var flow_entry: Dictionary = file.sections.get("run_flow", {})
	var map_data: Dictionary = map_entry.get("data", {})
	var flow_data: Dictionary = flow_entry.get("data", {})
	var visited: Array = map_data.get("visited", [])
	_check("run service: a rejected command doesn't save", (
			rejected.is_rejected() and seq_rejected == seq_before
	))
	_check("run service: choosing a node saves the locked floor and the stage", (
			not chosen.is_rejected()
			and file.checkpoint_seq == seq_before + 1
			and visited.size() == 1
			and ItemInstance.read_int(visited[0], -1) == node_id
			and str(flow_data.get("stage", "")) == "node"
	), str(map_data.get("visited")))

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var continued: CampaignSession = service.get(&"session")
	_check("run service: a continued run is inside the chosen node", (
			continued.run != null
			and continued.run.node == node_id
			and not continued.run.is_on_map()
			and RunStateCases.run_text(continued.run) == RunStateCases.run_text(session.run)
	))
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# A new run's first save is written before its session exists, so it holds no run, a fresh id
# counter and no streams; a crash before the second save leaves just that. Continuing it builds
# the new run again, which is the same run, and saves it.
func _test_crash_between_first_writes() -> bool:
	if _skipped("run service crash between writes"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var first: CampaignSession = service.get(&"session")
	var built: String = RunStateCases.run_text(first.run)
	saves.call(&"close_save_file")

	var path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CampaignData.get_file_name(CampaignData.Mode.SOLO)
	)
	var envelope: Dictionary = SaveFile.read(path).envelope
	var sections: Dictionary = envelope[SaveFile.KEY_SECTIONS]
	for key: String in RUN_KEYS:
		sections[key] = {"version": 1, "data": {}}
	sections["rng"] = {"version": 1, "data": {}}
	sections["instance_ids"] = {"version": 1, "data": InstanceIdAllocator.new().capture()}
	var players: Array = envelope[SaveFile.KEY_CORE]["players"]
	for player: Variant in players:
		var player_sections: Dictionary = (player as Dictionary)["sections"]
		for key: String in SEAT_KEYS:
			player_sections[key] = {"version": 1, "data": {}}
	var rewritten: Error = SaveFile.write(path, envelope)

	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var continued: CampaignSession = service.get(&"session")
	_check("run service: a save holding no run continues as the same new run, saved", (
			rewritten == OK
			and continued.run != null
			and RunStateCases.run_text(continued.run) == built
			and _holds_run(_read_campaign(saves))
	), error_string(rewritten))
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


func _test_multiplayer_run() -> bool:
	if _skipped("run service multiplayer"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	var steam_ids: PackedInt64Array = [76561198000000001, 76561198000000002]
	saves.call(&"start_new_multiplayer_run", steam_ids)
	var hosted: CampaignSession = service.get(&"session")
	var seat_zero: SeatRun = hosted.run.seat_run(0) if hosted.run != null else null
	var seat_one: SeatRun = hosted.run.seat_run(1) if hosted.run != null else null
	var multi: CampaignData = _read_campaign(saves, CampaignData.Mode.MULTIPLAYER)
	_check("run service: a multiplayer run has an army and gold per seat, all saved", (
			seat_zero != null
			and seat_one != null
			and seat_zero.army.size() == 4
			and seat_one.army.size() == 4
			and seat_zero.army[0].instance_id != seat_one.army[0].instance_id
			and seat_one.gold == 100
			and _holds_run(multi)
			and multi.players.size() == 2
	), _section_summary(multi))
	saves.call(&"abandon_run", CampaignData.Mode.MULTIPLAYER)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# Counts a skip and says so when this run has no test user folder.
func _skipped(case_name: String) -> bool:
	if _has_test_user_dir():
		return false
	_skips += 1
	print("SKIP  %s: needs a test user folder (see run_all.gd's class doc)" % [case_name])
	return true


# Whether every run section of the file, and every seat's, is at its version (campaign_map,
# run_flow, economy and heirlooms 2, the rest 1) and holds a run.
func _holds_run(file: CampaignData) -> bool:
	for key: String in RUN_KEYS:
		var shared_version: int = (
				RunSaveSections.MAP_VERSION if key == "campaign_map"
				else RunSaveSections.FLOW_VERSION
		)
		if not _is_filled(file.sections.get(key), shared_version):
			return false
	for player: CampaignData.PlayerRun in file.players:
		for key: String in SEAT_KEYS:
			var version: int = RunSaveSections.VERSION
			if key == "economy":
				version = RunSaveSections.ECONOMY_VERSION
			elif key == "heirlooms":
				version = RunSaveSections.HEIRLOOMS_VERSION
			if not _is_filled(player.sections.get(key), version):
				return false
	return not file.players.is_empty()


func _is_filled(entry: Variant, version: int) -> bool:
	if not entry is Dictionary:
		return false
	var section: Dictionary = entry
	var data: Variant = section.get("data")
	return (
			ItemInstance.read_int(section.get("version"), 0) == version
			and data is Dictionary
			and not (data as Dictionary).is_empty()
	)


func _section_summary(file: CampaignData) -> String:
	var keys: PackedStringArray = PackedStringArray(file.sections.keys())
	for player: CampaignData.PlayerRun in file.players:
		keys.append("seat %d: %s" % [player.seat, PackedStringArray(player.sections.keys())])
	return ", ".join(keys)


# text (a run_text()) as a save's JSON gives it back: pending offers keep their numbers as the
# file read them, so a whole number reads back as a whole float on one side only.
func _as_saved(text: String) -> String:
	return JSON.stringify(JSON.parse_string(text))


# The open save file 1's campaign of slot_mode as written on disk.
func _read_campaign(
		saves: Node, slot_mode: CampaignData.Mode = CampaignData.Mode.SOLO
) -> CampaignData:
	var path: String = (
			(saves.call(&"get_save_file_dir", 1) as String) + CampaignData.get_file_name(slot_mode)
	)
	var loaded: CampaignData = CampaignData.new()
	var result: SaveFile.ReadResult = SaveFile.read(path)
	if result.error != OK or loaded.load_envelope(result.envelope) != OK:
		push_error("sessions tests: can't read %s" % [path])
	return loaded
