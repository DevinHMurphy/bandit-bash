# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hint_bar_cases.gd
# Author:
# Created:  November 6, 2026
# Modified: November 6, 2026
# ==============================================================================

extends RefCounted
## Control hints' cases for tests/ui/run_all.gd (combat UI plan, UI8 row; question 24): the
## [ControlHintBar] against [constant BattleController.LIVE_ACTIONS]; its layout from its exports,
## clear of the HUD's map area at the 1152×648 base size; a rebound key changing its label; and
## two M1 battles walked by input through every hint context a solo battle reaches.[br]
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

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://scenes/ui/battle/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://scenes/ui/battle/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/battle/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://scenes/ui/battle/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://scenes/ui/battle/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://scenes/ui/battle/forecast_panel.tscn")
const HINT_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/control_hint_bar.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_hud.tscn")

# Loaded at run time: their scripts name autoloads (see the class doc).
const PAUSE_MENU_SCENE: String = "res://scenes/ui/pause_menu.tscn"
const SAVE_DEBUG_SCENE: String = "res://scenes/debug/save_debug_panel.tscn"

# Any fixed seed; the other UI cases use the same one.
const SEED: int = 0x0C0FFEE

# Player phases the walk may wait through to find the attack it needs.
const MAX_PHASES: int = 6

# The screen size the bar is checked at: Godot's default window, the canvas_items base size.
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1152, 648)

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
}

# Actions a second press undoes.
const TOGGLES: Array[StringName] = [&"toggle_danger_zone", &"toggle_save_debug"]

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
		_check.call("hints: the M1 map definition loads", false, M1_DEFINITION)
		return
	_candidates = _input_actions()
	var window: Window = _root as Window
	var old_size: Vector2i = window.size
	window.size = BASE_SCREEN_SIZE
	_test_table()
	_test_layout()
	_test_swap_window()
	_test_turn()
	_test_coverage()
	window.size = old_size


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
	_check.call("hints: LIVE_ACTIONS has a row per context, each action exists and has a label", (
			problems.is_empty()
	), "; ".join(problems))

	var wrong: PackedStringArray = []
	for action: StringName in _candidates:
		var expected: String = _first_key_name(action)
		var shown: String = ControlHintBar.key_name(action)
		if shown != ControlHintBar.SHORT_KEY_NAMES.get(expected, expected):
			wrong.append("%s: %s, InputMap %s" % [action, shown, expected])
	_check.call("hints: each key is named from the InputMap's first key event", (
			wrong.is_empty()
	), "; ".join(wrong))

	var unbound: BattleController = BattleController.new()
	_check.call("hints: an unbound controller has no context and no live actions", (
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
	_check.call("hints: at 1152×648 the bar is the strip its exports set, off the map area", (
			at.is_equal_approx(expected)
			and map_area.has_area()
			and not at.intersects(map_area)
	), "bar %s, expected %s, map area %s" % [at, expected, map_area])
	bar.edge = ControlHintBar.Edge.TOP
	at = bar.get_global_rect()
	_check.call("hints: edge TOP puts it edge_margin below the top", (
			is_equal_approx(at.position.y, bar.edge_margin)
			and is_equal_approx(at.size.y, bar.height)
	), str(at))
	bar.refresh()
	_check.call("hints: with no controller the bar stays hidden", not bar.visible)
	layer.free()


# The opening swap window, walked: SWAP and SWAP_PICKED, a swap's PLAYBACK with the pause menu
# over it and the skip, then Start from SWAP. Before the walk, a rebound key changes its label.
func _test_swap_window() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	_test_rebind(rig)
	_expect_context(rig, &"SWAP")
	var swapper: String = _swapper(h.session)
	if swapper.is_empty():
		_check.call("hints: the M1 swap window has a unit with a partner", false)
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
	_check.call("hints: Start from the swap window reaches the first player phase", (
			h.controller.get_hint_context() == &"IDLE"
	), str(h.controller.get_hint_context()))
	rig.close()


# end_turn rebound from its key to Y, and ui_cancel (a keycode binding) to Backspace: after a
# refresh each shows its new key, and its old key again once restored.
func _test_rebind(rig: Rig) -> void:
	var bar: ControlHintBar = rig.bar
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
	_check.call("hints: a rebound key changes its label, and back", (
			before.contains("%s %s" % [end_key, start])
			and before.contains("%s %s" % [cancel_key, pause])
			and rebound.contains("Y %s" % [start])
			and rebound.contains("Backspace %s" % [pause])
			and not rebound.contains("%s %s" % [end_key, start])
			and restored == before
	), "before '%s', rebound '%s', restored '%s'" % [before, rebound, restored])


# A player turn walked: Start from SWAP_PICKED; IDLE with the pause menu (PAUSED) and End Turn's
# question (END_CONFIRM); MOVE; ACTION; TARGET; CONFIRM on the dialog; FORECAST, two weapons and
# two targets, whose Confirm attacks; then End Turn confirmed, and a second attack confirmed on the
# dialog.
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
		_check.call("hints: a Hakkapel with Sidearm reaches two targets, one with both weapons", (
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
	_expect_acts(rig, &"ui_accept", &"MOVE")

	_expect_context(rig, &"MOVE")
	_expect_acts(rig, &"ui_cancel", &"IDLE")
	_expect_acts(rig, &"ui_accept", &"MOVE")
	_expect_acts(rig, &"end_turn", &"END_CONFIRM")
	_expect_acts(rig, &"ui_cancel", &"MOVE")
	h.controller.move_cursor(end)
	_expect_acts(rig, &"ui_accept", &"ACTION")

	_expect_context(rig, &"ACTION")
	_expect_acts(rig, &"ui_cancel", &"MOVE")
	_expect_acts(rig, &"ui_accept", &"ACTION")
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


# Every listed action of every context the walks reached acted there; and every context but
# INACTIVE was reached.
func _test_coverage() -> void:
	var missing: PackedStringArray = []
	for context: StringName in _reached:
		for action: StringName in BattleController.LIVE_ACTIONS.get(context, []):
			if action == &"toggle_save_debug" and not OS.is_debug_build():
				continue
			if not _acted.has("%s/%s" % [context, action]):
				missing.append("%s/%s" % [context, action])
	_check.call("hints: every listed action acted in every context reached", (
			missing.is_empty()
	), "never acted: " + ", ".join(missing))
	var unreached: PackedStringArray = []
	for context: StringName in BattleController.LIVE_ACTIONS:
		if context != &"INACTIVE" and not _reached.has(context):
			unreached.append(context)
	_check.call("hints: the walks reached every context but INACTIVE", (
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
		_check.call("hints: a unit is left to act for End Turn's question", false)
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
		_check.call("hints: a second attack for the confirm dialog", false)
		return
	var unit_id: String = pick[0]
	var end: Vector2i = pick[1]
	h.controller.forecast_panel_scene = null
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.confirm_tile(end)
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
	var problems: PackedStringArray = []
	if context != expected:
		problems.append("context %s" % [context])
	rig.bar.refresh()
	if not rig.bar.visible:
		problems.append("the bar is hidden")
	if rig.bar.get_shown_actions() != live:
		problems.append("shows %s, live %s" % [rig.bar.get_shown_actions(), live])
	problems.append_array(_text_problems(rig.bar, context, live))
	_check.call("hints %s: the bar shows exactly the controller's live actions, keyed" % [
		expected,
	], problems.is_empty(), "; ".join(problems))

	var acting: PackedStringArray = []
	for action: StringName in _candidates:
		if live.has(action):
			continue
		var before: String = _snapshot(rig)
		var after: PackedStringArray = _probe(rig, action)
		if after[0] != before or after[1] != before:
			acting.append("%s: %s -> %s" % [action, before, after[1]])
	_check.call("hints %s: no action outside its row acts" % [expected], acting.is_empty(), (
			" | ".join(acting)
	))

	var failed: PackedStringArray = []
	for action: StringName in live:
		if not _is_undoable(action):
			continue
		var problem: String = _acts_and_undoes(rig, action)
		if problem.is_empty():
			_acted["%s/%s" % [context, action]] = true
		else:
			failed.append("%s: %s" % [action, problem])
	_check.call("hints %s: each listed action that can be undone acts, and is undone" % [
		expected,
	], failed.is_empty(), " | ".join(failed))


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
	_check.call("hints %s: %s is listed and acts%s" % [
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


# Why the bar's line isn't live's hints: a key or label missing, or the line clipped.
func _text_problems(
		bar: ControlHintBar, context: StringName, live: Array[StringName]
) -> PackedStringArray:
	var problems: PackedStringArray = []
	var text: String = bar.get_text()
	for action: StringName in live:
		var key: String = ControlHintBar.key_name(action)
		if not text.contains(key):
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
# the danger zone and toggled ranges, the target and weapon, the panels and focus, playback speed
# and skip, pause, the save debug panel, and the commands sent.
func _snapshot(rig: Rig) -> String:
	var h: TurnInputCases.Harness = rig.h
	var c: BattleController = h.controller
	var list: TargetList = c.get_target_list()
	var focus: Control = _root.get_viewport().gui_get_focus_owner()
	var parts: PackedStringArray = [
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


func _hold(action: StringName, is_down: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = is_down
	_root.get_viewport().push_input(event, true)


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
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("hints: the M1 battle begins", false, "begin_battle gave no battle")
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
	for widget: Control in [h.bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.forecast_panel_scene = FORECAST_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	_root.add_child(h.controller)
	rig.bar = HINT_BAR_SCENE.instantiate()
	rig.bar.controller = h.controller
	h.hud.add_child(rig.bar)
	rig.debug = (load(SAVE_DEBUG_SCENE) as PackedScene).instantiate()
	h.hud.add_child(rig.debug)
	rig.debug.visible = false
	rig.pause = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	_root.add_child(rig.pause)
	h.view.bind(h.session)
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

	## Frees the nodes, unpausing, and closes the run.
	func close() -> void:
		pause.free()
		pause = null
		h.controller.get_tree().paused = false
		h.close()
