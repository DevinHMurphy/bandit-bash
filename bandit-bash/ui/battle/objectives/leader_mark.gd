# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leader_mark.gd
# Author:
# Created:  November 7, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name LeaderMark
extends Node2D
## The outline around an enemy the objective marks: Defeat the Leader's leader or Defeat the
## Boss's boss ([method Objectives.marked_ids]), so the player sees which enemies end the map.
##
## [BattleView] adds one as a child of each marked enemy's token, so it walks, fades and goes
## with the token; its origin is the tile's centre. The shape and width are the theme's
## [code]LeaderMark[/code] panel style ([code]battle_theme.tres[/code]), drawn white and tinted by
## [member color]. Distinct from a [TargetMark], which comes and goes with targeting. Holds no
## rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The outline's colour, apart from the side outlines and the target marks. Its alpha is its
## opacity. Defaults to the [code]accent[/code] token.[br]
## [b]Alpha 0.0:[/b] the mark is invisible.
@export var color: Color = UiTokens.color(UiTokens.ACCENT):
	set(value):
		color = value
		if is_node_ready():
			_outline.self_modulate = color

@onready var _outline: Panel = %Outline


func _ready() -> void:
	_outline.self_modulate = color


## The tint the outline is drawn with, for tests.
func get_tint() -> Color:
	return _outline.self_modulate
