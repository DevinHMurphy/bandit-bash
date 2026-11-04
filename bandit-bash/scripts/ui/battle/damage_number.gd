# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     damage_number.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name DamageNumber
extends Node2D
## A damage or heal number that rises from a unit and fades out, then frees itself.
##
## [BattleView] places one per damage or heal fact and steps its tween with the board's
## animations. Cosmetic: playback never waits for it ([member BattleView.number_hold] is the
## wait).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Colour of a damage number.
# ASSUMPTION: greybox colour; no palette is set (combat UI plan, Design Basis, Gaps).
@export var damage_color: Color = Color(1.0, 0.85, 0.3, 1.0)

## Colour of a heal number.
# ASSUMPTION: greybox colour, as above.
@export var heal_color: Color = Color(0.45, 1.0, 0.5, 1.0)

## How far the number rises while it fades.[br]
## [b]Units:[/b] pixels.
# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
@export_range(0.0, 128.0, 1.0) var rise_distance: float = 16.0

## How long the number stays on screen at playback speed 1.0.[br]
## [b]Units:[/b] seconds.
# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
@export_range(0.05, 5.0, 0.05) var lifetime: float = 0.8

@onready var _label: Label = %Amount


## Shows [param amount] as damage, or as healing when [param is_heal], and returns the rise and
## fade, paused for the caller to step ([method Tween.custom_step]). The node frees itself when it
## ends.
func play(amount: int, is_heal: bool) -> Tween:
	_label.text = ("+%d" if is_heal else "%d") % [amount]
	_label.modulate = heal_color if is_heal else damage_color
	var tween: Tween = create_tween()
	tween.pause()
	tween.set_parallel(true)
	tween.tween_property(self, ^"position:y", position.y - rise_distance, lifetime)
	tween.tween_property(self, ^"modulate:a", 0.0, lifetime)
	tween.chain().tween_callback(queue_free)
	return tween
