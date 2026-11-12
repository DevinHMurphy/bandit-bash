# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     logging_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Logging cases for tests/sessions/run_all.gd: the session logger's gating, and logging leaving
## a battle unchanged.

# NetLog's levels and categories through the script CombatSession preloads, for its logger().
const ERROR_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.ERROR
const WARN_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.WARN
const INFO_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.INFO
const DEBUG_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.DEBUG
const COMBAT_CATEGORY: CombatSession.NetLogScript.Category = (
		CombatSession.NetLogScript.Category.COMBAT
)
const EFFECTS_CATEGORY: CombatSession.NetLogScript.Category = (
		CombatSession.NetLogScript.Category.EFFECTS
)


func run() -> void:
	_run(_test_logger_gating)
	_run(_test_logging_changes_nothing)


func _test_logger_gating() -> bool:
	_set_log_level(LOG_WARN)
	_check("logging: lines below the level build nothing", (
			CombatSession.logger(DEBUG_LEVEL, COMBAT_CATEGORY) == null
			and CombatSession.logger(INFO_LEVEL, COMBAT_CATEGORY) == null
	))
	_check("logging: lines at or above the level print", (
			CombatSession.logger(WARN_LEVEL, COMBAT_CATEGORY) != null
			and CombatSession.logger(ERROR_LEVEL, EFFECTS_CATEGORY) != null
	))
	_set_log_level(LOG_DEBUG)
	_check("logging: DEBUG prints when asked for", (
			CombatSession.logger(DEBUG_LEVEL, EFFECTS_CATEGORY) != null
	))
	_set_log_level(LOG_WARN)
	return true


func _test_logging_changes_nothing() -> bool:
	var quiet: PackedStringArray = _scripted_battle(false)
	_set_log_level(LOG_DEBUG)
	print("    (DEBUG lines follow: a co-op battle with every log path and the draw trace)")
	var loud: PackedStringArray = _scripted_battle(true)
	_set_log_level(LOG_WARN)
	_check("logging: every level and the draw trace change no result", (
			quiet.size() > 20 and loud == quiet
	), "%d and %d lines" % [quiet.size(), loud.size()])
	return true


# A scripted co-op battle through the bridge: setup with loot, a cross-map heirloom that grants
# gold, rolls, a rejected command, a catch-up gap and a transfer. Returns every result as text:
# both maps' facts, the encounter's facts, the setup and the grants.
func _scripted_battle(is_tracing: bool) -> PackedStringArray:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	run.is_tracing_draws = is_tracing
	run.add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers)
	var request: CampaignSession.BattleRequest = _request(
			run, {0: ["Drengr", "Archer"], 1: ["Hakkapel"]}
	)
	var a0: String = request.armies[0].units[0].id
	var b0: String = request.armies[0].units[1].id
	var a1: String = request.armies[1].units[0].id
	var purse: EffectDefinition = _every_hit_by_allies(2)
	var gold: CampaignGrant = CampaignGrant.new()
	gold.amount = 50
	purse.operations.assign([gold])
	run.add_carrier(EffectInstance.new(
			run.ids.next_effect_id(),
			purse,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.HEIRLOOM
	))
	var battle: CombatEncounter = run.begin_battle(request)
	var s0: CombatSession = battle.get_session(0)
	var s1: CombatSession = battle.get_session(1)
	var e0: String = _add_enemy(run, s0)
	var e1: String = _add_enemy(run, s1)
	for i: int in 3:
		battle.submit(RollFixture.new(0, a0, e0), 0)
		battle.submit(AttackFixture.new(1, a1, e1), 1)
	battle.submit(MoveFixture.new(1, a0, Vector2i(2, 2)), 0)
	battle.resolve_queued()
	s0.mark_checkpoint()
	s0.facts_since(1)
	battle.submit(EndMapFixture.new(), 0)
	battle.resolve_queued()
	battle.send_unit(b0, 0, 1, Vector2i(1, 3))
	battle.deliver_arrivals(1)

	var lines: PackedStringArray = [battle.setup.summary()]
	for session: CombatSession in [s0, s1]:
		for fact: CombatFact in session.engine.fact_log:
			lines.append(fact.to_log_line())
		for record: RollRecord in session.engine.rolls.records:
			lines.append("roll %d %d" % [record.value, record.outcome])
	for fact: CombatFact in battle.fact_log:
		lines.append("e %s" % [fact.to_log_line()])
	for grant: CampaignSession.Grant in run.grants:
		lines.append(grant.describe())
	run.end_battle()
	return lines
