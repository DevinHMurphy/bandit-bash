# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     phase_banner.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name PhaseBanner
extends PanelContainer
## The banner at each phase change: "Player Phase" with its turn, or "Enemy Phase", fading in and
## out; and at the battle's end, "Victory" or "Defeat", which stays (combat UI plan, questions 11
## and 18 (f); game-vision.md, Combat: the UI shows the turn phases;
## Godot_FE's turn transition, [code]combat_ui.gd[/code] and
## [code]TurnTransitionAnimation.tscn[/code]).
##
## [BattleHud] calls [method show_phase] as each side's Phase Start fact plays. Like Godot_FE's, it
## holds nothing up: playback goes on under it. [BattleScreen] calls [method show_result] (through
## [method BattleHud.show_result]) once the battle has ended and its playback settled, and holds
## the route to Results for [member BattleScreen.end_banner_time]. A new banner replaces one still
## showing. Its fade runs on the scene tree, so it pauses with the pause menu and ignores
## fast-forward.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The player phase's text.
@export var player_text: String = "Player Phase"

## The enemy phase's text.
@export var enemy_text: String = "Enemy Phase"

## The turn's line under the player phase's text: [code]%d[/code] the turn. Empty shows none.
@export var turn_format: String = "Turn %d"

## The text when the player side wins. It shows in [member player_color].
@export var victory_text: String = "Victory"

## The text when the player side loses. It shows in [member enemy_color].
@export var defeat_text: String = "Defeat"

## The player phase's text colour (Godot_FE tints its player banner blue).
@export var player_color: Color = Color(0.55, 0.75, 1.0, 1.0)

## The enemy phase's text colour (Godot_FE tints its enemy banner red).
@export var enemy_color: Color = Color(1.0, 0.45, 0.4, 1.0)

## How long the banner takes to fade in (Godot_FE's [code]new_turn[/code] animation: 1.0 of its
## 2.0 s).[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it appears at once.
@export_range(0.0, 3.0, 0.05) var fade_in_time: float = 1.0

## How long the banner takes to fade out once fully shown (Godot_FE: the other 1.0 s).[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it vanishes at once.
@export_range(0.0, 3.0, 0.05) var fade_out_time: float = 1.0

var _tween: Tween = null
var _shown_count: int = 0

@onready var _text: Label = %Text
@onready var _turn: Label = %TurnLine


func _ready() -> void:
	visible = false


## Shows the banner for [param side]'s phase of turn [param turn]. Sides other than player and
## enemy show nothing.
func show_phase(side: CombatFact.CombatSide, turn: int) -> void:
	var is_player: bool = side == CombatFact.CombatSide.PLAYER
	if not is_player and side != CombatFact.CombatSide.ENEMY:
		return
	_text.text = player_text if is_player else enemy_text
	_text.add_theme_color_override(&"font_color", player_color if is_player else enemy_color)
	_turn.text = turn_format % [turn] if is_player and not turn_format.is_empty() else ""
	_turn.visible = not _turn.text.is_empty()
	_shown_count += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	modulate.a = 0.0 if fade_in_time > 0.0 else 1.0
	_tween = create_tween()
	if fade_in_time > 0.0:
		_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_time)
	_tween.tween_property(self, ^"modulate:a", 0.0, fade_out_time)
	_tween.tween_callback(hide)


## Shows the battle's end: [member victory_text] when [param is_won], else [member defeat_text].
## It fades in over [member fade_in_time] and stays until hidden or replaced.
func show_result(is_won: bool) -> void:
	_text.text = victory_text if is_won else defeat_text
	_text.add_theme_color_override(&"font_color", player_color if is_won else enemy_color)
	_turn.text = ""
	_turn.visible = false
	_shown_count += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	modulate.a = 0.0 if fade_in_time > 0.0 else 1.0
	if fade_in_time > 0.0:
		_tween = create_tween()
		_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_time)


## How many banners have been shown since the scene loaded.
func get_shown_count() -> int:
	return _shown_count


## The last banner's text and turn line.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_text.text, _turn.text])
