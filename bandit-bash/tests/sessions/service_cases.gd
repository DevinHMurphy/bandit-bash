# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     service_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## [code]CampaignService[/code] cases for tests/sessions/run_all.gd: its lifecycle, its
## [RngSaveSection]s and [InstanceIdSaveSection]s. They drive the real [code]SaveService[/code],
## so they run only with a test user folder and are skipped otherwise.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# A second run seed for the debug panel's seed restart.
const OTHER_SEED: int = 0x123456789ABCD


func run() -> void:
	_run(_test_service_lifecycle)
	_run(_test_service_rng_campaign_streams)
	_run(_test_service_rng_battle_streams)
	_run(_test_service_rng_held_data_dropped)
	_run(_test_service_instance_ids)


func _test_service_lifecycle() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service lifecycle: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var activations: Array[String] = []
	var run_ends: Array[int] = []
	var started: Array[CampaignSession] = []
	var ended: Array[CampaignSession] = []
	var on_activated: Callable = func(mode: CampaignData.Mode, resumed: bool) -> void:
		activations.append("%s %s" % [CampaignData.Mode.find_key(mode), resumed])
	var on_run_ended: Callable = func(mode: CampaignData.Mode, _won: bool) -> void:
		run_ends.append(mode)
	var on_started: Callable = func(session: CampaignSession) -> void: started.append(session)
	var on_ended: Callable = func(session: CampaignSession) -> void: ended.append(session)
	saves.connect(&"campaign_activated", on_activated)
	saves.connect(&"run_ended", on_run_ended)
	service.connect(&"session_started", on_started)
	service.connect(&"session_ended", on_ended)
	SaveFile.delete_folder("user://saves/")

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var first: CampaignSession = service.get(&"session")
	_check("service: a new run builds a session", (
			first != null
			and first.mode == CampaignData.Mode.SOLO
			and first.rng.run_seed == RUN_SEED
			and first.seats == PackedInt32Array([0])
			and activations == ["SOLO false"]
	), str(activations))
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	_check("service: abandoning tears it down", (
			service.get(&"session") == null and first.is_closed and ended == [first]
	))

	saves.call(&"start_new_solo_run", RUN_SEED)
	var second: CampaignSession = service.get(&"session")
	saves.call(&"close_save_file")
	_check("service: closing the save file tears it down", (
			second != null and second.is_closed and service.get(&"session") == null
	))

	# Closing the save file kept the run in its slot, so it is continued.
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var third: CampaignSession = service.get(&"session")
	_check("service: a continued run builds a session", (
			third != null
			and third.rng.run_seed == RUN_SEED
			and activations[activations.size() - 1] == "SOLO true"
	), str(activations))
	var panel_scene: PackedScene = load("res://ui/debug/save_debug_panel.tscn")
	var panel: Node = panel_scene.instantiate()
	root.add_child(panel)
	var field: LineEdit = panel.get_node(^"%SeedField")
	var button: Button = panel.get_node(^"%SeedRunButton")
	field.text = RunSeed.format(OTHER_SEED)
	started.clear()
	ended.clear()
	run_ends.clear()
	button.pressed.emit()
	var fourth: CampaignSession = service.get(&"session")
	_check("service: the debug seed restart ends with exactly one live session", (
			third.is_closed
			and fourth != null
			and not fourth.is_closed
			and fourth.rng.run_seed == OTHER_SEED
			and started == [fourth]
			and ended == [third]
			and run_ends == [CampaignData.Mode.SOLO]
	), "%d started, %d ended" % [started.size(), ended.size()])
	panel.free()

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var fifth: CampaignSession = service.get(&"session")
	_check("service: the restarted run continues from its seed", (
			fifth != null
			and fourth.is_closed
			and fifth.rng.run_seed == OTHER_SEED
			and activations[activations.size() - 1] == "SOLO true"
	), str(activations))

	var begun: int = service.call(&"begin_battle", _request(fifth, {0: ["Drengr"]}))
	_check("service: a battle begins and is saved", (
			begun == OK and fifth.encounter != null and saves.get(&"combat") != null
	), error_string(begun))
	var result: CampaignSession.BattleResult = service.call(&"end_battle")
	_check("service: the battle ends and is saved", (
			result != null and fifth.encounter == null and saves.get(&"combat") == null
	))

	saves.call(&"clear_campaign")
	_check("service: clearing the campaign tears the session down", (
			fifth.is_closed and service.get(&"session") == null and saves.get(&"campaign") == null
	))
	var steam_ids: PackedInt64Array = [76561198000000001, 76561198000000002]
	saves.call(&"start_new_multiplayer_run", steam_ids)
	var hosted: CampaignSession = service.get(&"session")
	var loaded: int = saves.call(&"load_multiplayer_campaign")
	_check("service: loading a multiplayer campaign tears the session down", (
			hosted != null
			and hosted.seats == PackedInt32Array([0, 1])
			and hosted.is_closed
			and service.get(&"session") == null
			and loaded == OK
	), error_string(loaded))

	saves.call(&"abandon_run", CampaignData.Mode.MULTIPLAYER)
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	saves.disconnect(&"campaign_activated", on_activated)
	saves.disconnect(&"run_ended", on_run_ended)
	service.disconnect(&"session_started", on_started)
	service.disconnect(&"session_ended", on_ended)
	SaveFile.delete_folder("user://saves/")
	return true


# Through the real SaveService: a new run draws campaign streams, saves, closes and continues, and
# its next draws match a run that was never interrupted. Events don't exist yet; REWARD stands in
# for a stream drawn mid-event, and ROUTE_DRAW for a run-level one (the run's start has already
# drawn MAP_GENERATION for its map, so that stream isn't fresh).
func _test_service_rng_campaign_streams() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service rng campaign streams: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	var keys: Array[RngKey] = [
		RngKey.new(RngKey.RngPurpose.ROUTE_DRAW),
		RngKey.new(RngKey.RngPurpose.REWARD, FLOOR, NODE, 0),
	]
	var uninterrupted: RngStreams = RngStreams.new(RUN_SEED)

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var first: CampaignSession = service.get(&"session")
	for key: RngKey in keys:
		_draws(first.rng.stream(key), 5)
		_draws(uninterrupted.stream(key), 5)
	var saved: int = saves.call(&"save_checkpoint")
	var file: CampaignData = _read_campaign(saves)
	var entry: Dictionary = file.sections.get("rng", {})
	var data: Dictionary = entry.get("data", {})
	var holds_keys: bool = true
	for key: RngKey in keys:
		holds_keys = holds_keys and data.has(key.to_save_key())
	_check("service rng: the campaign file has an rng section at version 1", (
			saved == OK
			and entry.get("version", 0) as int == 1
			and data == first.rng.capture_campaign()
			and holds_keys
	), str(entry))

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	var continued: int = saves.call(&"continue_solo_run")
	var second: CampaignSession = service.get(&"session")
	var expected: Array = []
	var actual: Array = []
	for key: RngKey in keys:
		expected.append(_draws(uninterrupted.stream(key), 10))
		actual.append(_draws(second.rng.stream(key), 10))
	_check("service rng: a continued run's campaign streams draw on as if never saved", (
			continued == OK and second != null and second != first and actual == expected
	), error_string(continued))

	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# Begin, roll, save, close and resume: the battle's rolls go on where they were. Then the same
# battle with a combat file that can't be trusted restarts from Begin (BATTLE_RETRY) from fresh
# streams, never from the file's saved rng section, and replays its Begin rolls.
func _test_service_rng_battle_streams() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service rng battle streams: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	var reward_key: RngKey = RngKey.new(RngKey.RngPurpose.REWARD, FLOOR, NODE, 0)
	var reward_reference: RngStream = RngStreams.new(RUN_SEED).stream(reward_key)
	var rolls_reference: RngStream = Battle.fresh_stream(RngKey.RngPurpose.COMBAT_ROLLS, 0, -1)

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	_draws(run.rng.stream(reward_key), 3)
	_draws(reward_reference, 3)
	var begun: int = service.call(&"begin_battle", _request(run, {0: ["Drengr"]}))
	# One roll through the battle's session, then the rest on the registry's stream: they match
	# the reference only if the session holds that very stream.
	var begin_hit: bool = rolls_reference.roll_percent(50)
	var begin_rolls: Array[int] = _draws(rolls_reference, 6)
	var first_hit: bool = run.encounter.get_session(0).engine.rolls.roll_percent(50)
	var first_rolls: Array[int] = _draws(run.rng.stream(Battle.rolls_key(0)), 6)
	var phase_saved: int = saves.call(&"save_checkpoint")
	var next_rolls: Array[int] = _draws(rolls_reference, 6)
	_check("service rng: a battle rolls from a fresh COMBAT_ROLLS stream", (
			begun == OK
			and phase_saved == OK
			and first_hit == begin_hit
			and first_rolls == begin_rolls
	), "%s, %s" % [error_string(begun), error_string(phase_saved)])

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var resumed: CampaignSession = service.get(&"session")
	var resume_point: int = saves.get(&"resume_point")
	_check("service rng: a resumed battle's rolls go on where they were saved", (
			resume_point == CombatData.ResumePoint.BATTLE
			and _draws(resumed.rng.stream(Battle.rolls_key(0)), 6) == next_rolls
	), "resume point %d" % [resume_point])
	_check("service rng: and the campaign streams are as they were at Begin", (
			_draws(resumed.rng.stream(reward_key), 4) == _draws(reward_reference, 4)
	))

	# A combat file several checkpoints ahead isn't trusted, though its rng section is readable and
	# holds the rolls already made.
	saves.call(&"close_save_file")
	var combat_path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CombatData.get_file_name(CampaignData.Mode.SOLO)
	)
	var combat_file: SaveFile.ReadResult = SaveFile.read(combat_path)
	var envelope: Dictionary = combat_file.envelope
	var saved_sections: Dictionary = envelope.get(SaveFile.KEY_SECTIONS, {})
	envelope[SaveFile.KEY_CHECKPOINT_SEQ] = envelope[SaveFile.KEY_CHECKPOINT_SEQ] as int + 5
	var rewritten: Error = SaveFile.write(combat_path, envelope)
	saves.call(&"open_save_file", 1)
	print("    (one warning about a battle that restarts from Begin follows)")
	saves.call(&"continue_solo_run")
	var retried: CampaignSession = service.get(&"session")
	var retry_point: int = saves.get(&"resume_point")
	var combat_section: RngSaveSection = service.get(&"_combat_rng")
	_check("service rng: an untrusted combat file restarts the battle with no combat streams", (
			rewritten == OK
			and saved_sections.has("rng")
			and retry_point == CombatData.ResumePoint.BATTLE_RETRY
			and retried.rng.capture_combat().is_empty()
			and combat_section.capture().is_empty()
	), "resume point %d" % [retry_point])
	var rebegun: int = service.call(&"begin_battle", _request(retried, {0: ["Drengr"]}))
	var retry_hit: bool = (
			rebegun == OK and retried.encounter.get_session(0).engine.rolls.roll_percent(50)
	)
	_check("service rng: the restarted battle replays its Begin rolls from fresh streams", (
			rebegun == OK
			and retry_hit == begin_hit
			and _draws(retried.rng.stream(Battle.rolls_key(0)), 6) == begin_rolls
	), error_string(rebegun))

	service.call(&"end_battle")
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# The instance_ids sections through the real SaveService: Begin saves the campaign's counter, each
# combat checkpoint the live one, a resumed battle mints on from the checkpoint and a battle
# restarted from Begin from Begin's counter (event bus plan, question 42).
func _test_service_instance_ids() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service instance ids: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var request: CampaignSession.BattleRequest = _request(run, {0: ["Drengr"]})
	var unit_id: String = request.armies[0].units[0].id
	var begun: int = service.call(&"begin_battle", request)
	var at_begin: int = run.ids.get_next_value()
	run.ids.next_enemy_id("Brute")
	var saved: int = saves.call(&"save_checkpoint")
	var expected: PackedStringArray = [run.ids.next_enemy_id("Brute"), run.ids.next_item_id("Axe")]
	var campaign_ids: Dictionary = _read_campaign(saves).sections.get("instance_ids", {})
	var begin_data: Dictionary = campaign_ids.get("data", {})

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var resumed: CampaignSession = service.get(&"session")
	var resume_point: int = saves.get(&"resume_point")
	var minted: PackedStringArray = [
		resumed.ids.next_enemy_id("Brute"), resumed.ids.next_item_id("Axe"),
	]
	_check("service ids: a resumed battle mints the ids the first run minted", (
			begun == OK
			and saved == OK
			and resume_point == CombatData.ResumePoint.BATTLE
			and minted == expected
			and resumed.ids.label_of(unit_id) == "Drengr"
	), "%s and %s" % [minted, expected])
	var version: float = campaign_ids.get("version", 0.0)
	var begin_next: float = begin_data.get("next", 0.0)
	_check("service ids: the campaign file holds the counter as Begin captured it", (
			roundi(version) == 1 and roundi(begin_next) == at_begin
	), str(campaign_ids))

	saves.call(&"close_save_file")
	var combat_path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CombatData.get_file_name(CampaignData.Mode.SOLO)
	)
	var envelope: Dictionary = SaveFile.read(combat_path).envelope
	var combat_sections: Dictionary = envelope.get(SaveFile.KEY_SECTIONS, {})
	envelope[SaveFile.KEY_CHECKPOINT_SEQ] = envelope[SaveFile.KEY_CHECKPOINT_SEQ] as int + 5
	SaveFile.write(combat_path, envelope)
	saves.call(&"open_save_file", 1)
	print("    (one warning about a battle that restarts from Begin follows)")
	saves.call(&"continue_solo_run")
	var retried: CampaignSession = service.get(&"session")
	var retry_point: int = saves.get(&"resume_point")
	_check("service ids: a battle restarted from Begin mints from Begin's counter", (
			combat_sections.has("instance_ids")
			and retry_point == CombatData.ResumePoint.BATTLE_RETRY
			and retried.ids.get_next_value() == at_begin
	), "next %d, Begin %d" % [retried.ids.get_next_value(), at_begin])

	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# Data SaveService restored but no session took yet (a multiplayer campaign waiting in its lobby)
# is dropped by clear_campaign() and by the run's end; loading a multiplayer campaign drops the
# run that was live before it (event bus plan, question 47).
func _test_service_rng_held_data_dropped() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service rng held data: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var campaign_rng: RngSaveSection = service.get(&"_campaign_rng")
	var combat_rng: RngSaveSection = service.get(&"_combat_rng")
	SaveFile.delete_folder("user://saves/")

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	saves.call(&"clear_campaign")
	var steam_ids: PackedInt64Array = [76561198000000001, 76561198000000002]
	saves.call(&"start_new_multiplayer_run", steam_ids)
	var hosted: CampaignSession = service.get(&"session")
	_draws(hosted.rng.stream(RngKey.new(RngKey.RngPurpose.REWARD, FLOOR, NODE, 1)), 4)
	service.call(&"begin_battle", _request(hosted, {}))
	_draws(hosted.rng.stream(Battle.rolls_key(1)), 4)
	saves.call(&"save_checkpoint")
	var hosted_campaign: Dictionary = campaign_rng.capture()
	var hosted_combat: Dictionary = combat_rng.capture()

	saves.call(&"clear_campaign")
	_check("service rng: clearing a live run leaves nothing to save", (
			campaign_rng.capture().is_empty() and combat_rng.capture().is_empty()
	))

	saves.call(&"continue_solo_run")
	var solo: CampaignSession = service.get(&"session")
	_draws(solo.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)), 3)
	var loaded: int = saves.call(&"load_multiplayer_campaign")
	_check("service rng: loading a multiplayer campaign drops the live run's streams", (
			loaded == OK
			and solo.is_closed
			and service.get(&"session") == null
			and not hosted_campaign.is_empty()
			and not hosted_combat.is_empty()
			and campaign_rng.capture() == hosted_campaign
			and combat_rng.capture() == hosted_combat
	), error_string(loaded))

	saves.call(&"clear_campaign")
	_check("service rng: clear_campaign drops the held data", (
			campaign_rng.capture().is_empty() and combat_rng.capture().is_empty()
	))

	saves.call(&"load_multiplayer_campaign")
	var was_held: bool = campaign_rng.capture() == hosted_campaign
	saves.call(&"end_run", false)
	_check("service rng: the run's end drops the held data", (
			was_held and campaign_rng.capture().is_empty() and combat_rng.capture().is_empty()
	))

	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# The next `count` d100 rolls of a stream.
func _draws(stream: RngStream, count: int) -> Array[int]:
	var rolls: Array[int] = []
	for i: int in count:
		rolls.append(stream.randi_range(0, 99))
	return rolls


# Save file 1's solo campaign as written on disk.
func _read_campaign(saves: Node) -> CampaignData:
	var path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CampaignData.get_file_name(CampaignData.Mode.SOLO)
	)
	var loaded: CampaignData = CampaignData.new()
	var result: SaveFile.ReadResult = SaveFile.read(path)
	if result.error != OK or loaded.load_envelope(result.envelope) != OK:
		push_error("sessions tests: can't read %s" % [path])
	return loaded
