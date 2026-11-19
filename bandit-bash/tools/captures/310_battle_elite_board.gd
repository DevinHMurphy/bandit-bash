# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     310_battle_elite_board.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The board's units with an elite among the enemies: the first prefixed enemy, else the first
## enemy given a prefix in this throwaway run (said in a NOTE), outlined by the LeaderMark a Defeat
## the Leader map's elite wears (drawing only, cleared by the next settle).[br]
## Needs: the battle started (300_battle_start).


func run() -> bool:
	var view: BattleView = battle_view()
	var session: CombatSession = view.get_session()
	var enemies: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	if enemies.is_empty():
		return true
	var elite_id: String = ""
	for enemy_id: String in enemies:
		if not session.state.unit(enemy_id).prefix_id.is_empty():
			elite_id = enemy_id
			break
	if elite_id.is_empty():
		elite_id = enemies[0]
		var prefixes: Array[Resource] = EffectCatalog.all_of(EffectCatalog.Kind.UNIT_PREFIX)
		if not prefixes.is_empty():
			session.state.unit(elite_id).prefix_id = str(prefixes[0].get(&"id"))
		note("elite board shot: %s given a prefix for the shot" % [elite_id])
	var objective: HudViewModel.ObjectiveView = HudViewModel.ObjectiveView.new()
	objective.marked_left_ids = PackedStringArray([elite_id])
	view.show_objective(objective)
	note("elite board shot: %s outlined as a leader; the board has no elite mark" % [elite_id])
	await frames(SETTLE_FRAMES)
	await capture("battle_board_elite")
	view.show_objective(null)
	return true
