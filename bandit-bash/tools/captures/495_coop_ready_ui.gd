# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     495_coop_ready_ui.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The co-op waiting UI, staged on the solo run, as no Steam session runs here: the map's
## [TeamReadyStatus] beside the vote's column with 2 and then 4 seats in mixed states; the loading
## screen's bars at mixed progress for 2 and 4 players; its Continue as a co-op [ReadyToggle], not
## Ready (the keyboard's glyph) and Ready (an Xbox pad's glyph), the device family in use put back
## after. Every state is set on the elements directly, so nothing is sent or saved; the group ends
## on the map, as it found it, so 500 starts where 494 left it.[br]
## Needs: the map, as the co-op pause menu shots leave it (494_coop_pause_menu).

# The Input Helper autoload, which tells the device adapters the pad family in use.
const HELPER_PATH: NodePath = ^"/root/InputHelper"

# A device name the addon reports for each family, to put the family in use back after the shots.
# Any name InputDeviceAdapter doesn't list reads as another pad.
const FAMILY_DEVICES: Dictionary[InputDeviceAdapter.Family, String] = {
	InputDeviceAdapter.Family.KEYBOARD_MOUSE: "keyboard",
	InputDeviceAdapter.Family.XBOX: "xbox",
	InputDeviceAdapter.Family.PLAYSTATION: "playstation",
	InputDeviceAdapter.Family.OTHER_PAD: "generic",
}

const TWO_NAMES: Dictionary[int, String] = {0: "You", 1: "Player 2"}
const FOUR_NAMES: Dictionary[int, String] = {
	0: "You", 1: "Player 2", 2: "Player 3", 3: "Player 4",
}


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the co-op ready shots need the map (screen %d)" % [router_screen()])
		return true
	note("co-op ready shots: every state staged on the elements over the solo run")
	await _map_status()
	await _loading()
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# The map's ready status in the co-op column: 2 seats, then 4, in mixed states.
func _map_status() -> void:
	var status: TeamReadyStatus = scene().call(&"get_ready_status")
	var side: Control = scene().get_node_or_null(^"%CoopSide") as Control
	if status == null or side == null:
		fail("the map has no ready status in a co-op column")
		return
	side.visible = true
	status.set_state(PackedInt32Array([0]), PackedInt32Array([0, 1]), {}, TWO_NAMES)
	await frames(SETTLE_FRAMES)
	await capture("coop_ready_status_2")
	var progress: Dictionary[int, float] = {3: 0.6}
	status.set_state(PackedInt32Array([0, 2]), PackedInt32Array([0, 1, 2]), progress, FOUR_NAMES)
	await frames(SETTLE_FRAMES)
	await capture("coop_ready_status_4")
	status.clear()
	side.visible = false


# The loading screen's bars for 2 and 4 players, then its Continue as a co-op toggle, off and on.
func _loading() -> void:
	node(^"SceneRouter").call(&"goto_screen", SCREEN_LOADING)
	await frames(SETTLE_FRAMES)
	if router_screen() != SCREEN_LOADING:
		fail("the loading screen didn't open (screen %d)" % [router_screen()])
		return
	var two: Dictionary[int, float] = {1: 0.35}
	scene().call(&"set_state", PackedInt32Array(), PackedInt32Array([0]), two, TWO_NAMES)
	await frames(SETTLE_FRAMES)
	await capture("loading_bars_2")
	var four: Dictionary[int, float] = {1: 0.8, 3: 0.15}
	scene().call(
			&"set_state", PackedInt32Array([0]), PackedInt32Array([0, 2]), four, FOUR_NAMES
	)
	await frames(SETTLE_FRAMES)
	await capture("loading_bars_4")
	var toggle: ReadyToggle = scene().call(&"get_continue_button")
	var hints: ScreenHints = scene().get_node(^"%ScreenHints") as ScreenHints
	var adapter: InputDeviceAdapter = (
			scene().get_node_or_null(^"InputDeviceAdapter") as InputDeviceAdapter
	)
	var was: InputDeviceAdapter.Family = InputDeviceAdapter.Family.KEYBOARD_MOUSE
	if adapter != null:
		was = adapter.get_family()
	toggle.is_coop = true
	hints.context = &"LOADING_COOP"
	toggle.grab_focus()
	_set_family("keyboard", -1)
	await frames(SETTLE_FRAMES)
	await capture("ready_toggle_off")
	_set_family("xbox", 0)
	toggle.set_ready(true)
	await frames(SETTLE_FRAMES)
	await capture("ready_toggle_on")
	_set_family(FAMILY_DEVICES[was], -1 if was == InputDeviceAdapter.Family.KEYBOARD_MOUSE else 0)


# Tells the device adapters the family in use, as the addon does when a device is pressed.
func _set_family(device: String, index: int) -> void:
	var helper: Node = node(HELPER_PATH) if tree.root.has_node(HELPER_PATH) else null
	if helper != null:
		helper.emit_signal(&"device_changed", device, index)
