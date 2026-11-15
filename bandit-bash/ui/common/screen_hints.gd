# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     screen_hints.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name ScreenHints
extends HintSource
## The hints of a screen outside battle: a fixed list of actions per context, the context set by
## the screen as it moves between its steps ([member context]).
##
## While the tree is paused (the pause menu) the context is PAUSED and the actions are
## [member paused_actions], as on the battle screen. What each action is called per context is the
## screen's [ControlHintBar]'s [member ControlHintBar.labels], set in the screen's scene. Reads no
## input itself.

## The context while the tree is paused, whose actions are [member paused_actions].
const PAUSED_CONTEXT: StringName = &"PAUSED"

## The screen's step, a key of [member actions]. [b]Empty or missing from it:[/b] the bar hides.
@export var context: StringName = &"":
	set(value):
		if value == context:
			return
		context = value
		live_actions_changed.emit()

## The input actions live in each context, in the order the bar shows them; action names from
## [code]project.godot[/code]'s input map.
@export var actions: Dictionary[StringName, PackedStringArray] = {}

## The actions live while the pause menu has paused the tree: its focus moves, presses and closes.
@export var paused_actions: PackedStringArray = ["ui_up", "ui_down", "ui_accept", "ui_cancel"]


func get_hint_context() -> StringName:
	if context.is_empty():
		return &""
	if is_inside_tree() and get_tree().paused:
		return PAUSED_CONTEXT
	return context


func get_live_actions() -> Array[StringName]:
	var live: Array[StringName] = []
	var shown: StringName = get_hint_context()
	if shown.is_empty():
		return live
	var names: PackedStringArray = paused_actions
	if shown != PAUSED_CONTEXT:
		names = actions.get(shown, PackedStringArray())
	for action: String in names:
		live.append(StringName(action))
	return live
