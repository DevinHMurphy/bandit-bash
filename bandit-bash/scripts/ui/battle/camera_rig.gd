# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camera_rig.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name CameraRig
extends Node2D
## The battle camera: frames the whole map ([method frame]) and pans to a point
## ([method pan_to]) without leaving the map.
##
## [BattleView] owns it and steps its pans with the rest of the board's animations, so a pan
## takes the playback's time. A map that fits the screen is centred, and a pan on that axis keeps
## it centred.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## How long a pan to a unit takes at playback speed 1.0 (Godot_FE [code]CController.gd[/code],
## [code]move_camera[/code]).[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] the camera jumps.
@export_range(0.0, 2.0, 0.01) var pan_time: float = 0.2

## Space kept clear around the map when framing it, which keeps the map off the HUD's edge strips
## (the battle debug bar).[br]
## [b]Units:[/b] screen pixels.
# ASSUMPTION: greybox value; Godot_FE frames to the map's edge with no margin.
@export_range(0.0, 256.0, 1.0) var frame_margin: float = 48.0

## The map's area in the board's space, as last framed; empty before [method frame].
var map_rect: Rect2 = Rect2()

@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)


## Zooms so all of [param rect] (the map, in the board's space) fits the screen with
## [member frame_margin] around it, and centres on it.
func frame(rect: Rect2) -> void:
	map_rect = rect
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var room: Vector2 = screen - Vector2.ONE * frame_margin * 2.0
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or room.x <= 0.0 or room.y <= 0.0:
		_camera.position = rect.get_center()
		return
	var fit: float = minf(room.x / rect.size.x, room.y / rect.size.y)
	_camera.zoom = Vector2(fit, fit)
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


## The camera centre nearest [param point] that shows no space beyond the map; on an axis where
## the map fits the screen, the map's centre.
func clamp_to_map(point: Vector2) -> Vector2:
	if not map_rect.has_area():
		return point
	var half_view: Vector2 = get_viewport().get_visible_rect().size / (_camera.zoom * 2.0)
	var low: Vector2 = map_rect.position + half_view
	var high: Vector2 = map_rect.end - half_view
	var clamped: Vector2 = point
	clamped.x = map_rect.get_center().x if low.x >= high.x else clampf(point.x, low.x, high.x)
	clamped.y = map_rect.get_center().y if low.y >= high.y else clampf(point.y, low.y, high.y)
	return clamped


## Where the camera centre is now, in the board's space.
func get_focus() -> Vector2:
	return _camera.position


func _on_viewport_size_changed() -> void:
	if map_rect.has_area():
		frame(map_rect)
