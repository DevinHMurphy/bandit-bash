# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     skip_fade.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name SkipFade
extends CanvasLayer
## The fade to black, and back, that hides a skipped playback ([method BattleView.skip_playback]).
##
## Covers the whole screen, the HUD included: its canvas layer (5, set in the scene) is above the
## battle HUD's (1) and below the pause menu's (10). It never takes the mouse. [BattleView] owns it
## and steps its fades in real time, unscaled by game speed or fast-forward; each fade is a tween
## returned paused for the caller to step ([method Tween.custom_step]), so a test can drive it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## How long the screen takes to go black before the skipped facts play.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it goes black at once.
@export_range(0.0, 2.0, 0.01) var fade_out_time: float = 0.25

## How long the screen takes to clear after them.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it clears at once.
@export_range(0.0, 2.0, 0.01) var fade_in_time: float = 0.25

@onready var _shade: ColorRect = %Shade


func _ready() -> void:
	clear()


## Starts the fade to black and returns its tween, paused for the caller to step.
func fade_out() -> Tween:
	_shade.visible = true
	return _fade_to(1.0, fade_out_time)


## Starts the fade back from black and returns its tween, paused as [method fade_out]'s; the shade
## hides when it ends.
func fade_in() -> Tween:
	var tween: Tween = _fade_to(0.0, fade_in_time)
	tween.tween_callback(clear)
	return tween


## Clears the screen at once.
func clear() -> void:
	_shade.modulate.a = 0.0
	_shade.visible = false


## How dark the screen is.[br]
## [b]0.0:[/b] clear. [b]1.0:[/b] black.
func get_opacity() -> float:
	return _shade.modulate.a if _shade.visible else 0.0


func _fade_to(alpha: float, seconds: float) -> Tween:
	var tween: Tween = create_tween()
	tween.pause()
	tween.tween_property(_shade, ^"modulate:a", alpha, seconds)
	return tween
