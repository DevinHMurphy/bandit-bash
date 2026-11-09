# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     objective_panel.gd
# Author:
# Created:  November 5, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name ObjectivePanel
extends PanelContainer
## The map's objective on the HUD: its text, such as "Rout: defeat every enemy" (combat UI plan,
## question 11; game-vision.md, Combat maps: Objectives), and under it the objective's own HUD.
##
## The objectives' scenes ([RoutObjective], [LeaderObjective], [SeizeObjective],
## [SurviveObjective], [DefendObjective]) and the [ReinforcementStatus] are children of
## [code]%Details[/code], each an [ObjectiveDetail]; [method show_view] shows those whose
## [method ObjectiveDetail.is_shown_for] holds for the map and hides the rest, so a new
## objective's scene is added there in the editor. [BattleHud] draws it on every settle, so it
## follows enemies falling and turns passing. Holds no rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The line shown before the objective; empty shows the objective alone.
@export var heading: String = "Objective"

var _view: HudViewModel.ObjectiveView = null

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _details: VBoxContainer = %Details


func _ready() -> void:
	_heading.text = heading
	_heading.visible = not heading.is_empty()


## Shows [param text] as the objective, with no details; [method show_view] shows both.
func show_objective(text: String) -> void:
	_text.text = text


## Shows [param view]'s text and the details that apply to it; null shows no objective.
func show_view(view: HudViewModel.ObjectiveView) -> void:
	_view = view
	show_objective("" if view == null else view.text)
	for detail: ObjectiveDetail in get_details():
		detail.visible = view != null and detail.is_shown_for(view)
		if detail.visible:
			detail.show_objective(view)


## The view shown; null before [method show_view].
func get_view() -> HudViewModel.ObjectiveView:
	return _view


## The objective shown.
func get_text() -> String:
	return _text.text


## Every detail scene under [code]%Details[/code], shown or not, in order.
func get_details() -> Array[ObjectiveDetail]:
	var found: Array[ObjectiveDetail] = []
	for child: Node in _details.get_children():
		var detail: ObjectiveDetail = child as ObjectiveDetail
		if detail != null:
			found.append(detail)
	return found


## The details shown now, for tests.
func get_shown_details() -> Array[ObjectiveDetail]:
	var shown: Array[ObjectiveDetail] = []
	for detail: ObjectiveDetail in get_details():
		if detail.visible:
			shown.append(detail)
	return shown
