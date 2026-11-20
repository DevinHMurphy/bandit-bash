# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     350_battle_event_log.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The event log after whole phases played: each unit attacks where it can while more than one
## enemy stands (so the battle goes on) and waits elsewhere, until a darkness phase has played or
## [constant LOG_PHASES] pass, so the log holds lines of every group.[br]
## Needs: the battle started and idle (300_battle_start).

# Phases played for the event log's shot at most: past the M1 darkness's arrival (end of turn 4).
const LOG_PHASES: int = 6

# Darkness phases played since the event log's phases began.
var _darkness_phases: int = 0


func run() -> bool:
	var view: BattleView = battle_view()
	var session: CombatSession = view.get_session()
	_darkness_phases = 0
	view.darkness_phase_started.connect(_on_view_darkness_phase_started)
	for _phase: int in LOG_PHASES:
		if session.is_finished or _darkness_phases > 0:
			break
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			var command: Command = UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT)
			var pick: Array = find_attack(session)
			var enemies: int = session.state.units_of(CombatFact.CombatSide.ENEMY).size()
			if not pick.is_empty() and pick[0] == unit_id and enemies > 1:
				var option: TurnInputModel.ActionOption = pick[2]
				command = option.targets[0].command
			session.submit(command)
			session.resolve_next()
			settle(view)
			if session.is_finished:
				break
		if not session.is_finished:
			session.submit(EndTurnCommand.new(0))
			session.resolve_next()
		settle(view)
		await frames(SETTLE_FRAMES)
	view.darkness_phase_started.disconnect(_on_view_darkness_phase_started)
	await capture("battle_event_log")
	return true


func _on_view_darkness_phase_started(_turn: int) -> void:
	_darkness_phases += 1
