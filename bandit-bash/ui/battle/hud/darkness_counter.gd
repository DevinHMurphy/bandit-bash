# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     darkness_counter.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name DarknessCounter
extends PanelContainer
## When the darkness comes: the turns until it arrives, then the turns until its next wave (combat
## UI plan, question 11; the-darkness.md).
##
## Draws a [HudViewModel.DarknessView], whose count is [method Darkness.source_counters]'s: 1
## means at the end of this turn. On a map the darkness never reaches it shows
## [member none_text].
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @tutorial(The darkness): docs/design/the-darkness.md

## Before arrival: [code]%d[/code] the turns until it arrives, 2 or more.
@export var arrives_format: String = "Darkness arrives in %d turns"

## Before arrival, when it arrives at the end of this turn.
@export var arrives_now_text: String = "Darkness arrives at the end of this turn"

## After arrival: [code]%d[/code] the turns until the next wave, 2 or more.
@export var wave_format: String = "Next darkness wave in %d turns"

## After arrival, when the next wave comes at the end of this turn.
@export var wave_now_text: String = "Next darkness wave at the end of this turn"

## On a map the darkness never comes to (Survive and Defend maps).
@export var none_text: String = "No darkness on this map"

var _view: HudViewModel.DarknessView = null

@onready var _text: Label = %Text


## Shows [param view].
func show_darkness(view: HudViewModel.DarknessView) -> void:
	_view = view
	if view == null:
		return
	if not view.is_coming:
		_text.text = none_text
	elif view.has_arrived:
		_text.text = wave_now_text if view.turns <= 1 else wave_format % [view.turns]
	else:
		_text.text = arrives_now_text if view.turns <= 1 else arrives_format % [view.turns]


## The view shown; null before [method show_darkness].
func get_view() -> HudViewModel.DarknessView:
	return _view


## The text shown.
func get_text() -> String:
	return _text.text
