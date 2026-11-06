# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camera_rig.gd
# Author:
# Created:  November 4, 2026
# Modified: November 6, 2026
# ==============================================================================

class_name CameraRig
extends Node2D
## The battle camera: frames the whole map ([method frame]) and pans to a point
## ([method pan_to]) without leaving the map.
##
## [BattleView] owns it and steps its pans with the rest of the board's animations, so a pan
## takes the playback's time. A map that fits is centred, and a pan on that axis keeps it
## centred.[br]
## [b]Where it frames:[/b] inside [member screen_area] when one is set (the HUD's free space,
## [member BattleView.map_area]), else the whole screen less [member frame_margin]. The camera's
## offset puts the area's centre, not the screen's, on the point it looks at, so
## [method clamp_to_map] and [method get_focus] mean the same thing either way.[br]
## [b]Screen space:[/b] [method board_to_screen] is where the camera draws the board, which
## the [UnitInfoLayer] follows; a [method shake] moves it too.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The map was framed again ([method frame]), so the board moved on screen without a tween.
signal framed()

## How long a pan to a unit takes at playback speed 1.0 (Godot_FE [code]CController.gd[/code],
## [code]move_camera[/code]).[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] the camera jumps.
@export_range(0.0, 2.0, 0.01) var pan_time: float = 0.2

# ASSUMPTION: greybox value; Godot_FE frames to the map's edge with no margin.
## Space kept clear around the map when it is framed on the whole screen, with no
## [member screen_area]. Ignored inside a screen area, which keeps clear of the HUD itself.[br]
## [b]Units:[/b] screen pixels.
@export_range(0.0, 256.0, 1.0) var frame_margin: float = 48.0

## The map's area in the board's space, as last framed; empty before [method frame].
var map_rect: Rect2 = Rect2()

## Where on screen the map is framed, in screen pixels; empty for the whole screen less
## [member frame_margin]. Takes effect at the next [method frame].
var screen_area: Rect2 = Rect2()

# The camera's offset as frame() set it; a shake moves the camera around it.
var _framed_offset: Vector2 = Vector2.ZERO

# Cosmetic randomness for shake directions: unsaved and never a gameplay stream (gdscript.md 8.5).
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)


## Zooms so all of [param rect] (the map, in the board's space) fits the framing area (see the
## class doc), and centres the area on it. Emits [signal framed].
func frame(rect: Rect2) -> void:
	map_rect = rect
	var area: Rect2 = _frame_area()
	_camera.position = rect.get_center()
	_framed_offset = Vector2.ZERO
	if rect.size.x > 0.0 and rect.size.y > 0.0 and area.size.x > 0.0 and area.size.y > 0.0:
		var fit: float = minf(area.size.x / rect.size.x, area.size.y / rect.size.y)
		_camera.zoom = Vector2(fit, fit)
		# The screen's centre shows position + offset; this puts position at the area's centre.
		var screen_center: Vector2 = get_viewport().get_visible_rect().get_center()
		_framed_offset = (screen_center - area.get_center()) / fit
	_camera.offset = _framed_offset
	framed.emit()


## Where the camera draws the board now: board (global) coordinates to screen pixels, the same
## transform the [Camera2D] gives the viewport (the framing area's offset and any shake included).
func board_to_screen() -> Transform2D:
	var zoom: Vector2 = _camera.zoom
	var looked_at: Vector2 = _camera.global_position + _camera.offset
	var half_screen: Vector2 = get_viewport().get_visible_rect().size * 0.5
	return Transform2D(0.0, zoom, 0.0, half_screen - looked_at * zoom)


## Starts a shake of [param strength] screen pixels that dies away over [param seconds], each step
## in a random direction, and returns its tween, paused for the caller to step; null when either is
## 0. The camera ends where [method frame] put it.
func shake(strength: float, seconds: float) -> Tween:
	if strength <= 0.0 or seconds <= 0.0:
		return null
	var tween: Tween = create_tween()
	tween.pause()
	tween.tween_method(_shake_step.bind(strength), 1.0, 0.0, seconds)
	return tween


## Starts a pan to [param point] (in the board's space), kept inside the map, and returns its
## tween, paused for the caller to step ([method Tween.custom_step]); null when there is nothing
## to pan.
func pan_to(point: Vector2) -> Tween:
	var target: Vector2 = clamp_to_map(point)
	if pan_time <= 0.0:
		_camera.position = target
		return null
	var tween: Tween = create_tween()
	tween.pause()
	tween.tween_property(_camera, ^"position", target, pan_time)
	return tween


## The point to look at nearest [param point] that shows no space beyond the map in the framing
## area; on an axis where the map fits the area, the map's centre.
func clamp_to_map(point: Vector2) -> Vector2:
	if not map_rect.has_area():
		return point
	var shown: Vector2 = (
			screen_area.size if screen_area.has_area()
			else get_viewport().get_visible_rect().size
	)
	var half_view: Vector2 = shown / (_camera.zoom * 2.0)
	var low: Vector2 = map_rect.position + half_view
	var high: Vector2 = map_rect.end - half_view
	var clamped: Vector2 = point
	clamped.x = map_rect.get_center().x if low.x >= high.x else clampf(point.x, low.x, high.x)
	clamped.y = map_rect.get_center().y if low.y >= high.y else clampf(point.y, low.y, high.y)
	return clamped


## The point the framing area's centre shows now, in the board's space.
func get_focus() -> Vector2:
	return _camera.position


# The screen rect the map is fitted into: screen_area, else the screen less frame_margin.
func _frame_area() -> Rect2:
	if screen_area.has_area():
		return screen_area
	return get_viewport().get_visible_rect().grow(-frame_margin)


# left: how much of the shake is left, 1.0 to 0.0; the offset is in board units, so divided by zoom.
func _shake_step(left: float, strength: float) -> void:
	var direction: Vector2 = Vector2.from_angle(_shake_rng.randf() * TAU)
	_camera.offset = _framed_offset + direction * strength * left / _camera.zoom.x


func _on_viewport_size_changed() -> void:
	if map_rect.has_area():
		frame(map_rect)
