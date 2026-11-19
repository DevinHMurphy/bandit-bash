# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_info_layer.gd
# Author:
# Created:  November 6, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitInfoLayer
extends CanvasLayer
## The screen-space layer above the board that holds each unit's [UnitInfo] (its bars, numbers and
## icons) and keeps it on its [UnitToken] through the camera (combat UI plan, question 29 (2)).
##
## Drawn on screen, the bars and numbers stay crisp at any zoom, while the token's sprite, outline
## and grayscale stay in the world. [BattleView] adds an info per token ([method add_info]) and
## calls [method follow] with the camera's transform whenever the camera or a token can have moved;
## nothing runs per frame by itself. An info follows its token's fade and is freed with it.[br]
## [b]Pop-ups[/b] (the [DamageNumber]s) live here too ([method add_popup]), kept on the board
## point they rose from as the camera moves, a unit's own stacked a row apart, and drawn above
## every info by their [member CanvasItem.z_index]. A pop-up outlives its unit's info: a killing
## blow's number keeps rising while the unit fades.[br]
## [b]Layer order:[/b] [member CanvasLayer.layer] 1, above the board and below the HUD (layer 2 in
## [code]gameplay.tscn[/code]); two canvas layers on one number draw in no set order.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The info placed for each unit ([UnitInfo]).[br]
## [b]Unset:[/b] no unit shows bars, numbers or icons, and an error is reported per token.
@export var info_scene: PackedScene = null

## Where an info sits from its unit's centre on screen, at scale 1.0; it scales with the info.[br]
## [b]Units:[/b] screen pixels. [b](0, 0):[/b] the info's origin on the unit's centre.
@export var unit_offset: Vector2 = Vector2.ZERO

## The smallest scale an info is drawn at as the camera zooms out; with [member max_scale] it
## clamps the camera's zoom, so 1.0 for both keeps every info at its authored size.[br]
## [b]1.0:[/b] one screen pixel per pixel of the info scene.
@export_range(0.1, 8.0, 0.05) var min_scale: float = 1.0

## The largest scale an info is drawn at as the camera zooms in (see [member min_scale]).[br]
## [b]1.0:[/b] one screen pixel per pixel of the info scene.
@export_range(0.1, 8.0, 0.05) var max_scale: float = 1.0

# ASSUMPTION: no basis in Godot_FE (its numbers overlapped); the big-number size, 28, so stacked
# rows of 28-unit digits never touch.
## How far apart a unit's stacked pop-ups sit ([method add_popup]): each new one pushes the ones
## still showing up by this much.[br]
## [b]Units:[/b] screen pixels at info scale 1.0. [b]0.0:[/b] pop-ups don't stack.
@export_range(0.0, 128.0, 1.0) var popup_row_height: float = 28.0

# Each unit's info and the token it follows, by unit id.
var _infos: Dictionary[String, UnitInfo] = {}
var _tokens: Dictionary[String, UnitToken] = {}

# The board-to-screen transform of the last follow().
var _to_screen: Transform2D = Transform2D.IDENTITY

# Each live pop-up and, at the same index, the board point it rose from, its stack's key (empty:
# none) and its row in that stack (0 the newest).
var _popups: Array[Node2D] = []
var _popup_points: PackedVector2Array = []
var _popup_keys: PackedStringArray = []
var _popup_rows: PackedInt32Array = []


## Places an info for [param token], the token of [param unit_id], links it as the token's
## [member UnitToken.info] and puts it over the token. The info is freed when the token leaves the
## tree. Returns it; null when [member info_scene] is unset.
func add_info(unit_id: String, token: UnitToken) -> UnitInfo:
	if info_scene == null:
		push_error("UnitInfoLayer: no info scene set")
		return null
	remove_info(unit_id)
	var info: UnitInfo = info_scene.instantiate()
	add_child(info)
	token.info = info
	_infos[unit_id] = info
	_tokens[unit_id] = token
	token.tree_exiting.connect(_on_token_tree_exiting.bind(unit_id, token), CONNECT_ONE_SHOT)
	_place(unit_id, info_scale())
	return info


## Frees [param unit_id]'s info, if it has one.
func remove_info(unit_id: String) -> void:
	var info: UnitInfo = _infos.get(unit_id, null)
	_infos.erase(unit_id)
	_tokens.erase(unit_id)
	if is_instance_valid(info):
		remove_child(info)
		info.queue_free()


## Frees every info and pop-up.
func clear() -> void:
	for unit_id: String in _infos.keys():
		remove_info(unit_id)
	for popup: Node2D in _popups:
		if is_instance_valid(popup):
			popup.queue_free()
	_popups.clear()
	_popup_points.clear()
	_popup_keys.clear()
	_popup_rows.clear()


## Adds [param popup], a pop-up such as a [DamageNumber], over [param board_point] (a point on the
## board in its global coordinates, such as a token's [member Node2D.global_position]), scaled as
## the infos are, and keeps it there through each [method follow] until it frees itself. Pop-ups
## sharing a [param stack_key] (a unit id) stack: the new one takes the bottom row and pushes the
## live ones up by [member popup_row_height]; one [param is_beside] the newest shares its row. Its
## scene's [member CanvasItem.z_index] must be above the infos' 0.
func add_popup(
		popup: Node2D, board_point: Vector2, stack_key: String = "", is_beside: bool = false,
) -> void:
	_drop_freed_popups()
	if not stack_key.is_empty() and not is_beside:
		for index: int in _popups.size():
			if _popup_keys[index] == stack_key:
				_popup_rows[index] += 1
	add_child(popup)
	_popups.append(popup)
	_popup_points.append(board_point)
	_popup_keys.append(stack_key)
	_popup_rows.append(0)
	var scale_now: float = info_scale()
	for index: int in _popups.size():
		_place_popup(index, scale_now)


## The pop-ups still on the layer, oldest first.
func get_popups() -> Array[Node2D]:
	var live: Array[Node2D] = []
	for popup: Node2D in _popups:
		if is_instance_valid(popup) and not popup.is_queued_for_deletion():
			live.append(popup)
	return live


## [param popup]'s row in its stack, 0 the newest; -1 when the layer doesn't hold it.
func popup_row_of(popup: Node2D) -> int:
	var index: int = _popups.find(popup)
	return -1 if index < 0 else _popup_rows[index]


## Puts every info over its token, as [param to_screen] (the camera's board-to-screen transform,
## [method CameraRig.board_to_screen]) draws the token, scaled as [method info_scale] says,
## with its token's fade; and every pop-up over its board point, dropping those that freed
## themselves. Writes only what changed.
func follow(to_screen: Transform2D) -> void:
	_to_screen = to_screen
	var scale_now: float = info_scale()
	for unit_id: String in _infos:
		_place(unit_id, scale_now)
	var index: int = 0
	while index < _popups.size():
		var popup: Node2D = _popups[index]
		if not is_instance_valid(popup) or popup.is_queued_for_deletion():
			_remove_popup_at(index)
			continue
		_place_popup(index, scale_now)
		index += 1


## The scale infos are drawn at now: the camera's zoom clamped to [member min_scale] and
## [member max_scale].
func info_scale() -> float:
	return clampf(_to_screen.get_scale().x, min_scale, max_scale)


## Where [param unit_id]'s info should be on screen now: its token's centre through the last
## [method follow]'s transform, plus [member unit_offset]. [constant Vector2.INF] with no token.
func screen_point_of(unit_id: String) -> Vector2:
	var token: UnitToken = _tokens.get(unit_id, null)
	if not is_instance_valid(token):
		return Vector2.INF
	return _to_screen * token.global_position + unit_offset * info_scale()


## [param unit_id]'s info; null when it has none.
func info_of(unit_id: String) -> UnitInfo:
	return _infos.get(unit_id, null)


## How many infos the layer holds.
func info_count() -> int:
	return _infos.size()


func _place(unit_id: String, scale_now: float) -> void:
	var token: UnitToken = _tokens[unit_id]
	var info: UnitInfo = _infos[unit_id]
	if not is_instance_valid(token) or not is_instance_valid(info):
		return
	var at: Vector2 = screen_point_of(unit_id)
	if info.position != at:
		info.position = at
	var size_now: Vector2 = Vector2(scale_now, scale_now)
	if info.scale != size_now:
		info.scale = size_now
	if info.modulate != token.modulate:
		info.modulate = token.modulate
	if info.visible != token.visible:
		info.visible = token.visible


# Puts the pop-up at index over its board point, raised by its row.
func _place_popup(index: int, scale_now: float) -> void:
	var popup: Node2D = _popups[index]
	if not is_instance_valid(popup):
		return
	var raise: Vector2 = Vector2(0.0, -popup_row_height * _popup_rows[index] * scale_now)
	var at: Vector2 = _to_screen * _popup_points[index] + raise
	if popup.position != at:
		popup.position = at
	var size_now: Vector2 = Vector2(scale_now, scale_now)
	if popup.scale != size_now:
		popup.scale = size_now


func _drop_freed_popups() -> void:
	var index: int = 0
	while index < _popups.size():
		var popup: Node2D = _popups[index]
		if is_instance_valid(popup) and not popup.is_queued_for_deletion():
			index += 1
		else:
			_remove_popup_at(index)


func _remove_popup_at(index: int) -> void:
	_popups.remove_at(index)
	_popup_points.remove_at(index)
	_popup_keys.remove_at(index)
	_popup_rows.remove_at(index)


func _on_token_tree_exiting(unit_id: String, token: UnitToken) -> void:
	if _tokens.get(unit_id, null) == token:
		remove_info(unit_id)
