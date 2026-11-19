# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     strike_look.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name StrikeLook
extends Resource
## How one strike result looks on the board ([StrikeFeedback]): a flash on the struck unit, a pop
## of its token, a camera shake and a pulse of its Block badge, each off at 0. Tweens only; the
## pop-up words and numbers are the [DamageNumber]'s. Every time is at playback speed 1.0, and the
## board's fast-forward and skip apply.
##
## @tutorial(UI lift, UL6): docs/design/ui-lift.md

## The colour the struck unit flashes toward ([method UnitToken.flash]) while
## [member flash_token] is empty.
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## A colour token ([UiTokens], such as [code]&"block"[/code]) the flash takes instead of
## [member flash_color]. [b]Empty:[/b] [member flash_color] is used.
@export var flash_token: StringName = &""

## How long the flash takes to fade.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] no flash.
@export_range(0.0, 1.0, 0.01) var flash_time: float = 0.0

## How large the token grows at the height of its pop, then shrinks back.[br]
## [b]1.0:[/b] no pop. [b]1.25:[/b] a quarter larger at the peak.
@export_range(1.0, 2.0, 0.01) var pop_scale: float = 1.0

## How long the pop and the badge pulse take, out and back.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] neither plays.
@export_range(0.0, 1.0, 0.01) var pop_time: float = 0.0

## How far the camera shakes, dying away over [member shake_time].[br]
## [b]Units:[/b] screen pixels. [b]0.0:[/b] no shake.
@export_range(0.0, 32.0, 0.5) var shake_strength: float = 0.0

## How long the shake lasts.[br]
## [b]Units:[/b] seconds. Unused while [member shake_strength] is 0.
@export_range(0.0, 2.0, 0.01) var shake_time: float = 0.0

## How large the unit's Block badge grows at the height of its pulse, over [member pop_time].[br]
## [b]1.0:[/b] no pulse.
@export_range(1.0, 2.0, 0.01) var badge_pulse_scale: float = 1.0


## The flash's colour: [member flash_token]'s when set, else [member flash_color].
func flash_tint() -> Color:
	return flash_color if flash_token.is_empty() else UiTokens.color(flash_token)
