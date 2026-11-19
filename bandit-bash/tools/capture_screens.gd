# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     capture_screens.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

extends SceneTree
## Screenshots every screen at one window size, for checking the UI's layout by eye (UI style
## guide: base 1280×720, shown at 1920×1080 and the Steam Deck's 1280×800). Drives the real
## router through a new solo run: boot, start, save select, main menu, new run, options, lobby,
## loading, the campaign map, the battle (swap window, HUD with the unit panel and rune bar,
## action menu, forecast, unit detail, runes, the event log after turns played into the first
## darkness phase, pause), Results (grades, XP, level-ups, the item
## pick), placement, and the run's end. Each shot is [code]<out>/<size>/<nn>_<name>.png[/code].
## Each shot also lists visible text under [constant MIN_FONT_SIZE] base units and visible
## controls reaching outside the window, and the run ends with their count.[br]
## Run windowed (a headless run renders nothing), from the repo root, with a throwaway user folder
## (it starts a run in save file 1; set APPDATA on Windows):
## [code]godot --path bandit-bash --script res://tools/capture_screens.gd -- --out <dir>
## --size 1920x1080[/code]. Authoring tooling: nothing in the game loads it. Never names an
## autoload (a [code]--script[/code] run compiles before they register); it reaches them as nodes.
##
## @tutorial(UI style guide): docs/design/ui-style.md

# SceneRouter.Screen values (the script can't name the autoload; see the class doc).
const SCREEN_START: int = 0
const SCREEN_LOBBY: int = 1
const SCREEN_LOADING: int = 2
const SCREEN_GAMEPLAY: int = 3
const SCREEN_RESULTS: int = 4
const SCREEN_MAIN_MENU: int = 5
const SCREEN_OPTIONS: int = 6
const SCREEN_SAVE_SELECT: int = 7
const SCREEN_NEW_RUN: int = 8
const SCREEN_MAP: int = 9
const SCREEN_COMBAT_RESULTS: int = 10

const BOOT_SCENE: String = "res://ui/screens/boot.tscn"

## The style guide's floor for text, in base units.
const MIN_FONT_SIZE: int = 14

# Any fixed run seed, and the save file the run is written to.
const RUN_SEED: int = 0x51A7E
const SAVE_NUMBER: int = 1

# Frames left after a scene change or an action for layout, focus and tweens to settle.
const SETTLE_FRAMES: int = 20

# Player phases the battle may wait through for a unit with an attack target.
const TURNS_FOR_ATTACK: int = 4

# Phases played for the event log's shot at most: past the M1 darkness's arrival (end of turn 4).
const LOG_PHASES: int = 6

var _out_dir: String = ""

# Darkness phases played since the event log's phases began.
var _darkness_phases: int = 0
var _size: Vector2i = Vector2i(1280, 720)
var _shot: int = 0
var _issues: int = 0


func _initialize() -> void:
	if not _read_args():
		quit(1)
		return
	_run.call_deferred()


func _read_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size() - 1:
		if args[i] == "--out":
			_out_dir = args[i + 1]
		elif args[i] == "--size":
			var parts: PackedStringArray = args[i + 1].split("x")
			if parts.size() == 2:
				_size = Vector2i(parts[0].to_int(), parts[1].to_int())
	if _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		push_error("CaptureScreens: run windowed with -- --out <dir> [--size WxH]")
		return false
	_out_dir = _out_dir.path_join("%dx%d" % [_size.x, _size.y])
	return DirAccess.make_dir_recursive_absolute(_out_dir) == OK


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = _size
	root.position = Vector2i.ZERO
	await _frames(SETTLE_FRAMES)
	if root.size != _size:
		print("NOTE  the window is %s, not %s (screen %s)" % [
			root.size, _size, DisplayServer.screen_get_size(),
		])
	change_scene_to_file(BOOT_SCENE)
	await process_frame
	await _capture("boot")
	await _frames(SETTLE_FRAMES)
	await _capture("start")
	await _goto(SCREEN_SAVE_SELECT, "save_select")
	_node(^"SaveService").call(&"open_save_file", SAVE_NUMBER)
	await _goto(SCREEN_MAIN_MENU, "main_menu")
	await _goto(SCREEN_NEW_RUN, "new_run")
	await _goto(SCREEN_OPTIONS, "options")
	await _goto(SCREEN_LOBBY, "lobby")
	var err: Error = _node(^"SaveService").call(&"start_new_solo_run", RUN_SEED)
	if err != OK:
		print("FAIL  a new solo run did not start: %s" % [error_string(err)])
		_end()
		return
	await _goto(SCREEN_LOADING, "loading")
	(current_scene.get_node(^"%ContinueButton") as Button).pressed.emit()
	await _frames(SETTLE_FRAMES)
	if not await _campaign_map():
		_end()
		return
	await _battle()
	await _results()
	await _goto(SCREEN_RESULTS, "run_end")
	_end()


# Captures the map, then enters its first reachable combat node. Returns whether the battle opened.
func _campaign_map() -> bool:
	await _capture("campaign_map")
	var view: CampaignMapView = current_scene.call(&"get_map_view")
	for node_id: int in view.get_reachable():
		var button: MapNodeButton = view.get_node_button(node_id)
		if button.node_type == CampaignGraph.NodeType.STANDARD:
			button.pressed.emit()
			await _frames(SETTLE_FRAMES)
			return _router_screen() == SCREEN_GAMEPLAY
	print("FAIL  no reachable Standard combat node on the map")
	return false


func _battle() -> void:
	var view: BattleView = current_scene.call(&"get_view")
	var controller: BattleController = current_scene.call(&"get_controller")
	_settle(view)
	await _frames(SETTLE_FRAMES)
	await _capture("battle_swap_window")
	controller.request_start()
	_settle(view)
	await _frames(SETTLE_FRAMES)
	var session: CombatSession = view.get_session()
	var first: String = session.state.units_of(CombatFact.CombatSide.PLAYER)[0]
	controller.move_cursor(session.state.tile_of(first))
	await _frames(SETTLE_FRAMES)
	await _capture("battle_hud")
	if controller.request_unit_detail(first):
		await _frames(SETTLE_FRAMES)
		await _capture("battle_unit_detail")
		controller.step_back()
		await _frames(SETTLE_FRAMES)
	if controller.request_runes():
		await _frames(SETTLE_FRAMES)
		await _capture("battle_runes")
		controller.step_back()
		await _frames(SETTLE_FRAMES)
	await _attack(view, controller, session)
	await _play_for_log(view, session)
	await _capture("battle_event_log")
	var pause: Node = current_scene.get_node(^"PauseMenu")
	pause.call(&"open")
	await _frames(SETTLE_FRAMES)
	await _capture("battle_pause")
	pause.call(&"close")
	await _frames(SETTLE_FRAMES)
	current_scene.set(&"end_banner_time", 0.0)
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	session.engine.record(ended)
	_settle(view)
	view.settled.emit()
	await _frames(SETTLE_FRAMES)


# Walks a unit to an enemy in reach and opens Attack, capturing the action menu and the forecast;
# waits whole phases out while no unit has a target, up to TURNS_FOR_ATTACK.
func _attack(view: BattleView, controller: BattleController, session: CombatSession) -> void:
	for _turn: int in TURNS_FOR_ATTACK:
		var pick: Array = _find_attack(session)
		if not pick.is_empty():
			var unit_id: String = pick[0]
			var walk: Array = pick[1]
			var path: Array[Vector2i] = []
			path.assign(walk)
			var end: Vector2i = session.state.tile_of(unit_id) if path.is_empty() else path[-1]
			controller.confirm_tile(session.state.tile_of(unit_id))
			controller.confirm_tile(end)
			for _step: int in 600:
				if not view.is_staged_walking():
					break
				view.advance(1.0 / 60.0)
			_settle(view)
			await _frames(SETTLE_FRAMES)
			await _capture("battle_action_menu")
			var host: PanelHost = current_scene.get_node(^"%PanelHost")
			var menu: ActionMenu = host.top() as ActionMenu
			if menu != null:
				var options: Array[TurnInputModel.ActionOption] = menu.get_options()
				for i: int in options.size():
					if options[i].kind == TurnInputModel.ActionKind.ATTACK:
						menu.get_rows()[i].pressed.emit()
						break
				await _frames(SETTLE_FRAMES)
				await _capture("battle_target")
				var option: TurnInputModel.ActionOption = pick[2]
				controller.confirm_tile(option.targets[0].tile)
				await _frames(SETTLE_FRAMES)
				await _capture("battle_forecast")
			while controller.step_back():
				await process_frame
			_settle(view)
			return
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			session.submit(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
			session.resolve_next()
		if not session.is_finished:
			session.submit(EndTurnCommand.new(0))
			session.resolve_next()
		_settle(view)
		await _frames(SETTLE_FRAMES)
	print("NOTE  no unit had an attack target within %d turns: no forecast shot" % [
		TURNS_FOR_ATTACK,
	])


# Whole phases, each unit attacking where it can while more than one enemy stands (so the battle
# goes on) and waiting elsewhere, until a darkness phase has played or LOG_PHASES pass: the event
# log then holds lines of every group.
func _play_for_log(view: BattleView, session: CombatSession) -> void:
	_darkness_phases = 0
	view.darkness_phase_started.connect(_on_view_darkness_phase_started)
	for _phase: int in LOG_PHASES:
		if session.is_finished or _darkness_phases > 0:
			break
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			var command: Command = UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT)
			var pick: Array = _find_attack(session)
			var enemies: int = session.state.units_of(CombatFact.CombatSide.ENEMY).size()
			if not pick.is_empty() and pick[0] == unit_id and enemies > 1:
				var option: TurnInputModel.ActionOption = pick[2]
				command = option.targets[0].command
			session.submit(command)
			session.resolve_next()
			_settle(view)
			if session.is_finished:
				break
		if not session.is_finished:
			session.submit(EndTurnCommand.new(0))
			session.resolve_next()
		_settle(view)
		await _frames(SETTLE_FRAMES)
	view.darkness_phase_started.disconnect(_on_view_darkness_phase_started)


func _on_view_darkness_phase_started(_turn: int) -> void:
	_darkness_phases += 1


func _find_attack(session: CombatSession) -> Array:
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		if not TurnInputModel.can_act(session, unit_id):
			continue
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					session, unit_id, path
			):
				var is_attack: bool = option.kind == TurnInputModel.ActionKind.ATTACK
				if is_attack and not option.targets.is_empty():
					return [unit_id, path, option]
	return []


# Results as the battle left it, then the placement panel for the pick's first card.
func _results() -> void:
	if _router_screen() != SCREEN_COMBAT_RESULTS:
		print("FAIL  the won battle did not reach Results (screen %d)" % [_router_screen()])
		return
	await _capture("results")
	var pick: ItemPickPanel = current_scene.call(&"get_pick_panel")
	var cards: Array[ItemOfferCard] = pick.get_offer_cards()
	if cards.is_empty():
		print("NOTE  Results offered no item: no placement shot")
		return
	cards[0].pressed.emit()
	await _frames(SETTLE_FRAMES)
	await _capture("placement")
	var placement: PlacementPanel = current_scene.call(&"get_placement_panel")
	placement.visible = false


func _goto(screen: int, shot_name: String) -> void:
	_node(^"SceneRouter").call(&"goto_screen", screen)
	await _frames(SETTLE_FRAMES)
	await _capture(shot_name)


# Saves the window as the next shot and lists its text and clipping issues.
func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path: String = _out_dir.path_join("%02d_%s.png" % [_shot, shot_name])
	var image: Image = root.get_texture().get_image()
	var err: Error = image.save_png(path)
	print("SHOT  %s%s" % [path, "" if err == OK else " (%s)" % [error_string(err)]])
	for issue: String in _issues_in(root):
		_issues += 1
		print("  ISSUE  %s: %s" % [shot_name, issue])


# Visible text under the floor, and visible controls reaching outside the window.
func _issues_in(top: Node) -> PackedStringArray:
	var found: PackedStringArray = []
	var bounds: Rect2 = root.get_visible_rect().grow(0.5)
	for node: Node in top.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree():
			continue
		var size: int = _font_size_of(control)
		if size > 0 and size < MIN_FONT_SIZE and _has_text(control):
			found.append("%s text at %d" % [control.get_path(), size])
		# A scroll container's content may run past it; the container itself is checked.
		if _is_scrolled(control):
			continue
		# On screen, through any camera or canvas layer above it.
		var to_screen: Transform2D = control.get_global_transform_with_canvas()
		var rect: Rect2 = to_screen * Rect2(Vector2.ZERO, control.size)
		if rect.has_area() and not bounds.encloses(rect):
			found.append("%s outside the window %s" % [control.get_path(), rect])
	return found


func _font_size_of(control: Control) -> int:
	if control is RichTextLabel:
		return control.get_theme_font_size(&"normal_font_size")
	if control is Label or control is Button or control is LineEdit:
		return control.get_theme_font_size(&"font_size")
	return 0


func _has_text(control: Control) -> bool:
	if control is Label:
		return not (control as Label).text.is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).get_parsed_text().is_empty()
	if control is Button:
		return not (control as Button).text.is_empty()
	return true


func _is_scrolled(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _settle(view: BattleView) -> void:
	for _step: int in 600:
		if view.is_settled():
			return
		view.advance(1.0 / 60.0)


func _frames(count: int) -> void:
	for _frame: int in count:
		await process_frame


func _router_screen() -> int:
	return _node(^"SceneRouter").get(&"current_screen")


func _node(path: NodePath) -> Node:
	return root.get_node(path)


func _end() -> void:
	print("--- %d shots, %d issues ---" % [_shot, _issues])
	quit(0)
