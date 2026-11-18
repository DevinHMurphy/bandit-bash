# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 7, 2026
# Modified: November 18, 2026
# ==============================================================================

extends "res://tests/ui/ui_suite.gd"
## Combat UI input suite (combat UI plan, P07): turn input, targeting, rune casting (each rune by
## keys, mouse and pad, from the rune bar; discards), the control hints and pads (joypad bindings,
## the device adapter, glyphs,
## focus navigation, the cursor's repeat, hints that hide when they can do nothing), unit detail
## (opened and closed by keys, mouse and pad), a cases
## file each in [code]tests/ui/battle/[/code] (preloaded below;
## each one's class doc lists its checks); then the gameplay screen's pause menu, opened by Esc and
## closed by Esc or Resume, pausing the tree and the board's playback and unpausing both, with the
## hint bar following over real frames. The shared helpers are [code]tests/ui/ui_suite.gd[/code]'s.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/input/run_all.gd[/code].
## Prints one PASS, FAIL or SKIP line per check and
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure.[br]
## The cases run from the first frame, when autoloads exist; the pause case over real frames while
## the board plays. It needs a test user folder (see the base).

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Input, targeting, runes, hints, pads, unit detail, pause menu"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/battle/input/turn_input_cases.gd")
const TargetingCases = preload("res://tests/ui/battle/input/targeting_cases.gd")
const RuneCases = preload("res://tests/ui/battle/input/rune_cases.gd")
const RuneBarCases = preload("res://tests/ui/battle/input/rune_bar_cases.gd")
const HintBarCases = preload("res://tests/ui/battle/hud/hint_bar_cases.gd")
const PadCases = preload("res://tests/ui/battle/input/pad_cases.gd")
const UnitDetailCases = preload("res://tests/ui/battle/unit/unit_detail_cases.gd")

# How long the pause case holds the menu open, checking the board doesn't move meanwhile.
const PAUSE_HOLD_MSEC: int = 300

# How long the pause case waits for the board to settle once the menu closes.
const PAUSE_SETTLE_TIMEOUT_MSEC: int = 10000

var _frame: int = 0
var _is_pause_started: bool = false
var _is_pause_done: bool = false


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_start("Combat UI tests: input")
		GroupClock.lap("turn_input_cases")
		TurnInputCases.new(_check, root).run()
		GroupClock.lap("targeting_cases")
		TargetingCases.new(_check, root).run()
		GroupClock.lap("rune_cases")
		RuneCases.new(_check, root).run()
		GroupClock.lap("rune_bar_cases")
		RuneBarCases.new(_check, root).run()
		GroupClock.lap("hint_bar_cases")
		HintBarCases.new(_check, root).run()
		GroupClock.lap("pad_cases")
		PadCases.new(_check, root).run()
		GroupClock.lap("unit_detail_cases")
		UnitDetailCases.new(_check, root).run()
		return false
	if not _is_pause_started:
		_is_pause_started = true
		if not _has_test_user_dir():
			_skip("pause", "the gameplay screen needs a test user folder (see the base)")
			_finish()
			return false
		# A coroutine over frames of its own; it sets _is_pause_done as it ends.
		GroupClock.lap("pause case")
		_run_pause_case()
		return false
	if not _is_pause_done:
		return false
	_finish()
	_is_pause_done = false
	return false


# A new solo run's gameplay screen past the swap window's Start; twice, a unit's walk starts to
# play, Esc opens the pause menu, which pauses the tree and holds the walk; closed by Esc the first
# time and by a click on Resume the second, the tree is unpaused and the walk plays to its end.
# A coroutine over real frames, since the board plays only in its own _process; it sets
# _is_pause_done as it ends.
func _run_pause_case() -> void:
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var screen: Node = null
	if err == OK and run != null:
		_enter_first_node()
		screen = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
		root.add_child(screen)
	var view: BattleView = null if screen == null else screen.call(&"get_view")
	var session: CombatSession = null if view == null else view.get_session()
	if session == null:
		_check("pause: a new solo run's battle opens", false, error_string(err))
	else:
		var controller: BattleController = screen.call(&"get_controller")
		if controller.swap_window.visible:
			controller.swap_window.get_start_button().pressed.emit()
			BattleViewCases.settle(view)
		var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
		var pause: Node = screen.get_node(^"PauseMenu")
		var hints: ControlHintBar = screen.get_node(^"%ControlHintBar")
		for round: int in mini(units.size(), 2):
			await _pause_round(
					run.encounter, session, view, pause, hints, units[round], round == 1
			)
	if screen != null:
		screen.free()
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	# A failed round may leave the menu open, and the tree paused, for the routing case.
	paused = false
	_is_pause_done = true


# One round of the pause case for unit_id: its walk to its farthest move tile starts, Esc opens the
# menu, the walk holds while the tree is paused, then Esc (or a click on Resume, when by_resume)
# closes it and the walk plays to its end. The hint bar, redrawn only by its own frames, shows
# PLAYBACK, then PAUSED, then PLAYBACK again.
func _pause_round(
		encounter: CombatEncounter,
		session: CombatSession,
		view: BattleView,
		pause: Node,
		hints: ControlHintBar,
		unit_id: String,
		by_resume: bool
) -> void:
	var how: String = "Resume" if by_resume else "Esc"
	var origin: Vector2i = session.state.tile_of(unit_id)
	var goal: Vector2i = origin
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		if session.state.grid.distance(tile, origin) > session.state.grid.distance(goal, origin):
			goal = tile
	var walk: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, goal)
	encounter.submit(
			UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", walk),
			session.session_id
	)
	encounter.resolve_queued()
	await process_frame
	var token: UnitToken = view.token_of(unit_id)
	var playing: bool = not view.is_settled() and token != null
	# process_frame comes before the nodes' own _process, so the bar draws a frame later.
	await process_frame
	var hinted: Array[StringName] = [hints.get_context()]
	_press_key(KEY_ESCAPE)
	await process_frame
	var menu: Control = pause.get_node(^"%Root")
	var opened: bool = paused and menu.visible
	hinted.append(hints.get_context())
	var paused_actions: Array[StringName] = hints.get_shown_actions()
	var paused_live: Array[StringName] = hints.controller.get_live_actions()
	var held_at: Vector2 = token.position if token != null else Vector2.ZERO
	var hold_start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - hold_start < PAUSE_HOLD_MSEC:
		await process_frame
	var held: bool = (
			token != null and token.position == held_at and not view.is_settled() and paused
	)
	_check("pause (%s round): Esc opens the menu, pausing the tree, and the walk holds" % [how], (
			playing and opened and held
	), "playing %s, paused %s, menu %s, held %s" % [playing, paused, menu.visible, held])

	if by_resume:
		var resume: Button = pause.get_node(^"%ResumeButton")
		_click(resume.get_global_rect().get_center())
	else:
		_press_key(KEY_ESCAPE)
	await process_frame
	var closed: bool = not paused and not menu.visible
	hinted.append(hints.get_context())
	_check("pause (%s round): over real frames the hint bar shows playback, paused, playback" % [
		how,
	], (
			hinted == [&"PLAYBACK", &"PAUSED", &"PLAYBACK"]
			and hints.visible
			and not paused_actions.is_empty()
			and paused_actions == paused_live
	), "contexts %s; paused shows %s, live %s" % [hinted, paused_actions, paused_live])
	var settle_start: int = Time.get_ticks_msec()
	while not view.is_settled():
		if Time.get_ticks_msec() - settle_start > PAUSE_SETTLE_TIMEOUT_MSEC:
			break
		await process_frame
	var arrived: bool = (
			token != null
			and view.is_settled()
			and token.position.is_equal_approx(view.tile_to_position(goal))
	)
	_check("pause (%s round): %s closes it, unpausing the tree, and the walk plays on" % [
		how, how,
	], closed and arrived, "paused %s, menu %s, settled %s, token %s, goal %s" % [
		paused, menu.visible, view.is_settled(),
		token.position if token != null else Vector2.ZERO, view.tile_to_position(goal),
	])

