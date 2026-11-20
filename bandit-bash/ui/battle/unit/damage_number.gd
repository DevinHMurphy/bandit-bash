# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     damage_number.gd
# Author:
# Created:  November 4, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name DamageNumber
extends Node2D
## A pop-up that rises from a unit, holds, shrinks away and frees itself (Godot_FE's
## [code]DamageNumbers[/code]): a damage, heal or Block-absorbed number, a "Critical", a "Miss",
## "No damage", "Exposed", a Block gain or loss, or a Stance change ([enum Style]).
##
## [BattleView] places one per fact it shows on the [UnitInfoLayer]
## ([method UnitInfoLayer.add_popup]), which keeps it over its unit through the camera and stacks
## a unit's pop-ups a row apart; the label rises within it. The board steps its tween with its
## animations, so held fast-forward speeds it and a skip finishes it. Cosmetic: playback's waits
## are the board's. Each style has its
## colour and text here and its label style in the theme ([method label_style_of]).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @tutorial(UI lift, UL6): docs/design/ui-lift.md

## What a pop-up shows. Append only: tests and the board's signals carry these values.
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
	## A hit fully countered (0 damage): [member no_damage_text].
	NO_DAMAGE = 5,
	## The unit's Stance broke (reached 0): [member exposed_text] on a chip.
	EXPOSED = 6,
	## Block gained outside a refresh: [member block_gained_format] with the amount.
	BLOCK_GAINED = 7,
	## Block lost outside damage: [member block_lost_format] with the amount.
	BLOCK_LOST = 8,
	## A Stance change outside a refresh: [member stance_format] with the signed change.
	STANCE = 9,
}

# The styles drawn as words, which hold for text_lifetime, as Godot_FE's display_text did for its
# Miss, No Damage and heal; the rest are numbers and hold for lifetime.
# ASSUMPTION: Exposed, Block and Stance words take Godot_FE's text timing; it had none of them.
const _WORD_STYLES: Array[Style] = [
	Style.HEAL, Style.MISS, Style.NO_DAMAGE, Style.EXPOSED,
	Style.BLOCK_GAINED, Style.BLOCK_LOST, Style.STANCE,
]

# The minus sign the signed words use (U+2212), wider than a hyphen.
const _MINUS: String = "−"

@export_group("Colours")

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

## Colour of the Block-absorbed number and the Block gain and loss words. Defaults to the
## [code]block[/code] token.
@export var block_color: Color = UiTokens.color(UiTokens.BLOCK)

## Colour of "No damage" (Godot_FE's was white; muted here, as nothing happened). Defaults to the
## [code]text_muted[/code] token.
@export var no_damage_color: Color = UiTokens.color(UiTokens.TEXT_MUTED)

## Tint over the "Exposed" chip, label and fill together. [b]White:[/b] the theme's
## [code]text[/code] on its [code]danger_fill[/code] chip, unchanged (5.42:1).
@export var exposed_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Colour of a Stance change's word. Defaults to the [code]text[/code] token: the word, not the
## colour, says what changed.
@export var stance_color: Color = UiTokens.color(UiTokens.TEXT)

@export_group("Text")

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

## The text of a fully countered hit's pop-up (Godot_FE's [code]"No Damage"[/code]).
@export var no_damage_text: String = "No damage"

## The text of a Stance break's pop-up.
@export var exposed_text: String = "Exposed"

## A Block gain's text; [code]%d[/code] is the Block gained.
@export var block_gained_format: String = "+%d Block"

## A Block loss's text; [code]%d[/code] is the Block lost, shown after a minus sign.
@export var block_lost_format: String = "−%d Block"

## A Stance change's text; [code]%s[/code] is the signed change, such as [code]−1[/code].
@export var stance_format: String = "Stance %s"

@export_group("Motion")

## How far the pop-up rises before it holds (Godot_FE's [code]DamageNumbers[/code], 24 px).[br]
## [b]Units:[/b] screen pixels at info scale 1.0. [b]0.0:[/b] it doesn't rise.
@export_range(0.0, 128.0, 1.0) var rise_distance: float = 24.0

## How long the rise takes, easing out (Godot_FE: 0.25 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0.
@export_range(0.0, 2.0, 0.01) var rise_time: float = 0.25

## How long the pop-up takes to shrink away at the end of its life (Godot_FE: 0.25 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0. [b]0.0:[/b] it vanishes at once.
@export_range(0.0, 2.0, 0.01) var shrink_time: float = 0.25

## How long a number (damage, Critical, Block absorbed) stays, rise and shrink included
## (Godot_FE's [code]display_number[/code], 1.0 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0.
@export_range(0.05, 5.0, 0.05) var lifetime: float = 1.0

## How long a word (Miss, No damage, heal, Exposed, Block and Stance changes) stays (Godot_FE's
## [code]display_text[/code], 0.75 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0.
@export_range(0.05, 5.0, 0.05) var text_lifetime: float = 0.75

## The style shown, for tests; set by [method show_style].
var style: Style = Style.DAMAGE

@onready var _label: Label = %Amount


## Shows [param amount] as damage, or as healing when [param is_heal]; see [method show_style].
func play(amount: int, is_heal: bool) -> Tween:
	return show_style(Style.HEAL if is_heal else Style.DAMAGE, amount)


## Shows [param amount] in [param shown_style] (unused by Miss, No damage and Exposed; signed for
## a Stance change), and returns its rise, hold and shrink, paused for the caller to step
## ([method Tween.custom_step]). The label moves, not the node, so whoever places the node may move
## it meanwhile. The node frees itself when it ends.
func show_style(shown_style: Style, amount: int) -> Tween:
	style = shown_style
	_label.text = text_of(shown_style, amount)
	_label.modulate = color_of(shown_style)
	_label.theme_type_variation = label_style_of(shown_style)
	if shown_style == Style.BLOCK:
		_label.position += block_offset
	var life: float = lifetime_of(shown_style)
	var rise: float = minf(rise_time, life)
	var shrink: float = minf(shrink_time, life - rise)
	var tween: Tween = create_tween()
	tween.pause()
	if rise > 0.0:
		tween.tween_property(
				_label, ^"position:y", _label.position.y - rise_distance, rise
		).set_ease(Tween.EASE_OUT)
	tween.tween_interval(maxf(life - rise - shrink, 0.0))
	tween.tween_callback(_center_pivot)
	if shrink > 0.0:
		tween.tween_property(_label, ^"scale", Vector2.ZERO, shrink).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
	return tween


## How long [param shown_style] stays: [member text_lifetime] for words, else [member lifetime].
func lifetime_of(shown_style: Style) -> float:
	return text_lifetime if _WORD_STYLES.has(shown_style) else lifetime


## The text [param shown_style] draws for [param amount].
func text_of(shown_style: Style, amount: int) -> String:
	match shown_style:
		Style.HEAL:
			return "+%d" % [amount]
		Style.MISS:
			return miss_text
		Style.CRITICAL:
			return critical_format % [amount]
		Style.NO_DAMAGE:
			return no_damage_text
		Style.EXPOSED:
			return exposed_text
		Style.BLOCK_GAINED:
			return block_gained_format % [amount]
		Style.BLOCK_LOST:
			return block_lost_format % [absi(amount)]
		Style.STANCE:
			var signed: String = ("+%d" if amount >= 0 else _MINUS + "%d") % [absi(amount)]
			return stance_format % [signed]
	return str(amount)


# ASSUMPTION: DamageNumberBlockLabel's size in battle_theme.tres is the guide's 14-unit floor, for
# "a small blue number"; the Block and Stance words share it.
## The theme type variation [param shown_style]'s label is drawn with.
func label_style_of(shown_style: Style) -> StringName:
	match shown_style:
		Style.CRITICAL:
			return &"DamageNumberCriticalLabel"
		Style.BLOCK, Style.BLOCK_GAINED, Style.BLOCK_LOST, Style.STANCE:
			return &"DamageNumberBlockLabel"
		Style.NO_DAMAGE:
			return &"DamageNumberWordLabel"
		Style.EXPOSED:
			return &"DamageNumberExposedLabel"
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
		Style.BLOCK, Style.BLOCK_GAINED, Style.BLOCK_LOST:
			return block_color
		Style.NO_DAMAGE:
			return no_damage_color
		Style.EXPOSED:
			return exposed_color
		Style.STANCE:
			return stance_color
	return damage_color


## The text shown, for tests.
func get_text() -> String:
	return _label.text


# The label shrinks toward its centre; its size is final by the time the shrink starts.
func _center_pivot() -> void:
	_label.pivot_offset = _label.size * 0.5
