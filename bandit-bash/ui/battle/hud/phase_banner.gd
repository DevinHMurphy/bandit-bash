# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     phase_banner.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name PhaseBanner
extends PanelContainer
## The banner at each phase change: "Player Phase" with its turn, "Enemy Phase" or "Darkness",
## fading in and out; at the battle's end, "Victory" or "Defeat", which stays (combat UI plan,
## questions 11 and 18 (f); ui-lift.md, Darkness phase; Godot_FE's turn transition).
##
## [BattleHud] calls [method show_phase] as each side's Phase Start fact plays, and
## [method show_darkness] as a darkness phase that does anything begins; like Godot_FE's, it holds
## nothing up. [BattleScreen] calls [method show_result] once the battle has ended and settled. A
## new banner replaces one still showing, so a skip shows the last. Its fades run on the scene
## tree (they pause with the pause menu) at the board's pace ([method set_speed_scale]).
## Darkness, the enemy phase and Defeat are [code]text[/code] on a filled panel (ui-style.md,
## Chips). The HUD scene places it under the heirloom bar's row, so the two never meet.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# The panel's theme types for the darkness banner and the enemy side's (its phase, Defeat); the
# player's banners use the plain panel.
const _DARKNESS_PANEL: StringName = &"DarknessBannerPanel"
const _ENEMY_PANEL: StringName = &"EnemyBannerPanel"

## The player phase's text.
@export var player_text: String = "Player Phase"

## The enemy phase's text.
@export var enemy_text: String = "Enemy Phase"

## The darkness phase's text. It shows with no turn line.
@export var darkness_text: String = "Darkness"

## The turn's line under the player phase's text: [code]%d[/code] the turn. Empty shows none.
@export var turn_format: String = "Turn %d"

## The text when the player side wins. It shows in [member player_color].
@export var victory_text: String = "Victory"

## The text when the player side loses. It shows in [member enemy_color] on the enemy panel.
@export var defeat_text: String = "Defeat"

## The player phase's text colour (Godot_FE tints its player banner blue). Defaults to the
## [code]block[/code] token, the player side's colour.
@export var player_color: Color = UiTokens.color(UiTokens.BLOCK)

## The enemy phase's and Defeat's text colour, drawn on the [code]EnemyBannerPanel[/code] fill
## (Godot_FE tints its enemy banner red; here the fill carries it). Defaults to the
## [code]text[/code] token (5.42:1 on the [code]danger_fill[/code] fill).
@export var enemy_color: Color = UiTokens.color(UiTokens.TEXT)

## The darkness phase's text colour, drawn on the [code]DarknessBannerPanel[/code] fill. Defaults
## to the [code]text[/code] token (5.00:1 on the [code]darkness[/code] fill).
@export var darkness_color: Color = UiTokens.color(UiTokens.TEXT)

## How long the banner takes to fade in (ui-style.md, Motion: stage changes over 250 ms).[br]
## [b]Units:[/b] seconds at speed scale 1.0. [b]0.0:[/b] it appears at once.
@export_range(0.0, 3.0, 0.05) var fade_in_time: float = 0.25

## How long a phase's banner stays fully shown between its fades: Godot_FE's
## [code]new_turn[/code] animation lasted 2.0 s, fades included.[br]
## [b]Units:[/b] seconds at speed scale 1.0. [b]0.0:[/b] it fades out as soon as it is in.
@export_range(0.0, 5.0, 0.05) var hold_time: float = 1.5

## How long the banner takes to fade out (ui-style.md, Motion: 250 ms).[br]
## [b]Units:[/b] seconds at speed scale 1.0. [b]0.0:[/b] it vanishes at once.
@export_range(0.0, 3.0, 0.05) var fade_out_time: float = 0.25

var _tween: Tween = null
var _shown_count: int = 0

# How many times faster than real time the fades run (set_speed_scale()).
var _speed_scale: float = 1.0

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
	var turn_line: String = turn_format % [turn] if is_player and not turn_format.is_empty() else ""
	theme_type_variation = &"" if is_player else _ENEMY_PANEL
	_fade_through(
			player_text if is_player else enemy_text,
			player_color if is_player else enemy_color,
			turn_line
	)


## Shows the darkness phase's banner, [member darkness_text] in [member darkness_color] on the
## darkness-filled panel, fading in and out as a side's does.
func show_darkness() -> void:
	theme_type_variation = _DARKNESS_PANEL
	_fade_through(darkness_text, darkness_color, "")


## Shows the battle's end: [member victory_text] when [param is_won], else [member defeat_text].
## It fades in over [member fade_in_time] and stays until hidden or replaced.
func show_result(is_won: bool) -> void:
	theme_type_variation = &"" if is_won else _ENEMY_PANEL
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
		_tween.set_speed_scale(_speed_scale)
		_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_time)


## Runs the fades [param scale] times faster than real time, the one showing included: the board's
## [method BattleView.time_scale], so held fast-forward and the game speed pace them too. Values
## at or below 0 count as 1.0.
func set_speed_scale(scale: float) -> void:
	_speed_scale = scale if scale > 0.0 else 1.0
	if _tween != null and _tween.is_valid():
		_tween.set_speed_scale(_speed_scale)


## How long a phase's banner shows from start to hidden at speed scale 1.0.
func phase_time() -> float:
	return fade_in_time + hold_time + fade_out_time


## How many banners have been shown since the scene loaded.
func get_shown_count() -> int:
	return _shown_count


## The last banner's text and turn line.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_text.text, _turn.text])


# Shows text in color with turn_line under it (none when empty), fading in, then out, then hidden.
func _fade_through(text: String, color: Color, turn_line: String) -> void:
	_text.text = text
	_text.add_theme_color_override(&"font_color", color)
	_turn.text = turn_line
	_turn.visible = not _turn.text.is_empty()
	_shown_count += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	modulate.a = 0.0 if fade_in_time > 0.0 else 1.0
	_tween = create_tween()
	_tween.set_speed_scale(_speed_scale)
	if fade_in_time > 0.0:
		_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_time)
	if hold_time > 0.0:
		_tween.tween_interval(hold_time)
	_tween.tween_property(self, ^"modulate:a", 0.0, fade_out_time)
	_tween.tween_callback(hide)
