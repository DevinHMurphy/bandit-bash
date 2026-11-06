# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stance_pips.gd
# Author:
# Created:  November 6, 2026
# Modified: November 6, 2026
# ==============================================================================

class_name StancePips
extends Control
## A unit's Stance as one segment per point, read at a glance (combat UI plan, question 29 (3)).
##
## One segment per point up to the unit's maximum; points above it (Triage) in a second colour;
## at 0 every segment takes the Exposed look, since an Exposed unit can be crit and shoved. Past
## [member tick_fallback_count] segments it draws one bar with tick marks instead. While a
## forecast is open, [method show_preview] dims the segments the exchange would break.[br]
## [b]Look,[/b] modelled on the godot-segmented-bar addon (question 29 (6); its code isn't used):
## [member segment_texture], the theme's [code]separation[/code], a lagging change colour on the
## segments a drop took and a short flash. The segments stretch to share the pips' width, which
## [UnitInfo] anchors to the [HpBar]'s, so they always span the bar. Colours and the separation
## are the theme's [code]StancePips[/code] items ([code]battle_theme.tres[/code]).[br]
## [b]Event driven:[/b] it redraws only when [method show_stance] or [method show_preview] change
## it, or the change tween [method show_stance] returns is stepped; nothing runs per frame. It holds
## no rules: the values come from [UnitInfo].
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
	## A point the open forecast's exchange would break: [code]preview_color[/code].
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


func _draw() -> void:
	var count: int = pip_count()
	if count == 0:
		return
	var flash_color: Color = get_theme_color(&"flash_color")
	for i: int in count:
		var rect: Rect2 = segment_rect(i)
		var color: Color = color_of(pip_at(i)).lerp(flash_color, _flash)
		if segment_texture != null:
			draw_texture_rect(segment_texture, rect, false, color)
		else:
			draw_rect(rect, color)
	if not is_bar_mode():
		return
	var tick_color: Color = get_theme_color(&"tick_color")
	for i: int in range(1, count):
		var x: float = segment_rect(i).position.x
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), tick_color, 1.0)


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


## Dims the segments from [param after] up to the Stance shown: the forecast's Stance after its
## exchange. An [param after] at or above the Stance shown dims none.
func show_preview(after: int) -> void:
	preview_after = maxi(after, 0) if after < stance else -1
	queue_redraw()


## Dims no segment.
func clear_preview() -> void:
	preview_after = -1
	queue_redraw()


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
