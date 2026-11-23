# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seat_wait_overlay_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Wait overlay cases for tests/net/run_all.gd ([SeatWaitOverlay]), on a relay off the network,
## which hosts as solo does: it shows at the first wait, a line per dropped seat with its time,
## Save & Quit for the host and no Remove; Enter, pad A and a click press its button and a click
## elsewhere stops on it; the host's Remove shows once a seat has waited the full wait, for the
## seat waited for longest, reached and pressed by keyboard, pad and mouse; focus comes back from
## the screen beneath but not from a layer above; it hides when nobody is waited for, focus back
## where it was; a client that lost the host sees it reconnecting with Leave Match and no Remove.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")

# The pause menu's layer, above the overlay's.
const MENU_LAYER: int = 10

var _presses: int = 0


func run() -> void:
	var relay: NetRelayScript = NetRelayScript.new()
	relay.name = &"OverlayRelay"
	_root.add_child(relay)
	var beneath: Button = Button.new()
	beneath.set_anchors_preset(Control.PRESET_FULL_RECT)
	var beneath_presses: Array[int] = [0]
	beneath.pressed.connect(func() -> void: beneath_presses[0] += 1)
	_root.add_child(beneath)

	beneath.grab_focus()
	relay._seat_changed(1, SeatDirectory.State.DROPPED, 75.0)
	var overlay: SeatWaitOverlay = _overlay_of(relay)
	if overlay == null:
		_check("overlay: the first wait shows it", false)
		_free(relay, beneath)
		return
	overlay.refresh()
	var leave: Button = overlay.get_node(^"%LeaveButton")
	var remove: Button = overlay.get_node(^"%RemoveButton")
	_check("overlay: the first wait shows it, the seat's line and the host's Save & Quit", (
			overlay.visible
			and _text(overlay, ^"%Title") == "Waiting for players"
			and _text(overlay, ^"%Lines") == "Waiting for Player 2 · 1:15"
			and leave.text == "Save & Quit"
			and not remove.visible
			and leave.has_focus()
			and overlay.layer < MENU_LAYER
	), _text(overlay, ^"%Lines"))
	relay._seat_changed(2, SeatDirectory.State.DROPPED, 5.0)
	overlay.refresh()
	_check("overlay: one line per dropped seat, in seat order", (
			_text(overlay, ^"%Lines")
					== "Waiting for Player 2 · 1:15\nWaiting for Player 3 · 0:05"
	), _text(overlay, ^"%Lines"))

	# The button's own handler leaves the screen; these cases count presses instead.
	leave.pressed.disconnect(overlay._on_leave_button_pressed)
	leave.pressed.connect(_on_pressed)
	_press_key(KEY_ENTER)
	var by_key: int = _presses
	_press_pad(JOY_BUTTON_A)
	var by_pad: int = _presses
	_check("overlay: Enter and pad A press the focused button", (
			by_key == 1 and by_pad == 2
	), "%d, %d" % [by_key, by_pad])

	overlay.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	var target: Vector2 = leave.get_global_rect().get_center()
	_click(target)
	var by_click: int = _presses
	_click(Vector2(2.0, 2.0))
	_check("overlay: a click presses the button; one elsewhere stops on the overlay", (
			by_click == 3 and _presses == 3 and beneath_presses[0] == 0
	), "%d presses at %s, beneath %d" % [_presses, target, beneath_presses[0]])
	_test_remove(relay, overlay)

	beneath.grab_focus()
	overlay.refresh()
	var regained: bool = leave.has_focus()
	var menu: CanvasLayer = CanvasLayer.new()
	menu.layer = MENU_LAYER
	var menu_button: Button = Button.new()
	menu.add_child(menu_button)
	_root.add_child(menu)
	menu_button.grab_focus()
	overlay.refresh()
	_check("overlay: focus comes back from the screen beneath, never from a menu above", (
			regained and menu_button.has_focus()
	))
	menu.free()

	relay._seat_changed(1, SeatDirectory.State.CONNECTED, 80.0)
	relay._seat_changed(2, SeatDirectory.State.CONNECTED, 10.0)
	overlay.refresh()
	_check("overlay: it hides once nobody is waited for, focus back where it was", (
			not overlay.visible and beneath.has_focus()
	))

	var directory: SeatDirectory = SeatDirectory.new()
	directory.add_seat(0, 76561198000000301, 1)
	relay.seats = directory
	relay._on_multiplayer_server_disconnected()
	overlay.refresh()
	_check("overlay: a client that lost the host sees it reconnecting, with Leave Match", (
			overlay.visible
			and _text(overlay, ^"%Title") == "Connection lost"
			and _text(overlay, ^"%Lines") == "Reconnecting to Player 1 · 0:00"
			and leave.text == "Leave Match"
			and not remove.visible
	), _text(overlay, ^"%Lines"))
	_free(relay, beneath)


# Seats 1 (75 s) and 2 (5 s) are waited for. Remove shows once one has waited the full wait, for the
# seat waited for longest, and is reached by keyboard and pad and pressed by a click; the removal
# itself runs in the harness (forfeit_network_cases.gd), which has a run.
func _test_remove(relay: NetRelayScript, overlay: SeatWaitOverlay) -> void:
	var leave: Button = overlay.get_node(^"%LeaveButton")
	var remove: Button = overlay.get_node(^"%RemoveButton")
	var short_of_wait: float = NetRelayScript.REMOVE_WAIT - relay.waited(1) - 1.0
	relay._process(short_of_wait)
	overlay.refresh()
	var hidden_before: bool = not remove.visible
	relay._process(1.0)
	overlay.refresh()
	_check("overlay: Remove shows once a seat has waited the full wait, for that seat", (
			hidden_before and remove.visible and remove.text == "Remove Player 2"
	), "%s, %s" % [hidden_before, remove.text])
	relay._process(NetRelayScript.REMOVE_WAIT)
	overlay.refresh()
	_check("overlay: with two seats past the wait, Remove is for the one waited for longest", (
			remove.text == "Remove Player 2"
	), remove.text)

	remove.pressed.disconnect(overlay._on_remove_button_pressed)
	remove.pressed.connect(_on_pressed)
	var before: int = _presses
	# Laid out first: focus finds its neighbour by position.
	overlay.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	leave.grab_focus()
	_press_key(KEY_RIGHT)
	var by_key: bool = remove.has_focus()
	_press_pad(JOY_BUTTON_A)
	_press_pad(JOY_BUTTON_DPAD_LEFT)
	var back_by_pad: bool = leave.has_focus()
	_press_pad(JOY_BUTTON_DPAD_RIGHT)
	var by_pad: bool = remove.has_focus()
	_click(remove.get_global_rect().get_center())
	_check("overlay: Remove is reached by arrows and the d-pad, pressed by pad A and a click", (
			by_key and back_by_pad and by_pad and _presses == before + 2
	), "key %s, pad back %s, pad %s, %d presses" % [by_key, back_by_pad, by_pad, _presses - before])
	remove.pressed.disconnect(_on_pressed)
	remove.pressed.connect(overlay._on_remove_button_pressed)
	leave.grab_focus()


func _on_pressed() -> void:
	_presses += 1


func _overlay_of(relay: NetRelayScript) -> SeatWaitOverlay:
	for child: Node in relay.get_children():
		if child is SeatWaitOverlay:
			return child as SeatWaitOverlay
	return null


func _text(overlay: SeatWaitOverlay, path: NodePath) -> String:
	return (overlay.get_node(path) as Label).text


func _free(relay: NetRelayScript, beneath: Button) -> void:
	relay.free()
	beneath.free()


# A press and release of key.
func _press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = is_down
		_root.push_input(event, true)


# A press and release of joypad button.
func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = is_down
		_root.push_input(event, true)


# A left click at position, in the root's coordinates.
func _click(position: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	_root.push_input(motion, true)
	for is_down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = is_down
		_root.push_input(event, true)
