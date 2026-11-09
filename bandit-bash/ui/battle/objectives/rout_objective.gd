# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rout_objective.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name RoutObjective
extends ObjectiveDetail
## Rout's HUD: how many enemies are left on the map (game-vision.md, Combat maps: Objectives).
## Waves not yet arrived don't count: Rout's win cancels them.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The line shown; [code]%d[/code] is the enemies on the map.
@export var enemies_format: String = "Enemies left: %d"

@onready var _enemies: Label = %Enemies


func is_shown_for(view: HudViewModel.ObjectiveView) -> bool:
	return view.objective == CombatMapDefinition.Objective.ROUT


func show_objective(view: HudViewModel.ObjectiveView) -> void:
	_enemies.text = enemies_format % [view.enemies_left]
