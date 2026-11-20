# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_offer_service_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## The starting heirloom offer through the real [code]SaveService[/code] and
## [code]CampaignService[/code], for tests/sessions/run_all.gd: a new run's first save already
## holds its open offer; a quit and Continue brings the same offer back, still open; taking it
## saves at once, and a Continue after finds it taken, the heirloom held, and refuses a second
## take. Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"


func run() -> void:
	_run(_test_offer_saved_and_continued)


func _test_offer_saved_and_continued() -> bool:
	if _skipped("starting offer service"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var first: CampaignSession = service.get(&"session")
	var offer: StartingOffer = StartingOffer.pending(first.run.seat_run(0))
	var saved: Dictionary = _saved_offer(saves)
	_check("starting offer service: the new run's first save holds its open offer", (
			offer != null and not offer.is_resolved
			and not saved.is_empty()
			and _as_saved(saved) == _as_saved(offer.capture())
	), JSON.stringify(saved))

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var continued: CampaignSession = service.get(&"session")
	var again: StartingOffer = StartingOffer.pending(continued.run.seat_run(0))
	_check("starting offer service: a quit and Continue shows the same offer, still open", (
			continued != first and again != null and not again.is_resolved
			and _as_saved(again.capture()) == _as_saved(offer.capture())
	))

	var command: StartingHeirloomCommand = _first_takeable(continued)
	var took: CampaignBatch = service.call(&"submit_command", command)
	var heirloom_id: String = again.options[command.option].heirloom_id
	var is_saved_taken: bool = _saved_offer(saves).get("is_resolved", false) == true
	_check("starting offer service: taking it saves at once", (
			took != null and not took.is_rejected()
			and is_saved_taken
	), "" if took == null else took.rejected_reason)

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var resumed: CampaignSession = service.get(&"session")
	var second: CampaignBatch = service.call(&"submit_command", _first_takeable(resumed))
	_check("starting offer service: after Continue it is taken, held, and can't be taken again", (
			not StartingOffer.is_open(resumed.run.seat_run(0))
			and resumed.run.seat_run(0).heirloom_ids().has(heirloom_id)
			and second != null and second.is_rejected()
	))
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	return true


# The first option of session's offer that takes, with a sub-choice that fits a new run: the first
# recruit or weapon (to the convoy), the third unit of the army.
func _first_takeable(session: CampaignSession) -> StartingHeirloomCommand:
	var offer: StartingOffer = StartingOffer.pending(session.run.seat_run(0))
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var unit_id: String = session.run.seat_run(0).army[2].instance_id
	for index: int in offer.options.size():
		var definition: StartingHeirloomDefinition = StartingOffer.definition_of(
				offer.options[index], catalog
		)
		var command: StartingHeirloomCommand = StartingHeirloomCommand.new(0, index)
		match definition.bonus:
			StartingHeirloomDefinition.Bonus.RECRUIT:
				command.recruit = 0
			StartingHeirloomDefinition.Bonus.REPLACE:
				command.recruit = 0
				command.unit_id = unit_id
			StartingHeirloomDefinition.Bonus.UPGRADE:
				command.unit_id = unit_id
			StartingHeirloomDefinition.Bonus.WEAPON:
				command.weapon = 0
				command.placement = ItemPlacement.new(ItemPlacement.Destination.CONVOY)
		if command.validate(session.run).is_empty():
			return command
	return StartingHeirloomCommand.new(0)


# The offer in save file 1's economy section for seat 0, as written on disk; empty for none.
func _saved_offer(saves: Node) -> Dictionary:
	var path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CampaignData.get_file_name(CampaignData.Mode.SOLO)
	)
	var loaded: CampaignData = CampaignData.new()
	var result: SaveFile.ReadResult = SaveFile.read(path)
	if result.error != OK or loaded.load_envelope(result.envelope) != OK:
		return {}
	for player: CampaignData.PlayerRun in loaded.players:
		if player.seat != 0:
			continue
		var entry: Dictionary = player.sections.get("economy", {})
		var data: Dictionary = entry.get("data", {})
		var offers: Dictionary = data.get("pending_offers", {})
		return offers.get(StartingOffer.OFFER_KEY, {})
	return {}


func _as_saved(data: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(data)))


func _skipped(case_name: String) -> bool:
	if _has_test_user_dir():
		return false
	_skips += 1
	print("SKIP  %s: needs a test user folder (see run_all.gd's class doc)" % [case_name])
	return true
