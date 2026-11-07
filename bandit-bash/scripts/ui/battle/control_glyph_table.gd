# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     control_glyph_table.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name ControlGlyphTable
extends Resource
## The glyph drawn for each input of each device family in the control hints, and the text label
## shown where a family has no glyph (combat UI plan, question 32 (2)), kept in one editable
## table: [code]assets/sprites/controls/control_glyphs.tres[/code].
##
## Entries are keyed by [method input_id] of an [InputEvent]: [code]key:Q[/code] (a key, by
## [method OS.get_keycode_string] of its physical key, else its keycode), [code]button:0[/code]
## (a joypad button, by [enum JoyButton]), [code]axis:5+[/code] (a joypad axis, by
## [enum JoyAxis], and the direction it is pushed). A missing or null texture shows the label: a
## pad family's label entry, else the id; a key's label is the [ControlHintBar]'s key name. Swap
## in a full glyph pack by editing the texture entries. Presentation only.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The glyph of each key, by its [code]key:[/code] id ([method input_id]).[br]
## [b]Empty:[/b] every key shows its name.
@export var keyboard_glyphs: Dictionary[String, Texture2D] = {}

## The glyph of each Xbox pad input, by its [code]button:[/code] or [code]axis:[/code] id.[br]
## [b]Empty:[/b] every input shows its [member xbox_labels] entry.
@export var xbox_glyphs: Dictionary[String, Texture2D] = {}

## The glyph of each PlayStation pad input, by its id.[br]
## [b]Empty:[/b] every input shows its [member playstation_labels] entry.
@export var playstation_glyphs: Dictionary[String, Texture2D] = {}

## The glyph of each input of any other pad, by its id.[br]
## [b]Empty:[/b] every input shows its [member other_pad_labels] entry.
@export var other_pad_glyphs: Dictionary[String, Texture2D] = {}

## What an Xbox pad input without a glyph shows, by its id, such as [code]"axis:5+": "RT"[/code].
## [b]Missing:[/b] the id itself.
@export var xbox_labels: Dictionary[String, String] = {}

## What a PlayStation pad input without a glyph shows, by its id.[br]
## [b]Missing:[/b] the id itself.
@export var playstation_labels: Dictionary[String, String] = {}

## What an input of any other pad without a glyph shows, by its id.[br]
## [b]Missing:[/b] the id itself.
@export var other_pad_labels: Dictionary[String, String] = {}


## The glyph of [param id] for [param family]; null when the table has none.
func glyph_for(family: InputDeviceAdapter.Family, id: String) -> Texture2D:
	var glyphs: Dictionary[String, Texture2D] = keyboard_glyphs
	match family:
		InputDeviceAdapter.Family.XBOX:
			glyphs = xbox_glyphs
		InputDeviceAdapter.Family.PLAYSTATION:
			glyphs = playstation_glyphs
		InputDeviceAdapter.Family.OTHER_PAD:
			glyphs = other_pad_glyphs
	var glyph: Texture2D = glyphs.get(id, null)
	return glyph


## The label of pad input [param id] for [param family]: its label entry, else the id. Keys
## have no entries here: empty for [constant InputDeviceAdapter.Family.KEYBOARD_MOUSE].
func label_for(family: InputDeviceAdapter.Family, id: String) -> String:
	var labels: Dictionary[String, String] = {}
	match family:
		InputDeviceAdapter.Family.KEYBOARD_MOUSE:
			return ""
		InputDeviceAdapter.Family.XBOX:
			labels = xbox_labels
		InputDeviceAdapter.Family.PLAYSTATION:
			labels = playstation_labels
		InputDeviceAdapter.Family.OTHER_PAD:
			labels = other_pad_labels
	var label: String = labels.get(id, id)
	return label


## The table key of [param event]: [code]key:<name>[/code], [code]button:<index>[/code],
## [code]axis:<index><+ or ->[/code] or [code]mouse:<index>[/code]; empty for any other event.
static func input_id(event: InputEvent) -> String:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%s" % [OS.get_keycode_string(code)]
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button != null:
		return "button:%d" % [button.button_index]
	var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if motion != null:
		return "axis:%d%s" % [motion.axis, "-" if motion.axis_value < 0.0 else "+"]
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null:
		return "mouse:%d" % [mouse.button_index]
	return ""
