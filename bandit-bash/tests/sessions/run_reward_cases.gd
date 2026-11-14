# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_reward_cases.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## A won battle's rewards through the real [code]SaveService[/code] and
## [code]CampaignService[/code], for tests/sessions/run_all.gd: one script wins a node's M1 battle
## (a unit about to level up, two hits), takes an offer of the item pick and leaves the node, with
## no quit, and with a quit and Continue after the battle's end, after the pick is taken and after
## leaving. Every play ends in the same run; a Continue at the results brings back the same report,
## pick, rare offset and level-up, and a taken pick stays taken, its item in the convoy once. A
## skipped pick stays skipped. Skipped without a test user folder.

# The campaign suite's run_text(), which turns a run into comparable text.
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

# Where the script quits and continues, if anywhere.
enum Quit {
	NONE,
	## After CampaignService.end_battle() saved, with the pick still open.
	AFTER_END,
	## After the pick is taken or skipped, before leaving the node.
	AFTER_PICK,
	## After leaving the node.
	AFTER_LEAVE,
}

# XP the leveller holds before the battle: any Standard win's shared XP levels it up.
const XP_BEFORE: int = 95


func run() -> void:
	_run(_test_quit_around_the_pick)
	_run(_test_quit_after_a_skip)


func _test_quit_around_the_pick() -> bool:
	if _skipped("run rewards quits"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var straight: Play = _play(saves, service, Quit.NONE, 0)
	_check("run rewards: the battle is paid, the pick taken, the node left without a quit", (
			straight.errors.is_empty()
			and straight.offers > 0
			and straight.leveller_level == 2
			and straight.convoy_has_once
			and straight.is_on_map
	), "%s, %d offers, level %d" % [straight.errors, straight.offers, straight.leveller_level])
	for quit: Quit in [Quit.AFTER_END, Quit.AFTER_PICK, Quit.AFTER_LEAVE]:
		var label: String = (Quit.find_key(quit) as String).to_lower()
		var played: Play = _play(saves, service, quit, 0)
		_check("run rewards: a quit %s loses, rerolls and repeats nothing" % [label], (
				played.errors.is_empty()
				and played.results_text == straight.results_text
				and played.picked_text == straight.picked_text
				and played.text == straight.text
				and played.convoy_has_once
		), "%s\n      %s\n      %s" % [played.errors, played.text, straight.text])
		if quit == Quit.AFTER_END:
			_check("run rewards: Continue at the results brings back the report and open pick", (
					played.resume_points == [CombatData.ResumePoint.CAMPAIGN]
					and played.continued_text == straight.results_text
					and played.was_at_results
			), "%s\n      %s" % [played.continued_text, straight.results_text])
		elif quit == Quit.AFTER_PICK:
			_check("run rewards: after Continue the pick is still taken and can't be taken again", (
					played.continued_text == straight.picked_text
					and played.was_at_results
					and played.retake_rejected
			))
	return true


func _test_quit_after_a_skip() -> bool:
	if _skipped("run rewards skip"):
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var straight: Play = _play(saves, service, Quit.NONE, ItemPickCommand.SKIP)
	var played: Play = _play(saves, service, Quit.AFTER_PICK, ItemPickCommand.SKIP)
	_check("run rewards: a skipped pick stays skipped over a quit, and the node can be left", (
			straight.errors.is_empty()
			and played.errors.is_empty()
			and played.continued_text == straight.picked_text
			and played.text == straight.text
			and played.retake_rejected
			and not played.convoy_has_once
			and played.is_on_map
	), "%s / %s" % [straight.errors, played.errors])
	return true


# The script on a new solo run's first node: the battle won and ended, the pick taken (or
# skipped, with take SKIP), the node left. With quit, it quits and continues once at that point.
func _play(saves: Node, service: Node, quit: Quit, take: int) -> Play:
	var played: Play = Play.new()
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var leveller: UnitInstance = run.run.seat_run(0).army[1]
	played.leveller_id = leveller.instance_id
	leveller.xp = XP_BEFORE
	# Saved by the choice's checkpoint, before the battle begins.
	service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))
	var request: CampaignSession.BattleRequest = run.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if service.call(&"begin_battle", request) != OK:
		played.errors.append("begin")
		return _done(saves, played)
	run.encounter.submit(StartCommand.new(0), 0)
	run.encounter.resolve_queued()
	var map: CombatSession = run.encounter.get_session(0)
	var enemies: PackedStringArray = map.state.units_of(ENEMY)
	if enemies.is_empty():
		played.errors.append("no enemy on the map")
		return _done(saves, played)
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, played.leveller_id, enemies[0]))
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, played.leveller_id, enemies[0]))
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	map.engine.record(ended)
	if service.call(&"end_battle") == null:
		played.errors.append("end battle")
		return _done(saves, played)
	played.results_text = _text(run)
	var pick: ItemPick = ItemPick.pending(run.run.seat_run(0))
	played.offers = 0 if pick == null else pick.offers.size()
	if pick != null and take != ItemPickCommand.SKIP:
		played.taken_id = pick.offers[take].instance_id
	if quit == Quit.AFTER_END:
		run = _continue(saves, service, played)
		if run == null:
			return _done(saves, played)

	if _rejected(service, ItemPickCommand.new(0, take)):
		played.errors.append("pick")
	played.picked_text = _text(run)
	if quit == Quit.AFTER_PICK:
		run = _continue(saves, service, played)
		if run == null:
			return _done(saves, played)
	played.retake_rejected = _rejected(service, ItemPickCommand.new(0, 0))

	if _rejected(service, LeaveNodeCommand.new(0)):
		played.errors.append("leave")
	if quit == Quit.AFTER_LEAVE:
		run = _continue(saves, service, played)
		if run == null:
			return _done(saves, played)
	var seat_run: SeatRun = run.run.seat_run(0)
	played.text = _text(run)
	played.leveller_level = seat_run.unit(played.leveller_id).level
	played.convoy_has_once = (
			not played.taken_id.is_empty()
			and seat_run.convoy.count(played.taken_id) == 1
			and seat_run.items.has(played.taken_id)
	)
	played.is_on_map = run.run.is_on_map()
	return _done(saves, played)


# Save & Quit, then Continue. Returns the continued run, or null with an error.
func _continue(saves: Node, service: Node, played: Play) -> CampaignSession:
	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var run: CampaignSession = service.get(&"session")
	played.resume_points.append(saves.get(&"resume_point"))
	if run == null or run.run == null:
		played.errors.append("continue")
		return null
	played.continued_text = _text(run)
	played.was_at_results = run.run.flow.stage == RunFlow.Stage.RESULTS
	return run


# Whether the service rejected command.
func _rejected(service: Node, command: CampaignCommand) -> bool:
	var batch: CampaignBatch = service.call(&"submit_command", command)
	return batch == null or batch.is_rejected()


# The run as comparable text, after a trip through JSON as on disk, so a saved run's whole floats
# compare equal to the ints of one that never was.
func _text(run: CampaignSession) -> String:
	return JSON.stringify(JSON.parse_string(RunStateCases.run_text(run.run)))


func _done(saves: Node, played: Play) -> Play:
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return played


func _skipped(case_name: String) -> bool:
	if _has_test_user_dir():
		return false
	_skips += 1
	print("SKIP  %s: needs a test user folder (see run_all.gd's class doc)" % [case_name])
	return true


# What one play of the script ended with (_play).
class Play:
	extends RefCounted

	var errors: PackedStringArray = []
	# The run as comparable text at the results, after the pick, and at the end.
	var results_text: String = ""
	var picked_text: String = ""
	var text: String = ""
	# The run as the last Continue brought it back, and whether it was at the results then.
	var continued_text: String = ""
	var was_at_results: bool = false
	var resume_points: Array[int] = []
	var offers: int = 0
	var leveller_id: String = ""
	var leveller_level: int = 0
	var taken_id: String = ""
	var convoy_has_once: bool = false
	var retake_rejected: bool = false
	var is_on_map: bool = false
