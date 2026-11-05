# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camera_rig.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
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
## [method clamp_to_map] and [method get_focus] mean the same thing either way.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

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

@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)


## Zooms so all of [param rect] (the map, in the board's space) fits the framing area (see the
## class doc), and centres the area on it.
func frame(rect: Rect2) -> void:
	map_rect = rect
	var area: Rect2 = _frame_area()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or area.size.x <= 0.0 or area.size.y <= 0.0:
		_camera.offset = Vector2.ZERO
		_camera.position = rect.get_center()
		return
	var fit: float = minf(area.size.x / rect.size.x, area.size.y / rect.size.y)
	_camera.zoom = Vector2(fit, fit)
	# The screen's centre shows position + offset; this puts position at the area's centre.
	var screen_center: Vector2 = get_viewport().get_visible_rect().get_center()
	_camera.offset = (screen_center - area.get_center()) / fit
	_camera.position = rect.get_center()


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


func _on_viewport_size_changed() -> void:
	if map_rect.has_area():
		frame(map_rect)
