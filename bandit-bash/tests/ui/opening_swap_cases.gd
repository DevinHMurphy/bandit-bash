# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     opening_swap_cases.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

extends RefCounted
## The opening-swap setting's screen cases for the ui/display suite (combat UI plan, UI11 row; P02
## question 17), through the real [code]SaveService[/code]: the Options toggle shows the default
## (on), flips by focus and accept as a keyboard or pad would, and Apply writes it to the save
## file's [code]settings.json[/code]; closing and opening the save file again (a restart) reads it
## back; a new solo run's gameplay screen then opens at turn 1 with no swap window; a hand-edited
## bad value is repaired to on, and the next solo battle opens in the swap window.[br]
## Writes save files, so it runs only with a test user folder (see [code]ui_suite.gd[/code]); it
## deletes [code]user://saves/[/code] before and after. It never names an autoload: a suite
## compiles before they exist, so they are reached as nodes.

const OPTIONS_SCENE: String = "res://scenes/screens/options_screen.tscn"
const GAMEPLAY_SCENE: String = "res://scenes/gameplay/gameplay.tscn"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 1

# Any fixed run seed.
const RUN_SEED: int = 0x5A4B

var _check: Callable
var _root: Node = null
var _saves: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added and input is pushed.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_saves = root.get_node(^"SaveService")


## Runs every case. Call only with a test user folder.
func run() -> void:
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	_test_toggle_saves_and_restarts()
	_test_battle_without_window()
	_test_bad_value_and_window()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# Options shows on, accept on the focused toggle turns it off, Apply writes it, and a restart
# reads it back off.
func _test_toggle_saves_and_restarts() -> void:
	var scene: PackedScene = load(OPTIONS_SCENE)
	var options: Control = scene.instantiate()
	_root.add_child(options)
	var toggle: SettingToggle = options.get_node(^"%OpeningSwapToggle")
	var shown_on: bool = toggle.is_on()
	toggle.get_button().grab_focus()
	_press_action(&"ui_accept")
	var flipped_off: bool = not toggle.is_on()
	var apply: Button = options.get_node(^"%ApplyButton")
	apply.grab_focus()
	_press_action(&"ui_accept")
	options.free()
	var envelope: Dictionary = SaveFile.read(_settings_path()).envelope
	var core: Dictionary = envelope.get(SaveFile.KEY_CORE, {})
	var saved_off: bool = is_same(core.get(SettingsData.OPENING_SWAP_KEY), false)
	_saves.call(&"close_save_file")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var settings: SettingsData = _saves.get(&"settings")
	_check.call("opening swap: Options shows on, accept flips it off, Apply saves it", (
			shown_on and flipped_off and saved_off
	), "shown %s, flipped %s, saved %s" % [shown_on, flipped_off, core])
	_check.call("opening swap: off reloads after a restart", not settings.is_opening_swap_on)


# Off: a new solo run's battle opens at turn 1, in IDLE, with no swap window.
func _test_battle_without_window() -> void:
	var screen: Node = _open_battle()
	if screen == null:
		return
	var controller: BattleController = screen.call(&"get_controller")
	var session: CombatSession = (screen.call(&"get_view") as BattleView).get_session()
	var window: Control = screen.get_node(^"Hud/SwapWindow")
	_check.call("opening swap: off, the solo battle opens at turn 1 with no swap window", (
			session != null
			and session.state.turn == 1
			and not session.state.map.opening_swap_open
			and controller.get_stage() == BattleController.Stage.IDLE
			and not window.visible
	), "turn %d, window open %s, stage %d, shown %s" % [
		session.state.turn, session.state.map.opening_swap_open, controller.get_stage(),
		window.visible,
	])
	screen.free()


# A settings file whose opening swap isn't a bool loads repaired to on, and the next solo battle
# opens in the swap window.
func _test_bad_value_and_window() -> void:
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	var core: Dictionary = {SettingsData.OPENING_SWAP_KEY: "yes", "master_volume": 3}
	SaveFile.write(_settings_path(), SaveFile.make_envelope(SettingsData.SCHEMA_VERSION, core))
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var settings: SettingsData = _saves.get(&"settings")
	_check.call("opening swap: a bad value in settings.json is repaired to on", (
			settings.is_opening_swap_on and settings.master_volume == 3
	))
	var screen: Node = _open_battle()
	if screen == null:
		return
	var controller: BattleController = screen.call(&"get_controller")
	var session: CombatSession = (screen.call(&"get_view") as BattleView).get_session()
	var window: Control = screen.get_node(^"Hud/SwapWindow")
	_check.call("opening swap: on, the solo battle opens in the swap window", (
			session != null
			and session.state.map.opening_swap_open
			and controller.get_stage() == BattleController.Stage.SWAP
			and window.visible
	), "window open %s, stage %d, shown %s" % [
		session.state.map.opening_swap_open, controller.get_stage(), window.visible,
	])
	screen.free()


# A new solo run's gameplay screen, its battle begun; null, with the failure checked, if not.
func _open_battle() -> Node:
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	if err != OK:
		_check.call("opening swap: a new solo run starts", false, error_string(err))
		return null
	var scene: PackedScene = load(GAMEPLAY_SCENE)
	var screen: Node = scene.instantiate()
	_root.add_child(screen)
	return screen


func _settings_path() -> String:
	var folder: String = _saves.call(&"get_save_file_dir", SAVE_NUMBER)
	return folder + SettingsData.FILE_NAME


func _press_action(action: StringName) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)
