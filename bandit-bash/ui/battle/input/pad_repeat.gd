# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pad_repeat.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name PadRepeat
extends Node
## Turns a held d-pad direction or left-stick push into board cursor steps with a key-like repeat:
## one step when the direction is pressed, another after [member first_delay], then one every
## [member repeat_interval] while it stays held (combat UI plan, question 25).
##
## Keys repeat by themselves (the system's key echo); joypad buttons never echo, and a stick sends
## a motion event for every small change, so reading those as presses would jump the cursor
## several tiles per push. [BattleController] hands each joypad event to [method take] before its
## own reading and moves the cursor on [signal stepped]. Only the board cursor repeats: a panel's
## focus moves one row per press, as the GUI reads the stick by
## [method Input.is_action_just_pressed].
## Held state comes from the events alone, so it works with events pushed into a viewport.[br]
## When two directions are held (a diagonal push), the newest one repeats.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ============================================================
# INPUT MAP SETUP (project.godot; ui_* are Godot's built-in actions):
#   "ui_up" / "ui_down" /   -> d-pad (joypad buttons 11-14), left stick (axis 1 -/+,
#   "ui_left" / "ui_right"     axis 0 -/+, past the action's 0.5 deadzone)
#                              (any joypad event on them: pressed starts a direction, released or
#                              back inside the deadzone stops it; keys on the same actions are
#                              not read here, so take() returns false for them)
# ============================================================

## The cursor should move one tile in [param direction] ([constant Vector2i.UP] and so on).
signal stepped(direction: Vector2i)

## The board step of each direction action.
const DIRECTIONS: Dictionary[StringName, Vector2i] = {
	&"ui_up": Vector2i.UP,
	&"ui_down": Vector2i.DOWN,
	&"ui_left": Vector2i.LEFT,
	&"ui_right": Vector2i.RIGHT,
}

# ASSUMPTION: no basis in Godot_FE (its cursor stepped once per press, with no repeat) or the
# vision; near a common keyboard repeat delay, for the tuning pass.
## How long a direction is held before it starts repeating.[br]
## [b]Units:[/b] seconds.
@export_range(0.05, 2.0, 0.01) var first_delay: float = 0.35

# ASSUMPTION: as first_delay, for the tuning pass.
## The time between repeated steps once repeating.[br]
## [b]Units:[/b] seconds. [b]0.1:[/b] ten tiles a second.
@export_range(0.02, 1.0, 0.01) var repeat_interval: float = 0.1

# The directions held, oldest first; the last one repeats.
var _held: Array[StringName] = []

# Seconds until the next repeated step.
var _left: float = 0.0


func _process(delta: float) -> void:
	advance(delta)


## Reads [param event]: a joypad button or axis event on a direction action updates which
## directions are held, and a newly pressed one emits [signal stepped] at once. Returns whether
## it was such an event, which the caller then reads no further.
func take(event: InputEvent) -> bool:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return false
	var is_direction: bool = false
	for action: StringName in DIRECTIONS:
		if not event.is_action(action):
			continue
		is_direction = true
		var is_pressed: bool = event.is_action_pressed(action)
		var at: int = _held.find(action)
		if is_pressed and at < 0:
			_held.append(action)
			_left = first_delay
			stepped.emit(DIRECTIONS[action])
		elif not is_pressed and at >= 0:
			_held.remove_at(at)
	return is_direction


## Runs [param delta] seconds of the repeat: at most one step per call, so a long frame never
## jumps the cursor several tiles. [method Node._process] calls it; tests call it to stand for
## time passing.
func advance(delta: float) -> void:
	if _held.is_empty():
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = repeat_interval
	stepped.emit(DIRECTIONS[_held.back()])


## Forgets every held direction, so nothing repeats until a direction is pressed again.
func release_all() -> void:
	_held.clear()


## The directions held, oldest first.
func get_held() -> Array[StringName]:
	return _held.duplicate()
