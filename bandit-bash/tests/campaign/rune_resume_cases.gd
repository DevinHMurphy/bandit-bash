# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_resume_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## The run's runes through a battle quit and continued, through the real [code]SaveService[/code]
## and [code]CampaignService[/code], for tests/sessions/run_all.gd (BUG-014): a rune discarded
## before the checkpoint stays gone after the resume, the kept rune is still castable (its effect
## restored from the save), and the battle's end writes back only the kept rune. Skipped without a
## test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

const NEEDS_TEST_USER_FOLDER: bool = true

# The two runes given to the run: one discarded in battle, one kept.
const DISCARDED_RUNE: String = "mend"
const KEPT_RUNE: String = "aegis"


func run() -> void:
	_run(_test_runes_survive_resume)


func _test_runes_survive_resume() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var seat_run: SeatRun = run.run.seat_run(0)
	# These cases start past the starting heirloom offer, with nothing taken from it.
	seat_run.pending_offers.erase(StartingOffer.OFFER_KEY)
	var discarded_id: String = run.ids.next_rune_id(DISCARDED_RUNE)
	var kept_id: String = run.ids.next_rune_id(KEPT_RUNE)
	seat_run.rune_slots[0] = SeatRun.RuneSlot.new(discarded_id, DISCARDED_RUNE)
	seat_run.rune_slots[1] = SeatRun.RuneSlot.new(kept_id, KEPT_RUNE)
	service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))
	var begun: int = service.call(&"begin_battle", _node_request(run))
	var held: PackedStringArray = (
			PackedStringArray() if begun != OK
			else run.encounter.get_session(0).state.rune_slots.get(0, PackedStringArray())
	)
	_check("rune resume: the battle begins with both runes in its slots", (
			held == PackedStringArray([discarded_id, kept_id])
	), error_string(begun))
	if begun != OK:
		_close(saves)
		return true
	run.encounter.submit(StartCommand.new(0), 0)
	run.encounter.resolve_queued()
	run.encounter.submit(DiscardRuneCommand.new(0, discarded_id), 0)
	run.encounter.resolve_queued()
	var checkpoint: int = saves.call(&"save_checkpoint")
	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	run = service.get(&"session")
	var resumed: int = (
			ERR_UNAVAILABLE if run == null
			else service.call(&"resume_battle", _node_request(run))
	)
	var map: CombatSession = null if resumed != OK else run.encounter.get_session(0)
	var left: PackedStringArray = (
			PackedStringArray() if map == null
			else map.state.rune_slots.get(0, PackedStringArray())
	)
	_check("rune resume: after a quit and Continue the discarded rune is gone, the kept one held", (
			checkpoint == OK and map != null and left == PackedStringArray([kept_id])
			and RuneResolver.definition_of(map.engine, kept_id) != null
	), "%s, %s, %s" % [error_string(checkpoint), error_string(resumed), left])
	if map == null:
		_close(saves)
		return true
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	map.engine.record(ended)
	service.call(&"end_battle")
	var after: SeatRun = run.run.seat_run(0)
	_check("rune resume: the battle's end writes back only the kept rune, in its slot", (
			after.rune_slots[0].is_empty() and after.rune_slots[1].instance_id == kept_id
	), str(after.capture_runes()))
	_close(saves)
	return true


func _close(saves: Node) -> void:
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# The run's request for its current node, as the battle screen builds it.
func _node_request(run: CampaignSession) -> CampaignSession.BattleRequest:
	return run.run.battle_request(CombatMapPools.load_default(), EffectCatalog.index())
