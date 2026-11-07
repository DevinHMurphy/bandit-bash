# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pad_cases.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

extends RefCounted
## Pads' cases for tests/ui/input/run_all.gd (combat UI plan, UI9 row; questions 25 and 32): every
## action the hints list has a joypad binding; the [InputDeviceAdapter] switching family on a key,
## then a pad button, then a mouse move, through the Input Helper addon; the addon's device names
## mapped to families; the [ControlHintBar] drawing each family's glyph or label for every listed
## action and redrawing on a switch; and the [PadRepeat]'s one step on a press, its repeat while a
## stick is held, and none once it is let go. hint_bar_cases.gd walks every context by pad.[br]
## [b]The addon[/b] waits a second of drawn frames between two device changes, and a headless run
## draws none, so before each event the cases move the addon's last change far into the past (its
## public [code]device_last_changed_at[/code]), as a second of play would. Headless runs have no
## real pads, whose names Godot reports as empty, so a pad event names the other-pad family; the
## Xbox and PlayStation families are reached by the addon's own signal with their names.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")

const ADAPTER_SCENE: PackedScene = preload("res://scenes/ui/battle/input_device_adapter.tscn")
const HINT_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/control_hint_bar.tscn")
const PAD_REPEAT_SCENE: PackedScene = preload("res://scenes/ui/battle/pad_repeat.tscn")

# The Input Helper addon's autoload.
const HELPER_PATH: NodePath = ^"/root/InputHelper"

# Far enough back that the addon's one-second wait has passed.
const LONG_AGO: int = -1000000

# A mouse move past the addon's threshold (100 px² of motion), and one under it.
const BIG_MOVE: Vector2 = Vector2(30.0, 0.0)
const SMALL_MOVE: Vector2 = Vector2(3.0, 0.0)

const KEYBOARD: InputDeviceAdapter.Family = InputDeviceAdapter.Family.KEYBOARD_MOUSE
const XBOX: InputDeviceAdapter.Family = InputDeviceAdapter.Family.XBOX
const PLAYSTATION: InputDeviceAdapter.Family = InputDeviceAdapter.Family.PLAYSTATION
const OTHER_PAD: InputDeviceAdapter.Family = InputDeviceAdapter.Family.OTHER_PAD

var _check: Callable
var _root: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where nodes are added and input is pushed.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root


## Runs every case.
func run() -> void:
	var helper: Node = _root.get_node_or_null(HELPER_PATH)
	_check.call("pads: the Input Helper addon's autoload is loaded", helper != null)
	if helper == null:
		return
	_test_bindings()
	_test_family_names()
	_test_switching(helper)
	_test_glyphs(helper)
	_test_repeat()
	helper.emit_signal(&"device_changed", "keyboard", -1)


# Every action LIVE_ACTIONS lists has a joypad binding, and no pad input is bound to two of them.
func _test_bindings() -> void:
	var actions: Dictionary[StringName, bool] = {}
	for context: StringName in BattleController.LIVE_ACTIONS:
		for action: StringName in BattleController.LIVE_ACTIONS[context]:
			actions[action] = true
	var unbound: PackedStringArray = []
	var owner_of: Dictionary[String, StringName] = {}
	var shared: PackedStringArray = []
	for action: StringName in actions:
		if ControlHintBar.pad_event(action) == null:
			unbound.append(action)
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
				continue
			var id: String = ControlGlyphTable.input_id(event)
			if owner_of.has(id) and owner_of[id] != action:
				shared.append("%s: %s and %s" % [id, owner_of[id], action])
			owner_of[id] = action
	_check.call("pads: every listed action has a joypad binding, none shares a pad input", (
			unbound.is_empty() and shared.is_empty()
	), "unbound %s; shared %s" % [unbound, shared])


# The addon's device names, simplified and granular, map to their families.
func _test_family_names() -> void:
	var names: Dictionary[String, InputDeviceAdapter.Family] = {
		"keyboard": KEYBOARD,
		"xbox": XBOX,
		"xbox_series": XBOX,
		"playstation": PLAYSTATION,
		"playstation5": PLAYSTATION,
		"switch": OTHER_PAD,
		"steamdeck": OTHER_PAD,
		"generic": OTHER_PAD,
	}
	var wrong: PackedStringArray = []
	for device: String in names:
		if InputDeviceAdapter.family_of(device) != names[device]:
			wrong.append("%s -> %s" % [device, InputDeviceAdapter.family_of(device)])
	_check.call("pads: the addon's device names map to their families", wrong.is_empty(), (
			", ".join(wrong)
	))


# Through the addon: a pad button switches to a pad family, a key back to keyboard and mouse, a
# pad button to a pad again, a small mouse move to nothing, a large one back. One signal each.
func _test_switching(helper: Node) -> void:
	var adapter: InputDeviceAdapter = ADAPTER_SCENE.instantiate()
	_root.add_child(adapter)
	var changes: Array[InputDeviceAdapter.Family] = []
	var on_changed: Callable = func(family: InputDeviceAdapter.Family) -> void:
		changes.append(family)
	adapter.family_changed.connect(on_changed)
	var start: InputDeviceAdapter.Family = adapter.get_family()
	_push(helper, _button(JOY_BUTTON_GUIDE))
	_push(helper, _key(KEY_F12))
	_push(helper, _button(JOY_BUTTON_LEFT_STICK))
	_push(helper, _mouse(SMALL_MOVE))
	var after_small: InputDeviceAdapter.Family = adapter.get_family()
	_push(helper, _mouse(BIG_MOVE))
	adapter.family_changed.disconnect(on_changed)
	var expected: Array[InputDeviceAdapter.Family] = [OTHER_PAD, KEYBOARD, OTHER_PAD, KEYBOARD]
	_check.call("pads: the adapter switches on a pad button, a key, a pad button, a mouse move", (
			adapter.has_helper()
			and start == KEYBOARD
			and changes == expected
			and after_small == OTHER_PAD
			and adapter.get_family() == KEYBOARD
	), "start %s, changes %s, after a small move %s" % [start, changes, after_small])
	adapter.free()


# The bar in IDLE draws every listed action as its family's glyph or label, never unbound; on a
# switch it redraws at once (no frame between): Q's keyboard glyph, the Xbox Y and RT label, the
# PlayStation triangle and R2, the other pad's Y.
func _test_glyphs(helper: Node) -> void:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	var adapter: InputDeviceAdapter = ADAPTER_SCENE.instantiate()
	_root.add_child(adapter)
	var bar: ControlHintBar = HINT_BAR_SCENE.instantiate()
	bar.device = adapter
	_root.add_child(bar)
	var problems: PackedStringArray = []
	var drawn: Dictionary[String, String] = {}
	var families: Dictionary[String, InputDeviceAdapter.Family] = {
		"keyboard": KEYBOARD, "xbox": XBOX, "playstation": PLAYSTATION, "generic": OTHER_PAD,
	}
	for device: String in families:
		helper.emit_signal(&"device_changed", device, -1 if device == "keyboard" else 0)
		if adapter.get_family() != families[device]:
			problems.append("%s: family %s" % [device, adapter.get_family()])
		for context: StringName in BattleController.LIVE_ACTIONS:
			for action: StringName in BattleController.LIVE_ACTIONS[context]:
				var markup: String = bar.key_markup(action)
				if bar.key_text(action) == ControlHintBar.UNBOUND_KEY:
					problems.append("%s %s unbound" % [device, action])
				drawn["%s/%s" % [device, action]] = markup
	var expected: Dictionary[String, String] = {
		"keyboard/target_prev": "[img height=%d]res://assets/sprites/controls/keyboard/q.png[/img]",
		"keyboard/end_turn": "T",
		"xbox/end_turn": "[img height=%d]res://assets/sprites/controls/xbox_controller/y.png[/img]",
		"xbox/fast_forward": "RT",
		"playstation/end_turn": (
				"[img height=%d]res://assets/sprites/controls/ps_controller/triangle.png[/img]"
		),
		"playstation/fast_forward": "R2",
		"generic/end_turn": "Y",
	}
	for key: String in expected:
		var want: String = expected[key]
		if want.contains("%d"):
			want = want % [bar.glyph_height]
		if drawn.get(key, "") != want:
			problems.append("%s: '%s', expected '%s'" % [key, drawn.get(key, ""), want])
	_check.call("glyphs: each family draws every listed action's glyph or label", (
			problems.is_empty()
	), "; ".join(problems))

	var redraws: PackedStringArray = []
	var rig_ok: bool = _bar_on_battle(h, bar)
	if rig_ok:
		for device: String in ["xbox", "keyboard", "playstation"]:
			helper.emit_signal(&"device_changed", device, -1 if device == "keyboard" else 0)
			redraws.append(bar.get_markup())
	var y_path: String = "xbox_controller/y.png"
	_check.call("glyphs: the bar redraws on a family switch, with no frame between", (
			rig_ok
			and redraws.size() == 3
			and redraws[0].contains(y_path)
			and not redraws[1].contains(y_path)
			and redraws[1].contains("T[/color]")
			and redraws[2].contains("ps_controller/triangle.png")
	), " | ".join(redraws))
	bar.free()
	adapter.free()
	if h.controller != null:
		h.close()
	helper.emit_signal(&"device_changed", "keyboard", -1)


# A stick pushed up steps once at once, again after first_delay, then every repeat_interval; let
# back inside its deadzone it stops; the d-pad's button does the same; keys are left alone.
func _test_repeat() -> void:
	var repeat: PadRepeat = PAD_REPEAT_SCENE.instantiate()
	_root.add_child(repeat)
	var steps: Array[Vector2i] = []
	var on_stepped: Callable = func(direction: Vector2i) -> void:
		steps.append(direction)
	repeat.stepped.connect(on_stepped)
	var took_push: bool = repeat.take(_axis(JOY_AXIS_LEFT_Y, -1.0))
	var at_press: int = steps.size()
	repeat.take(_axis(JOY_AXIS_LEFT_Y, -0.9))
	var after_jitter: int = steps.size()
	repeat.advance(repeat.first_delay * 0.5)
	var before_delay: int = steps.size()
	repeat.advance(repeat.first_delay * 0.5 + 0.001)
	var at_delay: int = steps.size()
	repeat.advance(repeat.repeat_interval)
	repeat.advance(repeat.repeat_interval)
	var repeating: int = steps.size()
	repeat.take(_axis(JOY_AXIS_LEFT_Y, 0.1))
	repeat.advance(1.0)
	var released: int = steps.size()
	var took_key: bool = repeat.take(_key(KEY_UP))
	var down: InputEventJoypadButton = _button(JOY_BUTTON_DPAD_DOWN)
	repeat.take(down)
	var dpad_step: Vector2i = steps[steps.size() - 1]
	var up: InputEventJoypadButton = _button(JOY_BUTTON_DPAD_DOWN)
	up.pressed = false
	repeat.take(up)
	repeat.advance(1.0)
	repeat.stepped.disconnect(on_stepped)
	var all_up: bool = steps.slice(0, released).all(
			func(direction: Vector2i) -> bool: return direction == Vector2i.UP
	)
	_check.call("repeat: a stick push steps at once, repeats after the delay, stops on release", (
			took_push
			and at_press == 1
			and after_jitter == 1
			and before_delay == 1
			and at_delay == 2
			and repeating == 4
			and released == 4
			and all_up
	), "steps at press %d, jitter %d, half delay %d, delay %d, repeating %d, released %d" % [
		at_press, after_jitter, before_delay, at_delay, repeating, released,
	])
	_check.call("repeat: the d-pad steps too, and keys are left to their own echo", (
			not took_key and dpad_step == Vector2i.DOWN and steps.size() == released + 1
			and repeat.get_held().is_empty()
	), "key taken %s, d-pad step %s, steps %d" % [took_key, dpad_step, steps.size()])
	repeat.free()


# --- Fixtures --------------------------------------------------------------------------------


# Binds bar to an M1 battle in its swap window on turn_input_cases.gd's harness; false when the
# battle can't begin.
func _bar_on_battle(h: TurnInputCases.Harness, bar: ControlHintBar) -> bool:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var map: CombatMapDefinition = load("res://maps/standard/m1_greybox.tres")
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, 0x0C0FFEE, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(catalog, map, h.run)
	if h.battle == null:
		h.run.close()
		return false
	h.session = h.battle.get_session(0)
	h.view = (load("res://scenes/ui/battle/battle_view.tscn") as PackedScene).instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	h.host = (load("res://scenes/ui/battle/panel_host.tscn") as PackedScene).instantiate()
	h.hud.add_child(h.host)
	h.controller = BattleController.new()
	h.controller.view = h.view
	h.controller.panel_host = h.host
	_root.add_child(h.controller)
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	bar.controller = h.controller
	bar.refresh()
	return bar.visible


# Pushes event into the root viewport with the addon's wait between changes already passed.
func _push(helper: Node, event: InputEvent) -> void:
	helper.set(&"device_last_changed_at", LONG_AGO)
	_root.get_viewport().push_input(event, true)


static func _button(index: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


static func _key(key: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	return event


static func _mouse(relative: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(100.0, 100.0)
	return event
