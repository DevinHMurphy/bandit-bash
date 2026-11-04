# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_token.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name UnitToken
extends Node2D
## One unit on the battle board, greybox: a side-coloured square with its class letter and an HP
## bar (combat UI plan, question 4).
##
## [BattleView] places one per unit and moves it; the token only draws what it is given
## ([method show_unit], [method show_hp]) and holds no rules. Its origin is the tile's centre; the
## layout is authored in the scene for 32 px tiles.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Body colour of a player-side unit.
# ASSUMPTION: greybox colour; the combat UI plan sets no palette (Design Basis, Gaps).
@export var player_color: Color = Color(0.25, 0.45, 0.9, 1.0)

## Body colour of an enemy-side unit.
# ASSUMPTION: greybox colour, as above.
@export var enemy_color: Color = Color(0.85, 0.25, 0.25, 1.0)

## Body colour of a unit on neither side (a map object standing as a unit).
# ASSUMPTION: greybox colour, as above.
@export var other_color: Color = Color(0.6, 0.6, 0.6, 1.0)

## The unit this token stands for; empty until [method show_unit].
var unit_id: String = ""

## The tile the token shows the unit on. [BattleView] sets it when a move starts, so it is where
## the unit is going while the move plays.
var tile: Vector2i = CombatFact.NO_TILE

## The HP the token shows; follows the facts as they play.
var hp: int = 0

## The maximum HP the bar is drawn against.
var max_hp: int = 0

@onready var _body: ColorRect = %Body
@onready var _letter: Label = %Letter
@onready var _hp_bar: ProgressBar = %HpBar


## Draws [param view]: its side's colour, its class letter and its HP.
func show_unit(view: BoardViewModel.UnitView) -> void:
	unit_id = view.id
	tile = view.tile
	_body.color = color_of(view.side)
	_letter.text = view.letter
	show_hp(view.hp, view.max_hp)


## Shows [param current] HP of [param maximum] on the bar; HP is never shown below 0.
func show_hp(current: int, maximum: int) -> void:
	hp = maxi(current, 0)
	max_hp = maxi(maximum, 1)
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp


## The body colour for [param side].
func color_of(side: CombatFact.CombatSide) -> Color:
	match side:
		CombatFact.CombatSide.PLAYER:
			return player_color
		CombatFact.CombatSide.ENEMY:
			return enemy_color
	return other_color
