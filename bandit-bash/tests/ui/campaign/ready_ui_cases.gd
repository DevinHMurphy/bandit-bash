# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ready_ui_cases.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

extends RefCounted
## The co-op waiting UI, for tests/ui/campaign/run_all.gd: [TeamReadyStatus] rows and states from
## set_state with 2 and 4 seats (Ready, Choosing, Loading at its progress, Done), a forfeited seat
## leaving, an unknown seat ignored, seat order, clamped progress, solo hidden; [ReadyToggle] by
## keyboard, pad and mouse, solo (a plain button, its label kept) and co-op (Ready and Not ready,
## a take-back press marked), its detail, set_ready and its glyph for the device family in use;
## the loading screen's bars for 1 to 4 players. The gated screens' toggles are
## coop_seat_cases.gd's and node_screen_cases.gd's. Changes no scene; writes nothing.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"

const STATUS_SCENE: String = "res://ui/common/team_ready_status.tscn"
const TOGGLE_SCENE: String = "res://ui/common/ready_toggle.tscn"
const BAR_SCENE: String = "res://ui/battle/hud/control_hint_bar.tscn"
const DEVICE_SCENE: String = "res://ui/battle/input/input_device_adapter.tscn"
const LOADING_SCENE: String = "res://ui/screens/loading_gate.tscn"

# The Input Helper autoload, which tells the device adapters the pad family in use.
const HELPER_PATH: NodePath = ^"/root/InputHelper"

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# Where the toggle under test sits, clear of the root's corner, for clicks.
const TOGGLE_AT: Vector2 = Vector2(200.0, 200.0)

const NAMES: Dictionary[int, String] = {
	0: "You", 1: "Player 2", 2: "Player 3", 3: "Player 4",
}

var _check: Callable
var _root: Window = null

# What the toggle under test emitted since the last clear: each ready_changed value, the presses,
# and whether each press was marked as taking Ready back.
var _ready_changes: Array[bool] = []
var _presses: int = 0
var _take_backs: Array[bool] = []


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the elements are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


## Runs every case.
func run() -> void:
	_test_status_two_seats()
	_test_status_four_seats()
	_test_status_edges()
	_test_toggle_solo()
	_test_toggle_coop()
	_test_toggle_text()
	_test_toggle_glyph()
	_test_loading_screen()


func _test_status_two_seats() -> void:
	var status: TeamReadyStatus = _add_status()
	var names: Dictionary[int, String] = {0: NAMES[0], 1: NAMES[1]}
	status.set_state(PackedInt32Array([0]), PackedInt32Array([0, 1]), {}, names)
	_check.call("ready status (2 seats): a row each in seat order, Ready and Choosing", (
			status.visible
			and status.get_lines() == PackedStringArray(["You · Ready", "Player 2 · Choosing"])
			and status.state_of(0) == TeamReadyStatus.State.READY
			and status.state_of(1) == TeamReadyStatus.State.CHOOSING
			and not status.get_row(0).is_bar_shown()
	), str(status.get_lines()))
	status.set_state(PackedInt32Array(), PackedInt32Array([0]), {1: 0.25}, names)
	_check.call("ready status (2 seats): Ready taken back reads Choosing; unloaded reads Loading", (
			status.get_lines() == PackedStringArray(["You · Choosing", "Player 2 · Loading"])
			and is_equal_approx(status.progress_of(1), 0.25)
			and is_equal_approx(status.progress_of(0), 1.0)
	), "%s; %.2f" % [status.get_lines(), status.progress_of(1)])
	_free(status)


func _test_status_four_seats() -> void:
	var status: TeamReadyStatus = _add_status()
	var progress: Dictionary[int, float] = {2: 0.4}
	status.set_state(PackedInt32Array([1]), PackedInt32Array([0, 1, 3]), progress, NAMES)
	_check.call("ready status (4 seats): mixed states, the loading seat at its progress", (
			status.get_lines() == PackedStringArray([
				"You · Choosing", "Player 2 · Ready", "Player 3 · Loading",
				"Player 4 · Choosing",
			])
			and is_equal_approx(status.get_row(2).get_progress(), 0.4)
			and status.get_child_count() == 4
	), str(status.get_lines()))
	status.loaded_state = TeamReadyStatus.State.DONE
	status.shows_bars = true
	status.set_state(PackedInt32Array([1]), PackedInt32Array([0, 1, 3]), progress, NAMES)
	var bars: bool = true
	for seat: int in NAMES:
		bars = bars and status.get_row(seat).is_bar_shown()
	_check.call("ready status (4 seats, loading screen): loaded seats read Done, bars shown", (
			status.get_lines() == PackedStringArray([
				"You · Done", "Player 2 · Ready", "Player 3 · Loading", "Player 4 · Done",
			])
			and bars
			and is_equal_approx(status.get_row(3).get_progress(), 1.0)
	), str(status.get_lines()))
	var row_two: TeamReadyRow = status.get_row(2)
	var without: Dictionary[int, String] = NAMES.duplicate()
	without.erase(2)
	status.set_state(PackedInt32Array([1]), PackedInt32Array([0, 1, 3]), progress, without)
	_check.call("ready status: a forfeited seat left out of the names loses its row", (
			status.get_row(2) == null
			and (not is_instance_valid(row_two) or row_two.is_queued_for_deletion())
	), str(status.get_lines()))
	_check.call("ready status: the other rows stay, in seat order", (
			status.get_seats() == PackedInt32Array([0, 1, 3])
			and status.get_lines() == PackedStringArray([
				"You · Done", "Player 2 · Ready", "Player 4 · Done",
			])
			and status.get_child_count() == 3
	), str(status.get_lines()))
	var stray: Dictionary[int, float] = {7: 0.5}
	status.set_state(PackedInt32Array([7]), PackedInt32Array([0, 1, 3, 7]), stray, without)
	_check.call("ready status: a seat with no name is ignored", (
			status.get_row(7) == null
			and status.get_seats() == PackedInt32Array([0, 1, 3])
			and status.get_child_count() == 3
	), str(status.get_seats()))
	_free(status)


func _test_status_edges() -> void:
	var status: TeamReadyStatus = _add_status()
	var solo: Dictionary[int, String] = {0: NAMES[0]}
	status.set_state(PackedInt32Array(), PackedInt32Array([0]), {}, solo)
	var hidden_solo: bool = not status.visible
	status.min_seats = 1
	status.set_state(PackedInt32Array(), PackedInt32Array([0]), {}, solo)
	_check.call("ready status: hidden in solo by default; min_seats 1 shows the one row", (
			hidden_solo and status.visible and status.get_lines().size() == 1
	), str(status.get_lines()))
	var unordered: Dictionary[int, String] = {3: NAMES[3], 1: NAMES[1]}
	var odd: Dictionary[int, float] = {1: 1.7, 3: -0.5}
	status.set_state(PackedInt32Array(), PackedInt32Array(), odd, unordered)
	var children: PackedStringArray = []
	for child: Node in status.get_children():
		children.append((child as TeamReadyRow).get_name_text())
	_check.call("ready status: names given out of order show ascending; progress clamps to 0-1", (
			status.get_seats() == PackedInt32Array([1, 3])
			and children == PackedStringArray(["Player 2", "Player 4"])
			and is_equal_approx(status.progress_of(1), 1.0)
			and is_equal_approx(status.progress_of(3), 0.0)
	), "%s; %s" % [children, status.get_seats()])
	status.clear()
	_check.call("ready status: clear hides it with no rows", (
			not status.visible and status.get_seats().is_empty()
			and status.get_child_count() == 0
	))
	_free(status)


# Solo: a plain button by key, pad and mouse; each press acts, emits Ready, keeps its label.
func _test_toggle_solo() -> void:
	var toggle: ReadyToggle = _add_toggle()
	toggle.solo_text = "Leave"
	var wrong: PackedStringArray = []
	for device: String in ["key", "pad", "mouse"]:
		_clear_toggle_log()
		_press(toggle, device)
		if (
				_presses != 1 or _ready_changes != [true] or toggle.text != "Leave"
				or toggle.is_ready() or toggle.button_pressed or toggle.toggle_mode
				or _take_backs != [false]
		):
			wrong.append("%s: %d presses, %s, '%s'" % [
				device, _presses, _ready_changes, toggle.text,
			])
	_check.call("ready toggle (solo): key, pad and mouse each press it once, label kept", (
			wrong.is_empty()
	), "; ".join(wrong))
	_free(toggle.get_parent())


# Co-op: Enter makes Ready, pad A takes it back (marked), a click makes Ready again.
func _test_toggle_coop() -> void:
	var toggle: ReadyToggle = _add_toggle()
	toggle.is_coop = true
	var shown_first: String = toggle.text
	_clear_toggle_log()
	_press(toggle, "key")
	_check.call("ready toggle (co-op, keys): reads Ready; Enter makes the seat Ready", (
			shown_first == "Ready" and toggle.toggle_mode
			and toggle.is_ready() and toggle.text == "Not ready"
			and _ready_changes == [true] and _presses == 1 and _take_backs == [false]
	), "'%s' then '%s'; %s" % [shown_first, toggle.text, _ready_changes])
	_clear_toggle_log()
	_press(toggle, "pad")
	_check.call("ready toggle (co-op, pad): A takes Ready back, the press marked as such", (
			not toggle.is_ready() and toggle.text == "Ready"
			and _ready_changes == [false] and _presses == 1 and _take_backs == [true]
	), "'%s'; %s; %s" % [toggle.text, _ready_changes, _take_backs])
	_clear_toggle_log()
	_press(toggle, "mouse")
	_check.call("ready toggle (co-op, mouse): a click makes the seat Ready again", (
			toggle.is_ready() and toggle.text == "Not ready"
			and _ready_changes == [true] and _take_backs == [false]
	), "'%s'; %s" % [toggle.text, _ready_changes])
	_clear_toggle_log()
	toggle.set_ready(false)
	var after_reset: bool = not toggle.is_ready() and toggle.text == "Ready"
	toggle.set_ready(true)
	_check.call("ready toggle: set_ready changes Ready and its label, emitting nothing", (
			after_reset and toggle.is_ready() and toggle.text == "Not ready"
			and _ready_changes.is_empty() and _presses == 0
	), "'%s'; %s" % [toggle.text, _ready_changes])
	toggle.is_coop = false
	_check.call("ready toggle: back to solo drops Ready and shows the solo label", (
			not toggle.is_ready() and not toggle.button_pressed and not toggle.toggle_mode
			and toggle.text == "Continue"
	), toggle.text)
	_free(toggle.get_parent())


func _test_toggle_text() -> void:
	var toggle: ReadyToggle = _add_toggle()
	toggle.solo_text = "Leave"
	toggle.detail = "choose Feast or Train first"
	var solo: String = toggle.text
	toggle.is_coop = true
	var coop: String = toggle.text
	toggle.ready_text = "Ready to fight"
	_check.call("ready toggle: the detail follows either label; ready_text relabels", (
			solo == "Leave (choose Feast or Train first)"
			and coop == "Ready (choose Feast or Train first)"
			and toggle.text == "Ready to fight (choose Feast or Train first)"
	), "%s / %s / %s" % [solo, coop, toggle.text])
	_free(toggle.get_parent())


# The press action's glyph while focused, for the family in use; none while unfocused or unset.
func _test_toggle_glyph() -> void:
	var toggle: ReadyToggle = _add_toggle()
	var holder: Control = toggle.get_parent()
	var device: InputDeviceAdapter = (
			load(DEVICE_SCENE) as PackedScene
	).instantiate() as InputDeviceAdapter
	holder.add_child(device)
	var bar: ControlHintBar = (load(BAR_SCENE) as PackedScene).instantiate() as ControlHintBar
	bar.device = device
	holder.add_child(bar)
	toggle.grab_focus()
	var without_bar: bool = toggle.icon == null
	toggle.hint_bar = bar
	var keyboard: Texture2D = toggle.icon
	_set_family("xbox", 0)
	var pad: Texture2D = toggle.icon
	toggle.release_focus()
	var unfocused: bool = toggle.icon == null
	_set_family("keyboard", -1)
	_check.call("ready toggle: focused, it shows the press key's glyph for the family in use", (
			without_bar and unfocused
			and keyboard != null and keyboard == bar.glyph_of(&"ui_accept")
	), "keyboard %s, pad %s" % [keyboard, pad])
	_check.call("ready toggle: a pad family swaps in the pad's glyph", (
			pad != null and pad != keyboard
	), "keyboard %s, pad %s" % [keyboard, pad])
	_free(holder)


# The loading screen's bars: this machine's alone on arrival, then the gate's for 1 to 4 players.
func _test_loading_screen() -> void:
	var screen: Control = (load(LOADING_SCENE) as PackedScene).instantiate() as Control
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = SCREEN_SIZE
	var status: TeamReadyStatus = screen.call(&"get_status")
	var button: ReadyToggle = screen.call(&"get_continue_button")
	_check.call("loading: on arrival one bar, this machine's, full and Done; Continue", (
			status.visible
			and status.get_lines() == PackedStringArray(["You · Done"])
			and status.get_row(status.get_seats()[0]).is_bar_shown()
			and is_equal_approx(status.progress_of(status.get_seats()[0]), 1.0)
			and button.solo_text == "Continue"
	), str(status.get_lines()))
	var expected: Array[PackedStringArray] = [
		PackedStringArray(["You · Loading"]),
		PackedStringArray(["You · Done", "Player 2 · Loading"]),
		PackedStringArray(["You · Ready", "Player 2 · Loading", "Player 3 · Done"]),
		PackedStringArray([
			"You · Ready", "Player 2 · Loading", "Player 3 · Done", "Player 4 · Loading",
		]),
	]
	var ready_seats: PackedInt32Array = [0]
	var loaded_seats: PackedInt32Array = [0, 2]
	var progress: Dictionary[int, float] = {0: 0.1, 1: 0.5, 3: 0.75}
	var wrong: PackedStringArray = []
	for count: int in range(1, 5):
		var names: Dictionary[int, String] = {}
		for seat: int in count:
			names[seat] = NAMES[seat]
		var ready_now: PackedInt32Array = ready_seats if count >= 3 else PackedInt32Array()
		var loaded_now: PackedInt32Array = loaded_seats if count >= 2 else PackedInt32Array()
		screen.call(&"set_state", ready_now, loaded_now, progress, names)
		var bars_ok: bool = true
		for seat: int in count:
			bars_ok = bars_ok and status.get_row(seat).is_bar_shown()
		if status.get_lines() != expected[count - 1] or not status.visible or not bars_ok:
			wrong.append("%d: %s" % [count, status.get_lines()])
	_check.call("loading: a bar per player for 1 to 4 players, each Ready, Loading or Done", (
			wrong.is_empty()
			and is_equal_approx(status.get_row(1).get_progress(), 0.5)
			and is_equal_approx(status.get_row(3).get_progress(), 0.75)
			and is_equal_approx(status.get_row(2).get_progress(), 1.0)
	), "; ".join(wrong))
	_root.remove_child(screen)
	screen.free()


func _add_status() -> TeamReadyStatus:
	var status: TeamReadyStatus = (
			load(STATUS_SCENE) as PackedScene
	).instantiate() as TeamReadyStatus
	_root.add_child(status)
	return status


# A toggle in a holder at TOGGLE_AT, logging what it emits.
func _add_toggle() -> ReadyToggle:
	var holder: Control = Control.new()
	holder.size = SCREEN_SIZE
	_root.add_child(holder)
	var toggle: ReadyToggle = (load(TOGGLE_SCENE) as PackedScene).instantiate() as ReadyToggle
	holder.add_child(toggle)
	toggle.position = TOGGLE_AT
	toggle.ready_changed.connect(_on_toggle_ready_changed)
	toggle.pressed.connect(_on_toggle_pressed.bind(toggle))
	return toggle


func _free(node: Node) -> void:
	_root.remove_child(node)
	node.free()


func _clear_toggle_log() -> void:
	_ready_changes.clear()
	_presses = 0
	_take_backs.clear()


# Presses toggle by device: focus and Enter, focus and pad A, or a left click at its middle.
func _press(toggle: ReadyToggle, device: String) -> void:
	match device:
		"key":
			toggle.grab_focus()
			for is_down: bool in [true, false]:
				var key: InputEventKey = InputEventKey.new()
				key.physical_keycode = KEY_ENTER
				key.keycode = KEY_ENTER
				key.pressed = is_down
				_root.push_input(key, true)
		"pad":
			toggle.grab_focus()
			for is_down: bool in [true, false]:
				var button: InputEventJoypadButton = InputEventJoypadButton.new()
				button.device = 0
				button.button_index = JOY_BUTTON_A
				button.pressed = is_down
				_root.push_input(button, true)
		_:
			var point: Vector2 = toggle.get_global_rect().get_center()
			for is_down: bool in [true, false]:
				var click: InputEventMouseButton = InputEventMouseButton.new()
				click.position = point
				click.global_position = point
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = is_down
				_root.push_input(click, true)


# Tells the device adapters the family in use, as the addon does when a device is pressed.
func _set_family(device: String, index: int) -> void:
	var helper: Node = _root.get_node_or_null(HELPER_PATH)
	if helper != null:
		helper.emit_signal(&"device_changed", device, index)


func _on_toggle_ready_changed(is_ready: bool) -> void:
	_ready_changes.append(is_ready)


func _on_toggle_pressed(toggle: ReadyToggle) -> void:
	_presses += 1
	_take_backs.append(toggle.is_taking_back())
