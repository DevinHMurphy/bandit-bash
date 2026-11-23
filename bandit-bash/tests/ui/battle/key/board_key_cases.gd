# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     board_key_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## The board key's cases for the ui/display suite (RF-039, ui-lift.md UL11): its six rows, one per
## [ProfileMark] shape in the triangle's order with what each beats, then filled for the player
## side and hollow for the enemy; the pause menu with no key scene offering no Board Key, and with
## the battle's offering it under Resume; and the key's focus path, by keyboard and by pad events
## from the InputMap: Board Key opens it with Back focused, the d-pad and arrows keep focus on
## Back, and Back (accept) and Esc / B each show the buttons again with Board Key focused. The
## pause menu's script names autoloads, so its scene loads at run time.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/display"

const KEY_SCENE: PackedScene = preload("res://ui/battle/key/board_key.tscn")

# Loaded at run time: its script names autoloads (see the class doc).
const PAUSE_MENU_SCENE: String = "res://ui/common/pause_menu.tscn"

# The rows as the key words them (P15 UL11 decisions), top to bottom.
const LINES: PackedStringArray = [
	"Power — beats Balance",
	"Balance — beats Nimble",
	"Nimble — beats Power",
	"No profile — outside the triangle",
	"Filled — your units",
	"Hollow outline — enemies",
]

# Each row's shape and whether it is drawn filled.
const SHAPES: Array[ProfileMark.Shape] = [
	ProfileMark.Shape.SQUARE, ProfileMark.Shape.CIRCLE, ProfileMark.Shape.TRIANGLE,
	ProfileMark.Shape.BAR, ProfileMark.Shape.CIRCLE, ProfileMark.Shape.CIRCLE,
]
const FILLED: Array[bool] = [true, true, true, true, true, false]

# The moves that must leave focus on Back.
const MOVES: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]

var _check: Callable
var _root: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the key and the menu are added.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root


## Runs every case.
func run() -> void:
	_test_rows()
	_test_menu_entry()
	for is_pad: bool in [false, true]:
		_test_focus_path(is_pad)


func _test_rows() -> void:
	var key: BoardKey = KEY_SCENE.instantiate()
	_root.add_child(key)
	var rows: Array[BoardKeyRow] = key.get_rows()
	var wrong: PackedStringArray = []
	for index: int in mini(rows.size(), SHAPES.size()):
		var mark: ProfileMark = rows[index].get_profile_mark()
		if (
				not mark.is_shown() or mark.get_shape() != SHAPES[index]
				or mark.is_filled() != FILLED[index]
		):
			wrong.append("row %d: shape %d, filled %s" % [
				index, mark.get_shape(), mark.is_filled(),
			])
	_check.call("key: a row per shape, then the side rule, each worded as decided", (
			key.get_lines() == LINES
	), " / ".join(key.get_lines()))
	_check.call("key: each row draws its shape, filled but the enemy's hollow row", (
			rows.size() == SHAPES.size() and wrong.is_empty()
	), "%d rows; %s" % [rows.size(), "; ".join(wrong)])
	var back: Button = key.get_back_button()
	var stops: Array[Control] = _focus_stops(key)
	_check.call("key: the rows take no focus; Back is its one focus stop", (
			back.focus_mode == Control.FOCUS_ALL and stops.size() == 1 and stops[0] == back
	), "stops %s" % [stops])
	key.free()


func _test_menu_entry() -> void:
	var plain: CanvasLayer = _menu(null)
	plain.call(&"open")
	var plain_button: Button = plain.get_node(^"%BoardKeyButton") as Button
	_check.call("menu: with no key scene there is no Board Key", (
			not plain_button.visible and plain.call(&"get_board_key") == null
	))
	plain.call(&"close")
	plain.free()
	var menu: CanvasLayer = _menu(KEY_SCENE)
	menu.call(&"open")
	var resume: Button = menu.get_node(^"%ResumeButton") as Button
	var button: Button = menu.get_node(^"%BoardKeyButton") as Button
	_check.call("menu: the battle's key gives Board Key, next under Resume in the focus column", (
			button.visible and menu.call(&"get_board_key") is BoardKey
			and resume.get_node(resume.focus_neighbor_bottom) == button
			and button.get_node(button.focus_neighbor_top) == resume
	))
	button.pressed.emit()
	var is_open: bool = menu.call(&"is_board_key_open")
	_check.call("menu: pressing Board Key (the mouse's way) shows the key in the buttons' place", (
			is_open and not (menu.get_node(^"%Column") as Control).visible
	))
	menu.call(&"close")
	menu.call(&"open")
	_check.call("menu: closing the menu closes the key; it opens on the buttons again", (
			not menu.call(&"is_board_key_open")
			and (menu.get_node(^"%Column") as Control).visible
	))
	menu.call(&"close")
	menu.free()


# The key's focus path through real input events of the keyboard or a pad.
func _test_focus_path(is_pad: bool) -> void:
	var tag: String = "focus (%s)" % ["pad" if is_pad else "keyboard"]
	var menu: CanvasLayer = _menu(KEY_SCENE)
	menu.call(&"open")
	var viewport: Viewport = _root.get_viewport()
	var button: Button = menu.get_node(^"%BoardKeyButton") as Button
	button.grab_focus()
	_press(&"ui_accept", is_pad)
	var key: BoardKey = menu.call(&"get_board_key")
	var back: Button = key.get_back_button()
	_check.call(tag + ": accept on Board Key opens the key, Back focused", (
			menu.call(&"is_board_key_open") and viewport.gui_get_focus_owner() == back
	), "focus %s" % [viewport.gui_get_focus_owner()])
	var left: PackedStringArray = []
	for move: StringName in MOVES:
		_press(move, is_pad)
		if viewport.gui_get_focus_owner() != back:
			left.append("%s to %s" % [move, viewport.gui_get_focus_owner()])
			back.grab_focus()
	_check.call(tag + ": every move keeps focus on Back", left.is_empty(), "; ".join(left))
	_press(&"ui_accept", is_pad)
	_check.call(tag + ": accept on Back shows the buttons, Board Key focused", (
			not menu.call(&"is_board_key_open") and viewport.gui_get_focus_owner() == button
	), "focus %s" % [viewport.gui_get_focus_owner()])
	_press(&"ui_accept", is_pad)
	_press(&"ui_cancel", is_pad)
	_check.call(tag + ": cancel in the key shows the buttons, Board Key focused, menu open", (
			not menu.call(&"is_board_key_open")
			and (menu.get_node(^"%Root") as Control).visible
			and viewport.gui_get_focus_owner() == button
	), "focus %s" % [viewport.gui_get_focus_owner()])
	viewport.gui_release_focus()
	menu.call(&"open_board_key")
	viewport.gui_release_focus()
	_check.call(tag + ": focus lost while the key shows comes back to Back", (
			menu.call(&"keep_focus") and viewport.gui_get_focus_owner() == back
	))
	menu.call(&"close")
	menu.free()


# A pause menu in the tree, its board key scene key_scene (null for none).
func _menu(key_scene: PackedScene) -> CanvasLayer:
	var menu: CanvasLayer = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	menu.set(&"board_key_scene", key_scene)
	_root.add_child(menu)
	return menu


# Presses and lets go of action through its first binding: a key, or the pad's button or axis.
func _press(action: StringName, is_pad: bool) -> void:
	var source: InputEvent = null
	for event: InputEvent in InputMap.action_get_events(action):
		var is_pad_event: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_pad_event == is_pad and (is_pad or event is InputEventKey):
			source = event
			break
	if source == null:
		_check.call("focus: %s has a %s binding" % [action, "pad" if is_pad else "key"], false)
		return
	for is_down: bool in [true, false]:
		var sent: InputEvent = source.duplicate()
		if sent is InputEventJoypadMotion:
			var motion: InputEventJoypadMotion = sent
			motion.axis_value = motion.axis_value if is_down else 0.0
		elif sent is InputEventJoypadButton:
			(sent as InputEventJoypadButton).pressed = is_down
		elif sent is InputEventKey:
			(sent as InputEventKey).pressed = is_down
		_root.get_viewport().push_input(sent, true)


# Every control under node that can take focus, in tree order.
static func _focus_stops(node: Node) -> Array[Control]:
	var stops: Array[Control] = []
	for child: Node in node.find_children("*", "Control", true, false):
		var control: Control = child
		if control.focus_mode != Control.FOCUS_NONE:
			stops.append(control)
	return stops
