# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     target_mark.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name TargetMark
extends Node2D
## The outline around one valid target while an action is aimed (combat UI plan, question 21):
## every target in the [TargetList] gets one, the current target a stronger one.
##
## Coloured by the target's side, as Godot_FE's [code]StrokeShader[/code] outlined units
## ([code]combat_unit_display.gd[/code]: NAVY_BLUE for players, DARK_RED for enemies, white for
## neither). The outline's shape and widths are the theme's [code]TargetMark[/code] and
## [code]TargetMarkCurrent[/code] panel styles ([code]battle_theme.tres[/code]), drawn white and
## tinted here. [BattleView] places one per target on the target's tile, over the tokens; its
## origin is the tile's centre. While tokens are letters it stands around the token; a sprite's
## own outline shader can take its place later (UI7). It holds no rules.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The theme type of a target's outline.
const OTHER_STYLE: StringName = &"TargetMark"

## The theme type of the current target's outline.
const CURRENT_STYLE: StringName = &"TargetMarkCurrent"

## The outline of a player-side target (Godot_FE's [code]Color.NAVY_BLUE[/code]).
@export var player_color: Color = Color(0.0, 0.0, 0.501961, 1.0)

## The outline of an enemy-side target (Godot_FE's [code]Color.DARK_RED[/code]).
@export var enemy_color: Color = Color(0.545098, 0.0, 0.0, 1.0)

## The outline of a target on neither side, such as a map object (Godot_FE's white).
@export var other_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## How opaque a target's outline is while another target is current; the current one is fully
## opaque.[br]
## [b]0.0:[/b] only the current target shows. [b]1.0:[/b] they differ by width alone.
# ASSUMPTION: greybox value; Godot_FE outlined units with one stroke whatever was targeted.
@export_range(0.0, 1.0, 0.01) var other_alpha: float = 0.75

## The tile the mark stands on; [constant CombatFact.NO_TILE] until [method show_mark].
var tile: Vector2i = CombatFact.NO_TILE

## The side it is coloured for.
var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE

## Whether it marks the current target.
var is_current: bool = false

@onready var _outline: Panel = %Outline


## Marks [param mark]'s tile for its side, strongly when it is the current target.
func show_mark(mark: Spec) -> void:
	tile = mark.tile
	side = mark.side
	is_current = mark.is_current
	_outline.theme_type_variation = CURRENT_STYLE if is_current else OTHER_STYLE
	var tint: Color = color_of(side)
	if not is_current:
		tint.a *= other_alpha
	_outline.self_modulate = tint


## The outline's colour for [param of_side], before [member other_alpha].
func color_of(of_side: CombatFact.CombatSide) -> Color:
	match of_side:
		CombatFact.CombatSide.PLAYER:
			return player_color
		CombatFact.CombatSide.ENEMY:
			return enemy_color
	return other_color


## The theme type the outline is drawn with now, for tests.
func get_style() -> StringName:
	return _outline.theme_type_variation


## The tint the outline is drawn with now, for tests.
func get_tint() -> Color:
	return _outline.self_modulate


## What one mark shows.
class Spec:
	extends RefCounted

	## The target's tile.
	var tile: Vector2i = CombatFact.NO_TILE
	## The target's side; NONE for a map object.
	var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE
	## Whether it is the current target.
	var is_current: bool = false
