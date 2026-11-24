# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/ui/ui_suite.gd"
## Menu screens suite: the real router and save service, walked once each by keyboard, mouse and
## pad. Start (Play) to Save Select (New) to the Main Menu (New Run's place checked), Options (the
## first volume slider focused and outlined by the theme's slider focus style, a step heard,
## Apply, Back by Esc, B or a click), the Lobby (Host primary but refused without Steam, focus on
## Back, Back), then the Main Menu's New Run and New Run's Start, which reaches Loading. On every
## screen: the title in the title style, the main action a primary button with focus, the MENU
## hints, pad glyphs by pad.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/menus/run_all.gd[/code].
## Prints one PASS, FAIL or SKIP line per check and
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure. It needs
## a test user folder (see the base): the walk creates and deletes save files.

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Menu screens by key, mouse, pad: styles, main actions, sliders"

# SceneRouter.Screen values: a suite can't name the autoload (see the base).
const SCREEN_START: int = 0
const SCREEN_LOBBY: int = 1
const SCREEN_LOADING: int = 2
const SCREEN_MAIN_MENU: int = 5
const SCREEN_OPTIONS: int = 6
const SCREEN_SAVE_SELECT: int = 7
const SCREEN_NEW_RUN: int = 8

const DEVICES: PackedStringArray = ["keyboard", "mouse", "pad"]

# Frames left after an action for the router's scene change, layout and deferred focus.
const SETTLE_FRAMES: int = 4

# Most focus steps a walk to a button may take before it counts as unreachable.
const MAX_STEPS: int = 12

# The Input Helper autoload, which tells the device adapters the pad family in use.
const HELPER_PATH: NodePath = ^"/root/InputHelper"

# The theme types the style guide names for titles and a screen's main action.
const TITLE_TYPE: StringName = &"TitleLabel"
const PRIMARY_TYPE: StringName = &"PrimaryButton"

# The focus look's outline (ui-style.md, Focus and hover). Units: base units.
const FOCUS_OUTLINE_WIDTH: int = 2

var _old_root_size: Vector2i = Vector2i.ZERO


func _process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_start("Menu screens tests")
	if not _has_test_user_dir():
		_skip("menu screens", "the screens need a test user folder (see the class doc)")
		_finish()
		return
	_old_root_size = root.size
	root.size = BASE_SCREEN_SIZE
	for device: String in DEVICES:
		GroupClock.lap("menus by %s" % [device])
		_use_device(device)
		SaveFile.delete_folder("user://saves/")
		await _walk(device)
	_use_device("keyboard")
	root.get_node(^"SaveService").call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	if current_scene != null:
		current_scene.queue_free()
	root.size = _old_root_size
	_finish()


# One device's walk through the menu screens; stops at the first screen that doesn't route on.
func _walk(device: String) -> void:
	await _goto(SCREEN_START)
	var scene: Node = current_scene
	var play: Button = scene.call(&"get_main_button")
	if not await _press_main(device, "start", scene, play, SCREEN_SAVE_SELECT):
		return
	scene = current_scene
	var cards: VBoxContainer = scene.get_node(^"%Cards")
	var first: SaveCard = cards.get_child(0) as SaveCard
	var open: Button = first.get_open_button() if first != null else null
	if open == null or not await _press_main(device, "save select", scene, open, SCREEN_MAIN_MENU):
		return
	scene = current_scene
	var new_run: Button = scene.get_node(^"%NewRunButton")
	_check_screen(device, "main menu", scene, new_run)
	await _goto(SCREEN_OPTIONS)
	if not await _walk_options(device):
		return
	await _goto(SCREEN_LOBBY)
	if not await _walk_lobby(device):
		return
	scene = current_scene
	new_run = scene.get_node(^"%NewRunButton")
	if not await _press_main(device, "main menu", scene, new_run, SCREEN_NEW_RUN):
		return
	scene = current_scene
	var start: Button = scene.get_node(^"%StartButton")
	await _press_main(device, "new run", scene, start, SCREEN_LOADING)
	root.get_node(^"SaveService").call(&"close_save_file")


# Options: the first slider has focus and its row draws the theme's slider focus outline; a step
# by the device is heard on the bus; Apply is the primary button and saves; Back by cancel.
func _walk_options(device: String) -> bool:
	var scene: Node = current_scene
	var apply: Button = scene.get_node(^"%OptionsPanel/%ApplyButton")
	var row: VolumeRow = scene.call(&"get_volume_row", SettingsData.Channel.MASTER)
	var slider: HSlider = row.get_slider()
	var style: StyleBoxFlat = row.get_theme_stylebox(&"focus", &"HSlider") as StyleBoxFlat
	_check("options (%s): the title is a title, Apply primary, MENU hints" % [device], (
			_is_title(scene)
			and apply.theme_type_variation == PRIMARY_TYPE
			and _hint_context(scene) == &"MENU"
			and (device != "pad" or _has_glyphs(scene))
	))
	_check("options (%s): the first slider has focus, outlined by its focus style" % [device], (
			slider.has_focus()
			and row.is_showing_focus()
			and style != null
			and not style.draw_center
			and style.border_width_left == FOCUS_OUTLINE_WIDTH
			and style.border_color == UiTokens.color(UiTokens.ACCENT)
	), "focus %s; style %s" % [slider.has_focus(), style])
	var before: float = slider.value
	match device:
		"keyboard":
			_press_key(KEY_LEFT if before > slider.min_value else KEY_RIGHT)
		"pad":
			_press_pad(
					JOY_BUTTON_DPAD_LEFT if before > slider.min_value else JOY_BUTTON_DPAD_RIGHT
			)
		_:
			var rect: Rect2 = slider.get_global_rect()
			_click(Vector2(rect.position.x + rect.size.x * 0.25, rect.get_center().y))
	await _settle()
	_check("options (%s): the slider moves by %s" % [device, device], (
			slider.value != before
	), "%s -> %s" % [before, slider.value])
	if device != "mouse":
		var other: Control = await _step_focus_to(device, apply)
		_check("options (%s): leaving the slider drops its outline" % [device], (
				apply.has_focus() and not row.is_showing_focus()
		), str(other))
	await _accept(device, apply)
	var status: Label = scene.get_node(^"%OptionsPanel/%Status")
	_check("options (%s): Apply, the main action, saves" % [device], (
			status.text.begins_with("Applied.")
	), status.text)
	return await _back(device, scene, SCREEN_MAIN_MENU)


# Lobby without Steam: Host is the primary button but refused, the status says why, and focus
# rests on Back, which leaves.
func _walk_lobby(device: String) -> bool:
	var scene: Node = current_scene
	var host: Button = scene.get_node(^"%HostButton")
	var back: Button = scene.get_node(^"%BackButton")
	var status: Label = scene.get_node(^"%Status")
	var has_steam: bool = root.get_node(^"SteamManager").get(&"is_available")
	if has_steam:
		_skip("lobby (%s)" % [device], "Steam is running, so the lobby goes live")
		return await _back(device, scene, SCREEN_MAIN_MENU)
	_check("lobby (%s): title styled, Host primary but refused, focus on Back" % [device], (
			_is_title(scene)
			and host.theme_type_variation == PRIMARY_TYPE
			and host.disabled
			and not status.text.is_empty()
			and back.has_focus()
			and _hint_context(scene) == &"MENU"
			and (device != "pad" or _has_glyphs(scene))
	), "status '%s'; focus %s" % [status.text, scene.get_viewport().gui_get_focus_owner()])
	return await _back(device, scene, SCREEN_MAIN_MENU)


# Checks screen's look, then presses its main action by device; returns whether the router
# reached next.
func _press_main(
		device: String, where: String, scene: Node, main: Button, next: int
) -> bool:
	_check_screen(device, where, scene, main)
	await _accept(device, main)
	return _check_routed(device, where, next)


# The title in the title style, the main action primary with focus, the MENU hints and, by pad,
# glyphs on the hint bar.
func _check_screen(device: String, where: String, scene: Node, main: Button) -> void:
	_check("%s (%s): title styled, main action primary and focused, MENU hints" % [
		where, device,
	], (
			_is_title(scene)
			and main.theme_type_variation == PRIMARY_TYPE
			and main.has_focus()
			and _hint_context(scene) == &"MENU"
			and (device != "pad" or _has_glyphs(scene))
	), "title %s; %s %s focus %s; hints %s" % [
		_is_title(scene), main.text, main.theme_type_variation, main.has_focus(),
		_hint_context(scene),
	])


# Presses button by device: Enter or A on it once focused, or a click.
func _accept(device: String, button: Button) -> void:
	match device:
		"mouse":
			_click(button.get_global_rect().get_center())
		"pad":
			if not button.has_focus():
				await _step_focus_to(device, button)
			_press_pad(JOY_BUTTON_A)
		_:
			if not button.has_focus():
				await _step_focus_to(device, button)
			_press_key(KEY_ENTER)
	await _settle()


# Back by cancel (Esc, or B on the pad: the Back button's shortcut) or a click on Back; returns
# whether the router reached next.
func _back(device: String, scene: Node, next: int) -> bool:
	var where: String = "back from %s" % [scene.name]
	match device:
		"mouse":
			# The Options screen's Back is its OptionsPanel's.
			var back: Button = scene.get_node_or_null(^"%BackButton") as Button
			if back == null:
				back = scene.get_node(^"%OptionsPanel/%BackButton") as Button
			_click(back.get_global_rect().get_center())
		"pad":
			_press_pad(JOY_BUTTON_B)
		_:
			_press_key(KEY_ESCAPE)
	await _settle()
	return _check_routed(device, where, next)


# Moves focus down (arrow or d-pad) until target has it; returns the control that had focus when
# it stopped.
func _step_focus_to(device: String, target: Control) -> Control:
	for _step: int in MAX_STEPS:
		if target.has_focus():
			break
		if device == "pad":
			_press_pad(JOY_BUTTON_DPAD_DOWN)
		else:
			_press_key(KEY_DOWN)
		await process_frame
	return target.get_viewport().gui_get_focus_owner()


func _check_routed(device: String, where: String, next: int) -> bool:
	var screen: int = _router().get(&"current_screen")
	_check("%s (%s): routes on to screen %d" % [where, device, next], screen == next, (
			"screen %d" % [screen]
	))
	return screen == next


func _goto(screen: int) -> void:
	_router().call(&"goto_screen", screen)
	await _settle()


func _settle() -> void:
	for _frame: int in SETTLE_FRAMES:
		await process_frame


func _is_title(scene: Node) -> bool:
	var title: Label = scene.get_node_or_null(^"%Title") as Label
	return title != null and title.theme_type_variation == TITLE_TYPE


func _hint_context(scene: Node) -> StringName:
	var bar: ControlHintBar = scene.get_node(^"%ControlHintBar")
	bar.refresh()
	return bar.get_context()


func _has_glyphs(scene: Node) -> bool:
	var bar: ControlHintBar = scene.get_node(^"%ControlHintBar")
	bar.refresh()
	return bar.get_markup().contains("[img")


# Tells the adapters which device is in use, as the addon does when one is pressed.
func _use_device(device: String) -> void:
	var helper: Node = root.get_node_or_null(HELPER_PATH)
	if helper == null:
		return
	if device == "pad":
		helper.emit_signal(&"device_changed", "xbox", 0)
	else:
		helper.emit_signal(&"device_changed", "keyboard", -1)


# A press and release of joypad button.
func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = is_down
		root.push_input(event, true)


func _router() -> Node:
	return root.get_node(^"SceneRouter")
