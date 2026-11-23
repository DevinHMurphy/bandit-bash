# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fast_forward_press_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/ui/battle/board/key_moment_cases.gd"
## What counts as a fast_forward press for the ui/board suite ([BattleController], BUG-049), on
## [code]key_moment_cases.gd[/code]'s keep boards: a held input that a player unit's defeat let go
## stays let go until it is released and pressed again, whatever it keeps sending. The trigger
## (RT, axis 5) held past halfway through the stop keeps sending motion events, which turn
## nothing back on; dropping under the deadzone and pushing past it again does. The key (F) and a
## pad button, bound to the action only for that case and unbound after, the same, solo; the
## trigger the same on a co-op map whose teammate holds throughout.

# The trigger's values: past the action's deadzone (0.5) and still past it, a held trigger's
# stream; under it, a let-go one.
const TRIGGER_FULL: float = 1.0
const TRIGGER_HELD: Array[float] = [0.95, 0.8, 0.9, 0.7, 1.0]
const TRIGGER_UNDER: float = 0.3
const TRIGGER_RELEASED: float = 0.0

# A pad button nothing in project.godot binds, bound to fast_forward for the button case only.
const CASE_BUTTON: JoyButton = JOY_BUTTON_MISC1


## Runs every case.
func run() -> void:
	_keep = load(KEEP_PATH) as CombatMapDefinition
	if _catalog == null or _keep == null:
		_check.call("fast-forward press: the catalog and the Powder Keep load", false, KEEP_PATH)
		return
	_test_trigger_solo()
	_test_deadzone()
	_test_key_solo()
	_test_button_solo()
	_test_trigger_coop()


# RT held through a player unit's defeat: its later motion events leave the hold let go; under
# the deadzone and past it again is a new press.
func _test_trigger_solo() -> void:
	var board: Board = _solo_board("trigger")
	if board == null:
		return
	var press: Callable = _trigger.bind(board, TRIGGER_FULL)
	var stream: Callable = _trigger_stream.bind(board)
	var release: Callable = _trigger.bind(board, TRIGGER_RELEASED)
	_check_held_through_stop(board, "the trigger, solo", press, stream, release)
	_free(board)


# A push that never passes the deadzone is no press; one that drops under it lets go.
func _test_deadzone() -> void:
	var board: Board = _solo_board("deadzone")
	if board == null:
		return
	_trigger(board, TRIGGER_UNDER)
	var under: bool = board.view.is_fast_forward()
	_trigger(board, TRIGGER_FULL)
	var past: bool = board.view.is_fast_forward()
	_trigger(board, TRIGGER_UNDER)
	var dropped: bool = board.view.is_fast_forward()
	_check.call("fast-forward press: the trigger counts past its deadzone, under it is let go", (
			not under and past and not dropped
	), "under %s, past %s, dropped %s" % [under, past, dropped])
	_free(board)


# F held through the stop: its key echo turns nothing back on; release and press does.
func _test_key_solo() -> void:
	var board: Board = _solo_board("key")
	if board == null:
		return
	var press: Callable = _key.bind(board, true, false)
	var stream: Callable = _key.bind(board, true, true)
	var release: Callable = _key.bind(board, false, false)
	_check_held_through_stop(board, "the key, solo", press, stream, release)
	_free(board)


# A pad button bound to the action for this case: as the key.
func _test_button_solo() -> void:
	var binding: InputEventJoypadButton = InputEventJoypadButton.new()
	binding.button_index = CASE_BUTTON
	binding.device = -1
	InputMap.action_add_event(&"fast_forward", binding)
	var board: Board = _solo_board("button")
	if board != null:
		var press: Callable = _button.bind(board, true)
		# A held button sends nothing until it is released.
		var stream: Callable = func() -> void: pass
		var release: Callable = _button.bind(board, false)
		_check_held_through_stop(board, "a pad button, solo", press, stream, release)
		_free(board)
	InputMap.action_erase_event(&"fast_forward", binding)


# Seat 0 on map 0, which holds a seat-1 visitor, the teammate holding there throughout: RT held
# through the stop stays let go, and a release and press is fast again with the teammate.
func _test_trigger_coop() -> void:
	var relay: Node = _root.get_node_or_null(^"/root/NetRelay")
	if relay == null:
		_check.call("fast-forward press: the co-op case has the NetRelay autoload", false)
		return
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	var request: CampaignSession.BattleRequest = _request([0, 1])
	request.armies[0] = _army(run, 2, 1)
	request.armies[1] = _army(run, 1, -1)
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		_check.call("fast-forward press: the co-op battle begins", false)
		run.close()
		return
	var board: Board = _board(run, battle, battle.session_of_seat(0), 0, "co-op trigger")
	if board == null:
		return
	var map_id: int = board.session.session_id
	# Read off the relay as the controller reads it, since a preload of the autoload's script
	# fails a parse check run without autoloads.
	var kind: int = BattleController._relay_notice_kind(relay, &"FAST_FORWARD")
	if kind < 0:
		_check.call("fast-forward press: the relay has a FAST_FORWARD notice kind", false)
		_free(board)
		return
	relay.emit_signal(&"notice_received", 1, kind, [map_id, true])
	var press: Callable = _trigger.bind(board, TRIGGER_FULL)
	var stream: Callable = _trigger_stream.bind(board)
	var release: Callable = _trigger.bind(board, TRIGGER_RELEASED)
	_check_held_through_stop(board, "the trigger, co-op", press, stream, release)
	relay.emit_signal(&"notice_received", 1, kind, [map_id, false])
	_free(board)


# Presses, plays a player unit's defeat (a key moment) while held, then sends stream, releases
# and presses again, checking the board's speed at each step under label.
func _check_held_through_stop(
		board: Board, label: String, press: Callable, stream: Callable, release: Callable
) -> void:
	press.call()
	var pressed: bool = board.view.is_fast_forward()
	var death: Array[CombatFact] = [_fact(DEFEATED, board.player, board.grunt)]
	board.session.playback.enqueue(death)
	var settled: bool = _settle(board.view)
	var stopped: bool = not board.view.is_fast_forward()
	stream.call()
	var held_on: bool = board.view.is_fast_forward()
	release.call()
	var released: bool = board.view.is_fast_forward()
	press.call()
	var pressed_again: bool = board.view.is_fast_forward()
	_check.call("fast-forward press (%s): held through a stop it stays let go" % [label], (
			pressed and settled and stopped and not held_on
	), "pressed %s, settled %s, stopped %s, fast while still held %s" % [
		pressed, settled, stopped, held_on,
	])
	_check.call("fast-forward press (%s): a release and a new press is fast again" % [label], (
			not released and pressed_again
	), "fast after release %s, after the press %s" % [released, pressed_again])
	release.call()


# RT at value, as the pad reports it.
func _trigger(board: Board, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	board.controller._unhandled_input(event)


# A held trigger's stream of motion events, every one past the deadzone.
func _trigger_stream(board: Board) -> void:
	for value: float in TRIGGER_HELD:
		_trigger(board, value)


# F pressed or released; is_echo for the key's repeat while held.
func _key(board: Board, is_pressed: bool, is_echo: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.device = InputEvent.DEVICE_ID_KEYBOARD
	event.physical_keycode = KEY_F
	event.pressed = is_pressed
	event.echo = is_echo
	board.controller._unhandled_input(event)


func _button(board: Board, is_pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = 0
	event.button_index = CASE_BUTTON
	event.pressed = is_pressed
	board.controller._unhandled_input(event)
