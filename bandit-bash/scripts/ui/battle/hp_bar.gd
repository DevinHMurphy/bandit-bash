# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hp_bar.gd
# Author:
# Created:  November 6, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name HpBar
extends ProgressBar
## A unit's HP bar on its [UnitInfo], with the HP drawn inside it (combat UI plan, question 29
## (1)).
##
## Godot_FE's [code]Healthbar[/code] look, as data: the theme's [code]HpBar[/code] background
## and fill styles and [code]HpBarLabel[/code] number ([code]battle_theme.tres[/code]). Unlike
## Godot_FE's, it always shows, full or not, and it draws its number; it takes the value it is
## given ([method show_hp]) and holds no rules.[br]
## [b]The forecast's flash[/b] (question 34 (1)): while a forecast is open, [method show_preview]
## pulses the part of the bar between the HP shown and the HP the action leaves toward
## [member preview_flash_color]: the HP a hit would take, or a heal would restore. The number keeps
## the HP now; the forecast panel has the before and after. The pulse is a looping tween, so the
## bar draws each frame only while it flashes.[br]
## [b]Not a [StancePips]:[/b] HP is a continuous bar of tens of points with a number, so it shares
## nothing with the pips' per-point segments, overflow colour or Exposed look.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Whether the number also shows the maximum, as [code]14/22[/code] (question 30 (d)).[br]
## [b]Off:[/b] only the current HP, as [code]14[/code].
@export var is_maximum_shown: bool = true:
	set(is_shown):
		is_maximum_shown = is_shown
		if not is_node_ready():
			return
		show_hp(roundi(value), roundi(max_value))

@export_group("Forecast flash")

## The colour the predicted loss or gain pulses toward while a forecast is open (question 34 (1):
## white for damage and heal alike). Its alpha is the pulse's peak opacity over the bar; below 1.0
## the white HP number stays legible at the peak (question 35 (2)).
@export var preview_flash_color: Color = Color(1.0, 1.0, 1.0, 0.8)

## How many times a second the predicted part pulses: from [member preview_flash_color] to the bar
## beneath and back. Tune with [member StancePips.preview_flash_rate], so a unit's bars pulse
## together.[br]
## [b]Units:[/b] pulses per second. [b]0.0:[/b] no pulse; the part stays lit.
@export_range(0.0, 8.0, 0.05) var preview_flash_rate: float = 1.5

@export_group("")

## The HP the open forecast leaves, which the bar flashes toward from the HP shown; -1 while no
## forecast flashes it.
var preview_after: int = -1

# How lit the predicted part is: 1.0 at preview_flash_color's alpha, 0.0 unlit.
var _flash_level: float = 0.0:
	set(level):
		_flash_level = level
		queue_redraw()

var _flash_tween: Tween = null

@onready var _number: Label = %Number


func _ready() -> void:
	show_hp(roundi(value), roundi(max_value))


# Drawn after the ProgressBar's own background and fill, and under the number, a child.
func _draw() -> void:
	if preview_after < 0 or _flash_level <= 0.0:
		return
	var rect: Rect2 = preview_rect()
	if not rect.has_area():
		return
	var color: Color = preview_flash_color
	color.a *= _flash_level
	draw_rect(rect, color)


## Shows [param current] HP of [param maximum]; HP is never shown below 0, and a maximum below 1
## is drawn as 1. A flash under way keeps flashing toward its HP after.
func show_hp(current: int, maximum: int) -> void:
	max_value = maxi(maximum, 1)
	value = maxi(current, 0)
	_number.text = text_of(current, maximum)
	queue_redraw()


## While a forecast is open: pulses the bar from the HP shown to [param after] (clamped to 0 and
## the maximum), restarting the pulse lit so every bar shown at once pulses together. An
## [param after] equal to the HP shown flashes nothing.
func show_preview(after: int) -> void:
	var clamped: int = clampi(after, 0, roundi(max_value))
	if clamped == roundi(value):
		clear_preview()
		return
	preview_after = clamped
	_start_flash()


## Flashes nothing.
func clear_preview() -> void:
	preview_after = -1
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash_tween = null
	_flash_level = 0.0


## Whether the bar flashes a forecast's change.
func is_previewing() -> bool:
	return preview_after >= 0


## Where the flash is drawn: the stretch of the fill between the HP shown and
## [member preview_after], within the fill style's top and bottom margins. Empty with no flash.
func preview_rect() -> Rect2:
	if preview_after < 0:
		return Rect2()
	var fill: StyleBox = get_theme_stylebox(&"fill")
	var top: float = 0.0 if fill == null else fill.get_margin(SIDE_TOP)
	var bottom: float = 0.0 if fill == null else fill.get_margin(SIDE_BOTTOM)
	var left: float = _fill_end(mini(roundi(value), preview_after))
	var right: float = _fill_end(maxi(roundi(value), preview_after))
	return Rect2(left, top, right - left, maxf(size.y - top - bottom, 0.0))


## How lit the flash is now, from 0.0 to 1.0; for tests.
func get_flash_level() -> float:
	return _flash_level


## The pulse's tween while one loops; null otherwise. For tests that step it.
func get_flash_tween() -> Tween:
	return _flash_tween if is_instance_valid(_flash_tween) else null


## The number drawn inside the bar.
func get_text() -> String:
	return _number.text


## The number the bar draws for [param current] HP of [param maximum], as [method show_hp] clamps
## them: [code]14/22[/code], or [code]14[/code] with [member is_maximum_shown] off.
func text_of(current: int, maximum: int) -> String:
	var shown: int = maxi(current, 0)
	return "%d/%d" % [shown, maxi(maximum, 1)] if is_maximum_shown else str(shown)


# Lit at once, then down and up again, preview_flash_rate times a second.
func _start_flash() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash_tween = null
	_flash_level = 1.0
	if preview_flash_rate <= 0.0:
		return
	var half: float = 0.5 / preview_flash_rate
	_flash_tween = create_tween().set_loops()
	_flash_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flash_tween.tween_property(self, ^"_flash_level", 0.0, half)
	_flash_tween.tween_property(self, ^"_flash_level", 1.0, half)


# The right edge of the fill drawn for amount HP: ProgressBar draws the fill style's minimum width
# plus its share of the rest, and no fill at 0.
func _fill_end(amount: int) -> float:
	if amount <= 0 or max_value <= 0.0:
		return 0.0
	var fill: StyleBox = get_theme_stylebox(&"fill")
	var least: float = 0.0 if fill == null else fill.get_minimum_size().x
	var ratio: float = clampf(float(amount) / max_value, 0.0, 1.0)
	return minf(roundf(ratio * (size.x - least)) + least, size.x)
