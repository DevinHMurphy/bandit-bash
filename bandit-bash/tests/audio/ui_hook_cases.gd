# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ui_hook_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The interface sound hook, on controls made after it attached, as a screen's are: a first focus
## is silent and a move sounds the focus cue, or a control's own ([constant
## UiSoundHook.FOCUS_CUE_META]); a press sounds the press cue, a Back button
## ([constant UiSoundHook.BACK_GROUP], and a [NavButton] set to Go Back) the back cue; a click or
## accept on a disabled button sounds refused; a focused slider's step sounds the focus cue and an
## unfocused one nothing; anything under [constant UiSoundHook.OFF_GROUP] is silent; and a detached
## hook sounds nothing. The hook here records instead of playing.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "audio"

const NAV_BUTTON_SCRIPT: String = "res://ui/common/nav_button.gd"
# The campaign map's nodes sound this on focus (MapNodeButton).
const MAP_NODE_CUE: StringName = &"campaign_map_room_hovered"

var _check: Callable
var _root: Window
var _heard: Array[StringName] = []


func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	var hook: UiSoundHook = UiSoundHook.new(_record)
	hook.attach(_root.get_tree())
	var screen: VBoxContainer = VBoxContainer.new()
	screen.name = "AudioHookScreen"
	_root.add_child(screen)
	var first: Button = _button(screen, "First")
	var second: Button = _button(screen, "Second")

	first.grab_focus()
	_check.call("ui hook: a screen's first focus is silent", _heard.is_empty(), _text())
	second.grab_focus()
	_expect("ui hook: moving focus sounds the focus cue", [UiSoundHook.FOCUS_CUE])
	var map_node: Button = _button(screen, "Node")
	map_node.set_meta(UiSoundHook.FOCUS_CUE_META, MAP_NODE_CUE)
	map_node.grab_focus()
	_expect("ui hook: a control's own focus cue replaces the focus cue", [MAP_NODE_CUE])
	second.grab_focus()
	_heard.clear()

	second.pressed.emit()
	_expect("ui hook: a press sounds the press cue", [UiSoundHook.PRESS_CUE])

	var back: Button = _button(screen, "Back")
	back.add_to_group(UiSoundHook.BACK_GROUP)
	back.pressed.emit()
	_expect("ui hook: a Back button's press sounds the back cue", [UiSoundHook.BACK_CUE])
	_check_nav_button(screen)

	_check_refused(screen)
	_check_slider(screen, second)
	_check_opt_out(screen, second)

	hook.detach()
	second.pressed.emit()
	_expect("ui hook: a detached hook sounds nothing", [])
	screen.free()


func _check_nav_button(screen: Control) -> void:
	var script: GDScript = load(NAV_BUTTON_SCRIPT) as GDScript
	if script == null:
		_check.call("ui hook: the NavButton script loads", false)
		return
	var nav: Button = script.new() as Button
	nav.set(&"action", 1)
	screen.add_child(nav)
	_check.call(
			"ui hook: a NavButton set to Go Back joins the Back group",
			nav.is_in_group(UiSoundHook.BACK_GROUP),
	)
	nav.free()


func _check_refused(screen: Control) -> void:
	var disabled: Button = _button(screen, "Disabled")
	disabled.disabled = true
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	disabled.gui_input.emit(click)
	_expect("ui hook: a click on a disabled button sounds refused", [UiSoundHook.REFUSED_CUE])
	var accept: InputEventAction = InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	disabled.gui_input.emit(accept)
	_expect("ui hook: accept on a disabled button sounds refused", [UiSoundHook.REFUSED_CUE])
	disabled.disabled = false
	disabled.gui_input.emit(click)
	_expect("ui hook: a click on an enabled button isn't refused", [])


func _check_slider(screen: Control, other: Control) -> void:
	var slider: HSlider = HSlider.new()
	slider.max_value = 10.0
	slider.step = 1.0
	screen.add_child(slider)
	slider.value = 3.0
	_expect("ui hook: an unfocused slider's change is silent", [])
	slider.grab_focus()
	_heard.clear()
	slider.value = 4.0
	_expect("ui hook: a focused slider's step sounds the focus cue", [UiSoundHook.FOCUS_CUE])
	other.grab_focus()
	_heard.clear()


func _check_opt_out(screen: Control, other: Control) -> void:
	var quiet: VBoxContainer = VBoxContainer.new()
	quiet.add_to_group(UiSoundHook.OFF_GROUP)
	screen.add_child(quiet)
	var silenced: Button = _button(quiet, "Silenced")
	silenced.grab_focus()
	silenced.pressed.emit()
	_expect("ui hook: under the opt-out group, focus and press are silent", [])
	other.grab_focus()
	_heard.clear()
	_check.call(
			"ui hook: is_silenced sees the group on a parent",
			UiSoundHook.is_silenced(silenced) and not UiSoundHook.is_silenced(other),
	)


func _button(parent: Control, text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	parent.add_child(button)
	return button


func _expect(case_name: String, cues: Array[StringName]) -> void:
	_check.call(case_name, _heard == cues, _text())
	_heard.clear()


func _text() -> String:
	return "heard [%s]" % [", ".join(PackedStringArray(_heard))]


func _record(cue_id: StringName) -> void:
	_heard.append(cue_id)
