# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     survive_objective.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name SurviveObjective
extends ObjectiveDetail
## Survive's HUD: the turns left of [member CombatMapDefinition.survive_turns], the current turn
## counted until its enemy phase ends (combat map plan, Objectives).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The line shown: [code]%d[/code] the turns left, then the turns to survive.
@export var turns_format: String = "Turns left: %d of %d"

@onready var _turns: Label = %Turns


func is_shown_for(view: HudViewModel.ObjectiveView) -> bool:
	return view.objective == CombatMapDefinition.Objective.SURVIVE


func show_objective(view: HudViewModel.ObjectiveView) -> void:
	_turns.text = turns_format % [view.turns_left, view.survive_turns]
