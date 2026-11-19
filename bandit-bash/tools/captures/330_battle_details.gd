# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     330_battle_details.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Unit detail for the first player unit and for an enemy (an elite where there is one), then the
## runes panel, each where the controller opens it.[br]
## Needs: the battle started (300_battle_start); an elite only if 310_battle_elite_board ran.


func run() -> bool:
	var controller: BattleController = battle_controller()
	var session: CombatSession = battle_view().get_session()
	if controller.request_unit_detail(first_player(session)):
		await frames(SETTLE_FRAMES)
		await capture("battle_unit_detail")
		controller.step_back()
		await frames(SETTLE_FRAMES)
	if controller.request_unit_detail(_elite_or_first_enemy(session)):
		await frames(SETTLE_FRAMES)
		await capture("battle_unit_detail_enemy")
		controller.step_back()
		await frames(SETTLE_FRAMES)
	if controller.request_runes():
		await frames(SETTLE_FRAMES)
		await capture("battle_runes")
		controller.step_back()
		await frames(SETTLE_FRAMES)
	return true


# The enemy whose name isn't its class's alone (a prefixed elite), else the first enemy.
func _elite_or_first_enemy(session: CombatSession) -> String:
	var enemies: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	for enemy_id: String in enemies:
		var type_id: String = session.state.unit_type_of(enemy_id)
		if BattleText.name_of(session, enemy_id) != BattleText.type_name(type_id):
			return enemy_id
	return enemies[0] if not enemies.is_empty() else ""
