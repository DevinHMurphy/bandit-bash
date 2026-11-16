# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 7, 2026
# Modified: November 16, 2026
# ==============================================================================

extends "res://tests/ui/ui_suite.gd"
## Combat UI board suite (combat UI plan, P07): the board, enemy information and the unit info
## layer, a cases file each in [code]tests/ui/battle/[/code] (preloaded below; each one's class
## doc lists its checks); then the gameplay screen itself: a run saved mid-battle and continued
## opens on the board at its saved state; a new solo run's first battle played to its end, the
## control hints showing PLAYBACK through its final playback until the end banner, its Victory or
## Defeat banner, and the route to Results. The shared helpers are
## [code]tests/ui/ui_suite.gd[/code]'s.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/board/run_all.gd[/code].
## Prints one PASS, FAIL or SKIP line per check and
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure.[br]
## The cases run from the first frame, when autoloads exist; the routing case over a few more for
## the scene change. The continue and routing cases need a test user folder (see the base).

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const IntentCases = preload("res://tests/ui/battle/intents/intent_cases.gd")
const UnitInfoCases = preload("res://tests/ui/battle/unit/unit_info_cases.gd")

# SceneRouter.Screen.RESULTS: this script can't name the autoload (see the base's class doc).
const SCREEN_RESULTS: int = 4

# Player phases the routing case presses End Turn for before giving up.
const MAX_PHASES: int = 60

# Frames left for the scene change to Results before the last checks.
const ROUTE_FRAMES: int = 3

# The routing case's end banner time (the screen's end_banner_time): long enough to be seen on
# a frame of its own, short enough not to slow the suite.
const ROUTE_BANNER_TIME: float = 0.2

# How long the routing case waits for the route to Results after the banner shows.
const ROUTE_TIMEOUT_MSEC: int = 5000

var _frame: int = 0
var _route_frame: int = -1
var _routed_frame: int = -1

# The routing case's screen and run, held while its end banner shows, and when the banner showed.
var _route_screen: Node = null
var _route_run: CampaignSession = null
var _route_started_msec: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_start("Combat UI tests: board")
		BattleViewCases.new(_check, root).run()
		IntentCases.new(_check, root).run()
		UnitInfoCases.new(_check, root).run()
		_run_continue_case()
		if _start_route_case():
			_route_frame = _frame
			return false
		_finish()
		return false
	if _route_frame < 0:
		return false
	if _routed_frame < 0:
		if not _poll_route():
			return false
		_routed_frame = _frame
		return false
	if _frame < _routed_frame + ROUTE_FRAMES:
		return false
	_finish_route_case()
	_finish()
	return false


# A new solo run's gameplay screen past Start, one unit's move and Wait, Save & Quit's checkpoint
# and a quit; then Continue and the gameplay screen again: it opens the battle on the board at its
# saved state (CampaignService.resume_battle), not the placeholder, ready for input.
func _run_continue_case() -> void:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  continue: the gameplay screen needs a test user folder (see the class doc)")
		return
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	saves.call(&"start_new_solo_run", RUN_SEED)
	_enter_first_node()
	var screen: Node = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	root.add_child(screen)
	var view: BattleView = screen.call(&"get_view")
	var session: CombatSession = view.get_session()
	var run: CampaignSession = service.get(&"session")
	if session == null or run == null:
		_check("continue: a new solo run's battle opens", false)
		screen.free()
		_end_continue_case()
		return
	var controller: BattleController = screen.call(&"get_controller")
	if controller.swap_window.visible:
		controller.swap_window.get_start_button().pressed.emit()
		BattleViewCases.settle(view)
	var unit_id: String = TurnInputModel.acting_units(session, 0)[0]
	var goal: Vector2i = TurnInputModel.move_tiles(session, unit_id)[0]
	var walk: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, goal)
	run.encounter.submit(
			UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", walk),
			session.session_id
	)
	run.encounter.resolve_queued()
	BattleViewCases.settle(view)
	var saved: Error = saves.call(&"save_checkpoint")
	var saved_hash: int = session.state_hash()
	var saved_tile: Vector2i = session.state.tile_of(unit_id)
	var saved_turn: int = session.state.turn
	screen.free()
	saves.call(&"close_save_file")

	saves.call(&"open_save_file", SAVE_NUMBER)
	saves.call(&"continue_solo_run")
	var point: int = saves.get(&"resume_point")
	screen = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	root.add_child(screen)
	view = screen.call(&"get_view")
	controller = screen.call(&"get_controller")
	var again: CombatSession = view.get_session()
	var placeholder: Control = screen.get_node(^"%CoopPlaceholder")
	var sorted_ids: PackedStringArray = [] if again == null else again.state.unit_ids()
	sorted_ids.sort()
	_check("continue: a run saved mid-battle opens on the board at its saved state", (
			saved == OK
			and point == CombatData.ResumePoint.BATTLE
			and again != null
			and not placeholder.visible
			and again.state_hash() == saved_hash
			and again.state.turn == saved_turn
			and again.state.tile_of(unit_id) == saved_tile
			and again.state.unit(unit_id).has_acted
			and view.token_ids() == sorted_ids
			and view.mismatches().is_empty()
	), "saved %s, point %d, placeholder %s; %s" % [
		error_string(saved), point, placeholder.visible,
		"no battle" if again == null else str(view.mismatches()),
	])
	_check("continue: the resumed battle takes input, with its intents shown", (
			again != null
			and controller.is_accepting_input()
			and not controller.swap_window.visible
			and again.intents != null
			and not TurnInputModel.can_act(again, unit_id)
	))
	screen.free()
	_end_continue_case()


func _end_continue_case() -> void:
	var saves: Node = root.get_node(^"SaveService")
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# A new solo run enters the gameplay screen, which begins its first battle; the swap window's Start
# and the turn bar's End Turn (confirming its question) play it until it ends, and the screen ends
# it, shows its end banner and, after end_banner_time, routes to Results. Returns true once the
# banner shows, so _poll_route() waits for the route and the remaining checks a few frames more.
func _start_route_case() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  screen: routing to Results needs a test user folder (see the class doc)")
		return false
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var router: Node = root.get_node(^"SceneRouter")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"start_new_solo_run", RUN_SEED)
	_check("screen: a new solo run starts", err == OK, error_string(err))
	var run: CampaignSession = service.get(&"session")
	if run == null:
		return false
	_enter_first_node()

	var scene: PackedScene = load(GAMEPLAY_SCENE)
	var screen: Node = scene.instantiate()
	screen.set(&"end_banner_time", ROUTE_BANNER_TIME)
	root.add_child(screen)
	var view: BattleView = screen.call(&"get_view")
	var controller: BattleController = screen.call(&"get_controller")
	var session: CombatSession = view.get_session()
	# Not compared with the pools: loading them here leaves resources in use at exit.
	_check("screen: entering it begins a battle on a standard map, not M1", (
			run.encounter != null
			and session != null
			and session.setup.map.combat_type == CombatMapDefinition.CombatType.STANDARD
			and session.setup.map.id != "m1_greybox"
			and saves.get(&"combat") != null
	))
	if session == null:
		screen.free()
		return false
	var sorted_ids: PackedStringArray = session.state.unit_ids()
	sorted_ids.sort()
	# The army's 4 and a step-1 pack's 3; the map's breakable objects have tokens too.
	var fighters: int = (
			session.state.units_of(CombatFact.CombatSide.PLAYER).size()
			+ session.state.units_of(CombatFact.CombatSide.ENEMY).size()
	)
	_check("screen: one token per unit, each on its tile", (
			view.token_ids() == sorted_ids
			and fighters == 7
			and view.mismatches().is_empty()
	), "%s; %s" % [view.token_ids(), view.mismatches()])

	var swap_window: SwapWindow = controller.swap_window
	_check("screen: the swap window and its Start show before turn 1", (
			swap_window.visible == session.state.map.opening_swap_open
	))
	if swap_window.visible:
		swap_window.get_start_button().pressed.emit()
		BattleViewCases.settle(view)
	var end_turn: Button = controller.turn_bar.get_end_turn_button()
	var hints: ControlHintBar = screen.get_node(^"%ControlHintBar")
	# What the hints showed while the battle's final playback ran, and once it settled.
	var final_hints: PackedStringArray = []
	for _phase: int in MAX_PHASES:
		if session.is_finished:
			break
		if end_turn.disabled:
			BattleViewCases.settle(view)
			if end_turn.disabled:
				break
		end_turn.pressed.emit()
		var question: ConfirmDialog = controller.panel_host.top() as ConfirmDialog
		if question != null:
			question.get_confirm_button().pressed.emit()
		if session.is_finished:
			hints.refresh()
			final_hints.append("%s %s %s" % [
				hints.get_context(), hints.visible, hints.get_shown_actions(),
			])
		BattleViewCases.settle(view)
		if session.is_finished:
			hints.refresh()
			final_hints.append("%s %s" % [hints.get_context(), hints.visible])
	_check("screen: End Turn alone plays the battle to its end", session.is_finished, (
			"turn %d" % [session.state.turn]
	))
	var playing_actions: Array[StringName] = []
	playing_actions.assign(BattleController.LIVE_ACTIONS[&"PLAYBACK"])
	playing_actions.erase(&"toggle_danger_zone")
	if not OS.is_debug_build():
		playing_actions.erase(&"toggle_save_debug")
	_check("screen: the hints show PLAYBACK through the final playback, then hide at the banner", (
			final_hints == PackedStringArray([
				"PLAYBACK true %s" % [playing_actions], " false",
			])
	), " | ".join(final_hints))
	var screen_now: int = router.get(&"current_screen")
	var hud: BattleHud = screen.call(&"get_hud")
	var banner: PhaseBanner = hud.get_phase_banner()
	var expected: String = banner.victory_text if session.is_won else banner.defeat_text
	_check("screen: a finished battle shows its end banner before the route to Results", (
			session.is_finished
			and banner.visible
			and banner.get_texts()[0] == expected
			and screen_now != SCREEN_RESULTS
			and run.encounter != null
			and not controller.is_accepting_input()
	), "banner '%s' shown %s, expected '%s'; screen %d" % [
		banner.get_texts()[0], banner.visible, expected, screen_now,
	])
	_route_screen = screen
	_route_run = run
	_route_started_msec = Time.get_ticks_msec()
	return true


# Each frame after the end banner showed: true once the screen has routed to Results, or the wait
# has timed out, with the routing checked; the screen is then freed.
func _poll_route() -> bool:
	var router: Node = root.get_node(^"SceneRouter")
	var screen_now: int = router.get(&"current_screen")
	var waited: int = Time.get_ticks_msec() - _route_started_msec
	if screen_now != SCREEN_RESULTS and waited < ROUTE_TIMEOUT_MSEC:
		return false
	var combat_left: Object = root.get_node(^"SaveService").get(&"combat")
	_check("screen: after the banner the battle is ended and goes to Results", (
			screen_now == SCREEN_RESULTS and _route_run.encounter == null and combat_left == null
	), "screen %d after %d ms, encounter %s" % [screen_now, waited, _route_run.encounter])
	_route_screen.queue_free()
	_route_screen = null
	return true


# After the scene change: Results is the current scene; then the save file is dropped.
func _finish_route_case() -> void:
	var shown: Node = current_scene
	_check("screen: Results is the scene shown", (
			shown != null and shown.scene_file_path.ends_with("results_screen.tscn")
	), shown.scene_file_path if shown != null else "no scene")
	var saves: Node = root.get_node(^"SaveService")
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


