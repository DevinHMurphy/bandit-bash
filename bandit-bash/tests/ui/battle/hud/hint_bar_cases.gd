# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hint_bar_cases.gd
# Author:
# Created:  November 6, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Control hints' cases for tests/ui/input/run_all.gd (combat UI plan, UI8 and UI9 rows; questions
## 24, 25, 31 and 32; UI11's unit detail): the [ControlHintBar] against
## [constant BattleController.LIVE_ACTIONS]; its layout from its exports, clear of the HUD's map
## area at the 1280×720 base size; a rebound key changing its label; two M1 battles walked by
## input through every hint context a solo battle (unit detail's DETAIL included)
## reaches, by the actions' keys, then again by their joypad bindings with the bar drawing the Xbox
## family, with a third walking the rune bar (RUNE_SLOTS, DISCARD_CONFIRM), the rune menu (RUNE)
## and Recall's second pick
## (PAIR_TARGET); and the hints left out while they can do nothing (one target, one weapon). Each
## rig has an [EventLog] long enough to scroll, so its scroll actions act wherever it shows, and
## the turn walk focuses it (EVENT_LOG), and a [HeirloomBar] with two of the army's heirlooms, which
## the turn walk focuses too (HEIRLOOM_BAR).[br]
## [b]The pad walk[/b] presses each action's first joypad event (a button, or an axis pushed and
## let back) where the key walk sends the action, through a [PadRepeat] on the controller; and in
## every context with a panel or the pause menu open it presses the d-pad every way, checking
## after each press that a control inside it still has focus.[br]
## [b]The walk[/b] checks, in each context: the bar shows exactly
## [method BattleController.get_live_actions], each with its key and label, on one unclipped line;
## every candidate action outside that list, pressed, changes nothing; every listed action acts:
## the ones that can be undone (arrows, Q / E, the toggles, fast-forward, weapon cycling) are
## pressed and undone there, and the rest (accept, cancel, End Turn, the skip) are the presses
## that move the walk on. At the end every listed action of every context reached must have acted.
## So the table is checked against what the controller and the screen's panels do, not against a
## second list kept here. [b]Candidates[/b] are project.godot's own actions and the ui_* actions
## the controller's input block names; Godot's other ui_* (Tab's focus moves, text editing) are
## GUI navigation the hints don't list. INACTIVE is not reached: a solo battle never settles with
## the seat waiting.[br]
## The harness is [code]turn_input_cases.gd[/code]'s, with the forecast panel, the hint bar, the
## save debug panel (F3) and the pause menu (Esc), the last two loaded at run time as their
## scripts name autoloads. The pause menu grabs focus a frame after opening; the walk gives Resume
## focus as that frame would. The Sidearm fixture (a stowed sword, free swaps) is
## [code]forecast_cases.gd[/code]'s, so the forecast has two weapons to cycle.

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/battle/input/turn_input_cases.gd")
const CombatWorld = preload("res://tests/combat/combat_world.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const RUNE_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/rune_menu.tscn")
const RUNE_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/rune_bar.tscn")
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://ui/battle/forecast/forecast_panel.tscn")
const HINT_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/control_hint_bar.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/battle/hud/battle_hud.tscn")
const PAD_REPEAT_SCENE: PackedScene = preload("res://ui/battle/input/pad_repeat.tscn")
const ADAPTER_SCENE: PackedScene = preload("res://ui/battle/input/input_device_adapter.tscn")
const DETAIL_SCENE: PackedScene = preload("res://ui/battle/unit/unit_detail_panel.tscn")
const EVENT_LOG_SCENE: PackedScene = preload("res://ui/battle/hud/event_log/event_log.tscn")

# Heirlooms the rigs' armies hold beyond the faction's own, so the heirloom bar has two icons
# to move between.
const HEIRLOOMS: PackedStringArray = ["war_ledger"]
const HEIRLOOM_BAR_SCENE: PackedScene = preload("res://ui/common/heirlooms/heirloom_bar.tscn")

# Lines the rig's event log starts with, so it can scroll in every context it shows in.
const LOG_FILLER_LINES: int = 60

# The Input Helper addon's autoload, which the pad walk's adapter listens to.
const HELPER_PATH: NodePath = ^"/root/InputHelper"

# The d-pad presses the pad walk makes in each open panel, checking focus after each.
const FOCUS_MOVES: Array[StringName] = [
	&"ui_down", &"ui_down", &"ui_right", &"ui_right", &"ui_up", &"ui_up", &"ui_left", &"ui_left",
]

# Loaded at run time: their scripts name autoloads (see the class doc).
const PAUSE_MENU_SCENE: String = "res://ui/common/pause_menu.tscn"
const SAVE_DEBUG_SCENE: String = "res://ui/debug/save_debug_panel.tscn"

# Any fixed seed; the other UI cases use the same one.
const SEED: int = 0x0C0FFEE

# Player phases the walk may wait through to find the attack it needs.
const MAX_PHASES: int = 6

# The screen size the bar is checked at: Godot's default window, the canvas_items base size.
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1280, 720)

# The ui_* actions the controller's input block names; project.godot's own come from its [input].
const BUILTIN_ACTIONS: Array[StringName] = [
	&"ui_accept", &"ui_cancel", &"ui_up", &"ui_down", &"ui_left", &"ui_right",
]

# Each action that a press of another undoes.
const OPPOSITE: Dictionary[StringName, StringName] = {
	&"ui_up": &"ui_down",
	&"ui_down": &"ui_up",
	&"ui_left": &"ui_right",
	&"ui_right": &"ui_left",
	&"target_next": &"target_prev",
	&"target_prev": &"target_next",
	&"event_log_scroll_up": &"event_log_scroll_down",
	&"event_log_scroll_down": &"event_log_scroll_up",
}

# Actions a second press undoes.
const TOGGLES: Array[StringName] = [
	&"toggle_danger_zone", &"toggle_save_debug", &"event_log_focus", &"heirloom_bar_focus",
]

# Actions with no pad binding: the pad walk can't press them, and the bar leaves them out on a pad.
const KEYBOARD_ONLY: Array[StringName] = [&"toggle_save_debug"]

# The contexts besides the stages' names (BattleController's state block).
const EXTRA_CONTEXTS: Array[StringName] = [&"FORECAST", &"PLAYBACK", &"PAUSED"]

const STOWED_ID: String = "test:stowed_sword"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ATTACK: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null

# The actions pressed in each context: see BUILTIN_ACTIONS.
var _candidates: Array[StringName] = []

# The contexts the walks reached, and each "CONTEXT/action" seen to act in its context.
var _reached: Dictionary[StringName, bool] = {}
var _acted: Dictionary[String, bool] = {}

# Whether the walk presses each action's joypad binding instead of sending the action.
var _pad: bool = false

# The pad walk's device adapter, set to the Xbox family; null in the key walk.
var _adapter: InputDeviceAdapter = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the harness is added and input is pushed.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call(_tag() + ": the M1 map definition loads", false, M1_DEFINITION)
		return
	_candidates = _input_actions()
	var window: Window = _root as Window
	var old_size: Vector2i = window.size
	window.size = BASE_SCREEN_SIZE
	_test_table()
	_test_layout()
	_test_hidden_hints()
	_test_swap_window()
	_test_turn()
	_test_rune_walk()
	_test_coverage()
	_start_pad_walk()
	_test_swap_window()
	_test_turn()
	_test_rune_walk()
	_test_coverage()
	_end_pad_walk()
	window.size = old_size


# The pad walk's setup: presses by joypad binding, a fresh coverage record, and an adapter the
# addon has told an Xbox pad is in use, which the walk's bars draw for.
func _start_pad_walk() -> void:
	_pad = true
	_reached.clear()
	_acted.clear()
	_adapter = ADAPTER_SCENE.instantiate()
	_root.add_child(_adapter)
	var helper: Node = _root.get_node_or_null(HELPER_PATH)
	if helper == null:
		_check.call("hints (pad): the Input Helper autoload is loaded", false)
		return
	helper.emit_signal(&"device_changed", "xbox", 0)
	_check.call("hints (pad): the walk's adapter reports the Xbox family", (
			_adapter.get_family() == InputDeviceAdapter.Family.XBOX
	), str(_adapter.get_family()))


# Back to keys and keyboard and mouse.
func _end_pad_walk() -> void:
	var helper: Node = _root.get_node_or_null(HELPER_PATH)
	if helper != null:
		helper.emit_signal(&"device_changed", "keyboard", -1)
	_adapter.free()
	_adapter = null
	_pad = false


# The checks' name prefix: which walk is running.
func _tag() -> String:
	return "hints (pad)" if _pad else "hints"


# The table itself: a row for every stage and nothing else; every action in it exists and has a
# label; every context label names a row's action; each key is the InputMap's first key event.
func _test_table() -> void:
	var problems: PackedStringArray = []
	var contexts: Array[StringName] = EXTRA_CONTEXTS.duplicate()
	for stage_name: String in BattleController.Stage.keys():
		contexts.append(StringName(stage_name))
	for context: StringName in contexts:
		if not BattleController.LIVE_ACTIONS.has(context):
			problems.append("no row for %s" % [context])
	var bar: ControlHintBar = HINT_BAR_SCENE.instantiate()
	for context: StringName in BattleController.LIVE_ACTIONS:
		if not contexts.has(context):
			problems.append("a row for %s, which is no context" % [context])
		for action: StringName in BattleController.LIVE_ACTIONS[context]:
			if not InputMap.has_action(action):
				problems.append("%s/%s is no InputMap action" % [context, action])
			if bar.label_for(context, action) == String(action):
				problems.append("%s/%s has no label" % [context, action])
	for key: String in bar.labels:
		var parts: PackedStringArray = key.split("/")
		if parts.size() == 1:
			if not InputMap.has_action(StringName(key)):
				problems.append("label %s is no InputMap action" % [key])
			continue
		var row: Array = BattleController.LIVE_ACTIONS.get(StringName(parts[0]), [])
		if not row.has(StringName(parts[1])):
			problems.append("label %s names no action of a row" % [key])
	bar.free()
	_check.call(_tag() + (
			": LIVE_ACTIONS has a row per context, each action exists and has a label"
	), (
			problems.is_empty()
	), "; ".join(problems))

	var wrong: PackedStringArray = []
	for action: StringName in _candidates:
		var expected: String = _first_key_name(action)
		var shown: String = ControlHintBar.key_name(action)
		if shown != ControlHintBar.SHORT_KEY_NAMES.get(expected, expected):
			wrong.append("%s: %s, InputMap %s" % [action, shown, expected])
	_check.call(_tag() + ": each key is named from the InputMap's first key event", (
			wrong.is_empty()
	), "; ".join(wrong))

	var unbound: BattleController = BattleController.new()
	_check.call(_tag() + ": an unbound controller has no context and no live actions", (
			unbound.get_hint_context().is_empty() and unbound.get_live_actions().is_empty()
	))
	unbound.free()


# At the base size the bar, at its exports, is the bottom strip beside the turn bar's column, clear
# of the HUD's map area; TOP moves it to the top edge; it stays hidden with no controller.
func _test_layout() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	_root.add_child(layer)
	var hud: BattleHud = HUD_SCENE.instantiate()
	layer.add_child(hud)
	var bar: ControlHintBar = HINT_BAR_SCENE.instantiate()
	layer.add_child(bar)
	var screen: Vector2 = Vector2(BASE_SCREEN_SIZE)
	var expected: Rect2 = Rect2(
			bar.left_margin,
			screen.y - bar.edge_margin - bar.height,
			screen.x - bar.left_margin - bar.right_margin,
			bar.height
	)
	var at: Rect2 = bar.get_global_rect()
	var map_area: Rect2 = hud.get_map_area().get_global_rect()
	_check.call(_tag() + ": at 1280×720 the bar is the strip its exports set, off the map area", (
			at.is_equal_approx(expected)
			and map_area.has_area()
			and not at.intersects(map_area)
	), "bar %s, expected %s, map area %s" % [at, expected, map_area])
	bar.edge = ControlHintBar.Edge.TOP
	at = bar.get_global_rect()
	_check.call(_tag() + ": edge TOP puts it edge_margin below the top", (
			is_equal_approx(at.position.y, bar.edge_margin)
			and is_equal_approx(at.size.y, bar.height)
	), str(at))
	bar.refresh()
	_check.call(_tag() + ": with no controller the bar stays hidden", not bar.visible)
	layer.free()


# The opening swap window, walked: SWAP and SWAP_PICKED, a swap's PLAYBACK with the pause menu
# over it and the skip, then Start from SWAP. Before the walk, a rebound key changes its label.
func _test_swap_window() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	if not _pad:
		_test_rebind(rig)
	_expect_context(rig, &"SWAP")
	var swapper: String = _swapper(h.session)
	if swapper.is_empty():
		_check.call(_tag() + ": the M1 swap window has a unit with a partner", false)
		rig.close()
		return
	h.controller.move_cursor(h.session.state.tile_of(swapper))
	_expect_acts(rig, &"ui_accept", &"SWAP_PICKED")
	_expect_context(rig, &"SWAP_PICKED")
	_expect_acts(rig, &"ui_cancel", &"SWAP")
	_expect_acts(rig, &"ui_cancel", &"PAUSED")
	_expect_acts(rig, &"ui_cancel", &"SWAP")
	_expect_acts(rig, &"ui_accept", &"SWAP_PICKED")
	var partners: Array[TurnInputModel.TargetOption] = TurnInputModel.swap_partners(
			h.session, swapper
	)
	h.controller.move_cursor(partners[0].tile)
	_expect_acts(rig, &"ui_accept", &"PLAYBACK")
	_expect_context(rig, &"PLAYBACK")
	_expect_acts(rig, &"ui_cancel", &"PAUSED")
	_expect_acts(rig, &"ui_cancel", &"PLAYBACK")
	_expect_acts(rig, &"skip_playback", &"PLAYBACK")
	BattleViewCases.settle(h.view)
	_expect_acts(rig, &"end_turn", &"")
	BattleViewCases.settle(h.view)
	_check.call(_tag() + ": Start from the swap window reaches the first player phase", (
			h.controller.get_hint_context() == &"IDLE"
	), str(h.controller.get_hint_context()))
	rig.close()


# end_turn rebound from its key to Y, and ui_cancel (a keycode binding) to Backspace: after a
# refresh each shows its new key, and its old key again once restored. Checked as text, so with
# the bar's glyphs off (Backspace has one).
func _test_rebind(rig: Rig) -> void:
	var bar: ControlHintBar = rig.bar
	var glyphs: ControlGlyphTable = bar.glyphs
	bar.glyphs = null
	var old_end_turn: Array[InputEvent] = InputMap.action_get_events(&"end_turn")
	var old_cancel: Array[InputEvent] = InputMap.action_get_events(&"ui_cancel")
	var before: String = _shown_text(rig)
	var end_key: String = ControlHintBar.key_name(&"end_turn")
	var cancel_key: String = ControlHintBar.key_name(&"ui_cancel")
	var y: InputEventKey = InputEventKey.new()
	y.physical_keycode = KEY_Y
	var backspace: InputEventKey = InputEventKey.new()
	backspace.keycode = KEY_BACKSPACE
	InputMap.action_erase_events(&"end_turn")
	InputMap.action_add_event(&"end_turn", y)
	InputMap.action_erase_events(&"ui_cancel")
	InputMap.action_add_event(&"ui_cancel", backspace)
	var rebound: String = _shown_text(rig)
	InputMap.action_erase_events(&"end_turn")
	for event: InputEvent in old_end_turn:
		InputMap.action_add_event(&"end_turn", event)
	InputMap.action_erase_events(&"ui_cancel")
	for event: InputEvent in old_cancel:
		InputMap.action_add_event(&"ui_cancel", event)
	var restored: String = _shown_text(rig)
	var start: String = bar.label_for(&"SWAP", &"end_turn")
	var pause: String = bar.label_for(&"SWAP", &"ui_cancel")
	_check.call(_tag() + ": a rebound key changes its label, and back", (
			before.contains("%s %s" % [end_key, start])
			and before.contains("%s %s" % [cancel_key, pause])
			and rebound.contains("Y %s" % [start])
			and rebound.contains("Backspace %s" % [pause])
			and not rebound.contains("%s %s" % [end_key, start])
			and restored == before
	), "before '%s', rebound '%s', restored '%s'" % [before, rebound, restored])
	bar.glyphs = glyphs
	bar.refresh()


# Hints that can do nothing are left out (question 31 (a)), and the bar redraws as soon as that
# changes, with no frame between: Q / E with one target in TARGET and CONFIRM, and in FORECAST C
# exactly while the target shown has more than one weapon, through every target Q / E reach.
func _test_hidden_hints() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	var swapper: String = _swapper(h.session)
	h.controller.move_cursor(h.session.state.tile_of(swapper))
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	var hakkapel: String = _unit_of_type(h.session, "Hakkapel")
	if not hakkapel.is_empty():
		_give_sidearm(h.session, hakkapel)
	var single: Array = []
	var several: Array = []
	# Both picks from the same phase: the board a pick was found on is gone after a wait.
	for _phase: int in MAX_PHASES:
		if h.session.is_finished:
			break
		single = []
		for unit_id: String in TurnInputModel.acting_units(h.session, 0):
			if single.is_empty():
				single = _find_attack_with(h.session, unit_id, 1)
		several = _find_attack(h.session, hakkapel, 2, 2)
		if not single.is_empty() and not several.is_empty():
			break
		_wait_phase(h)
	if single.is_empty() or several.is_empty():
		_check.call("hints: attacks with one target and with two (one with two weapons)", false, (
				"one target %s, two %s" % [single, several]
		))
		rig.close()
		return

	var shown: PackedStringArray = []
	var single_unit: String = single[0]
	var single_end: Vector2i = single[1]
	_open_attack(rig, single_unit, single_end)
	shown.append("TARGET %s" % [_hides_targets(rig)])
	_expect_acts(rig, &"ui_accept", &"")
	shown.append("%s %s" % [h.controller.get_hint_context(), _hides_targets(rig)])
	h.controller.step_back()
	h.controller.step_back()
	h.controller.step_back()
	h.controller.step_back()
	_check.call("hints: one target leaves Q / E out of TARGET and its forecast", (
			shown == PackedStringArray(["TARGET true", "FORECAST true"])
	), " | ".join(shown))

	var seen: PackedStringArray = []
	var several_unit: String = several[0]
	var several_end: Vector2i = several[1]
	_open_attack(rig, several_unit, several_end)
	_expect_acts(rig, &"ui_accept", &"FORECAST")
	var list: TargetList = h.controller.get_target_list()
	for _i: int in list.targets().size():
		var shows_c: bool = rig.bar.get_shown_actions().has(&"cycle_weapon")
		var lists_c: bool = h.controller.get_live_actions().has(&"cycle_weapon")
		seen.append("%d weapons, C shown %s, live %s" % [list.weapon_count(), shows_c, lists_c])
		h.controller.cycle_target(true)
	var wrong: PackedStringArray = []
	for line: String in seen:
		var many: bool = not line.begins_with("1 ")
		if line != "%s weapons, C shown %s, live %s" % [line.get_slice(" ", 0), many, many]:
			wrong.append(line)
	_check.call("hints: C shows in the forecast exactly while the target has two weapons", (
			wrong.is_empty() and seen.size() >= 2 and not rig.bar.get_shown_actions().is_empty()
	), " | ".join(seen))
	rig.close()


# Opens the attack of unit_id moving to end, up to its target picker.
func _open_attack(rig: Rig, unit_id: String, end: Vector2i) -> void:
	var h: TurnInputCases.Harness = rig.h
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.confirm_tile(end)
	BattleViewCases.arrive(h.view)
	_focus_action(rig, ATTACK)
	_expect_acts(rig, &"ui_accept", &"TARGET")


# Whether the bar, as drawn now with no refresh, leaves out both Q and E while the controller
# leaves them out too.
func _hides_targets(rig: Rig) -> bool:
	var shown: Array[StringName] = rig.bar.get_shown_actions()
	var live: Array[StringName] = rig.h.controller.get_live_actions()
	return (
			not shown.is_empty()
			and not shown.has(&"target_next") and not shown.has(&"target_prev")
			and not live.has(&"target_next") and not live.has(&"target_prev")
	)


# A player turn walked: Start from SWAP_PICKED; IDLE with the pause menu (PAUSED) and End Turn's
# question (END_CONFIRM); MOVE; WALK to another tile, with the pause menu over it, its menu and
# back; ACTION; TARGET; CONFIRM on the dialog; FORECAST, two weapons and two targets, whose Confirm
# attacks; then End Turn confirmed, and a second attack confirmed on the dialog.
func _test_turn() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	var swapper: String = _swapper(h.session)
	h.controller.move_cursor(h.session.state.tile_of(swapper))
	_expect_acts(rig, &"ui_accept", &"SWAP_PICKED")
	_expect_acts(rig, &"end_turn", &"")
	BattleViewCases.settle(h.view)

	var hakkapel: String = _unit_of_type(h.session, "Hakkapel")
	if not hakkapel.is_empty():
		_give_sidearm(h.session, hakkapel)
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find_attack(h.session, hakkapel, 2, 2)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty():
		_check.call(_tag() + ": a Hakkapel with Sidearm reaches two targets, one with both weapons", (
				false
		), "within %d phases" % [MAX_PHASES])
		rig.close()
		return
	var unit_id: String = pick[0]
	var end: Vector2i = pick[1]
	var target_id: String = pick[2]

	h.controller.move_cursor(h.session.state.tile_of(unit_id))
	_expect_context(rig, &"IDLE")
	_expect_acts(rig, &"ui_cancel", &"PAUSED")
	_expect_context(rig, &"PAUSED")
	_expect_acts(rig, &"ui_accept", &"IDLE")
	_expect_acts(rig, &"ui_cancel", &"PAUSED")
	_expect_acts(rig, &"ui_cancel", &"IDLE")
	_expect_acts(rig, &"end_turn", &"END_CONFIRM")
	_expect_context(rig, &"END_CONFIRM")
	_expect_acts(rig, &"ui_cancel", &"IDLE")
	# The event log: focused by event_log_focus, its header collapsing and opening it by accept,
	# closed by Back and by event_log_focus.
	_expect_acts(rig, &"event_log_focus", &"EVENT_LOG")
	_expect_context(rig, &"EVENT_LOG")
	_expect_acts(rig, &"ui_accept", &"EVENT_LOG")
	_expect_acts(rig, &"ui_accept", &"EVENT_LOG")
	_expect_acts(rig, &"ui_cancel", &"IDLE")
	_expect_acts(rig, &"event_log_focus", &"EVENT_LOG")
	_expect_acts(rig, &"event_log_focus", &"IDLE")
	# The heirloom bar: focused by heirloom_bar_focus, closed by Back and by heirloom_bar_focus.
	_expect_acts(rig, &"heirloom_bar_focus", &"HEIRLOOM_BAR")
	_expect_context(rig, &"HEIRLOOM_BAR")
	_expect_acts(rig, &"ui_cancel", &"IDLE")
	_expect_acts(rig, &"heirloom_bar_focus", &"HEIRLOOM_BAR")
	_expect_acts(rig, &"heirloom_bar_focus", &"IDLE")
	# Unit detail: opened by unit_detail on the unit, closed by Back, by unit_detail and by accept
	# on its Close.
	_expect_acts(rig, &"unit_detail", &"DETAIL")
	_expect_context(rig, &"DETAIL")
	_expect_acts(rig, &"ui_cancel", &"IDLE")
	_expect_acts(rig, &"unit_detail", &"DETAIL")
	_expect_acts(rig, &"unit_detail", &"IDLE")
	_expect_acts(rig, &"unit_detail", &"DETAIL")
	(h.host.top() as BattlePanel).focus_first()
	_expect_acts(rig, &"ui_accept", &"IDLE")
	_expect_acts(rig, &"ui_accept", &"MOVE")

	_expect_context(rig, &"MOVE")
	_expect_acts(rig, &"unit_detail", &"DETAIL")
	_expect_acts(rig, &"ui_cancel", &"MOVE")
	_expect_acts(rig, &"ui_cancel", &"IDLE")
	_expect_acts(rig, &"ui_accept", &"MOVE")
	_expect_acts(rig, &"end_turn", &"END_CONFIRM")
	_expect_acts(rig, &"ui_cancel", &"MOVE")
	# The attack's tile may be the unit's own, which opens the menu with no walk: WALK is walked
	# on another tile first, then back to MOVE from its menu.
	h.controller.move_cursor(_other_move_tile(h.session, unit_id))
	_expect_acts(rig, &"ui_accept", &"WALK")

	_expect_context(rig, &"WALK")
	_expect_acts(rig, &"ui_cancel", &"PAUSED")
	_expect_acts(rig, &"ui_cancel", &"WALK")
	BattleViewCases.arrive(h.view)
	_expect_context(rig, &"ACTION")
	_expect_acts(rig, &"ui_cancel", &"MOVE")
	h.controller.move_cursor(end)
	_expect_acts(rig, &"ui_accept", &"")
	BattleViewCases.arrive(h.view)

	_expect_context(rig, &"ACTION")
	_expect_acts(rig, &"ui_cancel", &"MOVE")
	_expect_acts(rig, &"ui_accept", &"")
	BattleViewCases.arrive(h.view)
	_focus_action(rig, ATTACK)
	_expect_acts(rig, &"ui_accept", &"TARGET")
	_current_target(rig, target_id)

	_expect_context(rig, &"TARGET")
	_expect_acts(rig, &"ui_cancel", &"ACTION")
	_focus_action(rig, ATTACK)
	_expect_acts(rig, &"ui_accept", &"TARGET")
	_current_target(rig, target_id)

	h.controller.forecast_panel_scene = null
	_expect_acts(rig, &"ui_accept", &"CONFIRM")
	_expect_context(rig, &"CONFIRM")
	_expect_acts(rig, &"ui_cancel", &"TARGET")
	h.controller.forecast_panel_scene = FORECAST_SCENE
	_expect_acts(rig, &"ui_accept", &"FORECAST")

	_expect_context(rig, &"FORECAST")
	_expect_acts(rig, &"ui_cancel", &"TARGET")
	_expect_acts(rig, &"ui_accept", &"FORECAST")
	(h.host.top() as BattlePanel).focus_first()
	_expect_acts(rig, &"ui_accept", &"PLAYBACK")
	BattleViewCases.settle(h.view)

	_end_turn_by_dialog(rig)
	_confirm_attack_on_dialog(rig)
	rig.close()


# A third battle, with seat 0 holding Aegis and Recall: the rune bar (RUNE_SLOTS) from MOVE, a
# rune's targets from it and back, closed by cancel and by open_runes; the unit menu's Rune
# (RUNE) and back, its Recall on the unit itself (PAIR_TARGET) and back, then its forecast, whose
# Confirm casts; then from IDLE the bar's discard question (DISCARD_CONFIRM) and back, confirmed.
func _test_rune_walk() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	var aegis_id: String = h.session.ids.next_rune_id("Aegis")
	var recall_id: String = h.session.ids.next_rune_id("Recall")
	CombatWorld.give_rune(h.session.engine, 0, aegis_id, "aegis")
	CombatWorld.give_rune(h.session.engine, 0, recall_id, "recall")
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	var acting: PackedStringArray = TurnInputModel.acting_units(h.session, 0)
	if acting.size() < 3:
		_check.call(_tag() + ": three units can act for Recall's walk", false, str(acting))
		rig.close()
		return
	h.controller.move_cursor(h.session.state.tile_of(acting[0]))
	_expect_acts(rig, &"ui_accept", &"MOVE")
	_expect_acts(rig, &"open_runes", &"RUNE_SLOTS")
	_expect_context(rig, &"RUNE_SLOTS")
	_expect_acts(rig, &"ui_accept", &"TARGET")
	_expect_acts(rig, &"ui_cancel", &"RUNE_SLOTS")
	_expect_acts(rig, &"ui_cancel", &"MOVE")
	_expect_acts(rig, &"open_runes", &"RUNE_SLOTS")
	_expect_acts(rig, &"open_runes", &"MOVE")
	_expect_acts(rig, &"ui_accept", &"ACTION")
	_focus_action(rig, TurnInputModel.ActionKind.RUNE)
	_expect_acts(rig, &"ui_accept", &"RUNE")
	_expect_context(rig, &"RUNE")
	_expect_acts(rig, &"ui_cancel", &"ACTION")
	_focus_action(rig, TurnInputModel.ActionKind.RUNE)
	_expect_acts(rig, &"ui_accept", &"RUNE")
	_focus_rune(rig, recall_id)
	_expect_acts(rig, &"ui_accept", &"PAIR_TARGET")
	_expect_context(rig, &"PAIR_TARGET")
	_expect_acts(rig, &"ui_cancel", &"RUNE")
	_focus_rune(rig, recall_id)
	_expect_acts(rig, &"ui_accept", &"PAIR_TARGET")
	_expect_acts(rig, &"ui_accept", &"FORECAST")
	_expect_context(rig, &"FORECAST")
	(h.host.top() as BattlePanel).focus_first()
	_expect_acts(rig, &"ui_accept", &"PLAYBACK")
	BattleViewCases.settle(h.view)

	_expect_acts(rig, &"open_runes", &"RUNE_SLOTS")
	_hold(&"ui_down", true)
	_hold(&"ui_down", false)
	_expect_acts(rig, &"ui_accept", &"DISCARD_CONFIRM")
	_expect_context(rig, &"DISCARD_CONFIRM")
	_expect_acts(rig, &"ui_cancel", &"RUNE_SLOTS")
	_hold(&"ui_down", true)
	_hold(&"ui_down", false)
	_expect_acts(rig, &"ui_accept", &"DISCARD_CONFIRM")
	(h.host.top() as BattlePanel).focus_first()
	_expect_acts(rig, &"ui_accept", &"PLAYBACK")
	BattleViewCases.settle(h.view)
	rig.close()


# Every listed action of every context the walks reached acted there; and every context but
# INACTIVE was reached.
func _test_coverage() -> void:
	var missing: PackedStringArray = []
	for context: StringName in _reached:
		for action: StringName in BattleController.LIVE_ACTIONS.get(context, []):
			if action == &"toggle_save_debug" and not OS.is_debug_build():
				continue
			if _pad and KEYBOARD_ONLY.has(action):
				continue
			if not _acted.has("%s/%s" % [context, action]):
				missing.append("%s/%s" % [context, action])
	_check.call(_tag() + ": every listed action acted in every context reached", (
			missing.is_empty()
	), "never acted: " + ", ".join(missing))
	var unreached: PackedStringArray = []
	for context: StringName in BattleController.LIVE_ACTIONS:
		if context != &"INACTIVE" and not _reached.has(context):
			unreached.append(context)
	_check.call(_tag() + ": the walks reached every context but INACTIVE", (
			unreached.is_empty()
	), ", ".join(unreached))


# In IDLE with units left to act: End Turn's question, then accept on it, and the next player
# phase.
func _end_turn_by_dialog(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	if h.session.is_finished:
		return
	if h.controller.get_stage() == BattleController.Stage.MOVE:
		_expect_acts(rig, &"ui_cancel", &"IDLE")
	if TurnInputModel.acting_units(h.session, 0).is_empty():
		_check.call(_tag() + ": a unit is left to act for End Turn's question", false)
		return
	_expect_acts(rig, &"end_turn", &"END_CONFIRM")
	(h.host.top() as BattlePanel).focus_first()
	_expect_acts(rig, &"ui_accept", &"PLAYBACK")
	BattleViewCases.settle(h.view)


# Any attack, from TARGET to the confirm dialog (no forecast scene), confirmed by accept.
func _confirm_attack_on_dialog(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		if h.session.is_finished:
			break
		for unit_id: String in TurnInputModel.acting_units(h.session, 0):
			pick = _find_attack(h.session, unit_id, 1, 1)
			if not pick.is_empty():
				break
		if not pick.is_empty():
			break
		_wait_phase(h)
	if pick.is_empty():
		_check.call(_tag() + ": a second attack for the confirm dialog", false)
		return
	var unit_id: String = pick[0]
	var end: Vector2i = pick[1]
	h.controller.forecast_panel_scene = null
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.confirm_tile(end)
	BattleViewCases.arrive(h.view)
	_focus_action(rig, ATTACK)
	_expect_acts(rig, &"ui_accept", &"TARGET")
	_expect_acts(rig, &"ui_accept", &"CONFIRM")
	(h.host.top() as BattlePanel).focus_first()
	_expect_acts(rig, &"ui_accept", &"PLAYBACK")
	h.controller.forecast_panel_scene = FORECAST_SCENE
	BattleViewCases.settle(h.view)


# --- The walk's checks -----------------------------------------------------------------------


# One context's checks (class doc): the bar against the controller, the actions outside its row
# inert, and the ones that can be undone acting and undone.
func _expect_context(rig: Rig, expected: StringName) -> void:
	_lay_out(rig)
	var c: BattleController = rig.h.controller
	var context: StringName = c.get_hint_context()
	_reached[context] = true
	var live: Array[StringName] = c.get_live_actions()
	# What the bar can show: the live actions with a binding in the walk's family.
	var shown_live: Array[StringName] = []
	for action: StringName in live:
		if not (_pad and KEYBOARD_ONLY.has(action)):
			shown_live.append(action)
	var problems: PackedStringArray = []
	if context != expected:
		problems.append("context %s" % [context])
	rig.bar.refresh()
	if not rig.bar.visible:
		problems.append("the bar is hidden")
	if rig.bar.get_shown_actions() != shown_live:
		problems.append("shows %s, live %s" % [rig.bar.get_shown_actions(), shown_live])
	problems.append_array(_text_problems(rig.bar, context, shown_live))
	_check.call(_tag() + " %s: the bar shows exactly the controller's live actions, keyed" % [
		expected,
	], problems.is_empty(), "; ".join(problems))
	if _pad and _focus_root(rig) != null:
		var lost: PackedStringArray = _focus_problems(rig)
		_check.call(_tag() + " %s: navigated by the d-pad, a control inside keeps focus" % [
			expected,
		], lost.is_empty(), "; ".join(lost))

	var acting: PackedStringArray = []
	for action: StringName in _candidates:
		if live.has(action) or (_pad and KEYBOARD_ONLY.has(action)):
			continue
		var before: String = _snapshot(rig)
		var after: PackedStringArray = _probe(rig, action)
		if after[0] != before or after[1] != before:
			acting.append("%s: %s -> %s" % [action, before, after[1]])
	_check.call(_tag() + " %s: no action outside its row acts" % [expected], acting.is_empty(), (
			" | ".join(acting)
	))

	var failed: PackedStringArray = []
	for action: StringName in shown_live:
		if not _is_undoable(action):
			continue
		var problem: String = _acts_and_undoes(rig, action)
		if problem.is_empty():
			_acted["%s/%s" % [context, action]] = true
		else:
			failed.append("%s: %s" % [action, problem])
	_check.call(_tag() + " %s: each listed action that can be undone acts, and is undone" % [
		expected,
	], failed.is_empty(), " | ".join(failed))


# What must keep focus now: the pause menu while the tree is paused, else the top panel; null
# with neither.
func _focus_root(rig: Rig) -> Control:
	if _root.get_tree().paused:
		return rig.pause.get_node(^"%Root") as Control
	return rig.h.host.top()


# Why focus left the open panel or pause menu as the d-pad moved it every way (FOCUS_MOVES), or
# didn't come back to it when a click elsewhere released it (PanelHost.keep_focus,
# keep_focus() on the pause menu), in the target picker on the current target's row; empty when
# it never left. Focus ends where it began, so the walk's target and row are as they were.
func _focus_problems(rig: Rig) -> PackedStringArray:
	var problems: PackedStringArray = []
	var holder: Control = _focus_root(rig)
	var viewport: Viewport = _root.get_viewport()
	var start: Control = viewport.gui_get_focus_owner()
	if start == null or not holder.is_ancestor_of(start):
		problems.append("no focus inside before moving: %s" % [start])
		return problems
	for move: StringName in FOCUS_MOVES:
		_hold(move, true)
		_hold(move, false)
		var focused: Control = viewport.gui_get_focus_owner()
		if focused == null or not holder.is_ancestor_of(focused):
			problems.append("%s left it for %s" % [move, focused])
			start.grab_focus()
	viewport.gui_release_focus()
	var restored: bool = false
	if _root.get_tree().paused:
		restored = rig.pause.call(&"keep_focus")
	else:
		restored = rig.h.host.keep_focus()
	var back: Control = viewport.gui_get_focus_owner()
	if not restored or back == null or not holder.is_ancestor_of(back):
		problems.append("a released focus didn't come back: %s" % [back])
	elif rig.h.host.top() is TargetPicker and not _root.get_tree().paused:
		var picker: TargetPicker = rig.h.host.top() as TargetPicker
		var current: Button = picker.get_rows()[rig.h.controller.get_target_list().current_index()]
		if back != current:
			problems.append("the picker's focus came back on %s, not the current target's %s" % [
				back.name, current.name,
			])
	start.grab_focus()
	return problems


# Presses action, which must act and leave the walk in expected (any, when empty).
func _expect_acts(rig: Rig, action: StringName, expected: StringName) -> void:
	var c: BattleController = rig.h.controller
	var context: StringName = c.get_hint_context()
	var before: String = _snapshot(rig)
	var after: PackedStringArray = _probe(rig, action)
	var acted: bool = after[0] != before or after[1] != before
	var now: StringName = c.get_hint_context()
	if now == &"PAUSED" and context != &"PAUSED":
		# What the pause menu's deferred grab_focus does a frame later.
		(rig.pause.get_node(^"%ResumeButton") as Button).grab_focus()
	var is_listed: bool = _live_in(context, action)
	if acted and is_listed:
		_acted["%s/%s" % [context, action]] = true
	_check.call(_tag() + " %s: %s is listed and acts%s" % [
		context, action, "" if expected.is_empty() else ", to %s" % [expected],
	], acted and is_listed and (expected.is_empty() or now == expected), (
			"listed %s, now %s; %s -> %s" % [is_listed, now, before, after[1]]
	))


# Presses action and undoes it (OPPOSITE, TOGGLES, the weapon count); empty when it acted and the
# snapshot came back, else why not. At an end (a map edge, the first row) the opposite goes first.
func _acts_and_undoes(rig: Rig, action: StringName) -> String:
	var before: String = _snapshot(rig)
	var after: PackedStringArray = _probe(rig, action)
	if action == &"fast_forward":
		if after[0] == before:
			return "holding it changed nothing"
		return "" if after[1] == before else "releasing it left %s" % [after[1]]
	if after[1] == before and OPPOSITE.has(action):
		_probe(rig, OPPOSITE[action])
		var turned: String = _snapshot(rig)
		if turned == before:
			return "neither it nor %s acts" % [OPPOSITE[action]]
		_probe(rig, action)
		var back: String = _snapshot(rig)
		return "" if back == before else "after %s, it left %s" % [OPPOSITE[action], back]
	if after[1] == before:
		return "it changed nothing"
	if OPPOSITE.has(action):
		_probe(rig, OPPOSITE[action])
	elif TOGGLES.has(action):
		_probe(rig, action)
	elif action == &"cycle_weapon":
		var list: TargetList = rig.h.controller.get_target_list()
		for _i: int in list.weapon_count() - 1:
			_probe(rig, action)
	var undone: String = _snapshot(rig)
	return "" if undone == before else "not undone: %s" % [undone]


func _is_undoable(action: StringName) -> bool:
	return (
			OPPOSITE.has(action)
			or TOGGLES.has(action)
			or action == &"fast_forward"
			or action == &"cycle_weapon"
	)


static func _live_in(context: StringName, action: StringName) -> bool:
	var row: Array = BattleController.LIVE_ACTIONS.get(context, [])
	return row.has(action)


# Why the bar's line isn't live's hints: a key, glyph or label missing, or the line clipped. A
# binding with a glyph in the bar's family must draw that glyph; one without, its text.
func _text_problems(
		bar: ControlHintBar, context: StringName, live: Array[StringName]
) -> PackedStringArray:
	var problems: PackedStringArray = []
	var text: String = bar.get_text()
	var markup: String = bar.get_markup()
	for action: StringName in live:
		var glyph: Texture2D = bar.glyph_of(action)
		var key: String = bar.key_text(action)
		if glyph != null and not markup.contains(glyph.resource_path):
			problems.append("no glyph %s for %s" % [glyph.resource_path, action])
		elif glyph == null and (key == ControlHintBar.UNBOUND_KEY or not text.contains(key)):
			problems.append("no key %s for %s" % [key, action])
		if not text.contains(bar.label_for(context, action)):
			problems.append("no label for %s" % [action])
	# The bar's width less its panel's margins: the container sizes the label only on its next
	# sort, a frame away, and the cases run inside one frame.
	var room: float = bar.size.x - bar.get_theme_stylebox(&"panel").get_minimum_size().x
	var width: int = bar.get_text_label().get_content_width()
	if room <= 0.0 or width > room:
		problems.append("clipped: %d of %d px ('%s')" % [width, room, text])
	return problems


# What a press can change, as one line: the hint context, the stage and selection, the cursor,
# the danger zone and toggled ranges, the unit the detail shows, the target and weapon, the panels
# and focus, playback speed and skip, pause, the save debug panel, and the commands sent.
func _snapshot(rig: Rig) -> String:
	var h: TurnInputCases.Harness = rig.h
	var c: BattleController = h.controller
	var list: TargetList = c.get_target_list()
	var focus: Control = _root.get_viewport().gui_get_focus_owner()
	var detail: UnitDetailPanel = c.get_detail_panel()
	var parts: PackedStringArray = [
		"detail scroll %s" % ["-" if detail == null else str(detail.get_scroll())],
		"detail unit %s" % ["-" if detail == null else detail.get_view().unit_id],
		"context %s" % [c.get_hint_context()],
		"stage %d" % [c.get_stage()],
		"cursor %s" % [c.get_cursor_tile()],
		"unit %s" % [c.get_selected_unit()],
		"enemies %s" % [c.get_shown_enemies()],
		"danger %s" % [c.is_danger_zone_shown()],
		"target %s" % ["-" if list == null else "%d/%d" % [
			list.current_index(), list.weapon_index(),
		]],
		"panels %d" % [h.host.depth()],
		"focus %s" % ["-" if focus == null else String(focus.get_path())],
		"fast %s" % [h.view.is_fast_forward()],
		"skip %s" % [h.view.is_skipping()],
		"paused %s" % [_root.get_tree().paused],
		"debug %s" % [is_instance_valid(rig.debug) and rig.debug.visible],
		"sent %d" % [h.batches.size()],
		"log %s" % ["-" if rig.log == null else "%d %s %s" % [
			rig.log.get_scroll(), rig.log.is_open(), rig.log.get_filter_row().get_shown_mask(),
		]],
	]
	return ", ".join(parts)


# Sorts every container of the widgets and the pause menu, parents first, as the frame's deferred
# sort would. The cases run inside one frame, and a panel opened in it is not laid out yet: its
# buttons overlap, so the arrows, which find focus neighbours by position in the forecast, the
# dialogs and the pause menu, find none. Twice, so a child's new size reaches its own children.
func _lay_out(rig: Rig) -> void:
	for _pass: int in 2:
		for top: Node in [rig.h.hud, rig.pause]:
			for node: Node in top.find_children("*", "Container", true, false):
				node.notification(Container.NOTIFICATION_SORT_CHILDREN)


# Holds action down, then lets go; the snapshots after each.
func _probe(rig: Rig, action: StringName) -> PackedStringArray:
	_hold(action, true)
	var down: String = _snapshot(rig)
	_hold(action, false)
	return [down, _snapshot(rig)]


# Sends action down or up: as the action itself in the key walk, as its first joypad event in the
# pad walk (a button pressed or let go, an axis pushed fully or let back to 0).
func _hold(action: StringName, is_down: bool) -> void:
	if not _pad:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)
		return
	var source: InputEvent = ControlHintBar.pad_event(action)
	var button: InputEventJoypadButton = source as InputEventJoypadButton
	var motion: InputEventJoypadMotion = source as InputEventJoypadMotion
	if button != null:
		var press: InputEventJoypadButton = InputEventJoypadButton.new()
		press.button_index = button.button_index
		press.pressed = is_down
		_root.get_viewport().push_input(press, true)
	elif motion != null:
		var push: InputEventJoypadMotion = InputEventJoypadMotion.new()
		push.axis = motion.axis
		push.axis_value = motion.axis_value if is_down else 0.0
		_root.get_viewport().push_input(push, true)
	else:
		_check.call("hints (pad): %s has a joypad binding" % [action], false)


# The bar's line, redrawn now.
func _shown_text(rig: Rig) -> String:
	rig.bar.refresh()
	return rig.bar.get_text()


# Focuses the open action menu's row for kind, from its first row, by ui_down.
func _focus_action(rig: Rig, kind: TurnInputModel.ActionKind) -> void:
	var menu: ActionMenu = rig.h.host.top() as ActionMenu
	if menu == null:
		return
	menu.focus_first()
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == kind:
			return
		_hold(&"ui_down", true)
		_hold(&"ui_down", false)


# Focuses the open rune menu's row for rune_id, from its first row, by ui_down.
func _focus_rune(rig: Rig, rune_id: String) -> void:
	var menu: RuneMenu = rig.h.host.top() as RuneMenu
	if menu == null:
		return
	menu.focus_first()
	for option: TurnInputModel.RuneOption in menu.get_options():
		if option.rune_id == rune_id:
			return
		_hold(&"ui_down", true)
		_hold(&"ui_down", false)


# Makes target_id the target list's current target by target_next.
func _current_target(rig: Rig, target_id: String) -> void:
	var list: TargetList = rig.h.controller.get_target_list()
	if list == null:
		return
	for _i: int in list.targets().size():
		if list.current().target_id == target_id:
			return
		rig.h.controller.cycle_target(true)


# --- Fixtures --------------------------------------------------------------------------------


# The M1 battle in its swap window, on turn_input_cases.gd's harness with the forecast panel, a
# hint bar, a hidden save debug panel and a pause menu.
func _rig() -> Rig:
	var rig: Rig = Rig.new()
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run, HEIRLOOMS)
	if h.battle == null:
		_check.call(_tag() + ": the M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	h.bar = TURN_BAR_SCENE.instantiate()
	h.swap = SWAP_WINDOW_SCENE.instantiate()
	h.host = PANEL_HOST_SCENE.instantiate()
	h.message = MESSAGE_SCENE.instantiate()
	var rune_bar: RuneBar = RUNE_BAR_SCENE.instantiate()
	for widget: Control in [h.bar, rune_bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.rune_bar = rune_bar
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.forecast_panel_scene = FORECAST_SCENE
	h.controller.unit_detail_scene = DETAIL_SCENE
	h.controller.rune_menu_scene = RUNE_MENU_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	var repeat: PadRepeat = PAD_REPEAT_SCENE.instantiate()
	h.controller.add_child(repeat)
	h.controller.pad_repeat = repeat
	rig.log = EVENT_LOG_SCENE.instantiate()
	h.hud.add_child(rig.log)
	h.controller.event_log = rig.log
	rig.heirlooms = HEIRLOOM_BAR_SCENE.instantiate()
	h.hud.add_child(rig.heirlooms)
	h.controller.heirloom_bar = rig.heirlooms
	_root.add_child(h.controller)
	rig.bar = HINT_BAR_SCENE.instantiate()
	rig.bar.controller = h.controller
	rig.bar.device = _adapter
	h.hud.add_child(rig.bar)
	rig.debug = (load(SAVE_DEBUG_SCENE) as PackedScene).instantiate()
	h.hud.add_child(rig.debug)
	rig.debug.visible = false
	rig.pause = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	_root.add_child(rig.pause)
	h.view.bind(h.session)
	rig.log.bind(h.session)
	rig.heirlooms.show_views(HeirloomViewModel.for_battle(h.run, h.session, 0, _catalog))
	for i: int in LOG_FILLER_LINES:
		var filler: EventLogWriter.Entry = EventLogWriter.Entry.new()
		filler.id = 1000000 + i
		filler.group = EventLogWriter.Group.EVENTS
		rig.log.add_entry(filler.add("Filler line %d" % [i]))
	h.controller.bind(h.battle, h.session, 0)
	h.session.batch_resolved.connect(h.record)
	rig.h = h
	return rig


# The first of seat 0's units with a swap partner; empty for none.
static func _swapper(session: CombatSession) -> String:
	for unit_id: String in session.state.units_of(PLAYER):
		if not TurnInputModel.swap_partners(session, unit_id).is_empty():
			return unit_id
	return ""


# [unit_id, end tile] for unit_id's attack with exactly targets targets; empty for none.
static func _find_attack_with(session: CombatSession, unit_id: String, targets: int) -> Array:
	if not TurnInputModel.can_act(session, unit_id):
		return []
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
		for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
				session, unit_id, path
		):
			if option.kind == ATTACK and option.targets.size() == targets:
				return [unit_id, tile]
	return []


# [unit_id, end tile, target id] for unit_id's attack with at least min_targets targets, from a
# target that has at least min_weapons weapons; empty for none.
static func _find_attack(
		session: CombatSession, unit_id: String, min_targets: int, min_weapons: int
) -> Array:
	if unit_id.is_empty() or not TurnInputModel.can_act(session, unit_id):
		return []
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
		for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
				session, unit_id, path
		):
			if option.kind != ATTACK or option.targets.size() < min_targets:
				continue
			for target: TurnInputModel.TargetOption in option.targets:
				if target.commands.size() >= min_weapons:
					return [unit_id, tile, target.target_id]
	return []


# The first of unit_id's move tiles that isn't its own, row-major; its own tile when it has none.
static func _other_move_tile(session: CombatSession, unit_id: String) -> Vector2i:
	var own: Vector2i = session.state.tile_of(unit_id)
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		if tile != own:
			return tile
	return own


# Every acting unit waits where it stands, then End Turn, sent straight to the encounter.
func _wait_phase(h: TurnInputCases.Harness) -> void:
	for unit_id: String in TurnInputModel.acting_units(h.session, 0):
		_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	if not h.session.is_finished:
		_send(h, EndTurnCommand.new(0))


func _send(h: TurnInputCases.Harness, command: Command) -> void:
	h.battle.submit(command, h.session.session_id)
	h.battle.resolve_queued()
	BattleViewCases.settle(h.view)


# The Sidearm fixture of forecast_cases.gd: a stowed sword and free weapon swaps for unit_id.
func _give_sidearm(session: CombatSession, unit_id: String) -> void:
	var sword: CombatState.WeaponStats = CombatState.WeaponStats.new()
	sword.id = STOWED_ID
	sword.label = "Stowed Sword"
	sword.weapon_type = "sword"
	sword.damage = 5
	sword.atk_x = 1
	sword.profile = WeaponTriangle.Profile.NIMBLE
	sword.range_min = 1
	sword.range_max = 1
	sword.hit = 80
	sword.crit_x = 3.0
	sword.weight = 8
	session.state.add_weapon(sword)
	session.state.unit(unit_id).stowed_weapon_id = STOWED_ID
	session.state.load_bases(session.engine, unit_id)
	var grant: SetPermission = SetPermission.new()
	grant.permission = CombatValue.Permission.FREE_WEAPON_SWAP
	grant.allow = true
	var definition: EffectDefinition = EffectDefinition.new()
	definition.id = "test_sidearm"
	definition.operations.append(grant)
	var state: CombatState = session.state
	var owner: EffectOwner = EffectOwner.for_unit(
			unit_id, state.seat_of(unit_id), state.side_of(unit_id)
	)
	session.engine.register(EffectInstance.new(
			"test:sidearm", definition, owner, Modifier.SourceKind.UNIT_TRAIT, "test:sidearm"
	))


static func _unit_of_type(session: CombatSession, label: String) -> String:
	for unit_id: String in session.state.units_of(PLAYER):
		if session.describe(unit_id).contains("(%s)" % [label]):
			return unit_id
	return ""


# project.godot's own actions and BUILTIN_ACTIONS (class doc).
static func _input_actions() -> Array[StringName]:
	var actions: Array[StringName] = BUILTIN_ACTIONS.duplicate()
	for property: Dictionary in ProjectSettings.get_property_list():
		var name: String = property["name"]
		if not name.begins_with("input/"):
			continue
		var action: String = name.trim_prefix("input/")
		if not action.begins_with("ui_"):
			actions.append(StringName(action))
	return actions


# The name of action's first key event, read here apart from ControlHintBar.key_name: headless,
# a physical key is named as itself.
static func _first_key_name(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key == null:
			continue
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code)
	return ControlHintBar.UNBOUND_KEY


## The walk's harness: turn_input_cases.gd's, with the bar, the save debug panel, the pause menu.
class Rig:
	extends RefCounted

	## The turn-input harness.
	var h: TurnInputCases.Harness = null
	## The hint bar, under the harness's widgets.
	var bar: ControlHintBar = null
	## The save debug panel, which F3 shows and hides.
	var debug: Control = null
	## The pause menu, which Esc opens and closes.
	var pause: Node = null
	## The heirloom bar, which HEIRLOOM_BAR focuses: the army's heirlooms.
	var heirlooms: HeirloomBar = null
	## The event log, which EVENT_LOG focuses and the scroll actions move.
	var log: EventLog = null

	## Frees the nodes, unpausing, and closes the run.
	func close() -> void:
		pause.free()
		pause = null
		h.controller.get_tree().paused = false
		h.close()
