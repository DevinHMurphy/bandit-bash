# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stance_pips.gd
# Author:
# Created:  November 6, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name StancePips
extends Control
## A unit's Stance as one segment per point, read at a glance (combat UI plan, question 29 (3)).
##
## One segment per point up to the unit's maximum; points above it (Triage) in a second colour;
## at 0 every segment takes the Exposed look, since an Exposed unit can be crit and shoved. Past
## [member tick_fallback_count] segments it draws one bar with tick marks instead. While a
## forecast is open, [method show_preview] dims the segments the action would break and pulses
## them toward [member preview_flash_color] (question 34 (1)).[br]
## [b]Look,[/b] modelled on the godot-segmented-bar addon (question 29 (6); its code isn't used):
## [member segment_texture], the theme's [code]separation[/code], a lagging change colour on the
## segments a drop took and a short flash; each segment outlined ([member outline_color],
## question 34 (2)) so they read apart at any count. The segments stretch to share the pips'
## width, which [UnitInfo] anchors to the [HpBar]'s, so they always span the bar. Colours and the
## separation are the theme's [code]StancePips[/code] items ([code]battle_theme.tres[/code]).[br]
## [b]Event driven:[/b] it redraws only when [method show_stance] or [method show_preview] change
## it, the change tween [method show_stance] returns is stepped, or the forecast's pulse loops;
## nothing runs per frame otherwise. It holds no rules: the values come from [UnitInfo].
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## How one segment is drawn.
enum Pip {
	## A point the unit doesn't have: [code]empty_color[/code].
	EMPTY = 0,
	## A point it has, up to its maximum: [code]fill_color[/code].
	FILLED = 1,
	## A point it has above its maximum (Triage): [code]overflow_color[/code].
	OVERFLOW = 2,
	## A point the open forecast's action would break: [code]preview_color[/code], pulsing toward
	## [member preview_flash_color].
	BREAKING = 3,
	## A point a drop just took, until [member lag_time] passes: [code]change_color[/code].
	LOST = 4,
	## A point it doesn't have while its Stance is 0 (Exposed): [code]exposed_color[/code].
	EXPOSED = 5,
}

## More segments than this draw as one bar with a tick mark between points, so a unit with a lot
## of Stance stays readable.[br]
## [b]Units:[/b] segments.
@export_range(1, 32) var tick_fallback_count: int = 6:
	set(value):
		tick_fallback_count = value
		queue_redraw()

## The texture each segment is drawn with, tinted by its colour (the addon's segment texture).[br]
## [b]Unset:[/b] each segment is a flat rectangle.
@export var segment_texture: Texture2D = null:
	set(value):
		segment_texture = value
		queue_redraw()

## How long the segments a drop took keep the change colour before they empty (the addon's HP
## example hangs 0.8 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0. [b]0.0:[/b] they empty at once.
@export_range(0.0, 3.0, 0.01) var lag_time: float = 0.8

## How long every segment flashes [code]flash_color[/code] when Stance drops (the addon's HP
## example flashes 0.1 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0. [b]0.0:[/b] no flash.
@export_range(0.0, 1.0, 0.01) var flash_time: float = 0.1

@export_group("Outline")

# The bg token at the tick marks' alpha, one pixel, so 5 px pips keep 3 px of colour.
## The outline drawn inside each segment's edge, so neighbouring segments read apart at any count,
## overflow and Exposed included; in bar mode it frames the whole bar.[br]
## [b]Transparent:[/b] no outline.
@export var outline_color: Color = UiTokens.with_alpha(UiTokens.BG, 0.85):
	set(value):
		outline_color = value
		queue_redraw()

## The outline's width, inside each segment, so the segments keep their size.[br]
## [b]Units:[/b] pixels at the info's scale. [b]0.0:[/b] no outline.
@export_range(0.0, 4.0, 0.5) var outline_width: float = 1.0:
	set(value):
		outline_width = value
		queue_redraw()

@export_group("Forecast flash")

## The colour the segments a forecast would break pulse toward, from the dimmed
## [code]preview_color[/code] (question 34 (1): white, at 0.8 alpha as question 35 (2) sets the
## HP bar's). Match [member HpBar.preview_flash_color].
@export var preview_flash_color: Color = Color(1.0, 1.0, 1.0, 0.8)

## How many times a second those segments pulse to [member preview_flash_color] and back. Keep it
## equal to [member HpBar.preview_flash_rate], so a unit's bars pulse together.[br]
## [b]Units:[/b] pulses per second. [b]0.0:[/b] no pulse; they stay lit.
@export_range(0.0, 8.0, 0.05) var preview_flash_rate: float = 1.5

@export_group("")

## The Stance shown.
var stance: int = 0

## The Stance maximum shown; segments above it are overflow.
var stance_max: int = 0

## The Stance the open forecast leaves; segments from it up to [member stance] are dimmed. -1
## while no forecast dims any.
var preview_after: int = -1

# How far up the change colour reaches while a drop's lag lasts; -1 when none does.
var _lag_from: int = -1

# How far the segments are drawn toward flash_color: 1.0 at a drop, tweened to 0.0.
var _flash: float = 0.0:
	set(value):
		_flash = value
		queue_redraw()

var _is_shown: bool = false

var _change: Tween = null

# How far the segments a forecast would break are drawn toward preview_flash_color: 1.0 lit.
var _preview_level: float = 0.0:
	set(level):
		_preview_level = level
		queue_redraw()

var _preview_tween: Tween = null


func _draw() -> void:
	var count: int = pip_count()
	if count == 0:
		return
	var flash_color: Color = get_theme_color(&"flash_color")
	for i: int in count:
		var rect: Rect2 = segment_rect(i)
		var pip: Pip = pip_at(i)
		var color: Color = color_of(pip)
		if pip == Pip.BREAKING:
			color = color.lerp(preview_flash_color, _preview_level)
		color = color.lerp(flash_color, _flash)
		if segment_texture != null:
			draw_texture_rect(segment_texture, rect, false, color)
		else:
			draw_rect(rect, color)
		if not is_bar_mode():
			_draw_outline(rect)
	if not is_bar_mode():
		return
	var tick_color: Color = get_theme_color(&"tick_color")
	for i: int in range(1, count):
		var x: float = segment_rect(i).position.x
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), tick_color, 1.0)
	_draw_outline(Rect2(Vector2.ZERO, size))


## Shows [param current] Stance of [param maximum]; neither is shown below 0. A drop from what was
## shown flashes and lags (see the class doc) and returns that tween, paused for the caller to
## step ([method Tween.custom_step]); otherwise returns null.
func show_stance(current: int, maximum: int) -> Tween:
	var shown: int = maxi(current, 0)
	var from: int = stance
	var dropped: bool = _is_shown and shown < from
	var lagged_from: int = _lag_from
	stance = shown
	stance_max = maxi(maximum, 0)
	_is_shown = true
	if is_instance_valid(_change):
		_change.kill()
	_change = null
	_lag_from = -1
	_flash = 0.0
	if not dropped or (lag_time <= 0.0 and flash_time <= 0.0):
		queue_redraw()
		return null
	# Two drops in one lag keep the change colour from the higher one.
	_lag_from = maxi(from, lagged_from)
	var tween: Tween = create_tween()
	tween.pause()
	tween.set_parallel(true)
	if flash_time > 0.0:
		_flash = 1.0
		tween.tween_property(self, ^"_flash", 0.0, flash_time)
	tween.tween_callback(_end_lag).set_delay(lag_time)
	_change = tween
	queue_redraw()
	return tween


## Dims the segments from [param after] up to the Stance shown, the forecast's Stance after its
## action, and pulses them toward [member preview_flash_color], restarting the pulse lit so every
## bar shown at once pulses together. An [param after] at or above the Stance shown flashes none.
func show_preview(after: int) -> void:
	if after >= stance:
		clear_preview()
		return
	preview_after = maxi(after, 0)
	_start_preview_flash()


## Dims and flashes no segment.
func clear_preview() -> void:
	preview_after = -1
	if is_instance_valid(_preview_tween):
		_preview_tween.kill()
	_preview_tween = null
	_preview_level = 0.0


## How lit the segments a forecast would break are now, from 0.0 to 1.0; for tests.
func get_preview_level() -> float:
	return _preview_level


## The forecast pulse's tween while one loops; null otherwise. For tests that step it.
func get_preview_tween() -> Tween:
	return _preview_tween if is_instance_valid(_preview_tween) else null


## How many outlines are drawn: one per segment, or one round the bar in bar mode; 0 with no
## segment, or with [member outline_width] 0 or [member outline_color] transparent.
func outline_count() -> int:
	if pip_count() == 0 or outline_width <= 0.0 or outline_color.a <= 0.0:
		return 0
	return 1 if is_bar_mode() else pip_count()


# ASSUMPTION: a unit with no Stance maximum and no Stance shows no segments (map objects have no
# Stance, and every MVP unit has 1 to 3), rather than one Exposed segment.
## How many segments are drawn: the Stance or its maximum, whichever is higher.
func pip_count() -> int:
	return maxi(stance, stance_max)


## Whether the segments are drawn as one bar with tick marks ([member tick_fallback_count]).
func is_bar_mode() -> bool:
	return pip_count() > tick_fallback_count


## How many tick marks the bar draws; 0 while separate segments are drawn.
func tick_count() -> int:
	return pip_count() - 1 if is_bar_mode() else 0


## Whether the Exposed look shows: Stance 0 with a maximum above 0.
func is_exposed() -> bool:
	return stance == 0 and stance_max > 0


## Where segment [param index] (0 is the leftmost) is drawn: the segments share the pips' whole
## width, the theme's [code]separation[/code] apart (none in bar mode), so they always span it.
## An empty rect while no segment is drawn.
func segment_rect(index: int) -> Rect2:
	var count: int = pip_count()
	if count == 0:
		return Rect2()
	var gap: float = 0.0 if is_bar_mode() else float(get_theme_constant(&"separation"))
	var width: float = maxf((size.x - gap * (count - 1)) / count, 0.0)
	return Rect2(index * (width + gap), 0.0, width, size.y)


## How segment [param index] (0 is the leftmost) is drawn now.
func pip_at(index: int) -> Pip:
	if index < stance:
		if preview_after >= 0 and index >= preview_after:
			return Pip.BREAKING
		return Pip.OVERFLOW if index >= stance_max else Pip.FILLED
	if index < _lag_from:
		return Pip.LOST
	return Pip.EXPOSED if stance == 0 else Pip.EMPTY


## The theme colour [param pip] is drawn in, before any flash.
func color_of(pip: Pip) -> Color:
	match pip:
		Pip.FILLED:
			return get_theme_color(&"fill_color")
		Pip.OVERFLOW:
			return get_theme_color(&"overflow_color")
		Pip.BREAKING:
			return get_theme_color(&"preview_color")
		Pip.LOST:
			return get_theme_color(&"change_color")
		Pip.EXPOSED:
			return get_theme_color(&"exposed_color")
	return get_theme_color(&"empty_color")


func _end_lag() -> void:
	_lag_from = -1
	queue_redraw()


# Lit at once, then down and up again, preview_flash_rate times a second (HpBar's pulse).
func _start_preview_flash() -> void:
	if is_instance_valid(_preview_tween):
		_preview_tween.kill()
	_preview_tween = null
	_preview_level = 1.0
	if preview_flash_rate <= 0.0:
		return
	var half: float = 0.5 / preview_flash_rate
	_preview_tween = create_tween().set_loops()
	_preview_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_preview_tween.tween_property(self, ^"_preview_level", 0.0, half)
	_preview_tween.tween_property(self, ^"_preview_level", 1.0, half)


# The outline inside rect's edge, outline_width wide; nothing when outline_count() is 0.
func _draw_outline(rect: Rect2) -> void:
	if outline_count() == 0:
		return
	var inset: Rect2 = rect.grow(-outline_width * 0.5)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		return
	draw_rect(inset, outline_color, false, outline_width)
