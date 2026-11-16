# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_battle_cases.gd
# Author:
# Created:  November 13, 2026
# Modified: November 16, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## A run's battle through the real [code]SaveService[/code] and [code]CampaignService[/code], for
## tests/sessions/run_all.gd: one script plays a node's battle (a unit hurt, one fallen, a Hit
## delta, two hits, a grant, a checkpoint, the win, the end) without a quit, and with a quit and
## Continue before the result is collected, after it is applied but not saved, and after the save;
## every play ends in the same run at the node's results, rewards and item pick included, the XP
## tally and the grant survive the quit, and nothing is applied or rolled twice. A solo loss ends
## the run; choosing a node moves Save Select's floor (BUG-010).
## Skipped without a test user folder.

# The campaign suite's run_text(), which turns a run into comparable text.
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

# Where the battle script quits and continues, if anywhere.
enum Quit {
	NONE,
	## After the mid-battle checkpoint, before the result is collected.
	BEFORE_COLLECT,
	## After the result is applied to the run in memory, before any save.
	AFTER_APPLY,
	## After CampaignService.end_battle() saved.
	AFTER_SAVE,
}

const HIT_GAIN: float = 5.0
const GRANT_GOLD: int = 40
const HURT_HP: int = 4
# A won Standard combat by turn 1, under any floor-1 map's par, with a unit fallen: 30, +8 for
# under par.
const STANDARD_GOLD: int = 38


func run() -> void:
	_run(_test_quit_at_each_step)
	_run(_test_solo_loss_ends_run)
	_run(_test_save_select_floor)


func _test_quit_at_each_step() -> bool:
	if _skipped("run battle quits"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var straight: Play = _play(saves, service, Quit.NONE)
	_check("run battle: the battle plays to its end without a quit", (
			straight.errors.is_empty() and not straight.text.is_empty()
	), str(straight.errors))
	_check("run battle: its result is on the run once, paid, and the run is at its results", (
			straight.gold == straight.start_gold + GRANT_GOLD + STANDARD_GOLD
			and straight.army_size == 3
			and straight.fallen_size == 1
			and straight.hurt_hp == HURT_HP
			and straight.hit_deltas == 1
			and straight.used_maps.size() == 1
			and _floor_1_maps().has(straight.used_maps[0])
			and straight.is_at_results
	), "%d gold, army %d, fallen %d, hp %d, %d Hit deltas, %s" % [
		straight.gold, straight.army_size, straight.fallen_size, straight.hurt_hp,
		straight.hit_deltas, straight.used_maps,
	])
	for quit: Quit in [Quit.BEFORE_COLLECT, Quit.AFTER_APPLY, Quit.AFTER_SAVE]:
		var label: String = (Quit.find_key(quit) as String).to_lower()
		var played: Play = _play(saves, service, quit)
		_check("run battle: a quit %s loses and repeats nothing" % [label], (
				played.errors.is_empty() and played.text == straight.text
		), "%s\n      %s\n      %s" % [played.errors, played.text, straight.text])
		if quit != Quit.AFTER_SAVE:
			_check("run battle: a quit %s resumes the battle with its tally" % [label], (
					played.resume_points == [CombatData.ResumePoint.BATTLE]
					and played.tally_resumed == played.tally_saved
					and not played.tally_saved.is_empty()
					and played.tally_saved.contains("\"hit\":2")
			), "%s; %s / %s" % [
				played.resume_points, played.tally_saved, played.tally_resumed,
			])
		else:
			_check("run battle: a quit after the save continues at the results, no battle", (
					played.resume_points == [CombatData.ResumePoint.CAMPAIGN]
					and played.is_at_results
					and not played.had_combat_file
			), str(played.resume_points))
	return true


func _test_solo_loss_ends_run() -> bool:
	if _skipped("run battle loss"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var ended: Array[bool] = []
	var on_run_ended: Callable = func(_mode: CampaignData.Mode, won: bool) -> void:
		ended.append(won)
	saves.connect(&"run_ended", on_run_ended)
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))
	var begun: int = service.call(&"begin_battle", _node_request(run))
	if begun == OK:
		_end_map(run, ENEMY)
	var result: CampaignSession.BattleResult = (
			service.call(&"end_battle") if begun == OK else null
	)
	var record: ArchiveRecord = saves.call(&"take_ended_run")
	var has_slot: bool = saves.call(&"has_solo_campaign")
	_check("run battle: a solo loss ends the run as lost", (
			begun == OK
			and result != null
			and result.is_finished
			and not result.is_won
			and ended == [false]
			and saves.get(&"campaign") == null
			and service.get(&"session") == null
			and run.is_closed
			and record != null
			and not record.won
			and not has_slot
	), "%s, ended %s" % [error_string(begun), ended])
	saves.disconnect(&"run_ended", on_run_ended)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# BUG-010: Save Select's floor (CampaignData.floors_climbed, read from disk) follows the run's.
func _test_save_select_floor() -> bool:
	if _skipped("run battle save select floor"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var before: SaveFileSummary = saves.call(&"get_summary", 1)
	service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))
	var after: SaveFileSummary = saves.call(&"get_summary", 1)
	_check("run battle: choosing a node moves Save Select's floor to the run's (BUG-010)", (
			before.solo_floors_climbed == 0
			and after.solo_floors_climbed == 1
			and run.run.floor_number == 1
	), "%d then %d" % [before.solo_floors_climbed, after.solo_floors_climbed])
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# The battle script on a new solo run's first node. With quit, it quits and continues once at
# that point; a quit inside the battle resumes it from the run's own request, as the screen does,
# and plays on from the checkpoint as a player would.
func _play(saves: Node, service: Node, quit: Quit) -> Play:
	var played: Play = Play.new()
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	played.start_gold = run.run.seat_run(0).gold
	service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))
	if service.call(&"begin_battle", _node_request(run)) != OK:
		played.errors.append("begin")
		return played
	run.encounter.submit(StartCommand.new(0), 0)
	run.encounter.resolve_queued()
	if not _act(run, played):
		return played
	if saves.call(&"save_checkpoint") != OK:
		played.errors.append("checkpoint")
	played.tally_saved = JSON.stringify(run.tally.capture())

	if quit == Quit.BEFORE_COLLECT:
		run = _continue(saves, service, played, true)
	if run == null:
		return played
	_end_map(run, PLAYER)
	if quit == Quit.AFTER_APPLY:
		# CampaignService.end_battle()'s first two steps, then a crash before its save.
		var result: CampaignSession.BattleResult = run.collect_battle()
		run.run = run.run.apply_battle(
				result, run.ids, run.reward_rolls(result), CombatRewardRules.load_default(),
				EffectCatalog.index()
		)
		run = _continue(saves, service, played, true)
		if run == null:
			return played
		_end_map(run, PLAYER)
	if service.call(&"end_battle") == null:
		played.errors.append("end battle")
		return played
	if quit == Quit.AFTER_SAVE:
		run = _continue(saves, service, played, false)
		if run == null:
			return played

	var seat_run: SeatRun = run.run.seat_run(0)
	# Through JSON as on disk, so a continued run's whole floats (its pending offers) compare equal.
	played.text = JSON.stringify(JSON.parse_string(RunStateCases.run_text(run.run)))
	played.gold = seat_run.gold
	played.army_size = seat_run.army.size()
	played.fallen_size = seat_run.fallen.size()
	played.hurt_hp = seat_run.unit(played.hurt_id).hp
	played.hit_deltas = seat_run.unit(played.hit_id).stat_deltas.size()
	played.used_maps = run.run.flow.used_maps
	played.is_at_results = run.run.flow.stage == RunFlow.Stage.RESULTS
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return played


# The battle's events before its checkpoint: a unit hurt, a Hit booster's delta, two hits on an
# enemy, a grant of gold and a unit fallen. False, with an error, when the map has no enemy.
func _act(run: CampaignSession, played: Play) -> bool:
	var map: CombatSession = run.encounter.get_session(0)
	var army: Array[UnitInstance] = run.run.seat_run(0).army
	played.hit_id = army[1].instance_id
	played.hurt_id = army[2].instance_id
	var fall_id: String = army[3].instance_id
	var enemies: PackedStringArray = map.state.units_of(ENEMY)
	if enemies.is_empty():
		played.errors.append("no enemy on the map")
		return false
	map.state.unit(played.hurt_id).hp = HURT_HP
	map.engine.add_delta(played.hit_id, Modifier.new(
			CombatValue.Key.HIT, Modifier.Mode.ADD, HIT_GAIN, Modifier.SourceKind.POUCH_ITEM,
			"item:900", "Hit Booster"
	))
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, played.hit_id, enemies[0]))
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, played.hit_id, enemies[0]))
	run.receive_grant(0, CampaignGrant.Grant.GOLD, GRANT_GOLD, "", "effect:900")
	map.state.defeat(map.engine, fall_id, enemies[0])
	return true


# Save & Quit, then Continue; a battle is resumed from the continued run's own request. Returns the
# continued run, or null with an error.
func _continue(saves: Node, service: Node, played: Play, in_battle: bool) -> CampaignSession:
	saves.call(&"close_save_file")
	played.had_combat_file = SaveFile.exists(
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CombatData.get_file_name(CampaignData.Mode.SOLO)
	)
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var run: CampaignSession = service.get(&"session")
	played.resume_points.append(saves.get(&"resume_point"))
	if run == null or run.run == null:
		played.errors.append("continue")
		return null
	if not in_battle:
		return run
	var resumed: int = service.call(&"resume_battle", _node_request(run))
	if resumed != OK or run.encounter == null:
		played.errors.append("resume: %s" % [error_string(resumed)])
		return null
	played.tally_resumed = JSON.stringify(run.tally.capture())
	return run


# The maps a floor-1 standard combat may draw.
func _floor_1_maps() -> PackedStringArray:
	return CombatMapPools.load_default().pool_for(CampaignGraph.NodeType.STANDARD, 1).map_ids()


# The run's request for its current node, as the battle screen builds it.
func _node_request(run: CampaignSession) -> CampaignSession.BattleRequest:
	return run.run.battle_request(CombatMapPools.load_default(), EffectCatalog.index())


# Ends the battle's map with winner as the objectives check would.
func _end_map(run: CampaignSession, winner: CombatFact.CombatSide) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	run.encounter.get_session(0).engine.record(ended)


func _skipped(case_name: String) -> bool:
	if _has_test_user_dir():
		return false
	_skips += 1
	print("SKIP  %s: needs a test user folder (see run_all.gd's class doc)" % [case_name])
	return true


# What one play of the battle script ended with (_play).
class Play:
	extends RefCounted

	var errors: PackedStringArray = []
	# The final run as comparable text, and the parts the checks name.
	var text: String = ""
	var start_gold: int = 0
	var gold: int = 0
	var army_size: int = 0
	var fallen_size: int = 0
	var hurt_hp: int = 0
	var hit_deltas: int = 0
	var used_maps: PackedStringArray = []
	var is_at_results: bool = false
	var hit_id: String = ""
	var hurt_id: String = ""
	# Per Continue: resume_point; whether a combat file was on disk at the quit.
	var resume_points: Array[int] = []
	var had_combat_file: bool = false
	# The tally as saved at the checkpoint, and as the resumed battle holds it.
	var tally_saved: String = ""
	var tally_resumed: String = ""
