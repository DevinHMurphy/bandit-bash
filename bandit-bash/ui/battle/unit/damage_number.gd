# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     damage_number.gd
# Author:
# Created:  November 4, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name DamageNumber
extends Node2D
## A pop-up that rises from a unit and fades out, then frees itself: a damage or heal number, a
## "Miss", a "Critical" with its damage, or the small number of a hit's damage Block absorbed
## (combat UI plan, questions 29 (4), 29 (5) and 30 (c)).
##
## [BattleView] places one per damage, heal, missed strike, critical hit and Block absorbed on
## the [UnitInfoLayer], above the units' info panels ([method UnitInfoLayer.add_popup]), which
## keeps it over its unit through the camera; the label rises within it. The board steps its
## tween with its animations, so held fast-forward speeds it and a skip finishes it. Cosmetic:
## playback never waits for it ([member BattleView.number_hold] is the wait). Each [enum Style]
## has its colour here and its label style in the theme ([code]DamageNumberLabel[/code],
## [code]DamageNumberCriticalLabel[/code] for the larger Critical,
## [code]DamageNumberBlockLabel[/code] for the smaller Block number).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## What a pop-up shows.
enum Style {
	## Damage taken, as its amount.
	DAMAGE = 0,
	## HP restored, as [code]+[/code] its amount.
	HEAL = 1,
	## A strike that missed: [member miss_text], on the unit that dodged it.
	MISS = 2,
	## A critical hit: [member critical_format] with its damage, larger, on the unit it struck.
	CRITICAL = 3,
	## The part of a hit's damage that Block absorbed, small, beside the hit's own number.
	BLOCK = 4,
}

## Colour of a damage number. Defaults to the [code]danger[/code] token.
@export var damage_color: Color = UiTokens.color(UiTokens.DANGER)

## Colour of a heal number. Defaults to the [code]heal[/code] token.
@export var heal_color: Color = UiTokens.color(UiTokens.HEAL)

## Colour of a "Miss" (Godot_FE's [code]DamageNumbers.miss[/code] was white). Defaults to the
## [code]text[/code] token.
@export var miss_color: Color = UiTokens.color(UiTokens.TEXT)

# ASSUMPTION: a Critical's label (the theme's DamageNumberCriticalLabel) is the guide's big-number
# size, 28, as damage's is; the guide sets no larger size for it.
## Colour of a "Critical": damage, so the [code]danger[/code] token by default, told apart by its
## word and its own label style.
@export var critical_color: Color = UiTokens.color(UiTokens.DANGER)

## Colour of the Block-absorbed number. Defaults to the [code]block[/code] token.
@export var block_color: Color = UiTokens.color(UiTokens.BLOCK)

# ASSUMPTION: no basis; set beside and below the hit's number so the two never overlap.
## Where the Block-absorbed number's label sits from where the other styles' label sits, so it
## shows beside the hit's own number.[br]
## [b]Units:[/b] screen pixels at info scale 1.0.
@export var block_offset: Vector2 = Vector2(22.0, 10.0)

## The text of a missed strike's pop-up (Godot_FE's [code]"Miss"[/code]).
@export var miss_text: String = "Miss"

# ASSUMPTION: Godot_FE showed only the number and a "!"; question 29 (5) asks for "Critical"
# with the damage.
## The text of a critical hit's pop-up; [code]%d[/code] is the crit's damage.
@export var critical_format: String = "Critical %d"

# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
## How far the pop-up rises while it fades.[br]
## [b]Units:[/b] pixels.
@export_range(0.0, 128.0, 1.0) var rise_distance: float = 16.0

# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
## How long the pop-up stays on screen at playback speed 1.0.[br]
## [b]Units:[/b] seconds.
@export_range(0.05, 5.0, 0.05) var lifetime: float = 0.8

## The style shown, for tests; set by [method show_style].
var style: Style = Style.DAMAGE

@onready var _label: Label = %Amount


## Shows [param amount] as damage, or as healing when [param is_heal]; see [method show_style].
func play(amount: int, is_heal: bool) -> Tween:
	return show_style(Style.HEAL if is_heal else Style.DAMAGE, amount)


## Shows [param amount] in [param shown_style] ([param amount] is unused by a Miss), and returns
## the rise and fade, paused for the caller to step ([method Tween.custom_step]). The label rises,
## not the node, so whoever places the node may move it meanwhile. The node frees itself when it
## ends.
func show_style(shown_style: Style, amount: int) -> Tween:
	style = shown_style
	_label.text = text_of(shown_style, amount)
	_label.modulate = color_of(shown_style)
	_label.theme_type_variation = label_style_of(shown_style)
	if shown_style == Style.BLOCK:
		_label.position += block_offset
	var tween: Tween = create_tween()
	tween.pause()
	tween.set_parallel(true)
	tween.tween_property(_label, ^"position:y", _label.position.y - rise_distance, lifetime)
	tween.tween_property(self, ^"modulate:a", 0.0, lifetime)
	tween.chain().tween_callback(queue_free)
	return tween


## The text [param shown_style] draws for [param amount].
func text_of(shown_style: Style, amount: int) -> String:
	match shown_style:
		Style.HEAL:
			return "+%d" % [amount]
		Style.MISS:
			return miss_text
		Style.CRITICAL:
			return critical_format % [amount]
	return str(amount)


# ASSUMPTION: DamageNumberBlockLabel's 12 px size in battle_theme.tres is a greybox choice under
# DamageNumberLabel's 18, for "a small blue number".
## The theme type variation [param shown_style]'s label is drawn with.
func label_style_of(shown_style: Style) -> StringName:
	match shown_style:
		Style.CRITICAL:
			return &"DamageNumberCriticalLabel"
		Style.BLOCK:
			return &"DamageNumberBlockLabel"
	return &"DamageNumberLabel"


## The colour [param shown_style] is drawn in.
func color_of(shown_style: Style) -> Color:
	match shown_style:
		Style.HEAL:
			return heal_color
		Style.MISS:
			return miss_color
		Style.CRITICAL:
			return critical_color
		Style.BLOCK:
			return block_color
	return damage_color


## The text shown, for tests.
func get_text() -> String:
	return _label.text
