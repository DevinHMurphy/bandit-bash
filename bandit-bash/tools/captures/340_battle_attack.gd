# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     340_battle_attack.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Walks a unit to an enemy in reach and opens Attack: the action menu, targeting, the forecast,
## and the forecast as a multi-hit attack. Waits whole phases out while no unit has a target, up
## to [constant TURNS_FOR_ATTACK]; backs out of every panel after.[br]
## Needs: the battle started and idle (300_battle_start).

# Player phases the battle may wait through for a unit with an attack target.
const TURNS_FOR_ATTACK: int = 4


func run() -> bool:
	var view: BattleView = battle_view()
	var controller: BattleController = battle_controller()
	var session: CombatSession = view.get_session()
	for _turn: int in TURNS_FOR_ATTACK:
		var pick: Array = find_attack(session)
		if not pick.is_empty():
			await _attack_with(view, controller, session, pick)
			return true
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			session.submit(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
			session.resolve_next()
		if not session.is_finished:
			session.submit(EndTurnCommand.new(0))
			session.resolve_next()
		settle(view)
		await frames(SETTLE_FRAMES)
	note("no unit had an attack target within %d turns: no forecast shot" % [TURNS_FOR_ATTACK])
	return true


# The shots for one find_attack pick, then every panel backed out of.
func _attack_with(
		view: BattleView, controller: BattleController, session: CombatSession, pick: Array
) -> void:
	var unit_id: String = pick[0]
	var walk: Array = pick[1]
	var path: Array[Vector2i] = []
	path.assign(walk)
	var end: Vector2i = session.state.tile_of(unit_id) if path.is_empty() else path[-1]
	controller.confirm_tile(session.state.tile_of(unit_id))
	controller.confirm_tile(end)
	for _step: int in 600:
		if not view.is_staged_walking():
			break
		view.advance(1.0 / 60.0)
	settle(view)
	await frames(SETTLE_FRAMES)
	await capture("battle_action_menu")
	var host: PanelHost = scene().get_node(^"%PanelHost")
	var menu: ActionMenu = host.top() as ActionMenu
	if menu != null:
		var options: Array[TurnInputModel.ActionOption] = menu.get_options()
		for i: int in options.size():
			if options[i].kind == TurnInputModel.ActionKind.ATTACK:
				menu.get_rows()[i].pressed.emit()
				break
		await frames(SETTLE_FRAMES)
		await capture("battle_target")
		var option: TurnInputModel.ActionOption = pick[2]
		controller.confirm_tile(option.targets[0].tile)
		await frames(SETTLE_FRAMES)
		await capture("battle_forecast")
		await _multi_hit_forecast(controller, session, unit_id, option.targets[0].tile)
	while controller.step_back():
		await tree.process_frame
	settle(view)


# The forecast open in CONFIRM, shot again as a multi-hit attack: as it is when it already lists
# its hits, else with the attacker's weapon at AtkX 2 in this throwaway run (said in a NOTE), the
# forecast reopened on the same target.
func _multi_hit_forecast(
		controller: BattleController, session: CombatSession, unit_id: String, tile: Vector2i
) -> void:
	var host: PanelHost = scene().get_node(^"%PanelHost")
	var panel: ForecastPanel = host.top() as ForecastPanel
	if panel == null:
		return
	if panel.get_model().row(ForecastViewModel.HITS_LABEL) == null:
		var held: CombatState.WeaponStats = session.state.equipped_weapon(unit_id)
		if held == null:
			return
		note("multi-hit forecast: %s's weapon set to AtkX 2 for the shot" % [unit_id])
		held.atk_x = 2
		session.state.load_bases(session.engine, unit_id)
		controller.step_back()
		await frames(SETTLE_FRAMES)
		controller.confirm_tile(tile)
		await frames(SETTLE_FRAMES)
	await capture("battle_forecast_multi_hit")
