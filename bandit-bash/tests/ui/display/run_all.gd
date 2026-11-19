# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 7, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/ui/ui_suite.gd"
## Combat UI display suite (combat UI plan, P07): the forecast, the HUD, the event log (P15 UL4),
## the heirloom bar (P15 UL8),
## the unit display and the
## display fixes of UI9 (pop-ups on the info layer, a hit's number past Block and its Block number,
## gray only in a unit's own phase, the HP bar's maximum), UI10's exchange feedback (the
## forecast's flash, outlined pips, move then act), and UI11's objective HUDs and the opening-swap
## setting (Options, settings.json and the solo battle; with a test user folder only), a cases
## file each in [code]tests/ui/battle/[/code] (preloaded below; each one's class doc lists its
## checks); then the gameplay screen's layout: its save debug panel (hidden when the battle opens,
## toggled by F3 and read afresh, clear of the M1 map at the 1280×720 base size, untouched by
## clicks on the deployment tiles); the HUD and the hint bar clear of the map at the base size and
## wider; the run seed on the pause screen; the unit panel keeping its unit under the mouse
## (BUG-015) and a real click on its Details opening unit detail. The shared helpers are
## [code]tests/ui/ui_suite.gd[/code]'s.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/display/run_all.gd[/code].
## Prints one PASS, FAIL or SKIP line per check and
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure.[br]
## The cases run from the first frame, when autoloads exist; the panel case over a few more frames
## so the layout and the camera settle. It needs a test user folder (see the base).

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Forecast, HUD, heirloom bar, unit display, objectives, layout"

const ForecastCases = preload("res://tests/ui/battle/forecast/forecast_cases.gd")
const HudCases = preload("res://tests/ui/battle/hud/hud_cases.gd")
const EventLogCases = preload("res://tests/ui/battle/hud/event_log_cases.gd")
const HeirloomBarCases = preload("res://tests/ui/battle/hud/heirloom_bar_cases.gd")
const UnitDisplayCases = preload("res://tests/ui/battle/unit/unit_display_cases.gd")
const DisplayFixCases = preload("res://tests/ui/battle/display_fix_cases.gd")
const ExchangeFeedbackCases = preload("res://tests/ui/battle/exchange_feedback_cases.gd")
const ObjectiveHudCases = preload("res://tests/ui/battle/objectives/objective_hud_cases.gd")
const OpeningSwapCases = preload("res://tests/ui/battle/menus/opening_swap_cases.gd")

# Frames left for the save debug panel's layout and the camera to settle before its checks.
const PANEL_FRAMES: int = 3

# A wider screen the HUD case lays out at too: 21:9 at the base height, so the expand aspect gives
# the HUD more width than the base size.
const WIDE_SCREEN_SIZE: Vector2i = Vector2i(1680, 720)

var _frame: int = 0
var _panel_frame: int = -1
var _wide_frame: int = -1
var _detail_frame: int = -1

# The panel case's gameplay screen, and the root's size before the case set it.
var _panel_screen: Node = null
var _old_root_size: Vector2i = Vector2i.ZERO


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_start("Combat UI tests: display")
		GroupClock.lap("forecast_cases")
		ForecastCases.new(_check, root).run()
		GroupClock.lap("hud_cases")
		HudCases.new(_check, root).run()
		GroupClock.lap("event_log_cases")
		EventLogCases.new(_check, root).run()
		GroupClock.lap("heirloom_bar_cases")
		HeirloomBarCases.new(_check, root).run()
		GroupClock.lap("unit_display_cases")
		UnitDisplayCases.new(_check, root).run()
		GroupClock.lap("display_fix_cases")
		DisplayFixCases.new(_check, root).run()
		GroupClock.lap("exchange_feedback_cases")
		ExchangeFeedbackCases.new(_check, root).run()
		GroupClock.lap("objective_hud_cases")
		ObjectiveHudCases.new(_check, root).run()
		if _has_test_user_dir():
			GroupClock.lap("opening_swap_cases")
			OpeningSwapCases.new(_check, root).run()
		else:
			_skip("opening swap", "the settings and gameplay screens need a test user folder")
		# Open over the frames the panel, wide and detail cases take.
		GroupClock.lap("gameplay screen layout")
		if _start_panel_case():
			_panel_frame = _frame
			return false
		_finish()
		return false
	if _panel_frame < 0:
		return false
	if _wide_frame < 0:
		if _frame < _panel_frame + PANEL_FRAMES:
			return false
		_finish_panel_case()
		_wide_frame = _frame
		return false
	if _detail_frame < 0:
		if _frame < _wide_frame + PANEL_FRAMES:
			return false
		_finish_wide_case()
		if not _start_detail_click_case():
			_end_panel_case()
			_finish()
			return false
		_detail_frame = _frame
		return false
	if _frame < _detail_frame + PANEL_FRAMES:
		return false
	_finish_detail_click_case()
	_end_panel_case()
	_finish()
	return false


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
	_enter_first_node()
	var scene: PackedScene = load(GAMEPLAY_SCENE)
	_panel_screen = scene.instantiate()
	root.add_child(_panel_screen)
	var panel: Control = _panel_screen.get_node(^"%SaveDebugPanel")
	var view: BattleView = _panel_screen.call(&"get_view")
	var is_hidden: bool = view.get_session() != null and not panel.visible
	var info: Label = panel.get_node(^"%Info")
	var begin: Button = panel.get_node(^"%BeginButton")
	# Read when the panel loaded, before the screen began the battle.
	var loaded_text: String = info.text
	var shown: Array[bool] = []
	for _press: int in 3:
		_press_key(KEY_F3)
		shown.append(panel.visible)
	_check("panel: hidden when the battle opens, and F3 shows and hides it", (
			is_hidden and shown == [true, false, true]
	), "hidden %s, then %s" % [is_hidden, shown])
	_check("panel: shown by F3 in a battle, it shows the battle and Begin Battle is disabled", (
			loaded_text.contains("No battle.")
			and info.text.contains("Battle: turn")
			and begin.disabled
	), "loaded '%s', shown '%s', Begin disabled %s" % [
		loaded_text.replace("\n", " / "), info.text.replace("\n", " / "), begin.disabled,
	])
	return true


# The panel's layout and the camera have settled: shown, the panel covers no M1 tile, and nor does
# any HUD widget; the pause screen shows the run seed; a click on each deployment tile presses
# none of the panel's buttons, while a click on it reaches it. Then the screen widens, for
# _finish_wide_case().
func _finish_panel_case() -> void:
	var covering: PackedStringArray = _hud_over_map()
	_check("hud: at 1280×720 no HUD widget, panel or bar covers the M1 map", (
			covering.size() == 1 and covering[0].begins_with("map ")
	), "; ".join(covering))
	var pause: Node = _panel_screen.get_node(^"PauseMenu")
	pause.call(&"open")
	var seed_text: String = pause.call(&"get_seed_text")
	pause.call(&"close")
	_check("pause: the pause screen shows the run seed (RunSeed.format)", (
			seed_text == "Seed %s" % [RunSeed.format(RUN_SEED)]
	), "'%s'" % [seed_text])

	var panel: Control = _panel_screen.get_node(^"%SaveDebugPanel")
	var view: BattleView = _panel_screen.call(&"get_view")
	var camera: Camera2D = root.get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	var to_screen: Transform2D = view.get_global_transform_with_canvas()
	var map_on_screen: Rect2 = to_screen * view.map_rect()
	var panel_rect: Rect2 = panel.get_global_rect()
	_check("panel: shown at 1280×720, it covers no tile of the M1 map", (
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
	field.release_focus()
	panel.visible = false
	root.size = WIDE_SCREEN_SIZE


# The screen has widened and the camera framed the map again: still nothing covers it.
func _finish_wide_case() -> void:
	var covering: PackedStringArray = _hud_over_map()
	_check("hud: at %d×%d (wider) nothing covers the M1 map either" % [
		WIDE_SCREEN_SIZE.x, WIDE_SCREEN_SIZE.y,
	], (
			root.get_visible_rect().size == Vector2(WIDE_SCREEN_SIZE)
			and covering.size() == 1
			and covering[0].begins_with("map ")
	), "visible %s; %s" % [root.get_visible_rect().size, "; ".join(covering)])


# Back at the base size, Start pressed and played, the cursor on the first player unit: frames
# lay the HUD out before _finish_detail_click_case() clicks its unit panel's Details. Returns
# whether the battle reached the player phase.
func _start_detail_click_case() -> bool:
	root.size = BASE_SCREEN_SIZE
	var controller: BattleController = _panel_screen.call(&"get_controller")
	var view: BattleView = _panel_screen.call(&"get_view")
	# The panel case's clicks on the deployment tiles may have sent swaps still playing.
	_settle(view)
	controller.step_back()
	controller.request_start()
	_settle(view)
	var session: CombatSession = view.get_session()
	var first: String = session.state.units_of(CombatFact.CombatSide.PLAYER)[0]
	controller.move_cursor(session.state.tile_of(first))
	var is_idle: bool = controller.get_stage() == BattleController.Stage.IDLE
	_check("unit detail (click): the battle reaches the player phase for the click", is_idle, (
			"stage %d, turn %d" % [controller.get_stage(), session.state.turn]
	))
	return is_idle


# Steps view a frame at a time, at most 10 s of play, until its playback settles.
func _settle(view: BattleView) -> void:
	for _step: int in 600:
		if view.is_settled():
			return
		view.advance(1.0 / 60.0)


# BUG-015: the mouse moves onto the laid-out unit panel, then the board's cursor moves to an
# enemy, as the mouse crossing the board would move it: the panel keeps its unit. A real left
# click on its Details then opens that unit's detail; a right click closes it.
func _finish_detail_click_case() -> void:
	var controller: BattleController = _panel_screen.call(&"get_controller")
	var hud: BattleHud = _panel_screen.call(&"get_hud")
	var view: BattleView = _panel_screen.call(&"get_view")
	var unit_panel: UnitPanel = hud.get_unit_panel()
	var button: Button = unit_panel.get_details_button()
	var shown: String = controller.detail_unit()
	var rect: Rect2 = button.get_global_rect()
	# Through Input, which keeps the mouse position a headless run reads (the root viewport's own
	# push_input doesn't move it).
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = rect.get_center()
	motion.global_position = rect.get_center()
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var enemy: String = view.get_session().state.units_of(CombatFact.CombatSide.ENEMY)[0]
	controller.move_cursor(view.get_session().state.tile_of(enemy))
	# Stands for the frame in which the HUD would follow the cursor.
	hud.call(&"_process", 0.0)
	var held: bool = (
			unit_panel.is_mouse_over()
			and unit_panel.get_view() != null
			and unit_panel.get_view().unit_id == shown
	)
	_check("unit panel (BUG-015): it keeps its unit while the mouse is over it", held, (
			"over %s, shows %s, expected %s" % [
				unit_panel.is_mouse_over(),
				unit_panel.get_view().unit_id if unit_panel.get_view() != null else "-", shown,
			]
	))
	_click(rect.get_center())
	var panel: UnitDetailPanel = controller.get_detail_panel()
	var opened: bool = (
			controller.get_stage() == BattleController.Stage.DETAIL
			and panel != null
			and panel.get_view().unit_id == shown
	)
	var right: InputEventMouseButton = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	root.push_input(right, true)
	_check("unit detail (click): a click on Details opens it; a right click closes it", (
			button.is_visible_in_tree()
			and root.get_visible_rect().encloses(rect)
			and opened
			and controller.get_stage() == BattleController.Stage.IDLE
	), "button %s, opened %s, stage %d" % [rect, opened, controller.get_stage()])


# The map's screen rect first, as "map <rect>", then each HUD widget, panel area or bar of the
# panel case's screen whose rect meets it, hidden ones included (the banner, the swap window and
# the message show at times). Each widget is checked on its own: the HUD's full-screen roots let
# everything through and draw nothing.
func _hud_over_map() -> PackedStringArray:
	var view: BattleView = _panel_screen.call(&"get_view")
	var camera: Camera2D = root.get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	var map: Rect2 = view.get_global_transform_with_canvas() * view.map_rect()
	var found: PackedStringArray = ["map %s" % [map]]
	if not map.has_area():
		found.append("the map has no area")
		return found
	var hud: BattleHud = _panel_screen.call(&"get_hud")
	var host: PanelHost = _panel_screen.get_node(^"%PanelHost")
	var widgets: Array[Control] = [
		hud.get_turn_counter(), hud.get_objective(), hud.get_darkness_counter(),
		hud.get_tile_info(), hud.get_unit_panel(), hud.get_fact_log(), hud.get_phase_banner(),
		hud.get_event_log(),
		_panel_screen.get_node(^"%TurnBar") as Control,
		_panel_screen.get_node(^"%ControlHintBar") as Control,
		_panel_screen.get_node(^"%SwapWindow") as Control,
		_panel_screen.get_node(^"%BattleMessage") as Control,
		_panel_screen.get_node(^"%SaveDebugPanel") as Control,
	]
	for widget: Control in widgets:
		if widget.get_global_rect().intersects(map):
			found.append("%s %s" % [widget.name, widget.get_global_rect()])
	if host.get_area_rect().intersects(map):
		found.append("panel area %s" % [host.get_area_rect()])
	return found


# Drops the panel case's screen and save file, and gives the root its size back.
func _end_panel_case() -> void:
	if _panel_screen != null:
		_panel_screen.free()
		_panel_screen = null
	var saves: Node = root.get_node(^"SaveService")
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	root.size = _old_root_size

