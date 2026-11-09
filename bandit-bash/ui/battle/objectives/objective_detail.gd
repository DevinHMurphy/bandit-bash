# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     objective_detail.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name ObjectiveDetail
extends VBoxContainer
## One part of the [ObjectivePanel]: what an objective's HUD shows beyond its text, such as the
## enemies left or the turns left (combat UI plan, UI11; game-vision.md, Combat maps: Objectives).
##
## Each objective's scene has a script that extends this one. The panel shows a detail only when
## [method is_shown_for] says so, then calls [method show_objective]; a detail formats the
## [HudViewModel.ObjectiveView] it is given and holds no rules. The base shows for nothing.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md


## Whether this detail shows for [param _view]: its objective, or (reinforcements) its points.
func is_shown_for(_view: HudViewModel.ObjectiveView) -> bool:
	return false


## Draws [param _view]. Called only while [method is_shown_for] holds.
func show_objective(_view: HudViewModel.ObjectiveView) -> void:
	pass


## Every line shown, joined by " | ", for tests.
func get_text() -> String:
	var lines: PackedStringArray = []
	for child: Node in get_children():
		var label: Label = child as Label
		if label != null and label.visible and not label.text.is_empty():
			lines.append(label.text)
	return " | ".join(lines)
