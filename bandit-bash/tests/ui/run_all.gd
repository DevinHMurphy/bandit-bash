# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends SceneTree
## Combat UI suite (combat UI plan, P07): the battle board's view-model, the board on the M1 map,
## an M1 battle's facts played through the board, the darkness overlay, held fast-forward and the
## faded skip ([code]battle_view_cases.gd[/code]); turn input: the action menu, the overlays and
## path, cancel, End Turn and Start, rejections, playback, a second move, and player turns played
## by input events ([code]turn_input_cases.gd[/code]); then the gameplay screen itself: its save
## debug panel (hidden when the battle opens, toggled by F3, clear of the M1 map at the 1152×648
## base size, and untouched by clicks on the deployment tiles), then a new solo run's M1 battle
## played to its end from Start and End Turn, and the route to Results.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/ui/run_all.gd[/code][br]
## Prints one PASS, FAIL or SKIP line per check and the summary line
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure.[br]
## The cases run from the first frame, when autoloads exist; the panel case runs over a few more
## frames so the panel's layout and the camera settle, and the routing case over a few after that
## so the scene change happens. This script never names an autoload, or the gameplay screen's
## class (whose script does), since it compiles before autoloads are registered; it reaches them
## as nodes and loads the screen at run time.[br]
## [b]The panel and routing cases[/b] drive the real [code]SaveService[/code], which writes save
## files, so they run only with a test user folder ([code]tools/run_tests.sh[/code] makes one; see
## [code]tests/sessions/run_all.gd[/code]) and are skipped otherwise.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")
const CatalogCases = preload("res://tests/content/catalog_cases.gd")

const GAMEPLAY_SCENE: String = "res://scenes/gameplay/gameplay.tscn"

# SceneRouter.Screen.RESULTS: this script can't name the autoload (see the class doc).
const SCREEN_RESULTS: int = 4

# NetLog.Level.WARN, for the same reason.
const LOG_WARN: int = 1

# Any fixed run seed.
const RUN_SEED: int = 0x51A7E

# The save file the panel and routing cases write, in the test user folder only.
const SAVE_NUMBER: int = 1

# Player phases the routing case presses End Turn for before giving up.
const MAX_PHASES: int = 60

# Frames left for the save debug panel's layout and the camera to settle before its checks.
const PANEL_FRAMES: int = 3

# Frames left for the scene change to Results before the last checks.
const ROUTE_FRAMES: int = 3

# The screen size the panel case lays the screen out at: the project sets no window size, so this
# is Godot's default window and the base size of the canvas_items stretch.
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1152, 648)

var _failures: int = 0
var _passes: int = 0
var _skips: int = 0
var _frame: int = 0
var _panel_frame: int = -1
var _route_frame: int = -1
var _before: Dictionary[String, String] = {}

# The panel case's gameplay screen, and the root's size before the case set it.
var _panel_screen: Node = null
var _old_root_size: Vector2i = Vector2i.ZERO


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		print("--- Combat UI tests ---")
		root.get_node(^"NetLog").set(&"min_level", LOG_WARN)
		# Hashed before the first case (event bus plan, question 50): no case may change a
		# definition.
		_before = CatalogCases.hash_definitions(PackedStringArray())
		BattleViewCases.new(_check, root).run()
		TurnInputCases.new(_check, root).run()
		if _start_panel_case():
			_panel_frame = _frame
			return false
		_begin_route()
		return false
	if _route_frame < 0:
		if _frame < _panel_frame + PANEL_FRAMES:
			return false
		_finish_panel_case()
		_begin_route()
		return false
	if _frame < _route_frame + ROUTE_FRAMES:
		return false
	_finish_route_case()
	_finish()
	return false


func _finish() -> void:
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			_before, CatalogCases.hash_definitions(PackedStringArray())
	)
	_check("definitions: none changed during the run (%d hashed)" % [_before.size()], (
			changed.is_empty()
	), ", ".join(changed))
	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)


# Starts the routing case, or ends the run when it can't start.
func _begin_route() -> void:
	if _start_route_case():
		_route_frame = _frame
		return
	_finish()


# A new solo run's gameplay screen at the base size: the save debug panel is hidden as the battle
# opens, and F3 shows, hides and shows it again, leaving it shown for _finish_panel_case(). Returns
# true when the screen is up.
func _start_panel_case() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  panel: the gameplay screen needs a test user folder (see the class doc)")
		return false
	_old_root_size = root.size
	root.size = BASE_SCREEN_SIZE
	var saves: Node = root.get_node(^"SaveService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"start_new_solo_run", RUN_SEED)
	if err != OK:
		_check("panel: a new solo run starts", false, error_string(err))
		_end_panel_case()
		return false
	var scene: PackedScene = load(GAMEPLAY_SCENE)
	_panel_screen = scene.instantiate()
	root.add_child(_panel_screen)
	var panel: Control = _panel_screen.get_node(^"%SaveDebugPanel")
	var view: BattleView = _panel_screen.call(&"get_view")
	var is_hidden: bool = view.get_session() != null and not panel.visible
	var shown: Array[bool] = []
	for _press: int in 3:
		_press_key(KEY_F3)
		shown.append(panel.visible)
	_check("panel: hidden when the battle opens, and F3 shows and hides it", (
			is_hidden and shown == [true, false, true]
	), "hidden %s, then %s" % [is_hidden, shown])
	return true


# The panel's layout and the camera have settled: shown, the panel covers no M1 tile; a click on
# each deployment tile presses none of its buttons, while a click on it reaches it.
func _finish_panel_case() -> void:
	var panel: Control = _panel_screen.get_node(^"%SaveDebugPanel")
	var view: BattleView = _panel_screen.call(&"get_view")
	var camera: Camera2D = root.get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	var to_screen: Transform2D = view.get_global_transform_with_canvas()
	var map_on_screen: Rect2 = to_screen * view.map_rect()
	var panel_rect: Rect2 = panel.get_global_rect()
	_check("panel: shown at 1152×648, it covers no tile of the M1 map", (
			panel.visible
			and root.get_visible_rect().size == Vector2(BASE_SCREEN_SIZE)
			and map_on_screen.has_area()
			and panel_rect.has_area()
			and not panel_rect.intersects(map_on_screen)
	), "panel %s, map %s" % [panel_rect, map_on_screen])

	# An Array, not a PackedStringArray: the lambdas capture it, and only an Array is shared.
	var pressed: Array[String] = []
	for node: Node in panel.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node
		var label: String = button.name
		button.pressed.connect(func() -> void: pressed.append(label))
	var clicked: int = 0
	var session: CombatSession = view.get_session()
	for marker: MapLayout.Marker in session.layout.markers_of(MapLayout.MarkerKind.DEPLOYMENT):
		_click(to_screen * view.tile_to_position(marker.tile))
		clicked += 1
	var saves: Node = root.get_node(^"SaveService")
	_check("panel: clicking every deployment tile presses nothing in it", (
			clicked > 0 and pressed.is_empty() and saves.get(&"campaign") != null
	), "%d tiles clicked; pressed %s" % [clicked, pressed])
	var field: LineEdit = panel.get_node(^"%SeedField")
	_click(field.get_global_rect().get_center())
	_check("panel: a click on the panel itself reaches it", field.has_focus())
	_end_panel_case()


# Drops the panel case's screen and save file, and gives the root its size back.
func _end_panel_case() -> void:
	if _panel_screen != null:
		_panel_screen.free()
		_panel_screen = null
	var saves: Node = root.get_node(^"SaveService")
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	root.size = _old_root_size


# A new solo run enters the gameplay screen, which begins the M1 battle; the swap window's Start
# and the turn bar's End Turn (confirming its question) play it until it ends, and the screen ends
# it and routes to Results. Returns true when the scene change is under way, so the remaining
# checks wait a few frames.
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

	var scene: PackedScene = load(GAMEPLAY_SCENE)
	var screen: Node = scene.instantiate()
	root.add_child(screen)
	var view: BattleView = screen.call(&"get_view")
	var controller: BattleController = screen.call(&"get_controller")
	var session: CombatSession = view.get_session()
	_check("screen: entering it begins the M1 battle", (
			run.encounter != null
			and session != null
			and session.setup.map.id == "m1_greybox"
			and saves.get(&"combat") != null
	))
	if session == null:
		screen.free()
		return false
	var sorted_ids: PackedStringArray = session.state.unit_ids()
	sorted_ids.sort()
	_check("screen: one token per unit, each on its tile", (
			view.token_ids() == sorted_ids
			and sorted_ids.size() == 7
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
		BattleViewCases.settle(view)
	_check("screen: End Turn alone plays the battle to its end", session.is_finished, (
			"turn %d" % [session.state.turn]
	))
	var screen_now: int = router.get(&"current_screen")
	var combat_left: Object = saves.get(&"combat")
	_check("screen: a finished battle is ended and goes to Results", (
			screen_now == SCREEN_RESULTS and run.encounter == null and combat_left == null
	), "screen %d, encounter %s" % [screen_now, run.encounter])
	screen.queue_free()
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


func _has_test_user_dir() -> bool:
	var custom_dir: bool = ProjectSettings.get_setting(
			"application/config/use_custom_user_dir", false
	)
	var dir_name: String = ProjectSettings.get_setting(
			"application/config/custom_user_dir_name", ""
	)
	return custom_dir and dir_name == "bandit_bash_tests"


# A press and release of key, by its physical position, as the input map binds it.
func _press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.pressed = is_down
		root.push_input(event, true)


# A left click at point, in the root viewport's visible rect.
func _click(point: Vector2) -> void:
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_down
		root.push_input(click, true)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
